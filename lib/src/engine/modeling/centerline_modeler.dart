part of '../../streaming_stroke_modeler.dart';

/// Causal streaming centerline with an immutable accepted prefix and a short,
/// replaceable prediction tip.
class PawStreamingCenterlineModeler {
  PawStreamingCenterlineModeler({
    required this.geometryCorrectionHorizon,
    required this.predictionHorizon,
    required this.strokeBoundsRadius,
    this.maximumMutableTipArc = 24,
    this.rawFidelityCorridor = 2,
    this.stableCausalJoins = false,
    this.fixedStep,
    this.curvedIntervalTargets = false,
    this.curvedTargetMaxHandleFactor = .5,
  })  : assert(maximumMutableTipArc > 0),
        assert(rawFidelityCorridor > 0);

  /// Spatial reach retained solely for unresolved centerline evidence.
  ///
  /// Brush footprint, fibers, and other material reach do not belong here.
  final double geometryCorrectionHorizon;

  /// Maximum spatial reach of speculative tip-only prediction.
  final double predictionHorizon;
  final double strokeBoundsRadius;

  /// Strict spatial ownership horizon for already-visible live geometry.
  /// Corner semantics may change inside this window, but can never keep older
  /// geometry mutable.
  final double maximumMutableTipArc;

  /// Maximum distance between a modeled point and its causal raw input chord.
  /// This is deliberately independent from brush footprint reach.
  final double rawFidelityCorridor;
  // Input interpretation must not change when the brush footprint changes.
  double get maximumTurnEvidenceArc => 240.0;
  final bool stableCausalJoins;
  final PawFixedStepModelParameters? fixedStep;
  final bool curvedIntervalTargets;
  final double curvedTargetMaxHandleFactor;
  final List<DrawingInputSample> _recentSamples = <DrawingInputSample>[];
  final List<DrawingInputSample> _rawPolyline = <DrawingInputSample>[];
  final List<PawStreamingSegmentCommand> _sealedSegments =
      <PawStreamingSegmentCommand>[];
  final List<PawStreamingSegmentCommand> _tailSegments =
      <PawStreamingSegmentCommand>[];
  List<PawStreamingSegmentCommand>? _assistedSegments;
  final Set<int> _preservedCornerMicros = <int>{};
  late final UnmodifiableListView<PawStreamingSegmentCommand> _sealedView =
      UnmodifiableListView<PawStreamingSegmentCommand>(_sealedSegments);
  late final UnmodifiableListView<PawStreamingSegmentCommand> _tailView =
      UnmodifiableListView<PawStreamingSegmentCommand>(_tailSegments);

  Offset _anchor = Offset.zero;
  Offset _anchorTangent = const Offset(1, 0);
  double _anchorPressure = .5;
  Duration _anchorTime = Duration.zero;
  Offset? _strokeStartPosition;
  double? _strokeStartPressure;
  double _anchorArc = 0;
  int _nextSegmentIndex = 0;
  int _revision = 0;
  int _centerlineReplacementEpoch = 0;
  bool _hasAnchor = false;
  bool _anchorPreservesCusp = false;
  bool _frozen = false;
  DrawingInputSample? _lastRawSample;
  DrawingInputSample? _penultimateRawSample;
  DrawingInputSample? _speculativeSample;
  final List<DrawingInputSample> _turnEpisodeSamples = <DrawingInputSample>[];
  int? _unresolvedCornerCandidateMicros;
  int? _currentCornerCandidateMicros;
  int? _confirmedSmoothUntilMicros;
  int? _pendingTurnStartMicros;
  int? _pendingTurnVertexMicros;
  int? _tailInvalidationMicros;
  int? _causalSealBarrierMicros;
  DrawingInputSample? _deferredSparseCorner;
  Offset _deferredSparseOutgoing = Offset.zero;
  double _deferredSparseTurnRadians = 0;
  int? _deferredSparseInvalidationMicros;
  double _deferredSparseCornerConfidence = 0;
  bool _deferredSparseAlternatingEvidence = false;
  double _sparseSmoothTurnRadians = 0;
  Offset? _fixedPosition;
  Offset _fixedVelocity = Offset.zero;
  Duration _fixedClock = Duration.zero;
  int _fixedRemainderMicros = 0;
  int lastModelStepCount = 0;
  int totalModelStepCount = 0;
  int _rawInputSampleCount = 0;
  int _largestInputGapMicros = 0;
  double _largestInputDistance = 0;
  double lastTipGap = 0;
  int lastPredictionHorizonMicros = 0;
  double lastPredictionAngularVelocity = 0;
  double lastPredictionCurvatureConfidence = 0;
  double lastCornerConfidence = 0;
  Offset? lastPreservedCornerPosition;
  double lastTurnEpisodeHeadingRadians = 0;
  double lastTurnEpisodePeakRadians = 0;
  double lastTurnEpisodeConcentration = 0;
  double lastTurnSignCoherence = 0;
  double lastTurnLocalization = 0;
  double lastTurnEpisodeArc = 0;
  Duration lastTurnEpisodeDuration = Duration.zero;
  int lastTurnEpisodeSignificantTurnCount = 0;
  String lastTurnEpisodeState = 'idle';
  PawLocalGeometryEvidence? lastLocalGeometryEvidence;

  int get revision => _revision;
  int get centerlineReplacementEpoch => _centerlineReplacementEpoch;
  bool get isEmpty => !_hasAnchor;
  bool get isFrozen => _frozen;
  int get rawInputSampleCount => _rawInputSampleCount;
  int get largestInputGapMicros => _largestInputGapMicros;
  double get largestInputDistance => _largestInputDistance;
  bool get inputStarved =>
      _largestInputGapMicros >= 50000 || _largestInputDistance >= 64;
  int get stableCenterlineSegmentCount => sealedSegmentCount;
  int get mutableCenterlineSegmentCount {
    final realTime = _lastRawSample?.timestamp;
    if (realTime == null || _assistedSegments != null) return 0;
    return _tailSegments.where((segment) => segment.endTime <= realTime).length;
  }

  int get predictionSegmentCount {
    final realTime = _lastRawSample?.timestamp;
    if (realTime == null || _assistedSegments != null) return 0;
    return _tailSegments.where((segment) => segment.endTime > realTime).length;
  }

  int get sealedSegmentCount =>
      _assistedSegments?.length ?? _sealedSegments.length;
  int get provisionalSegmentCount =>
      _assistedSegments == null ? _tailSegments.length : 0;
  Iterable<PawStreamingSegmentCommand> get sealedSegments => _sealedView;
  Iterable<PawStreamingSegmentCommand> get provisionalSegments => _tailView;
  double get sealedEndArc {
    final assisted = _assistedSegments;
    if (assisted != null && assisted.isNotEmpty) return assisted.last.arcEnd;
    return _sealedSegments.isEmpty ? 0 : _sealedSegments.last.arcEnd;
  }

  double get acceptedEndArc => sealedEndArc;
  double get renderEndArc => globalEndSegment?.arcEnd ?? 0;
  double get causalStableEndArc => acceptedEndArc;
  Duration? get turnEpisodeFirstTimestamp =>
      _turnEpisodeSamples.isEmpty ? null : _turnEpisodeSamples.first.timestamp;
  Duration? get turnEpisodeLastTimestamp =>
      _turnEpisodeSamples.isEmpty ? null : _turnEpisodeSamples.last.timestamp;
  Duration get turnEpisodeAge =>
      switch ((turnEpisodeFirstTimestamp, turnEpisodeLastTimestamp)) {
        (final first?, final last?) => last - first,
        _ => Duration.zero,
      };
  int? get unresolvedCornerCandidateMicros => _unresolvedCornerCandidateMicros;
  int? get currentCornerCandidateMicros => _currentCornerCandidateMicros;
  int? get confirmedSmoothUntilMicros => _confirmedSmoothUntilMicros;
  bool get pendingTurnActive => _pendingTurnStartMicros != null;
  Duration get unresolvedCornerCandidateAge {
    final candidate = _unresolvedCornerCandidateMicros;
    final latest = _lastRawSample?.timestamp.inMicroseconds;
    if (candidate == null || latest == null || latest <= candidate) {
      return Duration.zero;
    }
    return Duration(microseconds: latest - candidate);
  }

  bool get smoothHysteresisActive {
    final latest = _lastRawSample?.timestamp.inMicroseconds;
    return latest != null &&
        _confirmedSmoothUntilMicros != null &&
        latest <= _confirmedSmoothUntilMicros!;
  }

  Offset? get strokeStartPosition => _strokeStartPosition;
  double? get strokeStartPressure => _strokeStartPressure;
  Offset? get tailAnchorPosition => _hasAnchor ? _anchor : null;
  Offset get tailAnchorTangent => _anchorTangent;
  double get tailAnchorArc => _anchorArc;
  Offset? get speculativeTipPosition => _speculativeSample?.position;

  PawStreamingSegmentCommand? get globalStartSegment {
    final assisted = _assistedSegments;
    if (assisted != null && assisted.isNotEmpty) return assisted.first;
    if (_sealedSegments.isNotEmpty) return _sealedSegments.first;
    if (_tailSegments.isNotEmpty) return _tailSegments.first;
    return null;
  }

  PawStreamingSegmentCommand? get globalEndSegment {
    final assisted = _assistedSegments;
    if (assisted != null && assisted.isNotEmpty) return assisted.last;
    if (_tailSegments.isNotEmpty) return _tailSegments.last;
    if (_sealedSegments.isNotEmpty) return _sealedSegments.last;
    return null;
  }

  Iterable<PawStreamingSegmentCommand> get renderSegments sync* {
    final assisted = _assistedSegments;
    if (assisted != null) {
      yield* assisted;
      return;
    }
    yield* _sealedSegments;
    yield* _tailSegments;
  }

  PawStreamingSegmentCommand? segmentAtArc(
    double arc, {
    bool sealedOnly = false,
  }) {
    final assisted = _assistedSegments;
    if (assisted != null) return _segmentAtArc(assisted, arc);
    final sealed = _segmentAtArc(_sealedSegments, arc);
    if (sealed != null &&
        (sealedOnly || arc <= sealed.arcEnd || _tailSegments.isEmpty)) {
      return sealed;
    }
    if (sealedOnly) return sealed;
    return _segmentAtArc(_tailSegments, arc) ?? sealed;
  }

  PawStreamingMotionSample? motionSampleAtArc(double arc) {
    if (!arc.isFinite) return null;
    final segment = segmentAtArc(arc);
    if (segment == null) return null;
    final t = ((arc - segment.arcStart) /
            math.max(.000001, segment.arcEnd - segment.arcStart))
        .clamp(0.0, 1.0);
    return segment.motionAt(t, absoluteArc: arc);
  }

  Rect get bounds {
    if (!_hasAnchor) return Rect.zero;
    var result = Rect.fromCircle(
      center: _anchor,
      radius: strokeBoundsRadius,
    );
    for (final segment in renderSegments) {
      result = result.expandToInclude(
        Rect.fromCircle(
          center: segment.p0,
          radius: strokeBoundsRadius,
        ),
      );
      result = result.expandToInclude(
        Rect.fromCircle(
          center: segment.c1,
          radius: strokeBoundsRadius,
        ),
      );
      result = result.expandToInclude(
        Rect.fromCircle(
          center: segment.c2,
          radius: strokeBoundsRadius,
        ),
      );
      result = result.expandToInclude(
        Rect.fromCircle(
          center: segment.p1,
          radius: strokeBoundsRadius,
        ),
      );
    }
    return result;
  }

  bool appendSample(DrawingInputSample sample) {
    if (_frozen || !sample.hasFinitePosition) return false;
    // Production uses one centerline representation from PointerDown through
    // PointerUp. The legacy fixed-step/corner observer remains below for old
    // diagnostic configurations, but it is not allowed to switch geometry in
    // the stable causal runtime.
    if (stableCausalJoins) return _appendBoundedCausalSpline(sample);
    if (fixedStep == null &&
        _recentSamples.isNotEmpty &&
        sample.timestamp < _recentSamples.last.timestamp) {
      return false;
    }
    final parameters = fixedStep;
    if (parameters != null) return _appendFixedStep(sample, parameters);
    return _appendDirect(sample);
  }

  /// Replaces the complete visible centerline after an explicit Draw-and-Hold
  /// request. Normal streaming appends never call this method and therefore
  /// retain their immutable accepted-prefix contract.
  void replaceWithAssistedCenterline(
    Iterable<PawStreamingSegmentCommand> segments,
  ) {
    if (_frozen) {
      throw StateError('A frozen centerline cannot be assisted.');
    }
    final replacement = List<PawStreamingSegmentCommand>.unmodifiable(segments);
    if (replacement.isEmpty) {
      throw ArgumentError.value(segments, 'segments', 'must not be empty');
    }
    var previousArc = 0.0;
    Offset? previousEnd;
    for (var index = 0; index < replacement.length; index++) {
      final segment = replacement[index];
      final finite = <Offset>[segment.p0, segment.c1, segment.c2, segment.p1]
          .every((point) => point.dx.isFinite && point.dy.isFinite);
      if (!finite ||
          !segment.arcStart.isFinite ||
          !segment.arcEnd.isFinite ||
          segment.arcStart < previousArc - .001 ||
          segment.arcEnd <= segment.arcStart ||
          (previousEnd != null && (segment.p0 - previousEnd).distance > .01)) {
        throw ArgumentError.value(
          segments,
          'segments',
          'must form one finite, ordered centerline',
        );
      }
      previousArc = segment.arcEnd;
      previousEnd = segment.p1;
    }
    _assistedSegments = replacement;
    _centerlineReplacementEpoch++;
    _revision++;
  }

  void freeze() {
    if (_frozen) return;
    if (stableCausalJoins) {
      // Legacy callers use freeze() to preserve the exact live checkpoint,
      // including its bounded prediction. Ownership may change, but rebuilding
      // even the local tail here can alter anti-aliased pixels by one level.
      _sealedSegments.addAll(_tailSegments);
      _tailSegments.clear();
      _frozen = true;
      _revision++;
      return;
    }
    _finalizePendingCornerGeometry();
    _rebuildTail();
    _sealedSegments.addAll(_tailSegments);
    _tailSegments.clear();
    _clearPendingTurn();
    _frozen = true;
    _revision++;
  }

  /// Freezes the exact Draw-and-Hold geometry that is already on screen.
  /// PointerUp is an ownership transition only: it performs no append, fit,
  /// tangent update, endpoint correction, or revision change.
  void sealAssistedCenterlineAsDisplayed() {
    if (_frozen) return;
    if (_assistedSegments == null) {
      throw StateError('No assisted centerline is currently displayed.');
    }
    _frozen = true;
  }

  /// Finalizes the exact causal stroke through the newest real input.
  ///
  /// The speculative sample is presentation-only. The final raw endpoint is
  /// appended to the bounded local tail when the fixed-step model still lags
  /// it, then only that tail is rebuilt and sealed. No accepted prefix or
  /// whole-stroke geometry is replayed.
  void finalizeAcceptedOnly() {
    if (_frozen) return;
    final finalRaw = _lastRawSample;
    _speculativeSample = null;
    final preservedFinalCorner = _finalizePendingCornerGeometry();
    if (!preservedFinalCorner &&
        finalRaw != null &&
        (_recentSamples.isEmpty ||
            (finalRaw.position - _recentSamples.last.position).distance >
                .08)) {
      _acceptModeledSample(finalRaw);
    }
    _rebuildTail();
    _sealedSegments.addAll(_tailSegments);
    _tailSegments.clear();
    _clearPendingTurn();
    _frozen = true;
    _revision++;
  }
}
