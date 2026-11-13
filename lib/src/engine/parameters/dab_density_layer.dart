part of '../../streaming_dab_brush.dart';

@immutable
class PawDabDensityLayer {
  const PawDabDensityLayer({
    required this.count,
    this.alongCenterFactor = 0,
    this.alongSpreadFactor = 0,
    this.normalCenterFactor = 0,
    this.normalSpreadFactor = 0,
    required this.lengthFactors,
    required this.widthFactors,
    required this.coverage,
    this.softnessFactor = 0,
    this.angleJitterRadians = 0,
  });

  final int count;
  final double alongCenterFactor;
  final double alongSpreadFactor;
  final double normalCenterFactor;
  final double normalSpreadFactor;
  final PawDabRange lengthFactors;
  final PawDabRange widthFactors;
  final PawDabRange coverage;
  final double softnessFactor;
  final double angleJitterRadians;

  double get maximumReachX {
    final baseX = alongCenterFactor.abs() +
        alongSpreadFactor / 2 +
        lengthFactors.maximum / 2 +
        softnessFactor * 3;
    final baseY = normalCenterFactor.abs() +
        normalSpreadFactor / 2 +
        widthFactors.maximum / 2 +
        softnessFactor * 3;
    return baseX + baseY * math.sin(math.min(angleJitterRadians, math.pi / 2));
  }

  double get maximumReachY {
    final baseX = alongCenterFactor.abs() +
        alongSpreadFactor / 2 +
        lengthFactors.maximum / 2 +
        softnessFactor * 3;
    final baseY = normalCenterFactor.abs() +
        normalSpreadFactor / 2 +
        widthFactors.maximum / 2 +
        softnessFactor * 3;
    return baseY + baseX * math.sin(math.min(angleJitterRadians, math.pi / 2));
  }

  void validate() {
    lengthFactors.validate('density length', minimumAllowed: .0001);
    widthFactors.validate('density width', minimumAllowed: .0001);
    coverage.validate('density coverage', maximumAllowed: 1);
    if (count < 0 ||
        count > 32 ||
        !_finiteNonNegative(alongSpreadFactor) ||
        !_finiteNonNegative(normalSpreadFactor) ||
        !alongCenterFactor.isFinite ||
        !normalCenterFactor.isFinite ||
        !_finiteInRange(softnessFactor, 0, 1) ||
        !_finiteInRange(angleJitterRadians, 0, math.pi)) {
      throw ArgumentError('Invalid dab density layer.');
    }
  }
}
