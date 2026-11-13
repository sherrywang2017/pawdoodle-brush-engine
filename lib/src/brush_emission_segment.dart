import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'streaming_stroke_modeler.dart';

/// Renderer-independent brush input derived from one modeled centerline
/// command.
///
/// The command remains the source of truth for the causal centerline. This
/// value is an immutable hand-off object: preview and commit can consume the
/// same cubic, arc, pressure, frame, and clock data without sharing a stroke
/// model or a renderer/cache.
@immutable
class PawBrushEmissionSegment {
  PawBrushEmissionSegment({
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
    this.parameterizeByArcLength = false,
  });

  factory PawBrushEmissionSegment.fromCommand(
    PawStreamingSegmentCommand command, {
    bool parameterizeByArcLength = false,
  }) =>
      PawBrushEmissionSegment(
        index: command.index,
        p0: command.p0,
        c1: command.c1,
        c2: command.c2,
        p1: command.p1,
        startTangent: command.startTangent,
        endTangent: command.endTangent,
        arcStart: command.arcStart,
        arcEnd: command.arcEnd,
        startPressure: command.startPressure,
        endPressure: command.endPressure,
        startTime: command.startTime,
        endTime: command.endTime,
        parameterizeByArcLength: parameterizeByArcLength,
      );

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
  final bool parameterizeByArcLength;

  // Hold assistance replaces many short input intervals with a few long
  // cubics. Equal cubic parameters are not equal traveled distances (most
  // visibly on elongated ellipses). Cache the inverse arc map per immutable
  // segment; freehand segments keep their existing, inexpensive sampling.
  late final List<double> _arcSamples = _buildArcSamples();

  List<double> _buildArcSamples() {
    final lengths = <double>[0];
    var previous = p0;
    for (var i = 1; i <= 128; i++) {
      final point = pointAt(i / 128);
      lengths.add(lengths.last + (point - previous).distance);
      previous = point;
    }
    return lengths;
  }

  double parameterAtArcFraction(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    if (!parameterizeByArcLength || clamped == 0 || clamped == 1) {
      return clamped;
    }
    final lengths = _arcSamples;
    if (lengths.last <= .000001) return clamped;
    final target = clamped * lengths.last;
    var low = 0, high = lengths.length - 1;
    while (high - low > 1) {
      final middle = (low + high) >> 1;
      if (lengths[middle] < target) {
        low = middle;
      } else {
        high = middle;
      }
    }
    final span = lengths[high] - lengths[low];
    final local = span > .000001 ? (target - lengths[low]) / span : 0.0;
    return (low + local) / (lengths.length - 1);
  }

  ({Offset point, Offset tangent, PawStreamingMotionSample motion})
      sampleAtArcFraction(double fraction, {required double absoluteArc}) {
    if (!parameterizeByArcLength) {
      return sampleAt(fraction, absoluteArc: absoluteArc);
    }
    final sample =
        sampleAt(parameterAtArcFraction(fraction), absoluteArc: absoluteArc);
    return (
      point: sample.point,
      tangent: sample.tangent,
      motion: PawStreamingMotionSample(
        absoluteArc: absoluteArc,
        pressure: pressureAt(fraction),
        speedPixelsPerSecond: sample.motion.speedPixelsPerSecond,
        signedCurvature: sample.motion.signedCurvature,
      ),
    );
  }

  /// Timestamp aliases make the data contract explicit at renderer
  /// boundaries while retaining the command's established field names.
  Duration get startTimestamp => startTime;
  Duration get endTimestamp => endTime;

  double get arcLength => arcEnd - arcStart;

  /// Evaluate position, direction and motion with one set of scalar cubic
  /// derivatives. Material frames used to evaluate derivatives twice and
  /// allocate intermediate Offsets for every polynomial term.
  ({Offset point, Offset tangent, PawStreamingMotionSample motion}) sampleAt(
      double amount,
      {required double absoluteArc}) {
    final t = amount.clamp(0.0, 1.0), u = 1 - t;
    final a = u * u * u, b = 3 * u * u * t;
    final c = 3 * u * t * t, d = t * t * t;
    final x = p0.dx * a + c1.dx * b + c2.dx * c + p1.dx * d;
    final y = p0.dy * a + c1.dy * b + c2.dy * c + p1.dy * d;
    final da = 3 * u * u, db = 6 * u * t, dc = 3 * t * t;
    final dx =
        (c1.dx - p0.dx) * da + (c2.dx - c1.dx) * db + (p1.dx - c2.dx) * dc;
    final dy =
        (c1.dy - p0.dy) * da + (c2.dy - c1.dy) * db + (p1.dy - c2.dy) * dc;
    final length = math.sqrt(dx * dx + dy * dy);
    final ddx = (c2.dx - 2 * c1.dx + p0.dx) * 6 * u +
        (p1.dx - 2 * c2.dx + c1.dx) * 6 * t;
    final ddy = (c2.dy - 2 * c1.dy + p0.dy) * 6 * u +
        (p1.dy - 2 * c2.dy + c1.dy) * 6 * t;
    final curvature = length > .000001
        ? (dx * ddy - dy * ddx) / (length * length * length)
        : 0.0;
    final elapsed = (endTime - startTime).inMicroseconds;
    final speed = elapsed > 0 ? arcLength.abs() * 1000000 / elapsed : 600.0;
    return (
      point: Offset(x, y),
      tangent: length > .000001
          ? Offset(dx / length, dy / length)
          : _normalized(endTangent, fallback: const Offset(1, 0)),
      motion: PawStreamingMotionSample(
          absoluteArc: absoluteArc,
          pressure: pressureAt(t),
          speedPixelsPerSecond: speed.isFinite ? speed.clamp(0.0, 24000.0) : 0,
          signedCurvature: curvature.isFinite ? curvature.clamp(-1.0, 1.0) : 0)
    );
  }

  Offset pointAt(double amount) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    final oneMinusT = 1 - t;
    return p0 * (oneMinusT * oneMinusT * oneMinusT) +
        c1 * (3 * oneMinusT * oneMinusT * t) +
        c2 * (3 * oneMinusT * t * t) +
        p1 * (t * t * t);
  }

  Offset tangentAt(double amount) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    final derivative = _cubicDerivative(p0, c1, c2, p1, t);
    return _normalized(derivative, fallback: endTangent);
  }

  double pressureAt(double amount) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    return (startPressure + (endPressure - startPressure) * t)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Duration timestampAt(double amount) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    final micros = startTime.inMicroseconds +
        ((endTime.inMicroseconds - startTime.inMicroseconds) * t).round();
    return Duration(microseconds: micros);
  }

  /// Signed cubic curvature in inverse logical pixels.
  double curvatureAt(double amount) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    final first = _cubicDerivative(p0, c1, c2, p1, t);
    final second = _cubicSecondDerivative(p0, c1, c2, p1, t);
    final length = first.distance;
    if (length <= .000001) return 0;
    final cross = first.dx * second.dy - first.dy * second.dx;
    final curvature = cross / (length * length * length);
    return curvature.isFinite ? curvature.clamp(-1.0, 1.0).toDouble() : 0;
  }

  PawStreamingMotionSample motionAt(
    double amount, {
    double? absoluteArc,
  }) {
    final t = amount.clamp(0.0, 1.0).toDouble();
    final elapsedMicros = endTime.inMicroseconds - startTime.inMicroseconds;
    final speed = elapsedMicros > 0
        ? arcLength.abs() / (elapsedMicros / Duration.microsecondsPerSecond)
        : 600.0;
    return PawStreamingMotionSample(
      absoluteArc: absoluteArc?.isFinite == true
          ? absoluteArc!
          : arcStart + arcLength * t,
      pressure: pressureAt(t),
      speedPixelsPerSecond: speed.isFinite ? speed.clamp(0.0, 24000.0) : 0,
      signedCurvature: curvatureAt(t),
    );
  }

  bool get hasFiniteGeometry => <Offset>[p0, c1, c2, p1]
      .every((point) => point.dx.isFinite && point.dy.isFinite);
}

Offset _cubicDerivative(Offset p0, Offset c1, Offset c2, Offset p1, double t) {
  final oneMinusT = 1 - t;
  return (c1 - p0) * (3 * oneMinusT * oneMinusT) +
      (c2 - c1) * (6 * oneMinusT * t) +
      (p1 - c2) * (3 * t * t);
}

Offset _cubicSecondDerivative(
  Offset p0,
  Offset c1,
  Offset c2,
  Offset p1,
  double t,
) {
  final oneMinusT = 1 - t;
  return (c2 - c1 * 2 + p0) * (6 * oneMinusT) + (p1 - c2 * 2 + c1) * (6 * t);
}

Offset _normalized(Offset value, {required Offset fallback}) {
  final length = value.distance;
  if (length > .000001) return value / length;
  final fallbackLength = fallback.distance;
  return fallbackLength > .000001
      ? fallback / fallbackLength
      : const Offset(1, 0);
}
