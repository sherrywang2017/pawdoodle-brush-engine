import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum PawBrushRasterSourceType { generated, bundledAsset, userImported }

enum PawBrushRasterCoordinateSpace {
  canvasFixed,
  brushLocal,
  strokeFollowing,
}

enum PawBrushRasterAddressMode { clamp, repeat, mirror }

@immutable
class PawBrushRasterResourceMetadata {
  const PawBrushRasterResourceMetadata({
    required this.source,
    required this.author,
    required this.license,
    required this.commercialUse,
    required this.attribution,
    this.sourceFile,
    this.sourceBytes = 0,
  });

  final String source;
  final String author;
  final String license;
  final bool commercialUse;
  final String attribution;
  final String? sourceFile;
  final int sourceBytes;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source,
        'author': author,
        'license': license,
        'commercial_use': commercialUse,
        'attribution': attribution,
        'source_file': sourceFile,
        'source_bytes': sourceBytes,
      };
}

/// A prepared, read-only scalar field. Image decoding and preprocessing end
/// before this value reaches the brush executor.
@immutable
class PawBrushRasterResource {
  PawBrushRasterResource._({
    required this.resourceId,
    required this.sourceType,
    required this.width,
    required this.height,
    required Float32List samples,
    required this.metadata,
    required this.coordinateSpace,
    required this.addressMode,
    required Iterable<Float32List> mipLevels,
  })  : samples = Float32List.fromList(samples),
        mipLevels = List<Float32List>.unmodifiable([
          for (final level in mipLevels) Float32List.fromList(level),
        ]) {
    _validate();
  }

  factory PawBrushRasterResource.generated({
    required String resourceId,
    required int width,
    required int height,
    required Float32List samples,
    PawBrushRasterCoordinateSpace coordinateSpace =
        PawBrushRasterCoordinateSpace.canvasFixed,
    PawBrushRasterAddressMode addressMode = PawBrushRasterAddressMode.repeat,
    PawBrushRasterResourceMetadata metadata =
        const PawBrushRasterResourceMetadata(
      source: 'PawDoodle generated field',
      author: 'PawDoodle',
      license: 'PawDoodle-owned',
      commercialUse: true,
      attribution: 'None',
    ),
    Iterable<Float32List> mipLevels = const <Float32List>[],
  }) =>
      PawBrushRasterResource._(
        resourceId: resourceId,
        sourceType: PawBrushRasterSourceType.generated,
        width: width,
        height: height,
        samples: samples,
        metadata: metadata,
        coordinateSpace: coordinateSpace,
        addressMode: addressMode,
        mipLevels: mipLevels,
      );

  factory PawBrushRasterResource.bundledAsset({
    required String resourceId,
    required int width,
    required int height,
    required Float32List samples,
    required PawBrushRasterResourceMetadata metadata,
    PawBrushRasterCoordinateSpace coordinateSpace =
        PawBrushRasterCoordinateSpace.canvasFixed,
    PawBrushRasterAddressMode addressMode = PawBrushRasterAddressMode.repeat,
    Iterable<Float32List> mipLevels = const <Float32List>[],
  }) =>
      PawBrushRasterResource._(
        resourceId: resourceId,
        sourceType: PawBrushRasterSourceType.bundledAsset,
        width: width,
        height: height,
        samples: samples,
        metadata: metadata,
        coordinateSpace: coordinateSpace,
        addressMode: addressMode,
        mipLevels: mipLevels,
      );

  factory PawBrushRasterResource.bundledScalarBytes({
    required String resourceId,
    required int width,
    required int height,
    required Uint8List bytes,
    required PawBrushRasterResourceMetadata metadata,
    PawBrushRasterCoordinateSpace coordinateSpace =
        PawBrushRasterCoordinateSpace.canvasFixed,
    PawBrushRasterAddressMode addressMode = PawBrushRasterAddressMode.repeat,
    Iterable<Float32List> mipLevels = const <Float32List>[],
  }) {
    if (bytes.length != width * height) {
      throw ArgumentError('Bundled scalar bytes do not match raster size.');
    }
    final samples = Float32List(bytes.length);
    for (var index = 0; index < bytes.length; index++) {
      samples[index] = bytes[index] / 255;
    }
    return PawBrushRasterResource.bundledAsset(
      resourceId: resourceId,
      width: width,
      height: height,
      samples: samples,
      metadata: metadata,
      coordinateSpace: coordinateSpace,
      addressMode: addressMode,
      mipLevels: mipLevels,
    );
  }

  final String resourceId;
  final PawBrushRasterSourceType sourceType;
  final int width;
  final int height;
  final Float32List samples;
  final PawBrushRasterResourceMetadata metadata;
  final PawBrushRasterCoordinateSpace coordinateSpace;
  final PawBrushRasterAddressMode addressMode;
  final List<Float32List> mipLevels;

  int get scalarBytes => samples.lengthInBytes;
  int get mipBytes =>
      mipLevels.fold<int>(0, (sum, level) => sum + level.lengthInBytes);
  int get memoryBytes => scalarBytes + mipBytes;

  double sample(
    double u,
    double v, {
    PawBrushRasterAddressMode? addressMode,
    int mipLevel = 0,
  }) {
    final level = mipLevel.clamp(0, mipLevels.length).toInt();
    final levelWidth = level == 0 ? width : math.max(1, width >> level);
    final levelHeight = level == 0 ? height : math.max(1, height >> level);
    final values = level == 0 ? samples : mipLevels[level - 1];
    return _sampleScalar(
      values: values,
      width: levelWidth,
      height: levelHeight,
      u: u,
      v: v,
      addressMode: addressMode ?? this.addressMode,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'resource_id': resourceId,
        'source_type': sourceType.name,
        'width': width,
        'height': height,
        'scalar_bytes': scalarBytes,
        'mip_bytes': mipBytes,
        'coordinate_space': coordinateSpace.name,
        'address_mode': addressMode.name,
        'metadata': metadata.toJson(),
      };

  void _validate() {
    if (resourceId.isEmpty ||
        width < 2 ||
        height < 2 ||
        samples.length != width * height ||
        samples.any((value) => !value.isFinite || value < 0 || value > 1) ||
        metadata.source.isEmpty ||
        metadata.license.isEmpty ||
        metadata.sourceBytes < 0) {
      throw ArgumentError('Invalid brush raster resource.');
    }
    var expectedWidth = math.max(1, width >> 1);
    var expectedHeight = math.max(1, height >> 1);
    for (final level in mipLevels) {
      if (level.length != expectedWidth * expectedHeight ||
          level.any((value) => !value.isFinite || value < 0 || value > 1)) {
        throw ArgumentError('Invalid brush raster mip level.');
      }
      expectedWidth = math.max(1, expectedWidth >> 1);
      expectedHeight = math.max(1, expectedHeight >> 1);
    }
  }

  static double _wrap(double value, PawBrushRasterAddressMode mode) {
    if (!value.isFinite) return 0;
    return switch (mode) {
      PawBrushRasterAddressMode.clamp => value.clamp(0.0, 1.0).toDouble(),
      PawBrushRasterAddressMode.repeat => value - value.floorToDouble(),
      PawBrushRasterAddressMode.mirror => (() {
          final period = value % 2;
          final normalized = period < 0 ? period + 2 : period;
          return normalized <= 1 ? normalized : 2 - normalized;
        })(),
    };
  }

  static double _sampleScalar({
    required Float32List values,
    required int width,
    required int height,
    required double u,
    required double v,
    required PawBrushRasterAddressMode addressMode,
  }) {
    final wrappedU = _wrap(u, addressMode);
    final wrappedV = _wrap(v, addressMode);
    final repeat = addressMode == PawBrushRasterAddressMode.repeat;
    final x = repeat ? wrappedU * width : wrappedU * (width - 1);
    final y = repeat ? wrappedV * height : wrappedV * (height - 1);
    final left = x.floor().clamp(0, width - 1).toInt();
    final top = y.floor().clamp(0, height - 1).toInt();
    final right = repeat ? (left + 1) % width : math.min(width - 1, left + 1);
    final bottom = repeat ? (top + 1) % height : math.min(height - 1, top + 1);
    final fx = x - left;
    final fy = y - top;
    final upper = values[top * width + left] * (1 - fx) +
        values[top * width + right] * fx;
    final lower = values[bottom * width + left] * (1 - fx) +
        values[bottom * width + right] * fx;
    return (upper * (1 - fy) + lower * fy).clamp(0.0, 1.0).toDouble();
  }
}

/// A role compiled once at the unified brush-program boundary. The hot path
/// receives typed-array and mapping constants directly instead of resolving a
/// resource id, coordinate mapping, and rotation for every scalar sample.
@immutable
class PawPreparedRasterRole {
  const PawPreparedRasterRole._({
    required this.resource,
    required this.coordinateSpace,
    required this.cyclesPerCoordinateUnit,
    required this.offsetX,
    required this.offsetY,
    required this.cosine,
    required this.sine,
    required this.samples,
    required this.width,
    required this.height,
    required this.addressMode,
    required _PawPreparedRasterSampler sampler,
    PawBrushRasterResourceCache? cache,
  })  : _sampler = sampler,
        _cache = cache;

  factory PawPreparedRasterRole.compile({
    required PawBrushRasterResource resource,
    required PawBrushRasterCoordinateSpace coordinateSpace,
    required double cyclesPerCoordinateUnit,
    Offset offset = Offset.zero,
    double rotationRadians = 0,
    int mipLevel = 0,
    PawBrushRasterAddressMode? addressMode,
    PawBrushRasterResourceCache? cache,
  }) {
    final level = mipLevel.clamp(0, resource.mipLevels.length).toInt();
    final samples =
        level == 0 ? resource.samples : resource.mipLevels[level - 1];
    final width =
        level == 0 ? resource.width : math.max(1, resource.width >> level);
    final height =
        level == 0 ? resource.height : math.max(1, resource.height >> level);
    final resolvedAddressMode = addressMode ?? resource.addressMode;
    return PawPreparedRasterRole._(
      resource: resource,
      coordinateSpace: coordinateSpace,
      cyclesPerCoordinateUnit: cyclesPerCoordinateUnit,
      offsetX: offset.dx,
      offsetY: offset.dy,
      cosine: math.cos(rotationRadians),
      sine: math.sin(rotationRadians),
      samples: samples,
      width: width,
      height: height,
      addressMode: resolvedAddressMode,
      sampler: _PawPreparedRasterSampler.compile(
        coordinateSpace: coordinateSpace,
        cyclesPerCoordinateUnit: cyclesPerCoordinateUnit,
        offsetX: offset.dx,
        offsetY: offset.dy,
        cosine: math.cos(rotationRadians),
        sine: math.sin(rotationRadians),
        samples: samples,
        width: width,
        height: height,
        addressMode: resolvedAddressMode,
      ),
      cache: cache,
    );
  }

  final PawBrushRasterResource resource;
  final PawBrushRasterCoordinateSpace coordinateSpace;
  final double cyclesPerCoordinateUnit;
  final double offsetX;
  final double offsetY;
  final double cosine;
  final double sine;
  final Float32List samples;
  final int width;
  final int height;
  final PawBrushRasterAddressMode addressMode;
  final _PawPreparedRasterSampler _sampler;
  final PawBrushRasterResourceCache? _cache;

  /// Samples with normalized arc/normal values supplied by the caller when
  /// multiple stroke-following roles share the same contact coordinates.
  double sample({
    required double canvasX,
    required double canvasY,
    required double absoluteArc,
    required double signedNormal,
    required double brushWidth,
  }) {
    _cache?.recordPreparedSample();
    return _sampler.sample(
      canvasX,
      canvasY,
      absoluteArc,
      signedNormal,
      brushWidth,
    );
  }

  double sampleMapped({
    required double canvasX,
    required double canvasY,
    double normalizedArc = 0,
    double normalizedNormal = 0,
  }) {
    _cache?.recordPreparedSample();
    return _sampler.sampleMapped(
      canvasX,
      canvasY,
      normalizedArc,
      normalizedNormal,
    );
  }
}

/// The coordinate-space switch is paid once during role compilation. Each
/// sampler keeps one fixed mapping path for the contact loop.
abstract class _PawPreparedRasterSampler {
  const _PawPreparedRasterSampler(this._parameters);

  factory _PawPreparedRasterSampler.compile({
    required PawBrushRasterCoordinateSpace coordinateSpace,
    required double cyclesPerCoordinateUnit,
    required double offsetX,
    required double offsetY,
    required double cosine,
    required double sine,
    required Float32List samples,
    required int width,
    required int height,
    required PawBrushRasterAddressMode addressMode,
  }) {
    final parameters = _PawPreparedRasterSamplerParameters(
      cyclesPerCoordinateUnit: cyclesPerCoordinateUnit,
      offsetX: offsetX,
      offsetY: offsetY,
      cosine: cosine,
      sine: sine,
      samples: samples,
      width: width,
      height: height,
      addressMode: addressMode,
    );
    return switch (coordinateSpace) {
      PawBrushRasterCoordinateSpace.canvasFixed =>
        _PawPreparedCanvasFixedSampler(parameters),
      PawBrushRasterCoordinateSpace.brushLocal =>
        _PawPreparedBrushLocalSampler(parameters),
      PawBrushRasterCoordinateSpace.strokeFollowing =>
        _PawPreparedStrokeSampler(parameters),
    };
  }

  final _PawPreparedRasterSamplerParameters _parameters;

  double sample(
    double canvasX,
    double canvasY,
    double absoluteArc,
    double signedNormal,
    double brushWidth,
  );

  double sampleMapped(
    double canvasX,
    double canvasY,
    double normalizedArc,
    double normalizedNormal,
  );

  double sampleBase(double baseX, double baseY) {
    final parameters = _parameters;
    final scaledX =
        baseX * parameters.cyclesPerCoordinateUnit + parameters.offsetX;
    final scaledY =
        baseY * parameters.cyclesPerCoordinateUnit + parameters.offsetY;
    final transformedX =
        scaledX * parameters.cosine - scaledY * parameters.sine;
    final transformedY =
        scaledX * parameters.sine + scaledY * parameters.cosine;
    return PawBrushRasterResource._sampleScalar(
      values: parameters.samples,
      width: parameters.width,
      height: parameters.height,
      u: transformedX,
      v: transformedY,
      addressMode: parameters.addressMode,
    );
  }
}

class _PawPreparedRasterSamplerParameters {
  const _PawPreparedRasterSamplerParameters({
    required this.cyclesPerCoordinateUnit,
    required this.offsetX,
    required this.offsetY,
    required this.cosine,
    required this.sine,
    required this.samples,
    required this.width,
    required this.height,
    required this.addressMode,
  });

  final double cyclesPerCoordinateUnit;
  final double offsetX;
  final double offsetY;
  final double cosine;
  final double sine;
  final Float32List samples;
  final int width;
  final int height;
  final PawBrushRasterAddressMode addressMode;
}

class _PawPreparedCanvasFixedSampler extends _PawPreparedRasterSampler {
  const _PawPreparedCanvasFixedSampler(super.parameters);

  @override
  double sample(
    double canvasX,
    double canvasY,
    double absoluteArc,
    double signedNormal,
    double brushWidth,
  ) =>
      sampleBase(canvasX, canvasY);

  @override
  double sampleMapped(
    double canvasX,
    double canvasY,
    double normalizedArc,
    double normalizedNormal,
  ) =>
      sampleBase(canvasX, canvasY);
}

class _PawPreparedBrushLocalSampler extends _PawPreparedRasterSampler {
  const _PawPreparedBrushLocalSampler(super.parameters);

  @override
  double sample(
    double canvasX,
    double canvasY,
    double absoluteArc,
    double signedNormal,
    double brushWidth,
  ) =>
      sampleBase(
        signedNormal / math.max(brushWidth, .0001),
        absoluteArc / math.max(brushWidth, 1),
      );

  @override
  double sampleMapped(
    double canvasX,
    double canvasY,
    double normalizedArc,
    double normalizedNormal,
  ) =>
      sampleBase(normalizedNormal, normalizedArc);
}

class _PawPreparedStrokeSampler extends _PawPreparedRasterSampler {
  const _PawPreparedStrokeSampler(super.parameters);

  @override
  double sample(
    double canvasX,
    double canvasY,
    double absoluteArc,
    double signedNormal,
    double brushWidth,
  ) =>
      sampleBase(
        absoluteArc,
        signedNormal,
      );

  @override
  double sampleMapped(
    double canvasX,
    double canvasY,
    double normalizedArc,
    double normalizedNormal,
  ) =>
      sampleBase(normalizedArc, normalizedNormal);
}

/// Maps a material-declared role to the shared scalar resource sampler.
/// The sampler has no knowledge of Crayon, Watercolor, or Fur.
abstract final class PawBrushRasterResourceSampler {
  static double sample({
    required PawBrushRasterResource resource,
    required PawBrushRasterCoordinateSpace coordinateSpace,
    required double cyclesPerCoordinateUnit,
    required Offset offset,
    required double rotationRadians,
    required double canvasX,
    required double canvasY,
    required double absoluteArc,
    required double signedNormal,
    required double brushWidth,
    int mipLevel = 0,
  }) {
    final normalizedNormal = signedNormal / math.max(brushWidth, .0001);
    final normalizedArc = absoluteArc / math.max(brushWidth, 1);
    final base = switch (coordinateSpace) {
      PawBrushRasterCoordinateSpace.canvasFixed => Offset(canvasX, canvasY),
      PawBrushRasterCoordinateSpace.brushLocal =>
        Offset(normalizedNormal, normalizedArc),
      PawBrushRasterCoordinateSpace.strokeFollowing =>
        Offset(absoluteArc, signedNormal),
    };
    final scaled = Offset(
      base.dx * cyclesPerCoordinateUnit + offset.dx,
      base.dy * cyclesPerCoordinateUnit + offset.dy,
    );
    final cosine = math.cos(rotationRadians);
    final sine = math.sin(rotationRadians);
    final transformed = Offset(
      scaled.dx * cosine - scaled.dy * sine,
      scaled.dx * sine + scaled.dy * cosine,
    );
    return resource.sample(
      transformed.dx,
      transformed.dy,
      mipLevel: mipLevel,
    );
  }
}

/// Preparation/cache counters for resource diagnostics. There is no decode
/// method here by design: decoding belongs to the prepare boundary.
class PawBrushRasterResourceCache {
  PawBrushRasterResourceCache(Iterable<PawBrushRasterResource> resources)
      : _resources = <String, PawBrushRasterResource>{
          for (final resource in resources) resource.resourceId: resource,
        } {
    loadCount = _resources.length;
    sourceBytes = _resources.values.fold<int>(
      0,
      (sum, resource) => sum + resource.metadata.sourceBytes,
    );
    decodedScalarBytes = _resources.values.fold<int>(
      0,
      (sum, resource) => sum + resource.scalarBytes,
    );
    mipBytes = _resources.values.fold<int>(
      0,
      (sum, resource) => sum + resource.mipBytes,
    );
  }

  final Map<String, PawBrushRasterResource> _resources;
  late final int loadCount;
  late final int sourceBytes;
  late final int decodedScalarBytes;
  late final int mipBytes;
  int cacheHits = 0;
  int cacheMisses = 0;
  int runtimeSampleCount = 0;
  int assetDecodeDuringPointer = 0;

  Iterable<PawBrushRasterResource> get resources => _resources.values;

  PawPreparedRasterRole prepareRole({
    required PawBrushRasterResource resource,
    required PawBrushRasterCoordinateSpace coordinateSpace,
    required double cyclesPerCoordinateUnit,
    Offset offset = Offset.zero,
    double rotationRadians = 0,
    int mipLevel = 0,
    PawBrushRasterAddressMode? addressMode,
  }) {
    if (!_resources.containsKey(resource.resourceId)) {
      cacheMisses++;
      throw StateError('Missing brush raster resource: ${resource.resourceId}');
    }
    cacheHits++;
    return PawPreparedRasterRole.compile(
      resource: resource,
      coordinateSpace: coordinateSpace,
      cyclesPerCoordinateUnit: cyclesPerCoordinateUnit,
      offset: offset,
      rotationRadians: rotationRadians,
      mipLevel: mipLevel,
      addressMode: addressMode,
      cache: this,
    );
  }

  void recordPreparedSample() {
    runtimeSampleCount++;
  }

  double sample({
    required String resourceId,
    required PawBrushRasterCoordinateSpace coordinateSpace,
    required double cyclesPerCoordinateUnit,
    required Offset offset,
    required double rotationRadians,
    required double canvasX,
    required double canvasY,
    required double absoluteArc,
    required double signedNormal,
    required double brushWidth,
    int mipLevel = 0,
  }) {
    final resource = _resources[resourceId];
    if (resource == null) {
      cacheMisses++;
      throw StateError('Missing brush raster resource: $resourceId');
    }
    cacheHits++;
    runtimeSampleCount++;
    return PawBrushRasterResourceSampler.sample(
      resource: resource,
      coordinateSpace: coordinateSpace,
      cyclesPerCoordinateUnit: cyclesPerCoordinateUnit,
      offset: offset,
      rotationRadians: rotationRadians,
      canvasX: canvasX,
      canvasY: canvasY,
      absoluteArc: absoluteArc,
      signedNormal: signedNormal,
      brushWidth: brushWidth,
      mipLevel: mipLevel,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'resource_load_count': loadCount,
        'source_bytes': sourceBytes,
        'decoded_scalar_bytes': decodedScalarBytes,
        'mip_bytes': mipBytes,
        'cache_hits': cacheHits,
        'cache_misses': cacheMisses,
        'runtime_sample_count': runtimeSampleCount,
        'asset_decode_during_pointer': assetDecodeDuringPointer,
        'resources': [for (final resource in resources) resource.toJson()],
      };
}

/// Capability-level raster roles shared by brush kernels. A role describes
/// what the compiled brush program needs; neither the resource id nor the
/// brush name participates in renderer selection.
enum PawBrushRasterRoleKind { shape, grain, paper }

@immutable
class PawBrushRasterRoleBinding {
  const PawBrushRasterRoleBinding({
    required this.bindingId,
    required this.role,
    required this.resource,
    required this.coordinateSpace,
    required this.cyclesPerCoordinateUnit,
    this.weight = 1,
    this.center = .5,
    this.contrast = 1,
    this.offset = Offset.zero,
    this.rotationRadians = 0,
    this.detailCarrier = false,
    this.detailCoverageFloor = 0,
    this.detailThreshold = .62,
    this.detailSoftness = .2,
  });

  final String bindingId;
  final PawBrushRasterRoleKind role;
  final PawBrushRasterResource resource;
  final PawBrushRasterCoordinateSpace coordinateSpace;
  final double cyclesPerCoordinateUnit;
  final double weight;
  final double center;
  final double contrast;
  final Offset offset;
  final double rotationRadians;
  final bool detailCarrier;
  final double detailCoverageFloor;
  final double detailThreshold;
  final double detailSoftness;

  void validate() {
    if (bindingId.isEmpty ||
        !cyclesPerCoordinateUnit.isFinite ||
        cyclesPerCoordinateUnit <= 0 ||
        !weight.isFinite ||
        weight <= 0 ||
        weight > 1 ||
        !center.isFinite ||
        center < 0 ||
        center > 1 ||
        !contrast.isFinite ||
        contrast < 0 ||
        contrast > 4 ||
        !offset.dx.isFinite ||
        !offset.dy.isFinite ||
        !rotationRadians.isFinite) {
      throw ArgumentError('Invalid brush raster role binding.');
    }
    if (detailCarrier &&
        ((role != PawBrushRasterRoleKind.paper &&
                role != PawBrushRasterRoleKind.grain) ||
            coordinateSpace != PawBrushRasterCoordinateSpace.canvasFixed ||
            !detailCoverageFloor.isFinite ||
            detailCoverageFloor < 0 ||
            detailCoverageFloor >= 1 ||
            !detailThreshold.isFinite ||
            detailThreshold <= 0 ||
            detailThreshold >= 1 ||
            !detailSoftness.isFinite ||
            detailSoftness <= 0 ||
            detailSoftness > .5)) {
      throw ArgumentError('Invalid high-frequency detail carrier.');
    }
  }
}

/// Prepared scalar-field program shared by production brush definitions.
/// Resource preparation ends before a stroke enters its move path, so all
/// production kernels consume the same immutable, cached field representation.
@immutable
class PawBrushRasterProgram {
  PawBrushRasterProgram(
    Iterable<PawBrushRasterRoleBinding> bindings, {
    this.detailFilterQuality = FilterQuality.none,
  }) : bindings = List<PawBrushRasterRoleBinding>.unmodifiable(bindings) {
    final ids = <String>{};
    for (final binding in this.bindings) {
      binding.validate();
      if (!ids.add(binding.bindingId)) {
        throw ArgumentError('Duplicate brush raster binding id.');
      }
    }
  }

  final List<PawBrushRasterRoleBinding> bindings;
  final FilterQuality detailFilterQuality;

  bool hasRole(PawBrushRasterRoleKind role) =>
      bindings.any((binding) => binding.role == role);

  PawPreparedBrushRasterProgram prepare() {
    final detailCarriers =
        bindings.where((binding) => binding.detailCarrier).length;
    if (detailCarriers > 1) {
      throw ArgumentError(
        'The current drawVertices pass accepts one coordinate-correct detail '
        'carrier; incompatible domains must remain separate.',
      );
    }
    final cache = PawBrushRasterResourceCache(
      bindings.map((binding) => binding.resource),
    );
    return PawPreparedBrushRasterProgram._(
      cache: cache,
      detailFilterQuality: detailFilterQuality,
      bindings: <_PawPreparedBrushRasterBinding>[
        for (final binding in bindings)
          _PawPreparedBrushRasterBinding(
            source: binding,
            role: cache.prepareRole(
              resource: binding.resource,
              coordinateSpace: binding.coordinateSpace,
              cyclesPerCoordinateUnit: binding.cyclesPerCoordinateUnit,
              offset: binding.offset,
              rotationRadians: binding.rotationRadians,
            ),
          ),
      ],
    );
  }
}

class _PawPreparedBrushRasterBinding {
  const _PawPreparedBrushRasterBinding({
    required this.source,
    required this.role,
  });

  final PawBrushRasterRoleBinding source;
  final PawPreparedRasterRole role;
}

@immutable
class PawPreparedBrushRasterProgram {
  const PawPreparedBrushRasterProgram._({
    required this.cache,
    required this.detailFilterQuality,
    required List<_PawPreparedBrushRasterBinding> bindings,
  }) : _bindings = bindings;

  final PawBrushRasterResourceCache cache;
  final FilterQuality detailFilterQuality;
  final List<_PawPreparedBrushRasterBinding> _bindings;

  bool hasRole(PawBrushRasterRoleKind role) =>
      _bindings.any((binding) => binding.source.role == role);

  bool get hasHighFrequencyCoverage =>
      _bindings.any((binding) => binding.source.detailCarrier);

  PawBrushRasterCoordinateSpace? get highFrequencyCoordinateSpace {
    for (final binding in _bindings) {
      if (binding.source.detailCarrier) return binding.source.coordinateSpace;
    }
    return null;
  }

  double? get highFrequencyCanvasPeriod {
    for (final binding in _bindings) {
      if (binding.source.detailCarrier) {
        return 1 / binding.source.cyclesPerCoordinateUnit;
      }
    }
    return null;
  }

  int? get highFrequencyRasterWidth {
    for (final binding in _bindings) {
      if (binding.source.detailCarrier) return binding.source.resource.width;
    }
    return null;
  }

  int? get highFrequencyRasterHeight {
    for (final binding in _bindings) {
      if (binding.source.detailCarrier) return binding.source.resource.height;
    }
    return null;
  }

  double sampleHighFrequencyCoverage({
    required double canvasX,
    required double canvasY,
    double absoluteArc = 0,
    double signedNormal = 0,
    double brushWidth = 1,
  }) {
    for (final binding in _bindings) {
      final source = binding.source;
      if (!source.detailCarrier) continue;
      final raw = binding.role.sample(
        canvasX: canvasX,
        canvasY: canvasY,
        absoluteArc: absoluteArc,
        signedNormal: signedNormal,
        brushWidth: brushWidth,
      );
      final height =
          (source.center + (raw - .5) * source.contrast).clamp(0.0, 1.0);
      // Paper stores height (lower valleys contact first), while grain stores
      // material presence (higher values carry more pigment). Both compile to
      // the same cached alpha texture but need opposite transfer direction.
      final signedDistance = source.role == PawBrushRasterRoleKind.paper
          ? source.detailThreshold - height
          : height - source.detailThreshold;
      final t = (signedDistance / source.detailSoftness + .5).clamp(0.0, 1.0);
      final smooth = t * t * (3 - 2 * t);
      return source.detailCoverageFloor +
          (1 - source.detailCoverageFloor) * smooth;
    }
    return 1;
  }

  /// Paper roles blend as height fields. Shape and grain roles multiply as
  /// coverage responses, with each binding's weight controlling its effect.
  double sample({
    required PawBrushRasterRoleKind role,
    required double canvasX,
    required double canvasY,
    required double absoluteArc,
    required double signedNormal,
    required double brushWidth,
  }) {
    var weightedValue = 0.0;
    var totalWeight = 0.0;
    var coverage = 1.0;
    for (final binding in _bindings) {
      final source = binding.source;
      if (source.role != role) continue;
      final raw = binding.role.sample(
        canvasX: canvasX,
        canvasY: canvasY,
        absoluteArc: absoluteArc,
        signedNormal: signedNormal,
        brushWidth: brushWidth,
      );
      final adjusted =
          (source.center + (raw - .5) * source.contrast).clamp(0.0, 1.0);
      if (role == PawBrushRasterRoleKind.paper) {
        weightedValue += adjusted * source.weight;
        totalWeight += source.weight;
      } else {
        coverage *= 1 - source.weight + adjusted * source.weight;
      }
    }
    if (role == PawBrushRasterRoleKind.paper) {
      return totalWeight == 0
          ? .5
          : (weightedValue / totalWeight).clamp(0.0, 1.0);
    }
    return coverage.clamp(0.0, 1.0);
  }

  /// Combined non-paper response for the DAB body hot path. It walks the
  /// prepared bindings once, avoiding role-list rescans and temporary records
  /// for every emitted Dab while preserving each binding's own coordinates.
  double sampleDryMediaCoverage({
    required double canvasX,
    required double canvasY,
    required double absoluteArc,
    required double signedNormal,
    required double brushWidth,
  }) {
    var coverage = 1.0;
    for (final binding in _bindings) {
      final source = binding.source;
      if (source.role == PawBrushRasterRoleKind.paper) continue;
      final raw = binding.role.sample(
        canvasX: canvasX,
        canvasY: canvasY,
        absoluteArc: absoluteArc,
        signedNormal: signedNormal,
        brushWidth: brushWidth,
      );
      final adjusted =
          (source.center + (raw - .5) * source.contrast).clamp(0.0, 1.0);
      coverage *= 1 - source.weight + adjusted * source.weight;
    }
    return coverage.clamp(0.0, 1.0);
  }
}
