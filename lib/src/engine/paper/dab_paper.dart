part of '../../streaming_dab_brush.dart';

/// Immutable document/session paper. Its identity and seed deliberately live
/// outside a brush definition: every material on one canvas touches the same
/// sheet instead of synthesizing a brush-local imitation of paper.
@immutable
class PawPaperDefinition {
  const PawPaperDefinition({
    required this.id,
    required this.revision,
    required this.seed,
    this.coarseScale = 92,
    this.mediumScale = 27,
    this.fineScale = 7,
    this.coarseWeight = .48,
    this.mediumWeight = .34,
    this.fineWeight = .18,
  });

  static const PawPaperDefinition defaultPaper = PawPaperDefinition(
    id: 'pawdoodle-cold-press',
    revision: 1,
    seed: 0x51a7e,
  );

  final String id;
  final int revision;
  final int seed;
  final double coarseScale;
  final double mediumScale;
  final double fineScale;
  final double coarseWeight;
  final double mediumWeight;
  final double fineWeight;

  void validate() {
    final weight = coarseWeight + mediumWeight + fineWeight;
    if (id.isEmpty ||
        revision < 1 ||
        !_finitePositive(coarseScale) ||
        !_finitePositive(mediumScale) ||
        !_finitePositive(fineScale) ||
        !_finiteNonNegative(coarseWeight) ||
        !_finiteNonNegative(mediumWeight) ||
        !_finiteNonNegative(fineWeight) ||
        !weight.isFinite ||
        weight <= 0) {
      throw ArgumentError('Invalid paper definition.');
    }
  }
}

@immutable
class PawPaperHeightSample {
  const PawPaperHeightSample({
    required this.coarse,
    required this.medium,
    required this.fine,
  });

  final double coarse;
  final double medium;
  final double fine;

  double weightedHeight({
    required PawPaperDefinition definition,
    required double coarseResponseWeight,
    required double mediumResponseWeight,
    required double fineResponseWeight,
  }) {
    final coarseWeight = definition.coarseWeight * coarseResponseWeight;
    final mediumWeight = definition.mediumWeight * mediumResponseWeight;
    final fineWeight = definition.fineWeight * fineResponseWeight;
    final weight = coarseWeight + mediumWeight + fineWeight;
    if (weight <= 0) return 0;
    return ((coarse * coarseWeight +
                medium * mediumWeight +
                fine * fineWeight) /
            weight)
        .clamp(0.0, 1.0);
  }
}

/// Prepared, canvas-owned deterministic paper field. Each sample keeps the
/// three bounded spatial bands separate so a brush can distinguish macro
/// deposition from tooth without evaluating the paper noise twice.
@immutable
class PawPaperField {
  PawPaperField(this.definition, {this.rasterProgram}) {
    definition.validate();
  }

  final PawPaperDefinition definition;
  final PawPreparedBrushRasterProgram? rasterProgram;

  // Paper is immutable for a stroke. Cache scalar lattice values rather than
  // re-hashing four corners of four noise bands at every contact vertex.
  // Lazy 8x8 blocks preserve the exact procedural field (no resampling or
  // prepainted brush texture) with at most 512 KiB of numeric payload.
  final _noiseTiles = <(int, int, int), Float64List>{};

  double _latticeValue(int seed, int x, int y) {
    final key = (seed, x >> 3, y >> 3);
    var tile = _noiseTiles[key];
    if (tile == null) {
      if (_noiseTiles.length >= 1024) {
        _noiseTiles.remove(_noiseTiles.keys.first);
      }
      tile = Float64List(64)..fillRange(0, 64, double.nan);
      _noiseTiles[key] = tile;
    }
    final index = (y & 7) * 8 + (x & 7);
    var value = tile[index];
    if (value.isNaN) {
      value = PawDabResource._unit(
          PawDabResource._hash(seed ^ x * 0x45d9f3b, y ^ 0x6d2b79f5));
      tile[index] = value;
    }
    return value;
  }

  String get identity => '${definition.id}|${definition.revision}';

  double sampleHeight(Offset canvasPoint) => sample(canvasPoint).weightedHeight(
        definition: definition,
        coarseResponseWeight: 1,
        mediumResponseWeight: 1,
        fineResponseWeight: 1,
      );

  double sampleCoarse(Offset canvasPoint) => _paperNoise(
      canvasPoint, definition.coarseScale, definition.seed ^ 0x3c6ef35f);

  PawPaperHeightSample sample(Offset canvasPoint) {
    final d = definition;
    final preparedHeight =
        rasterProgram?.hasRole(PawBrushRasterRoleKind.paper) == true
            ? rasterProgram!.sample(
                role: PawBrushRasterRoleKind.paper,
                canvasX: canvasPoint.dx,
                canvasY: canvasPoint.dy,
                absoluteArc: 0,
                signedNormal: 0,
                brushWidth: 1,
              )
            : null;
    final fineBase = preparedHeight ??
        _paperNoise(canvasPoint, d.fineScale, d.seed ^ 0x7f4a7c15);
    // Paper tooth is not one smoothly interpolated noise band. A smaller
    // independent band breaks broad height islands into the fine, irregular
    // contacts visible in crayon and absorbent ink without introducing a
    // repeating brush-local texture tile.
    final microTooth = _paperNoise(
      canvasPoint,
      d.fineScale * .24,
      d.seed ^ 0x2c9277b5,
    );
    return PawPaperHeightSample(
      coarse: sampleCoarse(canvasPoint),
      medium: _paperNoise(canvasPoint, d.mediumScale, d.seed ^ 0x1bf5a),
      fine: (fineBase * .25 + microTooth * .75).clamp(0.0, 1.0),
    );
  }

  double _paperNoise(Offset point, double scale, int seed) {
    final x = point.dx / scale;
    final y = point.dy / scale;
    final left = x.floor();
    final top = y.floor();
    final fx = x - left;
    final fy = y - top;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);
    double sample(int cellX, int cellY) => _latticeValue(seed, cellX, cellY);
    final a = sample(left, top);
    final b = sample(left + 1, top);
    final c = sample(left, top + 1);
    final e = sample(left + 1, top + 1);
    return (a + (b - a) * sx) + ((c + (e - c) * sx) - (a + (b - a) * sx)) * sy;
  }
}
