part of '../../streaming_dab_brush.dart';

@immutable
class PawDabBrushDefinition {
  const PawDabBrushDefinition({
    required this.id,
    required this.revision,
    required this.fixedStep,
    required this.template,
    this.grain = const PawDabGrainParameters(),
    this.paperContact = const PawPaperContactParameters(),
    this.coverageTransfer = const PawDabCoverageTransferParameters(),
    this.dryWax = const PawDabDryWaxParameters(),
    this.wetMedia = const PawDabWetMediaParameters(),
    this.useWholeDabDryMediaCoverage = true,
    this.preparedFullTip = false,
    required this.emission,
    required this.maximumDabsPerChunk,
    required this.realtimePresentationTailDabBudget,
    required this.maximumBatchPictures,
    required this.compactionBatchSize,
    required this.identitySalt,
  });

  final String id;
  final int revision;
  final PawFixedStepModelParameters fixedStep;
  final PawDabTemplateParameters template;
  final PawDabGrainParameters grain;
  final PawPaperContactParameters paperContact;
  final PawDabCoverageTransferParameters coverageTransfer;
  final PawDabDryWaxParameters dryWax;
  final PawDabWetMediaParameters wetMedia;
  final bool useWholeDabDryMediaCoverage;
  final bool preparedFullTip;
  final PawDabEmissionParameters emission;
  final int maximumDabsPerChunk;

  /// Legacy constructor value retained as the production live-presentation
  /// budget. The full/final material safety tail is geometry-derived and may
  /// be larger; it is never rendered on the active-pointer path.
  final int realtimePresentationTailDabBudget;

  final int maximumBatchPictures;
  final int compactionBatchSize;
  final int identitySalt;

  double get maximumReachFactor =>
      math.sqrt(_maximumDynamicReachX * _maximumDynamicReachX +
              _maximumDynamicReachY * _maximumDynamicReachY) *
          emission.pressureSizeMaxFactor *
          (1 + emission.dynamics.sizeJitterFactor / 2) +
      emission.maximumScatterReach +
      emission.dynamics.maximumPositiveSpacingOffsetFactor;

  double get _maximumDynamicReachX {
    var result = template.maximumReachX;
    for (final layer in template.streamingFilamentLayers) {
      result = math.max(
        result,
        layer.maximumAlongReach *
            emission.pressureSizeMaxFactor *
            emission.dynamics.maximumFilamentLengthResponse,
      );
    }
    return result;
  }

  double get _maximumDynamicReachY {
    var result = template.maximumReachY;
    for (final layer in template.streamingFilamentLayers) {
      result = math.max(
        result,
        layer.maximumNormalReach *
            emission.pressureSizeMaxFactor *
            emission.dynamics.maximumFilamentSpreadResponse,
      );
    }
    return result;
  }

  double get maximumStreamingFilamentLength =>
      template.streamingFilamentLayers.fold<double>(
          0,
          (maximum, layer) => math.max(
                maximum,
                layer.lengthFactors.maximum *
                    emission.pressureSizeMaxFactor *
                    emission.dynamics.maximumFilamentLengthResponse,
              ));

  double get maximumPersistentTailHorizon =>
      template.persistentLaneLayers.fold<double>(
        0,
        (maximum, layer) => math.max(
          maximum,
          math.max(layer.tipFadeArcFactor, layer.segmentLengthFactor),
        ),
      );

  /// Material/emission reach behind an immutable centerline frontier.
  ///
  /// This affects only when rendered DAB batches are safe to retain. It must
  /// never expand the centerline correction window.
  double emissionMaterialSafetyHorizonFor(double brushSize) =>
      brushSize *
      math.max(
        maximumStreamingFilamentLength,
        maximumPersistentTailHorizon,
      );

  void validate() {
    fixedStep.validate();
    template.validate();
    if (preparedFullTip && template.logicalExtent > 8) {
      throw ArgumentError('Prepared tip extent must not exceed 8.');
    }
    grain.validate();
    paperContact.validate();
    coverageTransfer.validate();
    dryWax.validate();
    wetMedia.validate();
    emission.validate();
    if (id.isEmpty ||
        revision <= 0 ||
        maximumDabsPerChunk < 1 ||
        realtimePresentationTailDabBudget < 1 ||
        maximumBatchPictures < 2 ||
        compactionBatchSize < 2 ||
        !maximumReachFactor.isFinite ||
        maximumReachFactor <= 0) {
      throw ArgumentError('Invalid dab brush definition.');
    }
  }
}
