part of '../../streaming_stroke_modeler.dart';

class _CurvaturePrediction {
  const _CurvaturePrediction({
    required this.offset,
    required this.horizonSeconds,
    required this.signedAngularVelocity,
    required this.confidence,
  });

  final Offset offset;
  final double horizonSeconds;
  final double signedAngularVelocity;
  final double confidence;
}

_CurvaturePrediction _curvatureAwarePrediction({
  required List<DrawingInputSample> samples,
  required Offset velocity,
  required double baseHorizonSeconds,
}) {
  if (baseHorizonSeconds <= 0 || velocity.distance <= .0001) {
    return const _CurvaturePrediction(
      offset: Offset.zero,
      horizonSeconds: 0,
      signedAngularVelocity: 0,
      confidence: 0,
    );
  }
  if (samples.length < 3) {
    return _CurvaturePrediction(
      offset: velocity * baseHorizonSeconds,
      horizonSeconds: baseHorizonSeconds,
      signedAngularVelocity: 0,
      confidence: 0,
    );
  }
  final vertex = samples.length - 2;
  final incoming = samples[vertex].position - samples[vertex - 1].position;
  final outgoing = samples[vertex + 1].position - samples[vertex].position;
  final elapsedMicros = samples[vertex + 1].timestamp.inMicroseconds -
      samples[vertex].timestamp.inMicroseconds;
  if (elapsedMicros <= 0 ||
      incoming.distance <= .5 ||
      outgoing.distance <= .5) {
    return _CurvaturePrediction(
      offset: velocity * baseHorizonSeconds,
      horizonSeconds: baseHorizonSeconds,
      signedAngularVelocity: 0,
      confidence: 0,
    );
  }
  final turn = _signedTurnRadians(incoming, outgoing);
  final angularVelocity =
      turn / (elapsedMicros / Duration.microsecondsPerSecond);
  final evidence = PawLocalGeometryEvidence.analyze(samples, vertex);
  final confidence = evidence.evidenceConfidence;
  final angularSpeed = angularVelocity.abs();
  if (turn.abs() >= math.pi * .65) {
    // A starved near-reversal does not carry enough temporal geometry to
    // choose an extrapolation side. The modeler remains the sole prediction
    // owner, but deliberately publishes no speculative offset for this case.
    return _CurvaturePrediction(
      offset: Offset.zero,
      horizonSeconds: 0,
      signedAngularVelocity: angularVelocity,
      confidence: confidence,
    );
  }
  var horizonScale = 1 / (1 + angularSpeed * .045);
  if (confidence < .55 && angularSpeed > 18) {
    horizonScale *= (.35 + confidence).clamp(.35, .9);
  }
  if (confidence < .4 && angularSpeed > 90) horizonScale = 0;
  horizonScale = horizonScale.clamp(0.0, 1.0);
  final horizon = baseHorizonSeconds * horizonScale;
  if (horizon <= .00001) {
    return _CurvaturePrediction(
      offset: Offset.zero,
      horizonSeconds: 0,
      signedAngularVelocity: angularVelocity,
      confidence: confidence,
    );
  }
  final outgoingDirection = _normalized(outgoing, fallback: velocity);
  // Integrate a constant-turn-rate arc over the short speculative horizon.
  // Rotating by half the expected heading change approximates the arc chord
  // and avoids the tangent spike produced by constant-velocity prediction.
  final chordAngle = angularVelocity * horizon * .5;
  final cosine = math.cos(chordAngle);
  final sine = math.sin(chordAngle);
  final predictedDirection = Offset(
    outgoingDirection.dx * cosine - outgoingDirection.dy * sine,
    outgoingDirection.dx * sine + outgoingDirection.dy * cosine,
  );
  return _CurvaturePrediction(
    offset: predictedDirection * velocity.distance * horizon,
    horizonSeconds: horizon,
    signedAngularVelocity: angularVelocity,
    confidence: confidence,
  );
}
