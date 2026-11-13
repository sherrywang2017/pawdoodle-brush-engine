part of '../../streaming_dab_brush.dart';

/// Brush-owned response to the canvas-owned paper height field.
@immutable
class PawPaperContactParameters {
  const PawPaperContactParameters({
    this.minimumContact = 1,
    this.maximumContact = 1,
    this.pressureExponent = 1,
    this.depositionWeight = 0,
    this.toothContrast = 1,
    this.transitionSoftness = .08,
    this.maximumSampleSpacing = 6,
    this.toothCoarseWeight = 1,
    this.toothMediumWeight = 1,
    this.toothFineWeight = 1,
    this.coarseDepositionStrength = 0,
  });

  final double minimumContact;
  final double maximumContact;
  final double pressureExponent;
  final double depositionWeight;
  final double toothContrast;
  final double transitionSoftness;
  final double maximumSampleSpacing;
  final double toothCoarseWeight;
  final double toothMediumWeight;
  final double toothFineWeight;
  final double coarseDepositionStrength;

  bool get isEnabled =>
      minimumContact < 1 || maximumContact < 1 || coarseDepositionStrength > 0;

  void validate() {
    if (!_finiteInRange(minimumContact, 0, 1) ||
        !_finiteInRange(maximumContact, minimumContact, 1) ||
        !_finiteInRange(pressureExponent, .2, 5) ||
        !_finiteInRange(depositionWeight, 0, 1) ||
        !_finiteInRange(toothContrast, .2, 6) ||
        !_finiteInRange(transitionSoftness, .005, .35) ||
        !_finiteInRange(maximumSampleSpacing, .5, 64) ||
        !_finiteInRange(toothCoarseWeight, 0, 1) ||
        !_finiteInRange(toothMediumWeight, 0, 1) ||
        !_finiteInRange(toothFineWeight, 0, 1) ||
        !_finiteInRange(coarseDepositionStrength, 0, 1)) {
      throw ArgumentError('Invalid paper contact parameters.');
    }
  }

  double contactLevel({required double pressure, required double deposition}) {
    final pressureLevel = math.pow(pressure.clamp(0.0, 1.0), pressureExponent);
    final depositionLevel = (deposition / 4).clamp(0.0, 1.0);
    final response = pressureLevel * (1 - depositionWeight) +
        depositionLevel * depositionWeight;
    return minimumContact + (maximumContact - minimumContact) * response;
  }

  double coverageAt({
    required PawPaperField paper,
    required Offset canvasPoint,
    required double pressure,
    required double deposition,
  }) {
    final sample = paper.sample(canvasPoint);
    return _toothCoverage(
          paper: paper,
          sample: sample,
          pressure: pressure,
          deposition: deposition,
        ) *
        _coarseDeposition(sample);
  }

  double toothCoverageAt({
    required PawPaperField paper,
    required Offset canvasPoint,
    required double pressure,
    required double deposition,
  }) {
    return _toothCoverage(
      paper: paper,
      sample: paper.sample(canvasPoint),
      pressure: pressure,
      deposition: deposition,
    );
  }

  double _toothCoverage({
    required PawPaperField paper,
    required PawPaperHeightSample sample,
    required double pressure,
    required double deposition,
  }) {
    final level = contactLevel(pressure: pressure, deposition: deposition);
    final edge0 = level - transitionSoftness;
    final edge1 = level + transitionSoftness;
    final toothHeight = sample.weightedHeight(
      definition: paper.definition,
      coarseResponseWeight: toothCoarseWeight,
      mediumResponseWeight: toothMediumWeight,
      fineResponseWeight: toothFineWeight,
    );
    final t = ((edge1 - toothHeight) / math.max(.000001, edge1 - edge0))
        .clamp(0.0, 1.0);
    final smooth = t * t * (3 - 2 * t);
    return math.pow(smooth, toothContrast).toDouble().clamp(0.0, 1.0);
  }

  double coarseDepositionAt({
    required PawPaperField paper,
    required Offset canvasPoint,
  }) {
    if (coarseDepositionStrength == 0) return 1;
    return (1 - coarseDepositionStrength * paper.sampleCoarse(canvasPoint))
        .clamp(0.0, 1.0);
  }

  double _coarseDeposition(PawPaperHeightSample sample) =>
      (1 - coarseDepositionStrength * sample.coarse).clamp(0.0, 1.0);
}
