part of '../../streaming_stroke_modeler.dart';

class _TurnEpisodeObservation {
  const _TurnEpisodeObservation({
    this.confirmedCusp = false,
    this.inferredCorner,
    this.invalidationStartMicros,
  });

  final bool confirmedCusp;
  final DrawingInputSample? inferredCorner;
  final int? invalidationStartMicros;
}

const double _cornerPreservationThreshold = .44;

double _polylineArc(List<DrawingInputSample> samples) {
  var result = 0.0;
  for (var index = 1; index < samples.length; index++) {
    result += (samples[index].position - samples[index - 1].position).distance;
  }
  return result;
}

Offset? _lineIntersection(
  Offset firstStart,
  Offset firstEnd,
  Offset secondStart,
  Offset secondEnd,
) {
  final first = firstEnd - firstStart;
  final second = secondEnd - secondStart;
  final determinant = first.dx * second.dy - first.dy * second.dx;
  if (determinant.abs() <= .0001) return null;
  final delta = secondStart - firstStart;
  final distance = (delta.dx * second.dy - delta.dy * second.dx) / determinant;
  final result = firstStart + first * distance;
  return result.dx.isFinite && result.dy.isFinite ? result : null;
}

double _cornerConfidence(
  DrawingInputSample penultimate,
  DrawingInputSample previous,
  DrawingInputSample current,
) {
  final incoming = previous.position - penultimate.position;
  final outgoing = current.position - previous.position;
  final incomingLength = incoming.distance;
  final outgoingLength = outgoing.distance;
  if (incomingLength <= .5 || outgoingLength <= .5) return 0;

  final cosine = (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
      (incomingLength * outgoingLength);
  final turn = math.acos(cosine.clamp(-1.0, 1.0));
  final angleScore = _smoothUnit(
    (turn - 8 * math.pi / 180) / (42 * math.pi / 180),
  );
  final shortestLeg = math.min(incomingLength, outgoingLength);
  final longestLeg = math.max(incomingLength, outgoingLength);
  final legScore = _smoothUnit((shortestLeg - 2) / 18);
  final spacingScore = _smoothUnit((shortestLeg - 4) / 28);
  final balanceScore = shortestLeg / math.max(.0001, longestLeg);

  double speed(Offset leg, Duration start, Duration end) {
    final micros = end.inMicroseconds - start.inMicroseconds;
    return micros > 0
        ? leg.distance / (micros / Duration.microsecondsPerSecond)
        : 0;
  }

  final localSpeed = math.min(
    speed(incoming, penultimate.timestamp, previous.timestamp),
    speed(outgoing, previous.timestamp, current.timestamp),
  );
  final speedScore = _smoothUnit((localSpeed - 180) / 900);
  final support = .72 +
      legScore * .08 +
      spacingScore * .08 +
      speedScore * .07 +
      balanceScore * .05;
  return (angleScore * support).clamp(0.0, 1.0);
}

double _signedTurnRadians(Offset incoming, Offset outgoing) {
  if (incoming.distance <= .0001 || outgoing.distance <= .0001) return 0;
  final cross = incoming.dx * outgoing.dy - incoming.dy * outgoing.dx;
  final dot = incoming.dx * outgoing.dx + incoming.dy * outgoing.dy;
  return math.atan2(cross, dot);
}

/// Fraction of local absolute heading concentrated in the strongest one or
/// two adjacent intervals, weighted by how much denser that window is than the
/// whole retained episode. Unlike turn-sign coherence, a constant-curvature
/// arc stays low while an isolated cusp approaches one.
double _localizedTurnFraction({
  required List<double> turns,
  required List<double> legLengths,
  required List<Offset> points,
  required double absoluteHeading,
  required double totalArc,
}) {
  if (turns.isEmpty || absoluteHeading <= .0001 || totalArc <= .0001) return 0;
  var strongestTurn = 0.0;
  var strongestArc = double.infinity;
  var strongestStartTurn = 0;
  var strongestEndTurn = 0;
  for (var index = 0; index < turns.length; index++) {
    final singleTurn = turns[index].abs();
    final singleArc = math.max(
      .0001,
      (legLengths[index] + legLengths[index + 1]) * .5,
    );
    if (singleTurn > strongestTurn) {
      strongestTurn = singleTurn;
      strongestArc = singleArc;
      strongestStartTurn = index;
      strongestEndTurn = index;
    }
    if (index + 1 < turns.length) {
      final pairTurn = singleTurn + turns[index + 1].abs();
      final pairArc = math.max(
        .0001,
        (legLengths[index] +
                2 * legLengths[index + 1] +
                legLengths[index + 2]) /
            2,
      );
      if (pairTurn > strongestTurn) {
        strongestTurn = pairTurn;
        strongestArc = pairArc;
        strongestStartTurn = index;
        strongestEndTurn = index + 1;
      }
    }
  }
  final turnFraction = strongestTurn / absoluteHeading;
  final localDensity = strongestTurn / strongestArc;
  final meanDensity = absoluteHeading / totalArc;
  final densityContrast =
      localDensity / math.max(.0001, localDensity + meanDensity);
  final incomingEnd = strongestStartTurn + 1;
  final outgoingStart = strongestEndTurn + 1;
  final incomingResidual = _lineFitResidualRatio(
    points.sublist(0, math.min(points.length, incomingEnd + 1)),
  );
  final outgoingResidual = _lineFitResidualRatio(
    points.sublist(math.min(points.length - 1, outgoingStart)),
  );
  final straightLegEvidence =
      1 / (1 + 18 * (incomingResidual + outgoingResidual));
  final densityScore = turnFraction * densityContrast * straightLegEvidence;
  var splitScore = 0.0;
  for (var vertex = 1; vertex < points.length - 1; vertex++) {
    final incoming = points[vertex] - points.first;
    final outgoing = points.last - points[vertex];
    final incomingLength = incoming.distance;
    final outgoingLength = outgoing.distance;
    if (incomingLength <= .0001 || outgoingLength <= .0001) continue;
    final fittedTurn = _signedTurnRadians(incoming, outgoing).abs();
    final headingCapture = (fittedTurn / absoluteHeading).clamp(0.0, 1.0);
    final support = (math.min(incomingLength, outgoingLength) /
            math.max(.0001, totalArc * .2))
        .clamp(0.0, 1.0);
    final residual = _lineFitResidualRatio(points.sublist(0, vertex + 1)) +
        _lineFitResidualRatio(points.sublist(vertex));
    final straightness = 1 / (1 + 36 * residual);
    splitScore = math.max(
      splitScore,
      headingCapture * support * straightness,
    );
  }
  // A cusp may be sampled as one dense turn or as several distributed events;
  // accept whichever bounded local description has stronger straight-leg
  // evidence. A continuous arc scores poorly in both descriptions.
  return math.max(densityScore, splitScore).clamp(0.0, 1.0);
}

double _lineFitResidualRatio(List<Offset> points) {
  if (points.length < 3) return 0;
  final start = points.first;
  final chord = points.last - start;
  final length = chord.distance;
  if (length <= .0001) return 1;
  var squared = 0.0;
  for (final point in points.skip(1).take(points.length - 2)) {
    final offset = point - start;
    final distance =
        (offset.dx * chord.dy - offset.dy * chord.dx).abs() / length;
    squared += distance * distance;
  }
  final rms = math.sqrt(squared / math.max(1, points.length - 2));
  return (rms / length).clamp(0.0, 1.0);
}

double _smoothUnit(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
