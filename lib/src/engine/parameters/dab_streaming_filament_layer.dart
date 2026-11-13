part of '../../streaming_dab_brush.dart';

/// A finite, absolute-arc filament emitter. It shares the Dab template
/// interpreter with stamp-local [PawDabFilamentLayer], but its roots and tips
/// live on the modeled centerline rather than inside one atlas stamp.
@immutable
class PawDabStreamingFilamentLayer {
  const PawDabStreamingFilamentLayer({
    required this.countPerRoot,
    required this.rootSpacingFactor,
    required this.lengthFactors,
    required this.widthFactors,
    required this.spreadFactor,
    required this.coverage,
    this.centerDensityExponent = 1,
    this.directionJitterRadians = 0,
    this.shearAngleRadians = 0,
    this.bendFactor = 0,
    this.widthTaper = 1,
    this.opacityTaper = 1,
    this.taperExponent = 1,
    this.rootFadeFraction = 0,
    this.segmentLengthFactor = .25,
    this.grooming = const PawPersistentLaneGroomingParameters(),
    this.familyCoherence = 0,
    this.minimumPressureDensity = 1,
    this.softnessFactor = 0,
    this.clumpScaleFactor = 1.6,
    this.bendBias = 0,
    this.wanderAmplitudeFactor = 0,
    this.turnCompliance = 0,
  });

  final int countPerRoot;
  final double rootSpacingFactor;
  final PawDabRange lengthFactors;
  final PawDabRange widthFactors;
  final double spreadFactor;
  final double coverage;
  final double centerDensityExponent;
  final double directionJitterRadians;

  /// Signed angle applied to the whole filament family relative to stroke
  /// motion. Unlike an outward splay, every hair leans to the same side.
  final double shearAngleRadians;
  final double bendFactor;
  final double widthTaper;
  final double opacityTaper;
  final double taperExponent;
  final double rootFadeFraction;
  final double segmentLengthFactor;
  final PawPersistentLaneGroomingParameters grooming;
  final double familyCoherence;
  final double minimumPressureDensity;

  /// Extra transverse filter support in brush widths, with conserved pigment.
  final double softnessFactor;

  /// Correlation length of neighboring crossing hairs in brush widths.
  final double clumpScaleFactor;

  /// Blend a balanced S bend into a signed C bend, without mirrored root rows.
  final double bendBias;

  /// Small intrinsic strand irregularity, independent of whole-hair rotation.
  final double wanderAmplitudeFactor;

  /// Bounded response of a whole crossing strand to its root's turn curvature.
  final double turnCompliance;

  double pressureDensityCoverage({
    required double pressure,
    required int filamentHash,
  }) {
    if (minimumPressureDensity == 1) return 1;
    final density = minimumPressureDensity +
        (1 - minimumPressureDensity) * pressure.clamp(0.0, 1.0);
    final rank = PawDabResource._unitWindow(filamentHash, 43);
    return _smoothStep(
      ((density - rank) / .12 + .5).clamp(0.0, 1.0),
    );
  }

  double coherentUnitSample({
    required int familyHash,
    required int filamentHash,
    required int window,
  }) {
    final individual = PawDabResource._unitWindow(filamentHash, window);
    if (familyCoherence == 0) return individual;
    final family = PawDabResource._unitWindow(familyHash, window);
    return individual + (family - individual) * familyCoherence;
  }

  double coherentAngleSample({
    required int familyHash,
    required int filamentHash,
    required int window,
  }) {
    final individual =
        PawDabResource._unitWindow(filamentHash, window) * math.pi * 2;
    if (familyCoherence == 0) return individual;
    final family = PawDabResource._unitWindow(familyHash, window) * math.pi * 2;
    final shortestDelta = math.atan2(
      math.sin(family - individual),
      math.cos(family - individual),
    );
    return individual + shortestDelta * familyCoherence;
  }

  double coherentLateralUnit({
    required int familyHash,
    required double individualUnit,
  }) {
    if (familyCoherence == 0) return individualUnit;
    final familyUnit = PawDabResource._unitWindow(familyHash, 37) * 2 - 1;
    return individualUnit + (familyUnit - individualUnit) * familyCoherence;
  }

  int familyHashForRoot({
    required int layerHashSeed,
    required int rootIndex,
  }) =>
      PawDabResource._hash(layerHashSeed, rootIndex * 97);

  double rootArcFor({
    required double brushSize,
    required int rootIndex,
    required int familyHash,
  }) {
    final rootPeriod = math.max(.25, brushSize * rootSpacingFactor);
    return rootIndex * rootPeriod +
        PawDabResource._unitWindow(familyHash, 7) * rootPeriod * .72;
  }

  double get maximumAlongReach =>
      lengthFactors.maximum +
      widthFactors.maximum / 2 +
      softnessFactor +
      .75 * clumpScaleFactor * familyCoherence;

  double get maximumNormalReach =>
      spreadFactor / 2 * (1 + grooming.outerSplayFactor) +
      spreadFactor * .04 +
      widthFactors.maximum / 2 +
      bendFactor * (1 + bendBias.abs()) +
      softnessFactor +
      .65 * turnCompliance +
      2 * wanderAmplitudeFactor +
      math.sin(math.min(
              math.pi / 2, shearAngleRadians.abs() + familyCoherence * .425)) *
          lengthFactors.maximum +
      math.tan(directionJitterRadians) * lengthFactors.maximum;

  void validate() {
    lengthFactors.validate('streaming filament length', minimumAllowed: .0001);
    widthFactors.validate('streaming filament width', minimumAllowed: .0001);
    grooming.validate();
    if (countPerRoot < 0 ||
        countPerRoot > 64 ||
        !_finitePositive(rootSpacingFactor) ||
        !_finiteNonNegative(spreadFactor) ||
        !_finiteInRange(coverage, 0, 1) ||
        !_finiteInRange(centerDensityExponent, 1, 5) ||
        !_finiteInRange(directionJitterRadians, 0, math.pi / 2) ||
        !_finiteInRange(shearAngleRadians, -math.pi / 2, math.pi / 2) ||
        !_finiteNonNegative(bendFactor) ||
        !_finiteInRange(widthTaper, 0, 1) ||
        !_finiteInRange(opacityTaper, 0, 1) ||
        !_finiteInRange(taperExponent, .2, 6) ||
        !_finiteInRange(rootFadeFraction, 0, .45) ||
        !_finiteInRange(segmentLengthFactor, .05, 1) ||
        !_finiteInRange(familyCoherence, 0, .9) ||
        !_finiteInRange(minimumPressureDensity, 0, 1) ||
        !_finiteInRange(softnessFactor, 0, .15) ||
        !_finiteInRange(clumpScaleFactor, .08, 4) ||
        !_finiteInRange(bendBias, -1, 1) ||
        !_finiteInRange(wanderAmplitudeFactor, 0, .25) ||
        !_finiteInRange(turnCompliance, 0, 1)) {
      throw ArgumentError('Invalid streaming filament layer.');
    }
  }
}
