part of '../../held_stroke_assist.dart';

class PawHeldStrokeRefiner {
  const PawHeldStrokeRefiner({
    this.classifier = const PawStrokeAssistClassifier(),
  });

  final PawStrokeAssistClassifier classifier;

  PawStrokeAssistResult refine(
    List<DrawingInputSample> input, {
    required PawStrokeHoldAssistConfiguration configuration,
  }) {
    final raw = _deduplicateSamples(
      input,
      configuration.minimumRecordedPointDistance,
    );
    if (raw.length < 2) {
      return PawStrokeAssistResult(
        kind: PawStrokeAssistKind.freeformSmooth,
        confidence: 0,
        rawPointCount: raw.length,
        refinedSegments: const <PawStreamingSegmentCommand>[],
        maxRefinementDistance: 0,
      );
    }
    final points = raw.map((sample) => sample.position).toList();
    final scale = _pointScale(points);
    final ranked = classifier.rankCandidates(
      raw,
      configuration: configuration,
    );
    final hasAcceptedRoundLoop = ranked.any(
      (candidate) =>
          (candidate.kind == PawStrokeAssistKind.circle ||
              candidate.kind == PawStrokeAssistKind.ellipse) &&
          candidate.confidence >=
              configuration.minimumAcceptanceConfidenceFor(candidate.kind),
    );
    final cornerCount = _salientCornerCount(raw, scale);
    if (cornerCount >= 2 && !hasAcceptedRoundLoop) {
      // Draw-and-Hold is deliberately shape assistance, not a general-purpose
      // rewrite of a complex gesture. Two localized corners are enough to
      // make the user's topology unambiguous; leave the already-rendered
      // centerline untouched by returning no replacement geometry.
      return PawStrokeAssistResult(
        kind: PawStrokeAssistKind.freeformSmooth,
        confidence: 0,
        rawPointCount: raw.length,
        refinedSegments: const <PawStreamingSegmentCommand>[],
        maxRefinementDistance: 0,
        candidateScores: <String, Object>{
          'SUPPRESSED': <String, Object>{
            'reason': 'multiple_localized_corners',
            'corner_count': cornerCount,
          },
        },
      );
    }
    // Holding requests a clean geometric result when the observed gesture
    // already satisfies that shape's fit tolerances. A flexible multi-cubic
    // fit can have a lower residual while retaining the user's tiny wobbles.
    final simpleCandidates = ranked.where((candidate) =>
        (candidate.kind == PawStrokeAssistKind.line ||
            candidate.kind == PawStrokeAssistKind.arc) &&
        candidate.confidence >=
            configuration.minimumAcceptanceConfidenceFor(candidate.kind));
    final lines =
        simpleCandidates.where((c) => c.kind == PawStrokeAssistKind.line);
    final candidate = lines.isNotEmpty
        ? lines.first
        : simpleCandidates.isNotEmpty
            ? simpleCandidates.first
            : ranked.first;
    final classification = candidate.confidence >=
            configuration.minimumAcceptanceConfidenceFor(candidate.kind)
        ? candidate
        : const PawStrokeAssistClassification(
            kind: PawStrokeAssistKind.freeformSmooth,
            confidence: 0,
          );
    final cubics = switch (classification.kind) {
      PawStrokeAssistKind.line => _lineCubics(raw),
      PawStrokeAssistKind.polyline =>
        _polylineCubics(raw, classification.vertexIndices, closed: false),
      PawStrokeAssistKind.triangle ||
      PawStrokeAssistKind.quadrilateral =>
        _polylineCubics(raw, classification.vertexIndices, closed: true),
      PawStrokeAssistKind.arc => _arcCubics(raw, classification.circleFit!),
      PawStrokeAssistKind.curve ||
      PawStrokeAssistKind.continuousCurve =>
        _curveFitCubics(raw, classification.curveFit!),
      PawStrokeAssistKind.ellipse ||
      PawStrokeAssistKind.circle =>
        _ellipseCubics(raw, classification.ellipseFit!),
      PawStrokeAssistKind.freeformSmooth => _freeformCubics(raw, configuration),
    };
    var segments = _commandsFromCubics(cubics, raw);
    var maximumDistance = _maximumRefinementDistance(raw, segments);
    if (classification.kind == PawStrokeAssistKind.freeformSmooth) {
      final corridor = configuration.fidelityCorridorFor(scale);
      if (maximumDistance > corridor) {
        final fallback = _resampleByArc(raw, math.max(.75, corridor * .45));
        segments = _commandsFromCubics(
          _linearCubics(fallback),
          fallback,
        );
        maximumDistance = _maximumRefinementDistance(raw, segments);
      }
    }
    return PawStrokeAssistResult(
      kind: classification.kind,
      confidence: classification.confidence.clamp(0.0, 1.0),
      rawPointCount: raw.length,
      refinedSegments: List<PawStreamingSegmentCommand>.unmodifiable(segments),
      maxRefinementDistance: maximumDistance,
      fitResidual: classification.curveFit?.rmsResidual ?? 0,
      segmentReductionRatio: classification.curveFit?.segmentReductionRatio ??
          (raw.length <= 1 ? 0 : 1 - segments.length / (raw.length - 1)),
      candidateScores: <String, Object>{
        for (final value in ranked)
          value.kind.wireName: <String, Object>{
            ...value.score.toJson(),
            if (value.circleFit != null)
              'robust_arc': value.circleFit!.toJson(),
            if (value.curveFairing != null)
              'fairing': value.curveFairing!.metrics.toJson(),
            if (value.closureTopology.isNotEmpty)
              'closure_topology': value.closureTopology,
          },
      },
      fairingMetrics: classification.curveFairing?.metrics,
    );
  }

  PawStrokeAssistResult adjustLineEndpoint(
    PawStrokeAssistResult current,
    List<DrawingInputSample> input,
  ) {
    if (current.kind != PawStrokeAssistKind.line || input.length < 2) {
      return current;
    }
    final raw = _deduplicateSamples(input, 0);
    final segments = _commandsFromCubics(_lineCubics(raw), raw);
    return PawStrokeAssistResult(
      kind: current.kind,
      confidence: current.confidence,
      rawPointCount: raw.length,
      refinedSegments: List<PawStreamingSegmentCommand>.unmodifiable(segments),
      maxRefinementDistance: _maximumRefinementDistance(raw, segments),
      fitResidual: current.fitResidual,
      segmentReductionRatio: current.segmentReductionRatio,
      candidateScores: current.candidateScores,
      fairingMetrics: current.fairingMetrics,
    );
  }
}
