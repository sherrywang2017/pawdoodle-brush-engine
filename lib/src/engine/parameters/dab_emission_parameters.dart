part of '../../streaming_dab_brush.dart';

@immutable
class PawDabEmissionParameters {
  const PawDabEmissionParameters({
    required this.spacingFactor,
    required this.variantCount,
    this.alongScatterFactor = 0,
    this.normalScatterFactor = 0,
    this.rotationJitterRadians = 0,
    this.baseRotationRadians = 0,
    this.directionRotationFactor = 1,
    this.arcDensityPeriodFactor = 1,
    this.arcDensityAmplitude = 0,
    this.canvasDensityScaleFactor = 1,
    this.canvasDensityAmplitude = 0,
    this.pressureSizeMinFactor = 1,
    this.pressureSizeMaxFactor = 1,
    this.pressureOpacityMinFactor = 1,
    this.pressureOpacityMaxFactor = 1,
    this.dynamics = const PawDabDynamicsParameters(),
    this.footprintEdgeRoughness = 0,
    this.footprintEdgeRoughnessFrequency = 5,
  });

  final double spacingFactor;
  final int variantCount;
  final double alongScatterFactor;
  final double normalScatterFactor;
  final double rotationJitterRadians;
  final double baseRotationRadians;
  final double directionRotationFactor;
  final double arcDensityPeriodFactor;
  final double arcDensityAmplitude;
  final double canvasDensityScaleFactor;
  final double canvasDensityAmplitude;
  final double pressureSizeMinFactor;
  final double pressureSizeMaxFactor;
  final double pressureOpacityMinFactor;
  final double pressureOpacityMaxFactor;
  final PawDabDynamicsParameters dynamics;
  final double footprintEdgeRoughness;
  final int footprintEdgeRoughnessFrequency;

  double get maximumScatterReach =>
      math.sqrt(alongScatterFactor * alongScatterFactor +
          normalScatterFactor * normalScatterFactor) /
      2;

  void validate() {
    if (!_finitePositive(spacingFactor) ||
        variantCount < 1 ||
        variantCount > 32 ||
        !_finiteNonNegative(alongScatterFactor) ||
        !_finiteNonNegative(normalScatterFactor) ||
        !_finiteInRange(rotationJitterRadians, 0, math.pi) ||
        !_finiteInRange(baseRotationRadians, -math.pi, math.pi) ||
        !_finiteInRange(directionRotationFactor, -1, 1) ||
        !_finitePositive(arcDensityPeriodFactor) ||
        !_finiteInRange(arcDensityAmplitude, 0, .95) ||
        !_finitePositive(canvasDensityScaleFactor) ||
        !_finiteInRange(canvasDensityAmplitude, 0, .95) ||
        !_finitePositive(pressureSizeMinFactor) ||
        !_finitePositive(pressureSizeMaxFactor) ||
        pressureSizeMaxFactor < pressureSizeMinFactor ||
        !_finiteNonNegative(pressureOpacityMinFactor) ||
        !_finiteNonNegative(pressureOpacityMaxFactor) ||
        pressureOpacityMaxFactor < pressureOpacityMinFactor ||
        !_finiteInRange(footprintEdgeRoughness, 0, .25) ||
        footprintEdgeRoughnessFrequency < 1 ||
        footprintEdgeRoughnessFrequency > 24) {
      throw ArgumentError('Invalid dab emission parameters.');
    }
    dynamics.validate();
  }
}
