part of '../../streaming_dab_brush.dart';

enum PawDabGrainCoordinate { canvasFixed, rolling }

/// Structure synthesized into the cached grain carrier.
///
/// [generic] preserves the original pore-mask behavior. The material-specific
/// structures are data, not renderer branches keyed by a built-in brush id,
/// so authored brushes can reuse the same preparation and streaming paths.
enum PawDabGrainStructure {
  generic,
  waxAggregate,
  fibrousWash,
  absorbentWash,
}

@immutable
class PawDabGrainParameters {
  const PawDabGrainParameters({
    this.coordinate = PawDabGrainCoordinate.canvasFixed,
    this.structure = PawDabGrainStructure.generic,
    this.coarseStrength = 0,
    this.coarseScaleFactor = 1,
    this.coarseSeed = 0,
    this.fineStrength = 0,
    this.fineScaleFactor = .25,
    this.fineSeed = 0,
    this.poreAspectRatios = const PawDabRange(1, 1),
    this.poreAngleJitterRadians = 0,
    this.rotationRadians = 0,
    this.movement = 0,
    this.strokeAlignedStrength = 0,
    this.strokeAlignedAlongScaleFactor = .4,
    this.strokeAlignedNormalScaleFactor = .12,
    this.strokeAlignedSeed = 0,
  });

  final PawDabGrainCoordinate coordinate;
  final PawDabGrainStructure structure;
  final double coarseStrength;
  final double coarseScaleFactor;
  final int coarseSeed;
  final double fineStrength;
  final double fineScaleFactor;
  final int fineSeed;
  final PawDabRange poreAspectRatios;
  final double poreAngleJitterRadians;
  final double rotationRadians;
  final double movement;
  final double strokeAlignedStrength;
  final double strokeAlignedAlongScaleFactor;
  final double strokeAlignedNormalScaleFactor;
  final int strokeAlignedSeed;

  bool get isEnabled => coarseStrength > 0 || fineStrength > 0;

  /// A second grain domain that travels with the material pose.
  ///
  /// Canvas-fixed grain describes paper tooth. This field describes material
  /// dragged by the tip, such as elongated wax flakes. Keeping both domains
  /// separate avoids baking stroke direction into the document texture.
  double strokeAlignedCoverageAt({
    required double absoluteArc,
    required double signedNormal,
    required double brushSize,
    required int strokeSeed,
  }) {
    if (strokeAlignedStrength <= 0) return 1;
    final along = absoluteArc /
        math.max(.0001, brushSize * strokeAlignedAlongScaleFactor);
    final normal = signedNormal /
        math.max(.0001, brushSize * strokeAlignedNormalScaleFactor);
    final seed = strokeSeed ^ strokeAlignedSeed ^ coarseSeed ^ 0x62d41;
    final broad = PawDabResource._valueNoise2D(along, normal, seed);
    final detail = PawDabResource._valueNoise2D(
      along * 2.13 + 7.1,
      normal * 1.77 - 3.9,
      seed ^ fineSeed ^ 0x6d2b79f5,
    );
    final structure = broad * .72 + detail * .28;
    final flake = _smoothStep(
      ((structure - .16) / .72).clamp(0.0, 1.0),
    );
    final materialCoverage = .72 + flake * .28;
    return 1 - strokeAlignedStrength * (1 - materialCoverage);
  }

  void validate() {
    if (!_finiteInRange(coarseStrength, 0, 1) ||
        !_finitePositive(coarseScaleFactor) ||
        !_finiteInRange(fineStrength, 0, 1) ||
        !_finitePositive(fineScaleFactor) ||
        !_finiteInRange(poreAspectRatios.minimum, .1, 8) ||
        !_finiteInRange(poreAspectRatios.maximum, .1, 8) ||
        poreAspectRatios.maximum < poreAspectRatios.minimum ||
        !_finiteInRange(poreAngleJitterRadians, 0, math.pi) ||
        !_finiteInRange(rotationRadians, -math.pi, math.pi) ||
        !_finiteInRange(movement, -2, 2) ||
        !_finiteInRange(strokeAlignedStrength, 0, 1) ||
        !_finiteInRange(strokeAlignedAlongScaleFactor, .02, 8) ||
        !_finiteInRange(strokeAlignedNormalScaleFactor, .02, 8)) {
      throw ArgumentError('Invalid dab grain parameters.');
    }
  }
}
