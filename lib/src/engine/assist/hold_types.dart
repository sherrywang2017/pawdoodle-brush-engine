part of '../../held_stroke_assist.dart';

enum PawStrokeHoldAssistState {
  inactive,
  tracking,
  holdCandidate,
  assistedHolding,
  committed,
}

enum PawStrokeAssistKind {
  line,
  polyline,
  arc,
  curve,
  continuousCurve,
  ellipse,
  circle,
  triangle,
  quadrilateral,
  freeformSmooth,
}

extension PawStrokeAssistKindWireName on PawStrokeAssistKind {
  String get wireName => switch (this) {
        PawStrokeAssistKind.line => 'LINE',
        PawStrokeAssistKind.polyline => 'POLYLINE',
        PawStrokeAssistKind.arc => 'ARC',
        PawStrokeAssistKind.curve => 'CURVE',
        PawStrokeAssistKind.continuousCurve => 'CONTINUOUS_CURVE',
        PawStrokeAssistKind.ellipse => 'ELLIPSE',
        PawStrokeAssistKind.circle => 'CIRCLE',
        PawStrokeAssistKind.triangle => 'TRIANGLE',
        PawStrokeAssistKind.quadrilateral => 'QUADRILATERAL',
        PawStrokeAssistKind.freeformSmooth => 'FREEFORM_SMOOTH',
      };
}

@immutable
class PawHeldStrokeBeautificationPolicy {
  const PawHeldStrokeBeautificationPolicy({
    this.minimumCurveFitTolerance = 1.75,
    this.strokeScaleToleranceFraction = .0125,
    this.maximumCurveSegments = 8,
  });

  final double minimumCurveFitTolerance;
  final double strokeScaleToleranceFraction;
  final int maximumCurveSegments;

  double fitToleranceFor(
    double strokeScale, {
    int sampleCount = 0,
    double pathLength = 0,
    double turnVariation = 0,
    double brushWidth = 0,
  }) {
    final spacing = sampleCount <= 1 ? 0 : pathLength / (sampleCount - 1);
    final sparseAllowance = (spacing * .035).clamp(0.0, 1.8);
    final brushAllowance = (brushWidth * .08).clamp(0.0, 1.2);
    final topologyProtection = (1 - turnVariation.clamp(0.0, 1.0) * .28);
    return (math.max(
              minimumCurveFitTolerance,
              strokeScale.abs() * strokeScaleToleranceFraction,
            ) *
            topologyProtection +
        sparseAllowance +
        brushAllowance);
  }
}

@immutable
class HoldInputSnapshot {
  HoldInputSnapshot({
    required List<DrawingInputSample> samples,
    required this.lastMeaningfulMovement,
  }) : samples = List<DrawingInputSample>.unmodifiable(samples);

  final List<DrawingInputSample> samples;
  final Duration lastMeaningfulMovement;
  int get rawPointCount => samples.length;
}

@immutable
class PawStrokeHoldAssistConfiguration {
  const PawStrokeHoldAssistConfiguration({
    this.holdDelay = const Duration(milliseconds: 450),
    this.jitterRadius = 4,
    this.minimumMeaningfulPathLength = 12,
    this.minimumRecordedPointDistance = .08,
    this.baseFidelityCorridor = 3,
    this.strokeScaleFidelityFraction = .035,
    this.minimumLineConfidence = .3,
    this.minimumPolylineConfidence = .48,
    this.minimumArcConfidence = .4,
    this.minimumClosedShapeConfidence = .42,
    this.maximumRawPoints = 8192,
    this.beautificationPolicy = const PawHeldStrokeBeautificationPolicy(),
  })  : assert(jitterRadius > 0),
        assert(minimumMeaningfulPathLength > 0),
        assert(minimumRecordedPointDistance >= 0),
        assert(baseFidelityCorridor > 0),
        assert(strokeScaleFidelityFraction > 0),
        assert(minimumLineConfidence >= 0 && minimumLineConfidence <= 1),
        assert(
            minimumPolylineConfidence >= 0 && minimumPolylineConfidence <= 1),
        assert(minimumArcConfidence >= 0 && minimumArcConfidence <= 1),
        assert(minimumClosedShapeConfidence >= 0 &&
            minimumClosedShapeConfidence <= 1),
        assert(maximumRawPoints > 2);

  final Duration holdDelay;
  final double jitterRadius;
  final double minimumMeaningfulPathLength;
  final double minimumRecordedPointDistance;
  final double baseFidelityCorridor;
  final double strokeScaleFidelityFraction;
  final double minimumLineConfidence;
  final double minimumPolylineConfidence;
  final double minimumArcConfidence;
  final double minimumClosedShapeConfidence;
  final int maximumRawPoints;
  final PawHeldStrokeBeautificationPolicy beautificationPolicy;

  double fidelityCorridorFor(double strokeScale) => math.max(
        baseFidelityCorridor,
        strokeScale.abs() * strokeScaleFidelityFraction,
      );

  double minimumAcceptanceConfidenceFor(PawStrokeAssistKind kind) =>
      switch (kind) {
        PawStrokeAssistKind.line => minimumLineConfidence,
        PawStrokeAssistKind.polyline => minimumPolylineConfidence,
        PawStrokeAssistKind.arc => minimumArcConfidence,
        PawStrokeAssistKind.curve || PawStrokeAssistKind.continuousCurve => 0,
        PawStrokeAssistKind.ellipse ||
        PawStrokeAssistKind.circle ||
        PawStrokeAssistKind.triangle ||
        PawStrokeAssistKind.quadrilateral =>
          minimumClosedShapeConfidence,
        PawStrokeAssistKind.freeformSmooth => 0,
      };
}

@immutable
class PawStrokeCandidateScore {
  const PawStrokeCandidateScore({
    this.geometryResidual = 1,
    this.maximumResidual = 1,
    this.complexityPenalty = 0,
    this.closurePenalty = 0,
    this.sweepPenalty = 0,
    this.turnCoherence = 0,
    this.topologyPenalty = 0,
  });

  final double geometryResidual;
  final double maximumResidual;
  final double complexityPenalty;
  final double closurePenalty;
  final double sweepPenalty;
  final double turnCoherence;
  final double topologyPenalty;

  double get totalCost => (geometryResidual * .34 +
          maximumResidual * .22 +
          complexityPenalty +
          closurePenalty +
          sweepPenalty +
          (1 - turnCoherence) * .06 +
          topologyPenalty)
      .clamp(0.0, 2.0);

  Map<String, Object> toJson() => <String, Object>{
        'geometry_residual': geometryResidual,
        'maximum_residual': maximumResidual,
        'complexity_penalty': complexityPenalty,
        'closure_penalty': closurePenalty,
        'sweep_penalty': sweepPenalty,
        'turn_coherence': turnCoherence,
        'topology_penalty': topologyPenalty,
        'total_cost': totalCost,
      };
}

@immutable
class PawStrokeAssistDiagnosticEvent {
  const PawStrokeAssistDiagnosticEvent(this.name, this.fields);

  final String name;
  final Map<String, Object> fields;

  Map<String, Object> toJson() => <String, Object>{
        'event': name,
        ...fields,
      };
}

@immutable
class PawStrokeAssistClassification {
  const PawStrokeAssistClassification({
    required this.kind,
    required this.confidence,
    this.vertexIndices = const <int>[],
    this.circleFit,
    this.ellipseFit,
    this.curveFit,
    this.curveFairing,
    this.closureTopology = const <String, Object>{},
    this.score = const PawStrokeCandidateScore(),
  });

  final PawStrokeAssistKind kind;
  final double confidence;
  final List<int> vertexIndices;
  final PawCircleFit? circleFit;
  final PawEllipseFit? ellipseFit;
  final PawHeldCurveFit? curveFit;
  final PawHeldCurveFairingResult? curveFairing;
  final Map<String, Object> closureTopology;
  final PawStrokeCandidateScore score;

  PawStrokeAssistClassification withScore(PawStrokeCandidateScore value) =>
      PawStrokeAssistClassification(
        kind: kind,
        confidence: confidence,
        vertexIndices: vertexIndices,
        circleFit: circleFit,
        ellipseFit: ellipseFit,
        curveFit: curveFit,
        curveFairing: curveFairing,
        closureTopology: closureTopology,
        score: value,
      );
}

@immutable
class PawStrokeAssistResult {
  const PawStrokeAssistResult({
    required this.kind,
    required this.confidence,
    required this.rawPointCount,
    required this.refinedSegments,
    required this.maxRefinementDistance,
    this.fitResidual = 0,
    this.segmentReductionRatio = 0,
    this.candidateScores = const <String, Object>{},
    this.fairingMetrics,
  });

  final PawStrokeAssistKind kind;
  final double confidence;
  final int rawPointCount;
  final List<PawStreamingSegmentCommand> refinedSegments;
  final double maxRefinementDistance;
  final double fitResidual;
  final double segmentReductionRatio;
  final Map<String, Object> candidateScores;
  final PawHeldCurveFairingMetrics? fairingMetrics;

  PawHeldBezierQualityMetrics get bezierQuality =>
      pawHeldBezierQualityMetrics(refinedSegments);

  Map<String, Object> diagnostics(Duration holdDelay) => <String, Object>{
        'assist_kind': kind.wireName,
        'classification_confidence': confidence,
        'raw_point_count': rawPointCount,
        'refined_segment_count': refinedSegments.length,
        'max_refinement_distance': maxRefinementDistance,
        'hold_fit_residual': fitResidual,
        'hold_segment_reduction_ratio': segmentReductionRatio,
        'hold_centerline_delta': maxRefinementDistance,
        'hold_candidate_scores': candidateScores,
        if (fairingMetrics != null) ...fairingMetrics!.toJson(),
        ...bezierQuality.toJson(),
        'hold_delay_us': holdDelay.inMicroseconds,
      };
}
