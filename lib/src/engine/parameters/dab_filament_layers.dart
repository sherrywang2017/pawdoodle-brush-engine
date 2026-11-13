part of '../../streaming_dab_brush.dart';

@immutable
class PawDabFilamentLayer {
  const PawDabFilamentLayer({
    required this.count,
    this.alongCenterFactor = 0,
    this.alongSpreadFactor = 0,
    this.normalCenterFactor = 0,
    required this.normalSpreadFactor,
    this.normalJitterFactor = 0,
    this.normalDistributionExponent = 1,
    required this.lengthCenterFactor,
    required this.lengthEdgeFactor,
    this.lengthJitterFactor = 0,
    required this.widthFactors,
    this.bendCenterFactor = 0,
    this.bendEdgeFactor = 0,
    this.sweepCenterFactor = 0,
    this.sweepEdgeFactor = 0,
    this.angleJitterRadians = 0,
    this.crossingAngleRadians = 0,
    required this.coverageCenter,
    required this.coverageEdge,
    this.coverageJitter = 0,
    this.softnessFactor = 0,
    this.rootTaper = 0,
    required this.tipTaper,
  });

  final int count;
  final double alongCenterFactor;
  final double alongSpreadFactor;
  final double normalCenterFactor;
  final double normalSpreadFactor;
  final double normalJitterFactor;
  final double normalDistributionExponent;
  final double lengthCenterFactor;
  final double lengthEdgeFactor;
  final double lengthJitterFactor;
  final PawDabRange widthFactors;
  final double bendCenterFactor;
  final double bendEdgeFactor;
  final double sweepCenterFactor;
  final double sweepEdgeFactor;
  final double angleJitterRadians;
  final double crossingAngleRadians;
  final double coverageCenter;
  final double coverageEdge;
  final double coverageJitter;
  final double softnessFactor;
  final double rootTaper;
  final double tipTaper;

  double get _maximumLength =>
      math.max(lengthCenterFactor, lengthEdgeFactor) + lengthJitterFactor / 2;
  double get _maximumBend =>
      math.max(bendCenterFactor, bendEdgeFactor).abs() +
      math.max(sweepCenterFactor, sweepEdgeFactor).abs();

  double get maximumReachX {
    final baseX = alongCenterFactor.abs() +
        alongSpreadFactor / 2 +
        _maximumLength / 2 +
        widthFactors.maximum / 2;
    final baseY = normalCenterFactor.abs() +
        normalSpreadFactor / 2 +
        normalJitterFactor / 2 +
        _maximumBend +
        widthFactors.maximum / 2;
    final maximumAngle = math.min(
      crossingAngleRadians.abs() + angleJitterRadians,
      math.pi / 2,
    );
    return baseX + baseY * math.sin(maximumAngle);
  }

  double get maximumReachY {
    final baseX = alongCenterFactor.abs() +
        alongSpreadFactor / 2 +
        _maximumLength / 2 +
        widthFactors.maximum / 2;
    final baseY = normalCenterFactor.abs() +
        normalSpreadFactor / 2 +
        normalJitterFactor / 2 +
        _maximumBend +
        widthFactors.maximum / 2;
    final maximumAngle = math.min(
      crossingAngleRadians.abs() + angleJitterRadians,
      math.pi / 2,
    );
    return baseY + baseX * math.sin(maximumAngle);
  }

  void validate() {
    widthFactors.validate('filament width', minimumAllowed: .0001);
    if (count < 0 ||
        count > 96 ||
        !alongCenterFactor.isFinite ||
        !normalCenterFactor.isFinite ||
        !_finiteNonNegative(alongSpreadFactor) ||
        !_finiteNonNegative(normalSpreadFactor) ||
        !_finiteNonNegative(normalJitterFactor) ||
        !_finiteInRange(normalDistributionExponent, .1, 8) ||
        !_finiteNonNegative(lengthCenterFactor) ||
        !_finiteNonNegative(lengthEdgeFactor) ||
        !_finiteNonNegative(lengthJitterFactor) ||
        !_finiteNonNegative(bendCenterFactor) ||
        !_finiteNonNegative(bendEdgeFactor) ||
        !_finiteNonNegative(sweepCenterFactor) ||
        !_finiteNonNegative(sweepEdgeFactor) ||
        !_finiteInRange(angleJitterRadians, 0, math.pi) ||
        !_finiteInRange(crossingAngleRadians, -math.pi / 2, math.pi / 2) ||
        !_finiteInRange(coverageCenter, 0, 1) ||
        !_finiteInRange(coverageEdge, 0, 1) ||
        !_finiteInRange(coverageJitter, 0, 1) ||
        !_finiteInRange(softnessFactor, 0, 1) ||
        !_finiteInRange(rootTaper, 0, 1) ||
        !_finiteInRange(tipTaper, 0, 1)) {
      throw ArgumentError('Invalid dab filament layer.');
    }
  }
}

/// Parameterized complete-hair bundle used by curated and user-authored tips.
///
/// Both compiled layers contain whole ribbons that cross the local centerline.
/// A denser, wider core creates charcoal mass through overlapping hairs rather
/// than an unrelated opaque carrier; the guard layer supplies longer wisps.
@immutable
class PawDabCrossingHairBundleParameters {
  const PawDabCrossingHairBundleParameters({
    required this.density,
    required this.spreadFactor,
    required this.lengthFactor,
    required this.widthFactor,
    required this.crossingAngleRadians,
    required this.angleJitter,
    required this.clump,
    required this.wander,
    required this.flow,
    required this.tipTaper,
    this.softnessFactor = 0,
  });

  final double density;
  final double spreadFactor;
  final double lengthFactor;
  final double widthFactor;
  final double crossingAngleRadians;
  final double angleJitter;
  final double clump;
  final double wander;
  final double flow;
  final double tipTaper;
  final double softnessFactor;

  List<PawDabFilamentLayer> compile() {
    if (!_finiteInRange(density, 0, 1) ||
        !_finiteInRange(spreadFactor, .1, 2) ||
        !_finiteInRange(lengthFactor, .1, 2) ||
        !_finiteInRange(widthFactor, .005, .16) ||
        !_finiteInRange(crossingAngleRadians, -math.pi / 2, math.pi / 2) ||
        !_finiteInRange(angleJitter, 0, 1) ||
        !_finiteInRange(clump, 0, 1) ||
        !_finiteInRange(wander, 0, .3) ||
        !_finiteInRange(flow, 0, 1) ||
        !_finiteInRange(tipTaper, 0, 1) ||
        !_finiteInRange(softnessFactor, 0, 1)) {
      throw ArgumentError('Invalid crossing-hair bundle.');
    }
    final coreCount = (12 + density * 26).round().clamp(12, 40);
    // Guard hairs describe the silhouette.  Keeping this layer deliberately
    // sparse prevents the edge from becoming a short, uniform bottle brush.
    final guardCount = (4 + density * 11).round().clamp(4, 15);
    final coreCoverage = (.2 + .28 * clump) * flow;
    final edgeCoverage = (.026 + .035 * (1 - clump)) * flow;
    final rootTaper = tipTaper * .45;
    List<PawDabFilamentLayer> build(double geometryScale) =>
        <PawDabFilamentLayer>[
          PawDabFilamentLayer(
            count: coreCount,
            alongSpreadFactor: .72 * spreadFactor * geometryScale,
            normalSpreadFactor:
                (.42 + .3 * (1 - clump)) * spreadFactor * geometryScale,
            normalJitterFactor: .1 * angleJitter * geometryScale,
            normalDistributionExponent: 1 + clump * .72,
            lengthCenterFactor: 1.78 * lengthFactor * geometryScale,
            lengthEdgeFactor: 2.42 * lengthFactor * geometryScale,
            lengthJitterFactor: .82 * angleJitter * geometryScale,
            widthFactors: PawDabRange(
              widthFactor * 1.02 * geometryScale,
              widthFactor * 1.82 * geometryScale,
            ),
            bendCenterFactor: (.035 + wander * .38) * geometryScale,
            bendEdgeFactor: (.08 + wander * .82) * geometryScale,
            sweepCenterFactor: (.025 + wander * .42) * geometryScale,
            sweepEdgeFactor: (.06 + wander * .72) * geometryScale,
            angleJitterRadians: .045 + angleJitter * .24,
            crossingAngleRadians: crossingAngleRadians,
            coverageCenter: coreCoverage.clamp(0.0, 1.0),
            coverageEdge: edgeCoverage.clamp(0.0, 1.0),
            coverageJitter: .04 + angleJitter * .1,
            softnessFactor: softnessFactor * .72 * geometryScale,
            rootTaper: rootTaper,
            tipTaper: tipTaper,
          ),
          PawDabFilamentLayer(
            count: guardCount,
            alongCenterFactor: .02 * geometryScale,
            alongSpreadFactor: 1.18 * spreadFactor * geometryScale,
            normalSpreadFactor: 1.36 * spreadFactor * geometryScale,
            normalJitterFactor: .16 * angleJitter * geometryScale,
            normalDistributionExponent: .72 + clump * .18,
            lengthCenterFactor: 4.05 * lengthFactor * geometryScale,
            lengthEdgeFactor: 6.1 * lengthFactor * geometryScale,
            lengthJitterFactor: 1.42 * angleJitter * geometryScale,
            widthFactors: PawDabRange(
              widthFactor * .58 * geometryScale,
              widthFactor * 1.04 * geometryScale,
            ),
            bendCenterFactor: (.06 + wander * .55) * geometryScale,
            bendEdgeFactor: (.14 + wander) * geometryScale,
            sweepCenterFactor: (.05 + wander * .7) * geometryScale,
            sweepEdgeFactor: (.12 + wander * 1.25) * geometryScale,
            angleJitterRadians: .08 + angleJitter * .34,
            crossingAngleRadians: crossingAngleRadians + .04,
            coverageCenter: (coreCoverage * .62).clamp(0.0, 1.0),
            coverageEdge: (edgeCoverage * .72).clamp(0.0, 1.0),
            coverageJitter: .04 + angleJitter * .12,
            softnessFactor: softnessFactor * geometryScale,
            rootTaper: rootTaper,
            tipTaper: tipTaper,
          ),
        ];
    final unbounded = build(1);
    final maximumReach = unbounded.fold<double>(
      0,
      (reach, layer) =>
          math.max(reach, math.max(layer.maximumReachX, layer.maximumReachY)),
    );
    // Keep a small numerical margin below PawDabTemplateParameters' extent
    // ceiling; trigonometric reach reconstruction can otherwise exceed 8 by
    // a few ulps after the scale is applied.
    const maximumAtlasReach = 3.88;
    return maximumReach <= maximumAtlasReach
        ? unbounded
        : build(maximumAtlasReach / maximumReach);
  }
}
