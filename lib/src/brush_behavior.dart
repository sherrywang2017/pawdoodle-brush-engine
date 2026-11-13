import 'brush_arithmetic.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Renderer-facing data already carried by a planned DAB.
///
/// Keeping this as a narrow interface lets brush behavior consume the stable
/// emission result without owning Stroke, Emission, or commit concerns.
abstract interface class PawBrushBehaviorDab {
  Offset get point;
  Offset get tangent;
  int get hash;
  double get pressure;
  double get speedPixelsPerSecond;
  double get signedCurvature;
}

/// A brush-specific renderer behavior. This is deliberately not a material
/// program: it only turns one planned DAB into renderer-local response values.
abstract class PawBrushBehavior {
  const PawBrushBehavior();

  String get id;
}

/// One fiber in a coherent cluster. Instances are reused by
/// [PawFiberCluster] so generation does not allocate in the render loop.
class PawFiber {
  PawFiber();

  Offset direction = const Offset(1, 0);
  double angularDeviation = 0;
  double spread = 1;
  double length = 1;
  double density = 1;
  double tipFade = 1;
}

/// Fixed-capacity output storage for [PawFiberClusterGenerator].
class PawFiberCluster {
  PawFiberCluster({int maximumFibers = 8})
      : fibers = List<PawFiber>.generate(
          maximumFibers,
          (_) => PawFiber(),
          growable: false,
        );

  final List<PawFiber> fibers;
  int count = 0;
  Offset direction = const Offset(1, 0);
  double spread = 1;
  double length = 1;
  double density = 1;
  double tipFade = 1;

  PawFiber operator [](int index) {
    if (index < 0 || index >= count) throw RangeError.index(index, this);
    return fibers[index];
  }
}

class PawFiberClusterGenerator {
  const PawFiberClusterGenerator({this.behavior = const PawFurBehavior()});

  final PawFurBehavior behavior;

  void generateInto({
    required PawBrushBehaviorDab dab,
    required Offset previousTangent,
    Offset? followingTangent,
    bool preserveDirectionDiscontinuity = false,
    required double brushSize,
    required int fiberCount,
    required PawFiberCluster output,
    bool includeDirections = true,
  }) {
    behavior.populateCluster(
      dab: dab,
      previousTangent: previousTangent,
      followingTangent: followingTangent,
      preserveDirectionDiscontinuity: preserveDirectionDiscontinuity,
      brushSize: brushSize,
      fiberCount: fiberCount,
      output: output,
      includeDirections: includeDirections,
    );
  }
}

/// Fur flow shares one groomed direction and only uses small,
/// deterministic intra-cluster deviations. Fibers therefore follow motion
/// history instead of becoming unrelated random lines.
class PawFurBehavior extends PawBrushBehavior {
  const PawFurBehavior();

  @override
  String get id => 'production-fur';

  void populateCluster({
    required PawBrushBehaviorDab dab,
    required Offset previousTangent,
    Offset? followingTangent,
    bool preserveDirectionDiscontinuity = false,
    required double brushSize,
    required int fiberCount,
    required PawFiberCluster output,
    bool includeDirections = true,
  }) {
    if (fiberCount < 0 || fiberCount > output.fibers.length) {
      throw RangeError.range(fiberCount, 0, output.fibers.length, 'fiberCount');
    }
    final previous = _unit(previousTangent);
    final rawCurrent = _unit(dab.tangent);
    final following = _unit(followingTangent ?? rawCurrent);
    // The prepared tuft is much wider than an ordinary round tip, so a
    // coalesced input interval can magnify a harmless tangent step into a
    // visible polygon corner. A symmetric, renderer-local direction window
    // keeps the tuft rotating continuously without changing the modeled
    // centerline or any planned DAB identity.
    final incomingDelta = _signedAngle(previous, rawCurrent);
    final outgoingDelta = _signedAngle(rawCurrent, following);
    final directionWindowTurn = _signedAngle(previous, following).abs();
    final cornerQuality =
        (directionWindowTurn / (math.pi * .7)).clamp(0.0, 1.0).toDouble();
    // Interpolate material direction on both sides of a sharp centerline
    // corner. Before the vertex it leans toward the outgoing tangent; after
    // the vertex it retains the incoming tangent. The centerline stays sharp,
    // but prepared tufts overlap around the outside instead of meeting at a
    // guillotined seam.
    final groomWeight =
        .28 + cornerQuality * .12 + (preserveDirectionDiscontinuity ? .06 : 0);
    final rawAngle = math.atan2(rawCurrent.dy, rawCurrent.dx);
    final curvatureQuality =
        (dab.signedCurvature.abs() * brushSize).clamp(0.0, 1.0);
    // The symmetric window above already removes one-event tangent spikes.
    // Retain only a small amount of history lag: a larger weight held
    // a wide tuft too close to its old angle, so rapid circles exposed each
    // catch-up step as a polygon corner even though the centerline was smooth.
    final curvatureLead =
        (dab.signedCurvature * brushSize * .018).clamp(-.024, .024);
    final clusterAngle = rawAngle +
        outgoingDelta * groomWeight -
        incomingDelta * groomWeight +
        curvatureLead;
    final clusterDirection =
        Offset(math.cos(clusterAngle), math.sin(clusterAngle));
    final speedUnit = (dab.speedPixelsPerSecond / 1400).clamp(0.0, 1.0);
    final pressure = dab.pressure.clamp(0.0, 1.0);

    output
      ..count = fiberCount
      ..direction = clusterDirection
      // Turning the brush changes its heading, not its physical footprint.
      // Curvature-driven expansion made equal-pressure corners suddenly fat.
      ..spread = .76 + .18 * pressure
      ..length = .92 + .16 * pressure - .08 * speedUnit
      ..density = .46 + .54 * pressure
      ..tipFade = .76 + .18 * speedUnit + .06 * curvatureQuality;

    for (var index = 0; index < fiberCount; index++) {
      final fiber = output.fibers[index];
      final lateral = fiberCount <= 1 ? 0.0 : index / (fiberCount - 1) * 2 - 1;
      final unit = _unitFromHash(_mix(dab.hash, index + 1));
      // Most direction comes from cluster flow. Hash only breaks mechanical
      // symmetry inside a narrow, bounded cone.
      final deviation =
          lateral * (.03 + .025 * curvatureQuality + .018 * cornerQuality) +
              (unit - .5) * .02;
      if (includeDirections) {
        final angle = clusterAngle + deviation;
        fiber.direction = Offset(math.cos(angle), math.sin(angle));
      }
      fiber
        ..angularDeviation = deviation
        ..spread = output.spread * (.92 + .16 * unit)
        ..length = output.length *
            (.9 + .2 * _unitFromHash(_mix(dab.hash, index + 17)))
        ..density = output.density * (1 - lateral.abs() * .16)
        ..tipFade = output.tipFade * (.94 + .12 * unit);
    }
  }
}

class PawInkDabResponse {
  double widthScale = 1;
  double opacityScale = 1;
  double overlapDarkening = 0;
  double pressureSpread = 1;
  double velocityThinning = 1;
}

/// Sparse, stroke-local wet-media state.
///
/// Values live on tile vertices rather than tile faces so [sampleAt] can
/// bilinearly reconstruct a continuous field without revealing square tile
/// boundaries. A mutable tail can overlay an immutable prefix in the same way
/// as the soft-brush density field; this keeps preview, retained commands and
/// committed pictures on one causal material history.
class PawWetMediaTileAccumulator {
  PawWetMediaTileAccumulator({
    this.tileSize = 18,
    this.maximumTiles = 4096,
  })  : _capacity = _checkedDensityTableCapacity(maximumTiles),
        _tileXs = Int32List(_checkedDensityTableCapacity(maximumTiles)),
        _tileYs = Int32List(_checkedDensityTableCapacity(maximumTiles)),
        _pigment = Float64List(_checkedDensityTableCapacity(maximumTiles)),
        _water = Float64List(_checkedDensityTableCapacity(maximumTiles)),
        _occupied = Uint8List(_checkedDensityTableCapacity(maximumTiles)) {
    if (!tileSize.isFinite || tileSize <= 0) {
      throw ArgumentError.value(tileSize, 'tileSize');
    }
  }

  final double tileSize;
  final int maximumTiles;
  final int _capacity;
  final Int32List _tileXs;
  final Int32List _tileYs;
  final Float64List _pigment;
  final Float64List _water;
  final Uint8List _occupied;
  int _localTileCount = 0;
  int _signature = 0x71a9d;
  PawWetMediaTileAccumulator? _sealedPrefix;

  int get signature => _signature;

  int get tileCount {
    final prefix = _sealedPrefix;
    if (prefix == null) return _localTileCount;
    var count = prefix.tileCount;
    for (var slot = 0; slot < _capacity; slot++) {
      if (_occupied[slot] != 0 &&
          !prefix._containsTile(_tileXs[slot], _tileYs[slot])) {
        count++;
      }
    }
    return count;
  }

  void clear() {
    _occupied.fillRange(0, _occupied.length, 0);
    _localTileCount = 0;
    _sealedPrefix = null;
    _signature = 0x71a9d;
  }

  void resetOverlayFrom(PawWetMediaTileAccumulator sealedPrefix) {
    if (identical(this, sealedPrefix)) {
      throw ArgumentError('An accumulator cannot use itself as a prefix.');
    }
    _occupied.fillRange(0, _occupied.length, 0);
    _localTileCount = 0;
    _sealedPrefix = sealedPrefix;
    _signature = sealedPrefix.signature;
  }

  void deposit({
    required PawBrushBehaviorDab dab,
    required double flow,
    required double dilution,
    required double charge,
    double diffusion = 0,
  }) {
    final gridX = dab.point.dx / tileSize;
    final gridY = dab.point.dy / tileSize;
    final x0 = gridX.floor();
    final y0 = gridY.floor();
    final tx = gridX - x0;
    final ty = gridY - y0;
    final pressure = dab.pressure.clamp(0.0, 1.0);
    final boundedFlow = flow.clamp(0.0, 1.0);
    final pigmentMass = (.035 + .12 * pressure) *
        boundedFlow *
        (.58 + .42 * charge) *
        (1 - dilution * .28);
    final waterMass =
        (.055 + .16 * pressure) * boundedFlow * (.34 + .66 * dilution);
    final spread = diffusion.clamp(0.0, 1.0).toDouble();
    final corePigment = pigmentMass * (1 - spread * .22);
    final coreWater = waterMass * (1 - spread * .48);
    _splat(x0, y0, (1 - tx) * (1 - ty), corePigment, coreWater);
    _splat(x0 + 1, y0, tx * (1 - ty), corePigment, coreWater);
    _splat(x0, y0 + 1, (1 - tx) * ty, corePigment, coreWater);
    _splat(x0 + 1, y0 + 1, tx * ty, corePigment, coreWater);
    if (spread > .000001) {
      final centerX = gridX.round();
      final centerY = gridY.round();
      var weightSum = 0.0;
      for (var offsetY = -1; offsetY <= 1; offsetY++) {
        for (var offsetX = -1; offsetX <= 1; offsetX++) {
          final dx = centerX + offsetX - gridX;
          final dy = centerY + offsetY - gridY;
          weightSum += math.exp(-(dx * dx + dy * dy) / .78);
        }
      }
      final spreadPigment = pigmentMass * spread * .22;
      final spreadWater = waterMass * spread * .48;
      for (var offsetY = -1; offsetY <= 1; offsetY++) {
        for (var offsetX = -1; offsetX <= 1; offsetX++) {
          final tileX = centerX + offsetX;
          final tileY = centerY + offsetY;
          final dx = tileX - gridX;
          final dy = tileY - gridY;
          final weight = math.exp(-(dx * dx + dy * dy) / .78) / weightSum;
          _splat(tileX, tileY, weight, spreadPigment, spreadWater);
        }
      }
    }
    _signature = _mix(
      _signature ^ _mix(x0, y0),
      dab.hash ^ (pigmentMass * 1000000).round(),
    );
  }

  PawWetMediaTileSample sampleAt(Offset point) {
    final gridX = point.dx / tileSize;
    final gridY = point.dy / tileSize;
    final x0 = gridX.floor();
    final y0 = gridY.floor();
    final tx = gridX - x0;
    final ty = gridY - y0;
    double interpolate(double Function(int, int) valueAt) {
      final top = valueAt(x0, y0) * (1 - tx) + valueAt(x0 + 1, y0) * tx;
      final bottom =
          valueAt(x0, y0 + 1) * (1 - tx) + valueAt(x0 + 1, y0 + 1) * tx;
      return top * (1 - ty) + bottom * ty;
    }

    final pigmentMass = interpolate(_pigmentAt);
    final waterMass = interpolate(_waterAt);
    return PawWetMediaTileSample(
      pigment: (1 - math.exp(-pigmentMass * 1.7)).clamp(0.0, 1.0),
      wetness: (1 - math.exp(-waterMass * 1.25)).clamp(0.0, 1.0),
    );
  }

  void _splat(
    int tileX,
    int tileY,
    double weight,
    double pigmentMass,
    double waterMass,
  ) {
    if (weight <= .000001) return;
    final slot = _findSlot(tileX, tileY);
    if (_occupied[slot] == 0) {
      if (_localTileCount >= maximumTiles) {
        throw StateError('Wet-media tile capacity exceeded.');
      }
      _occupied[slot] = 1;
      _tileXs[slot] = tileX;
      _tileYs[slot] = tileY;
      _pigment[slot] = _sealedPrefix?._pigmentAt(tileX, tileY) ?? 0;
      _water[slot] = _sealedPrefix?._waterAt(tileX, tileY) ?? 0;
      _localTileCount++;
    }
    _pigment[slot] = (_pigment[slot] + pigmentMass * weight).clamp(0.0, 8.0);
    _water[slot] = (_water[slot] + waterMass * weight).clamp(0.0, 8.0);
  }

  bool _containsTile(int tileX, int tileY) {
    final slot = _findSlot(tileX, tileY);
    return _occupied[slot] != 0 ||
        (_sealedPrefix?._containsTile(tileX, tileY) ?? false);
  }

  double _pigmentAt(int tileX, int tileY) {
    final slot = _findSlot(tileX, tileY);
    return _occupied[slot] != 0
        ? _pigment[slot]
        : _sealedPrefix?._pigmentAt(tileX, tileY) ?? 0;
  }

  double _waterAt(int tileX, int tileY) {
    final slot = _findSlot(tileX, tileY);
    return _occupied[slot] != 0
        ? _water[slot]
        : _sealedPrefix?._waterAt(tileX, tileY) ?? 0;
  }

  int _findSlot(int tileX, int tileY) {
    var slot = _mix(tileX, tileY) & (_capacity - 1);
    for (var probe = 0; probe < _capacity; probe++) {
      if (_occupied[slot] == 0 ||
          (_tileXs[slot] == tileX && _tileYs[slot] == tileY)) {
        return slot;
      }
      slot = (slot + 1) & (_capacity - 1);
    }
    throw StateError('Wet-media tile table is full.');
  }
}

@immutable
class PawWetMediaTileSample {
  const PawWetMediaTileSample({required this.pigment, required this.wetness});

  final double pigment;
  final double wetness;
}

/// Ink response. Edge response remains owned by the existing footprint.
class PawInkBehavior extends PawBrushBehavior {
  const PawInkBehavior();

  @override
  String get id => 'production-ink';

  void evaluateInto(
    PawBrushBehaviorDab dab,
    PawInkDabResponse output,
  ) {
    final pressure = dab.pressure.clamp(0.0, 1.0);
    final speedUnit = (dab.speedPixelsPerSecond / 1500).clamp(0.0, 1.0);
    final pressureSpread = .82 + .32 * math.sqrt(pressure);
    final velocityThinning = 1 - .18 * speedUnit;
    output
      ..pressureSpread = pressureSpread
      ..velocityThinning = velocityThinning
      ..widthScale = pressureSpread * velocityThinning
      // Arc-length emission already gives slow and fast input the same number
      // of contacts per painted distance. Feeding speed or accumulated
      // overlap back into alpha made a held/slow stroke pulse dark even though
      // its pigment mass per unit arc had not changed.
      ..overlapDarkening = 0
      ..opacityScale = .9 + .1 * pressure;
  }
}

/// Sparse, continuous soft-brush density. A working accumulator may reference
/// a sealed prefix and only stores the mutable overlay touched by the tail.
class PawSoftTileDensityAccumulator {
  PawSoftTileDensityAccumulator({
    this.tileSize = 32,
    this.maximumTiles = 2048,
  })  : _capacity = _checkedDensityTableCapacity(maximumTiles),
        _tileXs = Int32List(_checkedDensityTableCapacity(maximumTiles)),
        _tileYs = Int32List(_checkedDensityTableCapacity(maximumTiles)),
        _densities = Float64List(_checkedDensityTableCapacity(maximumTiles)),
        _occupied = Uint8List(_checkedDensityTableCapacity(maximumTiles)) {
    if (!tileSize.isFinite || tileSize <= 0) {
      throw ArgumentError.value(tileSize, 'tileSize');
    }
  }

  final double tileSize;
  final int maximumTiles;
  final int _capacity;
  final Int32List _tileXs;
  final Int32List _tileYs;
  final Float64List _densities;
  final Uint8List _occupied;
  int _localTileCount = 0;
  PawSoftTileDensityAccumulator? _sealedPrefix;
  int _signature = 0x49f07;

  int get signature => _signature;
  int get tileCount {
    final prefix = _sealedPrefix;
    if (prefix == null) return _localTileCount;
    var count = prefix.tileCount;
    for (var slot = 0; slot < _capacity; slot++) {
      if (_occupied[slot] != 0 &&
          !prefix._containsTile(_tileXs[slot], _tileYs[slot])) {
        count++;
      }
    }
    return count;
  }

  void clear() {
    _occupied.fillRange(0, _occupied.length, 0);
    _localTileCount = 0;
    _sealedPrefix = null;
    _signature = 0x49f07;
  }

  void resetOverlayFrom(PawSoftTileDensityAccumulator sealedPrefix) {
    if (identical(this, sealedPrefix)) {
      throw ArgumentError('An accumulator cannot use itself as a prefix.');
    }
    _occupied.fillRange(0, _occupied.length, 0);
    _localTileCount = 0;
    _sealedPrefix = sealedPrefix;
    _signature = sealedPrefix.signature;
  }

  double densityAt(Offset point) {
    final (tileX, tileY) = _tileCoordinates(point);
    final fx = point.dx / tileSize - tileX;
    final fy = point.dy / tileSize - tileY;
    return _densityForTile(tileX, tileY) * (1 - fx) * (1 - fy) +
        _densityForTile(tileX + 1, tileY) * fx * (1 - fy) +
        _densityForTile(tileX, tileY + 1) * (1 - fx) * fy +
        _densityForTile(tileX + 1, tileY + 1) * fx * fy;
  }

  double accumulate({
    required PawBrushBehaviorDab dab,
    required double brushSize,
    double flow = 1,
  }) {
    final (tileX, tileY) = _tileCoordinates(dab.point);
    final pressure = dab.pressure.clamp(0.0, 1.0);
    final sizeResponse = (brushSize / tileSize).clamp(.25, 2.0).toDouble();
    // Flow is deposition rate, not a post-composite opacity. Retaining a
    // small floor keeps a single low-flow spray visible while repeated DABs
    // build density in the sparse tile accumulator.
    final flowResponse = (.08 + .92 * flow.clamp(0.0, 1.0)).clamp(.08, 1.0);
    final contribution =
        (.16 + .4 * pressure) * (.9 + .08 * sizeResponse) * flowResponse;
    // Deposit and sample the same bilinear field. Selecting a single cell
    // reset density at each 32 px boundary, abruptly lightening Soft even
    // with constant pressure. Neighboring vertices share the pigment instead.
    final fx = dab.point.dx / tileSize - tileX;
    final fy = dab.point.dy / tileSize - tileY;
    // Normalize the tent kernel's self-response so moving between grid
    // vertices does not change the amount deposited by one dab.
    final normalization =
        ((1 - fx) * (1 - fx) + fx * fx) * ((1 - fy) * (1 - fy) + fy * fy);
    void deposit(int x, int y, double weight) {
      if (weight <= 0) return;
      _setDensity(
          x,
          y,
          (_densityForTile(x, y) + contribution * weight / normalization)
              .clamp(0.0, 6.0));
    }

    deposit(tileX, tileY, (1 - fx) * (1 - fy));
    deposit(tileX + 1, tileY, fx * (1 - fy));
    deposit(tileX, tileY + 1, (1 - fx) * fy);
    deposit(tileX + 1, tileY + 1, fx * fy);
    _signature = _mix(
      _signature ^ _mix(tileX, tileY),
      dab.hash ^ (contribution * 1000000).round(),
    );
    return densityAt(dab.point);
  }

  bool _containsTile(int tileX, int tileY) {
    final slot = _findSlot(tileX, tileY);
    return _occupied[slot] != 0 ||
        (_sealedPrefix?._containsTile(tileX, tileY) ?? false);
  }

  double _densityForTile(int tileX, int tileY) {
    final slot = _findSlot(tileX, tileY);
    return _occupied[slot] != 0
        ? _densities[slot]
        : _sealedPrefix?._densityForTile(tileX, tileY) ?? 0;
  }

  void _setDensity(int tileX, int tileY, double density) {
    final slot = _findSlot(tileX, tileY);
    if (_occupied[slot] == 0) {
      if (_localTileCount >= maximumTiles) {
        throw StateError('Soft density tile capacity exceeded.');
      }
      _occupied[slot] = 1;
      _tileXs[slot] = tileX;
      _tileYs[slot] = tileY;
      _localTileCount++;
    }
    _densities[slot] = density;
  }

  int _findSlot(int tileX, int tileY) {
    var slot = _mix(tileX, tileY) & (_capacity - 1);
    for (var probe = 0; probe < _capacity; probe++) {
      if (_occupied[slot] == 0 ||
          (_tileXs[slot] == tileX && _tileYs[slot] == tileY)) {
        return slot;
      }
      slot = (slot + 1) & (_capacity - 1);
    }
    throw StateError('Soft density tile table is full.');
  }

  (int, int) _tileCoordinates(Offset point) => (
        (point.dx / tileSize).floor(),
        (point.dy / tileSize).floor(),
      );
}

class PawSoftBehavior extends PawBrushBehavior {
  const PawSoftBehavior();

  @override
  String get id => 'production-soft';

  double accumulate({
    required PawBrushBehaviorDab dab,
    required double brushSize,
    required PawSoftTileDensityAccumulator accumulator,
    double flow = 1,
  }) =>
      accumulator.accumulate(dab: dab, brushSize: brushSize, flow: flow);

  double opacityScaleForDensity(double density) =>
      (.88 + .12 * (1 - math.exp(-density * .58))).clamp(0.0, 1.0);
}

abstract final class PawBrushBehaviorRegistry {
  static const PawFurBehavior fur = PawFurBehavior();
  static const PawInkBehavior ink = PawInkBehavior();
  static const PawSoftBehavior soft = PawSoftBehavior();

  static PawBrushBehavior? forBrushId(String brushId) => switch (brushId) {
        'fur-dab' => fur,
        'ink-dab' => ink,
        'soft-dab' => soft,
        _ => null,
      };
}

Offset _unit(Offset value) {
  final length = value.distance;
  return length > .000001 ? value / length : const Offset(1, 0);
}

double _signedAngle(Offset from, Offset to) => math.atan2(
      from.dx * to.dy - from.dy * to.dx,
      from.dx * to.dx + from.dy * to.dy,
    );

int _checkedDensityTableCapacity(int maximumTiles) {
  if (maximumTiles <= 0 || maximumTiles > 1 << 20) {
    throw ArgumentError.value(maximumTiles, 'maximumTiles');
  }
  var capacity = 1;
  final target = math.max(2, maximumTiles * 2);
  while (capacity < target) {
    capacity <<= 1;
  }
  return capacity;
}

int _mix(int seed, int value) {
  var result = (seed ^ pawMultiplyUint32(value, 0x45d9f3b)) & 0xffffffff;
  result = pawMultiplyUint32(result ^ (result >> 16), 0x45d9f3b) & 0x7fffffff;
  result = pawMultiplyUint32(result ^ (result >> 16), 0x45d9f3b) & 0x7fffffff;
  return result ^ (result >> 16);
}

double _unitFromHash(int value) => (value & 0xffff) / 0xffff;
