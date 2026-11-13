part of '../../streaming_dab_brush.dart';

class PawStreamingDabStroke
    implements
        PawStreamingBrushStroke,
        PawTemporalBrushStroke,
        PawStreamingBrushRuntimeMetrics,
        PawStreamingInputRuntimeMetrics,
        PawStreamingBrushPreviewSource,
        PawHeldStrokeAssistTarget,
        PawDabEmissionSource {
  PawStreamingDabStroke({
    required this.definition,
    required this.seed,
    required this.color,
    required this.brushSize,
    required this.opacity,
    PawBrushEnvironmentSnapshot? environment,
  })  : environment =
            environment ?? PawBrushEnvironmentSnapshot.defaultEnvironment,
        _modeler = PawStreamingCenterlineModeler(
          geometryCorrectionHorizon: 12,
          // Material must end at a measured input, including on PointerUp.
          // Predicted positions are not observations and cannot own pigment.
          predictionHorizon: 0,
          strokeBoundsRadius: brushSize * definition.maximumReachFactor,
          stableCausalJoins: true,
          fixedStep: definition.fixedStep,
          curvedIntervalTargets: true,
          curvedTargetMaxHandleFactor: .5,
        ) {
    definition.validate();
    // The immutable atlas is prepared at PointerDown. Render caches only clone
    // an already-prepared image handle, so PointerMove never creates a resource.
    PawDabResource.prepare(
      definition,
      rasterProgram: this.environment.rasterProgram,
    );
  }

  @override
  final PawDabBrushDefinition definition;
  @override
  final Object emissionIdentity = Object();
  final PawStreamingCenterlineModeler _modeler;
  // A mutable segment replaces its index. Object keys retained every old
  // tail, while enumeration converted the immutable prefix again per frame.
  final Map<int, (PawStreamingSegmentCommand, PawBrushEmissionSegment)>
      _emissionCache = {};

  PawBrushEmissionSegment _emissionFor(PawStreamingSegmentCommand command) {
    final previous = _emissionCache[command.index];
    if (previous != null && identical(previous.$1, command)) return previous.$2;
    final emission = PawBrushEmissionSegment.fromCommand(command,
        parameterizeByArcLength: centerlineReplacementEpoch > 0);
    _emissionCache[command.index] = (command, emission);
    return emission;
  }

  @override
  final PawStrokeTextureSeed seed;
  @override
  final Color color;
  @override
  final double brushSize;
  @override
  final double opacity;
  @override
  final PawBrushEnvironmentSnapshot environment;
  bool _frozen = false;
  Duration _materialClock = Duration.zero;
  Duration _lastInputTime = Duration.zero;
  int _materialRevision = 0;

  @override
  bool get hasUnsettledMaterial =>
      !_frozen &&
      !isEmpty &&
      definition.wetMedia.enabled &&
      definition.wetMedia.settlingDuration > Duration.zero &&
      _materialClock < _lastInputTime + definition.wetMedia.settlingDuration;

  @override
  bool advanceMaterialClock(Duration elapsed) {
    if (!hasUnsettledMaterial || elapsed <= Duration.zero) return false;
    final end = _lastInputTime + definition.wetMedia.settlingDuration;
    final advanced = _materialClock + elapsed;
    _materialClock = advanced < end ? advanced : end;
    _materialRevision++;
    return true;
  }

  double settlementAtArc(double arc) {
    final duration = definition.wetMedia.settlingDuration.inMicroseconds;
    if (!definition.wetMedia.enabled || duration == 0) return 1;
    final segment = emissionSegmentAtArc(arc);
    final deposited = segment == null
        ? _lastInputTime
        : segment.timestampAt(
            (arc - segment.arcStart) / math.max(.000001, segment.arcLength));
    return _smoothStep(((_materialClock - deposited).inMicroseconds / duration)
        .clamp(0.0, 1.0));
  }

  double get settledMaterialEndArc {
    if (!definition.wetMedia.enabled ||
        definition.wetMedia.settlingDuration == Duration.zero) {
      return renderEndArc;
    }
    var low = 0.0, high = renderEndArc;
    for (var i = 0; i < 22; i++) {
      final middle = (low + high) * .5;
      if (settlementAtArc(middle) >= 1) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  @override
  double get acceptedEndArc => _modeler.acceptedEndArc;
  @override
  double get sealedEndArc => _modeler.sealedEndArc;
  @override
  double get renderEndArc => _modeler.renderEndArc;
  @override
  double get causalStableEndArc => _modeler.causalStableEndArc;
  double get geometryCorrectionHorizon => _modeler.geometryCorrectionHorizon;
  double get maximumMutableTipArc => _modeler.maximumMutableTipArc;
  double get rawFidelityCorridor => _modeler.rawFidelityCorridor;
  double get predictionHorizon => _modeler.predictionHorizon;
  double get maximumTurnEvidenceArc => _modeler.maximumTurnEvidenceArc;
  double get emissionMaterialSafetyHorizon =>
      PawStreamingDabRenderCache._materialDependencyArc(this);

  @override
  Iterable<PawStreamingSegmentCommand> get previewSegments =>
      _modeler.renderSegments;

  @override
  Iterable<PawBrushEmissionSegment> get emissionSegments =>
      previewSegments.map(_emissionFor);

  @override
  int get lastModelStepCount => _modeler.lastModelStepCount;
  @override
  int get sealedSegmentCount => _modeler.sealedSegmentCount;
  @override
  int get provisionalSegmentCount => _modeler.provisionalSegmentCount;
  @override
  int get rawInputSampleCount => _modeler.rawInputSampleCount;
  @override
  bool get inputStarved => _modeler.inputStarved;
  @override
  int get largestInputGapMicros => _modeler.largestInputGapMicros;
  @override
  double get largestInputDistance => _modeler.largestInputDistance;
  @override
  int get stableCenterlineSegmentCount => _modeler.stableCenterlineSegmentCount;
  @override
  int get mutableCenterlineSegmentCount =>
      _modeler.mutableCenterlineSegmentCount;
  @override
  int get predictionSegmentCount => _modeler.predictionSegmentCount;
  int get predictionHorizonMicros => _modeler.lastPredictionHorizonMicros;
  double get predictionAngularVelocity =>
      _modeler.lastPredictionAngularVelocity;
  double get predictionCurvatureConfidence =>
      _modeler.lastPredictionCurvatureConfidence;
  double get predictionTipGap => _modeler.lastTipGap;
  double get displayTipGap => _modeler.lastTipGap;
  Offset? get displayTipPosition => _modeler.globalEndSegment?.p1;
  Offset? get predictedTipPosition => _modeler.speculativeTipPosition;
  double get lastCornerConfidence => _modeler.lastCornerConfidence;
  Offset? get lastPreservedCornerPosition =>
      _modeler.lastPreservedCornerPosition;
  double get lastTurnEpisodeHeadingRadians =>
      _modeler.lastTurnEpisodeHeadingRadians;
  double get lastTurnEpisodePeakRadians => _modeler.lastTurnEpisodePeakRadians;
  double get lastTurnEpisodeConcentration =>
      _modeler.lastTurnEpisodeConcentration;
  double get lastTurnSignCoherence => _modeler.lastTurnSignCoherence;
  double get lastTurnLocalization => _modeler.lastTurnLocalization;
  double get lastTurnEpisodeArc => _modeler.lastTurnEpisodeArc;
  Duration get lastTurnEpisodeDuration => _modeler.lastTurnEpisodeDuration;
  int get lastTurnEpisodeSignificantTurnCount =>
      _modeler.lastTurnEpisodeSignificantTurnCount;
  String get lastTurnEpisodeState => _modeler.lastTurnEpisodeState;
  PawLocalGeometryEvidence? get lastLocalGeometryEvidence =>
      _modeler.lastLocalGeometryEvidence;
  Duration? get turnEpisodeFirstTimestamp => _modeler.turnEpisodeFirstTimestamp;
  Duration? get turnEpisodeLastTimestamp => _modeler.turnEpisodeLastTimestamp;
  Duration get turnEpisodeAge => _modeler.turnEpisodeAge;
  int? get unresolvedCornerCandidateMicros =>
      _modeler.unresolvedCornerCandidateMicros;
  int? get currentCornerCandidateMicros =>
      _modeler.currentCornerCandidateMicros;
  int? get confirmedSmoothUntilMicros => _modeler.confirmedSmoothUntilMicros;
  Duration get unresolvedCornerCandidateAge =>
      _modeler.unresolvedCornerCandidateAge;
  bool get smoothHysteresisActive => _modeler.smoothHysteresisActive;
  bool get pendingTurnActive => _modeler.pendingTurnActive;
  @override
  Offset? get strokeStartPosition => _modeler.strokeStartPosition;

  @override
  Offset? get previewStartPosition => strokeStartPosition;
  @override
  PawStreamingMotionSample get tapMotionSample => PawStreamingMotionSample(
        absoluteArc: 0,
        pressure: _modeler.strokeStartPressure ?? .5,
        speedPixelsPerSecond: 600,
        signedCurvature: 0,
      );

  @override
  PawBrushEmissionSegment? emissionSegmentAtArc(double arc) {
    final command = segmentAtArc(arc);
    if (command == null) return null;
    return _emissionFor(command);
  }

  @override
  PawStreamingMotionSample? emissionMotionSampleAtArc(double arc) {
    final segment = emissionSegmentAtArc(arc);
    if (segment == null) return null;
    final amount = ((arc - segment.arcStart) /
            math.max(.000001, segment.arcEnd - segment.arcStart))
        .clamp(0.0, 1.0)
        .toDouble();
    return segment.motionAt(amount, absoluteArc: arc);
  }

  PawStreamingSegmentCommand? segmentAtArc(double arc) =>
      _modeler.segmentAtArc(arc);
  PawStreamingMotionSample? motionSampleAtArc(double arc) =>
      _modeler.motionSampleAtArc(arc);

  @override
  void replaceWithAssistedCenterline(
    Iterable<PawStreamingSegmentCommand> segments,
  ) {
    _modeler.replaceWithAssistedCenterline(segments);
    _emissionCache.clear();
  }

  @override
  void sealAssistedCenterlineAsDisplayed() {
    if (_frozen) return;
    _modeler.sealAssistedCenterlineAsDisplayed();
    _frozen = true;
  }

  @override
  int get revision => _modeler.revision + _materialRevision;
  @override
  int get centerlineReplacementEpoch => _modeler.centerlineReplacementEpoch;
  @override
  bool get isEmpty => _modeler.isEmpty;
  @override
  bool get isFrozen => _frozen;
  @override
  Rect get bounds {
    final rawBounds = _modeler.bounds;
    if (rawBounds.isEmpty) {
      final point = strokeStartPosition;
      if (point == null) return Rect.zero;
      return Rect.fromCircle(
        center: point,
        radius: brushSize * definition.maximumReachFactor,
      );
    }
    return rawBounds;
  }

  @override
  bool appendSample(DrawingInputSample sample) {
    if (_frozen) return false;
    final changed = _modeler.appendSample(sample);
    if (changed) {
      if (sample.timestamp > _lastInputTime) _lastInputTime = sample.timestamp;
      if (sample.timestamp > _materialClock) _materialClock = sample.timestamp;
    }
    return changed;
  }

  @override
  void freeze() {
    if (_frozen) return;
    _modeler.freeze();
    _frozen = true;
  }

  void finalizeAcceptedOnly() {
    if (_frozen) return;
    _modeler.finalizeAcceptedOnly();
    _frozen = true;
  }
}
