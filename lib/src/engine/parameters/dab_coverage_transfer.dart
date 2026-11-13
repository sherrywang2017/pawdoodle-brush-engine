part of '../../streaming_dab_brush.dart';

/// Independent legacy remaps for the paper and texture factors. Paper and
/// texture still execute in separate multiplicative GPU stages; the two
/// floors are not a post-product joint carrier.
@immutable
class PawDabCoverageTransferParameters {
  const PawDabCoverageTransferParameters({
    this.paperContactFloor = 0,
    this.textureFloor = 0,
    this.expectedDabOverlaps = 1,
  });

  final double paperContactFloor;
  final double textureFloor;
  final double expectedDabOverlaps;

  double remapPaperContact(double rawCoverage) =>
      paperContactFloor + (1 - paperContactFloor) * rawCoverage;

  double remapTexture(double rawCoverage) =>
      textureFloor + (1 - textureFloor) * rawCoverage;

  /// Converts a desired local stroke coverage into the source alpha for one
  /// of the overlapping Dabs that will build it. Destination-over blending
  /// then reconstructs [coverage] without a destination readback, and later
  /// passes continue depositing into the remaining uncovered fraction.
  double linearizeDabCoverage(double coverage) {
    final target = coverage.clamp(0.0, 1.0).toDouble();
    if (expectedDabOverlaps <= 1 || target == 0 || target == 1) return target;
    return 1 - math.pow(1 - target, 1 / expectedDabOverlaps).toDouble();
  }

  void validate() {
    if (!_finiteInRange(paperContactFloor, 0, 1) ||
        !_finiteInRange(textureFloor, 0, 1) ||
        !_finiteInRange(expectedDabOverlaps, 1, 64)) {
      throw ArgumentError('Invalid dab coverage transfer parameters.');
    }
  }
}
