part of '../../streaming_dab_brush.dart';

/// Pure, bounded frame adjustment for a stroke-persistent lane endpoint.
/// Positive [signedLagAngleRadians] means that a left turn is lagging back
/// toward its past tangent.
@immutable
class PawPersistentLaneGroomingFrame {
  const PawPersistentLaneGroomingFrame({
    required this.direction,
    required this.normal,
    required this.signedLagAngleRadians,
    required this.signedCurvature,
    required this.curvatureQuality,
    required this.outerSplayFactor,
  });

  final Offset direction;
  final Offset normal;
  final double signedLagAngleRadians;
  final double signedCurvature;
  final double curvatureQuality;
  final double outerSplayFactor;

  double splayScaleFor(double effectiveOffsetUnit) {
    final outer = (-signedCurvature.sign * effectiveOffsetUnit).clamp(0.0, 1.0);
    return 1 + outerSplayFactor * curvatureQuality * outer;
  }
}

/// Finite-look-behind grooming shared by all persistent lane renderers.
/// Zero values are an explicit identity contract for existing definitions.
@immutable
class PawPersistentLaneGroomingParameters {
  const PawPersistentLaneGroomingParameters({
    this.lookBehindArcFactor = 0,
    this.inertia = 0,
    this.curvatureGain = 0,
    this.outerSplayFactor = 0,
    this.maximumLagAngleRadians = 0,
    this.preferredDirectionOffsetRadians = 0,
  });

  final double lookBehindArcFactor;
  final double inertia;
  final double curvatureGain;
  final double outerSplayFactor;
  final double maximumLagAngleRadians;
  final double preferredDirectionOffsetRadians;

  bool get isIdentity =>
      lookBehindArcFactor == 0 &&
      inertia == 0 &&
      curvatureGain == 0 &&
      outerSplayFactor == 0 &&
      maximumLagAngleRadians == 0 &&
      preferredDirectionOffsetRadians == 0;

  double pastArcFor({
    required double absoluteArc,
    required double brushSize,
  }) =>
      math.max(0.0, absoluteArc - brushSize * lookBehindArcFactor);

  PawPersistentLaneGroomingFrame evaluate({
    required Offset currentDirection,
    required Offset pastDirection,
    required double absoluteArc,
    required double brushSize,
    required double signedCurvature,
  }) {
    final current = _rotate(
      _unitDirection(currentDirection),
      preferredDirectionOffsetRadians,
    );
    if (isIdentity) {
      return PawPersistentLaneGroomingFrame(
        direction: current,
        normal: Offset(-current.dy, current.dx),
        signedLagAngleRadians: 0,
        signedCurvature: 0,
        curvatureQuality: 0,
        outerSplayFactor: 0,
      );
    }
    final past = _rotate(
      _unitDirection(pastDirection),
      preferredDirectionOffsetRadians,
    );
    final historyLength = brushSize * lookBehindArcFactor;
    final historyRamp = historyLength <= 0
        ? 0.0
        : (absoluteArc / historyLength).clamp(0.0, 1.0);
    final curvatureQuality =
        (signedCurvature.abs() * brushSize).clamp(0.0, 1.0);
    final delta = math.atan2(
      past.dx * current.dy - past.dy * current.dx,
      past.dx * current.dx + past.dy * current.dy,
    );
    final mix = (inertia + curvatureGain * curvatureQuality).clamp(0.0, 1.0) *
        historyRamp;
    final lag =
        (delta * mix).clamp(-maximumLagAngleRadians, maximumLagAngleRadians);
    final angle = math.atan2(current.dy, current.dx) - lag;
    final direction = Offset(math.cos(angle), math.sin(angle));
    return PawPersistentLaneGroomingFrame(
      direction: direction,
      normal: Offset(-direction.dy, direction.dx),
      signedLagAngleRadians: lag,
      signedCurvature: signedCurvature,
      curvatureQuality: curvatureQuality,
      outerSplayFactor: outerSplayFactor,
    );
  }

  void validate() {
    if (!_finiteInRange(lookBehindArcFactor, 0, 2) ||
        !_finiteInRange(inertia, 0, 1) ||
        !_finiteInRange(curvatureGain, 0, 2) ||
        !_finiteInRange(outerSplayFactor, 0, 1) ||
        !_finiteInRange(maximumLagAngleRadians, 0, math.pi / 3) ||
        !_finiteInRange(
          preferredDirectionOffsetRadians,
          -math.pi / 3,
          math.pi / 3,
        )) {
      throw ArgumentError('Invalid persistent lane grooming parameters.');
    }
  }

  static Offset _unitDirection(Offset value) {
    final distance = value.distance;
    return distance > .000001 ? value / distance : const Offset(1, 0);
  }

  static Offset _rotate(Offset value, double radians) {
    if (radians == 0) return value;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    return Offset(
      value.dx * cosine - value.dy * sine,
      value.dx * sine + value.dy * cosine,
    );
  }
}

/// Material role for one stroke-persistent ribbon bundle. Textured details use
/// the shared fine-tooth/coverage-void mask. Coarse carriers are narrow wax or
/// pigment deposits: they still consume paper macro deposition, but do not
/// repeat the body's fine negative texture.
enum PawDabPersistentLaneMaterial { texturedDetail, coarseCarrier }

/// A stroke-persistent ribbon bundle. Lane identity and lateral behavior are
/// pure functions of lane id and absolute arc; cache ranges only split meshes
/// and never restart fibers or pigment ribbons.
@immutable
class PawDabPersistentLaneLayer {
  const PawDabPersistentLaneLayer({
    required this.laneCount,
    required this.spreadFactor,
    required this.widthFactors,
    required this.coverage,
    this.centerDensityExponent = 1,
    this.wanderAmplitudeFactor = 0,
    this.wanderPeriodFactor = 2,
    this.clumpCount = 1,
    this.clumpStrength = 0,
    this.rootFadeArcFactor = .12,
    this.tipFadeArcFactor = .8,
    this.segmentLengthFactor = .18,
    this.grooming = const PawPersistentLaneGroomingParameters(),
    this.material = PawDabPersistentLaneMaterial.texturedDetail,
    this.coverageEnvelopeAmplitude = 0,
    this.coverageEnvelopePeriodFactor = 3,
    this.minimumPressureDensity = 1,
  });

  final int laneCount;
  final double spreadFactor;
  final PawDabRange widthFactors;
  final double coverage;
  final double centerDensityExponent;
  final double wanderAmplitudeFactor;
  final double wanderPeriodFactor;
  final int clumpCount;
  final double clumpStrength;
  final double rootFadeArcFactor;
  final double tipFadeArcFactor;
  final double segmentLengthFactor;
  final PawPersistentLaneGroomingParameters grooming;
  final PawDabPersistentLaneMaterial material;
  final double coverageEnvelopeAmplitude;
  final double coverageEnvelopePeriodFactor;
  final double minimumPressureDensity;

  double pressureDensityCoverage({
    required double pressure,
    required int laneHash,
  }) {
    if (minimumPressureDensity == 1) return 1;
    final density = minimumPressureDensity +
        (1 - minimumPressureDensity) * pressure.clamp(0.0, 1.0);
    final rank = PawDabResource._unitWindow(laneHash, 43);
    return _smoothStep(
      ((density - rank) / .12 + .5).clamp(0.0, 1.0),
    );
  }

  double coverageEnvelopeAt({
    required double absoluteArc,
    required double brushSize,
    required int layerHashSeed,
    required int laneId,
  }) {
    if (coverageEnvelopeAmplitude == 0) return 1;
    final groupHash = PawDabResource._hash(layerHashSeed, laneId % clumpCount);
    final period = math.max(
      .0001,
      brushSize *
          coverageEnvelopePeriodFactor *
          (.8 + PawDabResource._unitWindow(groupHash, 7) * .4),
    );
    final phase = PawDabResource._unitWindow(groupHash, 31) * math.pi * 2;
    return 1 +
        coverageEnvelopeAmplitude *
            math.sin(absoluteArc / period * math.pi * 2 + phase);
  }

  double get maximumNormalReach =>
      spreadFactor / 2 * (1 + grooming.outerSplayFactor) +
      wanderAmplitudeFactor +
      widthFactors.maximum / 2;

  void validate() {
    widthFactors.validate('persistent lane width', minimumAllowed: .0001);
    grooming.validate();
    if (laneCount < 0 ||
        laneCount > 96 ||
        !_finiteNonNegative(spreadFactor) ||
        !_finiteInRange(coverage, 0, 1) ||
        !_finiteInRange(centerDensityExponent, 1, 5) ||
        !_finiteNonNegative(wanderAmplitudeFactor) ||
        !_finitePositive(wanderPeriodFactor) ||
        clumpCount < 1 ||
        clumpCount > 24 ||
        !_finiteInRange(clumpStrength, 0, 1) ||
        !_finiteInRange(rootFadeArcFactor, 0, 4) ||
        !_finiteInRange(tipFadeArcFactor, 0, 4) ||
        !_finiteInRange(segmentLengthFactor, .05, 1) ||
        !_finiteInRange(coverageEnvelopeAmplitude, 0, .75) ||
        !_finiteInRange(coverageEnvelopePeriodFactor, .25, 32) ||
        !_finiteInRange(minimumPressureDensity, 0, 1)) {
      throw ArgumentError('Invalid persistent lane layer.');
    }
  }
}
