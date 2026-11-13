part of '../../streaming_stroke_modeler.dart';

/// Sampling-aware evidence used by the production causal spline.
///
/// A large three-point angle is not, by itself, a corner. A cusp requires a
/// localized angular impulse with approximately straight incoming/outgoing
/// neighborhoods. Same-sign turn distributed over the retained arc is smooth
/// curvature. Sparse neighborhoods lower [evidenceConfidence] and therefore
/// cannot force a near-zero tangent.
class PawLocalGeometryEvidence {
  const PawLocalGeometryEvidence({
    required this.turnMagnitude,
    required this.turnConcentration,
    required this.signCoherence,
    required this.incomingLineResidual,
    required this.outgoingLineResidual,
    required this.sampleDensity,
    required this.evidenceConfidence,
    required this.localizedCornerLikelihood,
    required this.distributedSmoothLikelihood,
    required this.insufficientGeometryEvidence,
  });

  final double turnMagnitude;
  final double turnConcentration;
  final double signCoherence;
  final double incomingLineResidual;
  final double outgoingLineResidual;
  final double sampleDensity;
  final double evidenceConfidence;
  final double localizedCornerLikelihood;
  final double distributedSmoothLikelihood;
  final bool insufficientGeometryEvidence;

  Map<String, Object> toJson() => <String, Object>{
        'turn_magnitude': turnMagnitude,
        'turn_concentration': turnConcentration,
        'sign_coherence': signCoherence,
        'incoming_line_residual': incomingLineResidual,
        'outgoing_line_residual': outgoingLineResidual,
        'sample_density': sampleDensity,
        'evidence_confidence': evidenceConfidence,
        'localized_corner_likelihood': localizedCornerLikelihood,
        'distributed_smooth_likelihood': distributedSmoothLikelihood,
        'insufficient_geometry_evidence': insufficientGeometryEvidence,
      };

  static PawLocalGeometryEvidence analyze(
    List<DrawingInputSample> samples,
    int vertexIndex, {
    double neighborhoodArc = 96,
  }) {
    if (vertexIndex <= 0 || vertexIndex >= samples.length - 1) {
      return const PawLocalGeometryEvidence(
        turnMagnitude: 0,
        turnConcentration: 0,
        signCoherence: 0,
        incomingLineResidual: 0,
        outgoingLineResidual: 0,
        sampleDensity: 0,
        evidenceConfidence: 0,
        localizedCornerLikelihood: 0,
        distributedSmoothLikelihood: 0,
        insufficientGeometryEvidence: true,
      );
    }
    var start = vertexIndex;
    var incomingArc = 0.0;
    while (
        start > 0 && vertexIndex - start < 4 && incomingArc < neighborhoodArc) {
      incomingArc +=
          (samples[start].position - samples[start - 1].position).distance;
      start--;
    }
    var end = vertexIndex;
    var outgoingArc = 0.0;
    while (end < samples.length - 1 &&
        end - vertexIndex < 4 &&
        outgoingArc < neighborhoodArc) {
      outgoingArc +=
          (samples[end + 1].position - samples[end].position).distance;
      end++;
    }
    final points = <Offset>[
      for (var index = start; index <= end; index++) samples[index].position,
    ];
    final legs = <double>[
      for (var index = 1; index < points.length; index++)
        (points[index] - points[index - 1]).distance,
    ];
    final turns = <double>[
      for (var index = 1; index < points.length - 1; index++)
        _signedTurnRadians(
          points[index] - points[index - 1],
          points[index + 1] - points[index],
        ),
    ];
    final localVertex = vertexIndex - start;
    final immediateTurn = _signedTurnRadians(
      points[localVertex] - points[localVertex - 1],
      points[localVertex + 1] - points[localVertex],
    );
    final absoluteHeading =
        turns.fold<double>(0, (sum, value) => sum + value.abs());
    final signedHeading = turns.fold<double>(0, (sum, value) => sum + value);
    final totalArc = legs.fold<double>(0, (sum, value) => sum + value);
    final concentration = _localizedTurnFraction(
      turns: turns,
      legLengths: legs,
      points: points,
      absoluteHeading: absoluteHeading,
      totalArc: totalArc,
    );
    final incomingResidual = _lineFitResidualRatio(
      points.sublist(0, localVertex + 1),
    );
    final outgoingResidual = _lineFitResidualRatio(
      points.sublist(localVertex),
    );
    final maximumLeg = legs.isEmpty ? double.infinity : legs.reduce(math.max);
    var maximumGapMicros = 0;
    for (var index = start + 1; index <= end; index++) {
      maximumGapMicros = math.max(
        maximumGapMicros,
        samples[index].timestamp.inMicroseconds -
            samples[index - 1].timestamp.inMicroseconds,
      );
    }
    final densityConfidence = (1 -
            .58 * _smoothUnit((maximumLeg - 24) / 96) -
            .42 * _smoothUnit((maximumGapMicros - 18000) / 82000))
        .clamp(0.0, 1.0);
    final incomingLegCount = localVertex;
    final outgoingLegCount = points.length - localVertex - 1;
    final fullSupport = incomingLegCount >= 2 && outgoingLegCount >= 2;
    final oneSidedSupport = incomingLegCount >= 2 || outgoingLegCount >= 2;
    final supportConfidence = fullSupport
        ? .72
        : oneSidedSupport
            ? .48
            : .28;
    final confidence = (supportConfidence +
            densityConfidence *
                (fullSupport
                    ? .28
                    : oneSidedSupport
                        ? .32
                        : .22))
        .clamp(0.0, 1.0);
    final coherence = absoluteHeading <= .0001
        ? 0.0
        : (signedHeading.abs() / absoluteHeading).clamp(0.0, 1.0);
    final straightLegs = 1 / (1 + 30 * (incomingResidual + outgoingResidual));
    final angleScore = _smoothUnit(
      (immediateTurn.abs() - 22 * math.pi / 180) / (58 * math.pi / 180),
    );
    final concentrationScore = _smoothUnit((concentration - .34) / .5);
    final corner = (angleScore * concentrationScore * straightLegs * confidence)
        .clamp(0.0, 1.0);
    final distributedTurnCount =
        turns.where((turn) => turn.abs() >= .025).length;
    final smooth = (_smoothUnit((coherence - .72) / .28) *
            _smoothUnit((distributedTurnCount - 1) / 3) *
            (1 - _smoothUnit((concentration - .45) / .42)) *
            confidence)
        .clamp(0.0, 1.0);
    return PawLocalGeometryEvidence(
      turnMagnitude: immediateTurn.abs(),
      turnConcentration: concentration,
      signCoherence: coherence,
      incomingLineResidual: incomingResidual,
      outgoingLineResidual: outgoingResidual,
      sampleDensity: totalArc <= .0001 ? 0 : legs.length / totalArc,
      evidenceConfidence: confidence,
      localizedCornerLikelihood: corner,
      distributedSmoothLikelihood: smooth,
      insufficientGeometryEvidence: confidence < .55,
    );
  }
}
