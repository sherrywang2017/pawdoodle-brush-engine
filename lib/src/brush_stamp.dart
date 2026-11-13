import 'dart:math' as math;

/// Cache-owned result of one brush/contact evaluation.
///
/// One instance is reset for every DAB and overwritten for every vertex of
/// that DAB. The renderer reads primitive fields only, keeping pointer-move
/// sampling allocation-free.
class PawBrushStamp {
  double coverage = 1;
  double pigmentAmount = 1;
  double grainAmount = 0;
  double rotation = 0;
  double pressure = 1;
  double _grainStrength = 0;
  double _deposition = 1;
  double _edgeSoftness = 0;
  double _materialSaturation = 0;

  void beginDab({
    required double rotation,
    required double pressure,
    double grainStrength = 0,
    double deposition = 1,
    double edgeSoftness = 0,
    double materialDensity = 0,
  }) {
    coverage = 1;
    pigmentAmount = 1;
    grainAmount = 0;
    this.rotation = rotation;
    this.pressure = pressure.clamp(0.0, 1.0).toDouble();
    _grainStrength = grainStrength.clamp(0.0, 1.0).toDouble();
    _deposition = deposition.clamp(0.0, 2.0).toDouble();
    _edgeSoftness = edgeSoftness.clamp(0.0, .5).toDouble();
    _materialSaturation = 1 - math.exp(-math.max(0.0, materialDensity) * .34);
  }

  /// Couples shape support, prepared grain, edge breakup and deposition.
  ///
  /// Grain is conditioned by actual contact: it affects silhouette breakup
  /// most near the edge, density across the shoulder, and pigment variation
  /// inside the body. This is intentionally not a chain of independent alpha
  /// multipliers.
  void evaluateContact({
    required double shapeCoverage,
    required double grainSample,
    required double radial,
  }) {
    final shape = shapeCoverage.clamp(0.0, 1.5).toDouble();
    if (shape <= 0) {
      coverage = 0;
      pigmentAmount = 0;
      grainAmount = 0;
      return;
    }
    final grain = grainSample.clamp(0.0, 1.0).toDouble();
    final strength = _grainStrength;
    final contact = shape.clamp(0.0, 1.0).toDouble();
    final edge = _smoothStep(
      (.52 - _edgeSoftness * .25).clamp(.36, .65),
      1,
      radial.clamp(0.0, 1.0),
    );
    final centered = (grain - .5) * 2;

    // Grain only breaks the boundary when shape contact is already weak;
    // dense core material receives restrained pigment variation instead.
    final densityResponse = 1 + centered * strength * (.16 + .22 * contact);
    final edgeResponse =
        1 + math.min(0.0, centered) * strength * edge * (1.05 - _edgeSoftness);
    final saturation = _materialSaturation;
    final materialResponse =
        1 + centered * strength * (.08 + .1 * (1 - saturation));

    grainAmount =
        strength * (.3 + .7 * contact) * (1 + edge * .45).clamp(0.0, 1.45);
    coverage = (shape * densityResponse * edgeResponse).clamp(0.0, 1.5);
    pigmentAmount = (_deposition * materialResponse * (1 + saturation * .08))
        .clamp(0.0, 2.0);
  }
}

double _smoothStep(num lower, num upper, num value) {
  final span = upper - lower;
  if (span.abs() <= .000001) return value < lower ? 0 : 1;
  final unit = ((value - lower) / span).clamp(0.0, 1.0).toDouble();
  return unit * unit * (3 - 2 * unit);
}
