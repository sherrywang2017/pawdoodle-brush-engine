part of '../../streaming_stroke_modeler.dart';

/// Immutable, absolute-arc input to material response. It is derived only
/// from a modeled segment, so evaluating it never changes centerline state.
class PawStreamingMotionSample {
  const PawStreamingMotionSample({
    required this.absoluteArc,
    required this.pressure,
    required this.speedPixelsPerSecond,
    required this.signedCurvature,
  });

  final double absoluteArc;
  final double pressure;
  final double speedPixelsPerSecond;
  final double signedCurvature;
}

class PawStreamingSegmentCommand {
  const PawStreamingSegmentCommand({
    required this.index,
    required this.p0,
    required this.c1,
    required this.c2,
    required this.p1,
    required this.startTangent,
    required this.endTangent,
    required this.arcStart,
    required this.arcEnd,
    this.startPressure = .5,
    this.endPressure = .5,
    this.startTime = Duration.zero,
    this.endTime = Duration.zero,
  });

  final int index;
  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p1;
  final Offset startTangent;
  final Offset endTangent;
  final double arcStart;
  final double arcEnd;
  final double startPressure;
  final double endPressure;
  final Duration startTime;
  final Duration endTime;

  Offset pointAt(double t) => _cubicPoint(p0, c1, c2, p1, t);

  Offset tangentAt(double t) => _normalized(
        _cubicDerivative(p0, c1, c2, p1, t),
        fallback: endTangent,
      );

  PawStreamingMotionSample motionAt(double t, {required double absoluteArc}) {
    final clampedT = t.clamp(0.0, 1.0);
    final first = _cubicDerivative(p0, c1, c2, p1, clampedT);
    final second = _cubicSecondDerivative(p0, c1, c2, p1, clampedT);
    final derivativeLength = first.distance;
    final elapsedMicros = endTime.inMicroseconds - startTime.inMicroseconds;
    // Invalid or simultaneous event clocks must not accidentally look like a
    // slow deliberate stroke. 600 px/s is the documented neutral fallback.
    final speed = elapsedMicros > 0
        ? (arcEnd - arcStart).abs() /
            (elapsedMicros / Duration.microsecondsPerSecond)
        : 600.0;
    final cross = first.dx * second.dy - first.dy * second.dx;
    final curvature = derivativeLength > .000001
        ? cross / (derivativeLength * derivativeLength * derivativeLength)
        : 0.0;
    return PawStreamingMotionSample(
      absoluteArc: absoluteArc.isFinite ? absoluteArc : arcStart,
      pressure: (startPressure + (endPressure - startPressure) * clampedT)
          .clamp(0.0, 1.0),
      speedPixelsPerSecond: speed.isFinite ? speed.clamp(0.0, 24000.0) : 0.0,
      signedCurvature: curvature.isFinite ? curvature.clamp(-1.0, 1.0) : 0.0,
    );
  }
}
