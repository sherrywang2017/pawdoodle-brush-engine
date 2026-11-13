part of '../../streaming_dab_brush.dart';

/// Local dry-wax response for DAB_DRY.
///
/// Coverage describes surface occupation; thickness describes the optical
/// strength of wax on the occupied paper. Both are deterministic scalars and
/// rely on the existing source-over DAB accumulation rather than persistent
/// per-pixel material state.
@immutable
class PawDabDryWaxParameters {
  const PawDabDryWaxParameters({
    this.enabled = false,
    this.coveragePressureFloor = 1,
    this.coveragePressureExponent = 1,
    this.grainSuppressionAtFullPressure = 0,
    this.thicknessPressureFloor = 1,
    this.thicknessPressureExponent = 1,
    this.opticalDensity = 1,
    this.coverageOpticalGain = 1,
    this.dragStrength = 0,
    this.dragLength = .22,
    this.dragWidth = .025,
  });

  static const physicalCrayon = PawDabDryWaxParameters(
    enabled: true,
    coveragePressureFloor: .52,
    coveragePressureExponent: .74,
    grainSuppressionAtFullPressure: .44,
    thicknessPressureFloor: .66,
    thicknessPressureExponent: .82,
    opticalDensity: 5.2,
    coverageOpticalGain: 2.3,
    dragStrength: .9,
    dragLength: .36,
    dragWidth: .018,
  );

  final bool enabled;
  final double coveragePressureFloor;
  final double coveragePressureExponent;
  final double grainSuppressionAtFullPressure;
  final double thicknessPressureFloor;
  final double thicknessPressureExponent;
  final double opticalDensity;
  final double coverageOpticalGain;

  /// Pressure dragging across paper, with dimensions in brush widths.
  final double dragStrength, dragLength, dragWidth;

  double waxGrainResponse({
    required double pressure,
    required double waxGrainAndScrape,
  }) {
    final grain = waxGrainAndScrape.clamp(0.0, 1.0).toDouble();
    if (!enabled || grainSuppressionAtFullPressure == 0) return grain;
    final pressureProgress =
        math.pow(pressure.clamp(0.0, 1.0), coveragePressureExponent).toDouble();
    return (grain +
            (1 - grain) * grainSuppressionAtFullPressure * pressureProgress)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double waxCoverageResponse({
    required double paperContact,
    required double pressure,
    required double waxGrainAndScrape,
  }) {
    if (!enabled) return paperContact * waxGrainAndScrape;
    final pressureProgress =
        math.pow(pressure.clamp(0.0, 1.0), coveragePressureExponent).toDouble();
    final pressureResponse =
        coveragePressureFloor + (1 - coveragePressureFloor) * pressureProgress;
    final grain = waxGrainAndScrape.clamp(0.0, 1.0).toDouble();
    final compressedGrain =
        grain + (1 - grain) * grainSuppressionAtFullPressure * pressureProgress;
    return (paperContact * pressureResponse * compressedGrain)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double waxThicknessResponse({
    required double sourceAlpha,
    required double pressure,
  }) {
    final waxMass = linearWaxMass(sourceAlpha: sourceAlpha, pressure: pressure);
    if (!enabled) return waxMass;
    return (1 - math.exp(-opticalDensity * waxMass)).clamp(0.0, 1.0).toDouble();
  }

  /// Contact rasters carry mass; optical density is applied once, after paper
  /// contact in the pixel stage. The bitmap path retains the resolved response.
  double linearWaxMass(
      {required double sourceAlpha, required double pressure}) {
    if (!enabled) return sourceAlpha.clamp(0.0, 1.0).toDouble();
    final pressureResponse = thicknessPressureFloor +
        (1 - thicknessPressureFloor) *
            math.pow(pressure.clamp(0.0, 1.0), thicknessPressureExponent);
    return (sourceAlpha.clamp(0.0, 1.0) * pressureResponse).toDouble();
  }

  double opticalCoverageResponse(double coverage) {
    final value = coverage.clamp(0.0, 1.0).toDouble();
    if (!enabled || coverageOpticalGain == 1 || value == 0 || value == 1) {
      return value;
    }
    return (1 - math.pow(1 - value, coverageOpticalGain))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void validate() {
    if (!_finiteInRange(coveragePressureFloor, 0, 1) ||
        !_finitePositive(coveragePressureExponent) ||
        !_finiteInRange(grainSuppressionAtFullPressure, 0, 1) ||
        !_finiteInRange(thicknessPressureFloor, 0, 1) ||
        !_finitePositive(thicknessPressureExponent) ||
        !_finitePositive(opticalDensity) ||
        !_finiteInRange(coverageOpticalGain, .5, 4) ||
        !_finiteInRange(dragStrength, 0, 1) ||
        !_finiteInRange(dragLength, .01, 2) ||
        !_finiteInRange(dragWidth, .002, .5)) {
      throw ArgumentError('Invalid dry-wax material parameters.');
    }
  }
}
