part of '../../streaming_dab_brush.dart';

@immutable
class PawDabRange {
  const PawDabRange(this.minimum, this.maximum);

  final double minimum;
  final double maximum;

  double sample(double unit) => minimum + (maximum - minimum) * unit;

  void validate(String name,
      {double minimumAllowed = 0, double? maximumAllowed}) {
    if (!minimum.isFinite ||
        !maximum.isFinite ||
        minimum < minimumAllowed ||
        maximum < minimum ||
        (maximumAllowed != null && maximum > maximumAllowed)) {
      throw ArgumentError('Invalid $name range.');
    }
  }
}

@immutable
class PawDabMultiScaleEdgeResponseParameters {
  const PawDabMultiScaleEdgeResponseParameters({
    this.macroInsetFactor = 0,
    this.macroArcScaleFactor = 1,
    this.microInsetFactor = 0,
    this.microCanvasScale = 7,
    this.edgeBandStart = .55,
    this.seed = 0,
  });

  final double macroInsetFactor;
  final double macroArcScaleFactor;
  final double microInsetFactor;
  final double microCanvasScale;
  final double edgeBandStart;
  final int seed;

  bool get isIdentity => macroInsetFactor == 0 && microInsetFactor == 0;

  double inwardInsetFactorAt({
    required double absoluteArc,
    required double brushSize,
    required Offset canvasPoint,
    required int strokeSeed,
    required int paperSeed,
  }) {
    if (isIdentity) return 0;
    var inset = 0.0;
    if (macroInsetFactor > 0) {
      final coordinate =
          absoluteArc / math.max(.0001, brushSize * macroArcScaleFactor);
      final left = coordinate.floor();
      final fraction = coordinate - left;
      final smooth = fraction * fraction * (3 - 2 * fraction);
      final macroSeed = strokeSeed ^ seed ^ 0x4e91;
      final first = PawDabResource._unit(
        PawDabResource._hash(macroSeed, left),
      );
      final second = PawDabResource._unit(
        PawDabResource._hash(macroSeed, left + 1),
      );
      inset += macroInsetFactor * (first + (second - first) * smooth);
    }
    if (microInsetFactor > 0) {
      final x = canvasPoint.dx / microCanvasScale;
      final y = canvasPoint.dy / microCanvasScale;
      final left = x.floor();
      final top = y.floor();
      final fx = x - left;
      final fy = y - top;
      final sx = fx * fx * (3 - 2 * fx);
      final sy = fy * fy * (3 - 2 * fy);
      final microSeed = paperSeed ^ seed ^ 0x713b;
      double sample(int cellX, int cellY) => PawDabResource._unit(
            PawDabResource._hash(
              microSeed ^ cellX * 0x45d9f3b,
              cellY ^ 0x6d2b79f5,
            ),
          );
      final upper =
          sample(left, top) + (sample(left + 1, top) - sample(left, top)) * sx;
      final lower = sample(left, top + 1) +
          (sample(left + 1, top + 1) - sample(left, top + 1)) * sx;
      inset += microInsetFactor * (upper + (lower - upper) * sy);
    }
    return inset.clamp(0.0, macroInsetFactor + microInsetFactor);
  }

  double edgeWeightAt(double radial) {
    if (isIdentity || radial <= edgeBandStart) return 0;
    final t = ((radial - edgeBandStart) / (1 - edgeBandStart)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  void validate() {
    if (!_finiteInRange(macroInsetFactor, 0, .18) ||
        !_finiteInRange(macroArcScaleFactor, .25, 16) ||
        !_finiteInRange(microInsetFactor, 0, .08) ||
        !_finiteInRange(microCanvasScale, 1, 64) ||
        !_finiteInRange(edgeBandStart, .25, .9) ||
        macroInsetFactor + microInsetFactor > .26) {
      throw ArgumentError('Invalid multi-scale edge response parameters.');
    }
  }
}

@immutable
class PawDabFootprintParameters {
  const PawDabFootprintParameters({
    required this.lengthFactor,
    required this.widthFactor,
    required this.shapeExponent,
    required this.centerCoverage,
    required this.edgeCoverage,
    required this.outerSoftnessFactor,
    this.capRoundness = 1,
    this.capRoughnessFactor = 0,
    this.rectangular = false,
    this.edgeResponse = const PawDabMultiScaleEdgeResponseParameters(),
  });

  final double lengthFactor;
  final double widthFactor;
  final double shapeExponent;
  final double centerCoverage;
  final double edgeCoverage;
  final double outerSoftnessFactor;
  final bool rectangular;

  /// 0 is a flat material cut and 1 is a semicircular swept cap.
  final double capRoundness;
  final double capRoughnessFactor;
  final PawDabMultiScaleEdgeResponseParameters edgeResponse;

  double get maximumReachX => lengthFactor / 2 + outerSoftnessFactor * 3;
  double get maximumReachY => widthFactor / 2 + outerSoftnessFactor * 3;

  void validate() {
    edgeResponse.validate();
    if (!lengthFactor.isFinite ||
        lengthFactor <= 0 ||
        !widthFactor.isFinite ||
        widthFactor <= 0 ||
        !shapeExponent.isFinite ||
        shapeExponent < 2 ||
        shapeExponent > 8 ||
        !_finiteInRange(centerCoverage, 0, 1) ||
        !_finiteInRange(edgeCoverage, 0, 1) ||
        !_finiteInRange(outerSoftnessFactor, 0, 1) ||
        !_finiteInRange(capRoundness, 0, 1) ||
        !_finiteInRange(capRoughnessFactor, 0, .25)) {
      throw ArgumentError('Invalid dab footprint parameters.');
    }
  }
}
