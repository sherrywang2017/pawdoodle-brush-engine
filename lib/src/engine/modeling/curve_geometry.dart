part of '../../streaming_stroke_modeler.dart';

PawStreamingSegmentCommand? _segmentAtArc(
  List<PawStreamingSegmentCommand> segments,
  double arc,
) {
  if (segments.isEmpty) return null;
  var low = 0;
  var high = segments.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final segment = segments[middle];
    if (arc < segment.arcStart) {
      high = middle - 1;
    } else if (arc > segment.arcEnd) {
      low = middle + 1;
    } else {
      return segment;
    }
  }
  return arc <= segments.first.arcStart ? segments.first : segments.last;
}

Offset _fixedIntervalTarget({
  required DrawingInputSample? penultimateRaw,
  required DrawingInputSample previousRaw,
  required DrawingInputSample sample,
  required double fraction,
  required bool curvedIntervalTargets,
  required bool conservativeTarget,
  required double curvedTargetMaxHandleFactor,
}) =>
    curvedIntervalTargets && !conservativeTarget && penultimateRaw != null
        ? _curvedIntervalPoint(
            penultimateRaw.position,
            previousRaw.position,
            sample.position,
            fraction,
            curvedTargetMaxHandleFactor,
          )
        : Offset.lerp(
            previousRaw.position,
            sample.position,
            fraction,
          )!;

int? _minimumMicros(int? first, int? second) {
  if (first == null) return second;
  if (second == null) return first;
  return math.min(first, second);
}

Offset _curvedIntervalPoint(
  Offset penultimate,
  Offset start,
  Offset end,
  double t,
  double maximumHandleFactor,
) {
  final chord = end - start;
  final distance = chord.distance;
  if (distance <= .0001) return start;
  final ax = penultimate.dx;
  final ay = penultimate.dy;
  final bx = start.dx;
  final by = start.dy;
  final cx = end.dx;
  final cy = end.dy;
  final determinant = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
  if (determinant.abs() > .0001) {
    final aa = ax * ax + ay * ay;
    final bb = bx * bx + by * by;
    final cc = cx * cx + cy * cy;
    final center = Offset(
      (aa * (by - cy) + bb * (cy - ay) + cc * (ay - by)) / determinant,
      (aa * (cx - bx) + bb * (ax - cx) + cc * (bx - ax)) / determinant,
    );
    final startRadius = start - center;
    final endRadius = end - center;
    final radius = startRadius.distance;
    final cross = (start - penultimate).dx * chord.dy -
        (start - penultimate).dy * chord.dx;
    if (radius.isFinite && radius > .0001 && cross.abs() > .0001) {
      final direction = cross > 0 ? 1.0 : -1.0;
      final startTangent = _normalized(
        Offset(-startRadius.dy, startRadius.dx) * direction,
        fallback: chord,
      );
      final endTangent = _normalized(
        Offset(-endRadius.dy, endRadius.dx) * direction,
        fallback: chord,
      );
      final cosine =
          (startRadius.dx * endRadius.dx + startRadius.dy * endRadius.dy) /
              (radius * radius);
      final angle = math.acos(cosine.clamp(-1.0, 1.0));
      final handle = math.min(
        4 / 3 * math.tan(angle / 4) * radius,
        distance * maximumHandleFactor,
      );
      return _cubicPoint(
        start,
        start + startTangent * handle,
        end - endTangent * handle,
        end,
        t,
      );
    }
  }
  final previousChord = start - penultimate;
  final startTangent = _normalized(end - penultimate, fallback: chord);
  final endTangent = _normalized(
    chord * 2 - previousChord,
    fallback: chord,
  );
  final handle = distance / 3;
  return _cubicPoint(
    start,
    start + startTangent * handle,
    end - endTangent * handle,
    end,
    t,
  );
}

Offset _initialCircularTangent(
  Offset first,
  Offset second,
  Offset third, {
  required Offset fallback,
}) {
  final incoming = second - first;
  final outgoing = third - second;
  final incomingLength = incoming.distance;
  final outgoingLength = outgoing.distance;
  if (incomingLength <= .0001 || outgoingLength <= .0001) return fallback;
  final turn = _signedTurnRadians(incoming, outgoing);
  if (turn.abs() < 2 * math.pi / 180 ||
      turn.abs() > 65 * math.pi / 180 ||
      math.min(incomingLength, outgoingLength) /
              math.max(incomingLength, outgoingLength) <
          .16) {
    return fallback;
  }
  final ax = first.dx;
  final ay = first.dy;
  final bx = second.dx;
  final by = second.dy;
  final cx = third.dx;
  final cy = third.dy;
  final determinant = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by));
  if (determinant.abs() <= .0001) return fallback;
  final aa = ax * ax + ay * ay;
  final bb = bx * bx + by * by;
  final cc = cx * cx + cy * cy;
  final center = Offset(
    (aa * (by - cy) + bb * (cy - ay) + cc * (ay - by)) / determinant,
    (aa * (cx - bx) + bb * (ax - cx) + cc * (bx - ax)) / determinant,
  );
  final radius = first - center;
  if (!radius.distance.isFinite || radius.distance <= .0001) return fallback;
  var tangent = _normalized(
    Offset(-radius.dy, radius.dx) * (turn < 0 ? -1.0 : 1.0),
    fallback: fallback,
  );
  if (tangent.dx * incoming.dx + tangent.dy * incoming.dy < 0) {
    tangent = -tangent;
  }
  return tangent;
}

double _curveLength(Offset p0, Offset c1, Offset c2, Offset p1) {
  var length = 0.0;
  var previous = p0;
  for (var index = 1; index <= 8; index++) {
    final point = _cubicPoint(p0, c1, c2, p1, index / 8);
    length += (point - previous).distance;
    previous = point;
  }
  return length;
}

({Offset c1, Offset c2}) _boundedCubicHandles({
  required Offset p0,
  required Offset c1,
  required Offset c2,
  required Offset p1,
  required double corridor,
}) {
  final chord = p1 - p0;
  final length = chord.distance;
  if (length > .000001) {
    double projection(Offset point) =>
        ((point.dx - p0.dx) * chord.dx + (point.dy - p0.dy) * chord.dy) /
        length;
    final firstProjection = projection(c1), secondProjection = projection(c2);
    if (firstProjection >= 0 &&
        firstProjection <= length &&
        secondProjection >= 0 &&
        secondProjection <= length) {
      // Within the chord's longitudinal slab, the exact corridor distance is
      // the perpendicular cubic. Its two derivative roots replace repeated
      // point probes, which could miss the maximum between probes.
      double normal(Offset point) =>
          (chord.dx * (point.dy - p0.dy) - chord.dy * (point.dx - p0.dx)) /
          length;
      final q1 = normal(c1), q2 = normal(c2);
      final a = 3 * (q1 - q2), b = 2 * q2 - 4 * q1, c = q1;
      var maximum = 0.0;
      void probe(double t) {
        if (t <= 0 || t >= 1) return;
        final u = 1 - t;
        maximum = math.max(maximum, (3 * t * u * (q1 * u + q2 * t)).abs());
      }

      if (a.abs() < 1e-12) {
        if (b.abs() > 1e-12) probe(-c / b);
      } else {
        final discriminant = b * b - 4 * a * c;
        if (discriminant >= 0) {
          final root = math.sqrt(discriminant);
          probe((-b - root) / (2 * a));
          probe((-b + root) / (2 * a));
        }
      }
      final scale = maximum <= corridor ? 1.0 : corridor / maximum;
      return (c1: Offset.lerp(p0, c1, scale)!, c2: Offset.lerp(p1, c2, scale)!);
    }
  }
  bool fits(double scale) {
    final first = Offset.lerp(p0, c1, scale)!;
    final second = Offset.lerp(p1, c2, scale)!;
    for (var probe = 1; probe < 8; probe++) {
      final point = _cubicPoint(p0, first, second, p1, probe / 8);
      if (_distanceToChordSegment(point, p0, p1) > corridor + .0001) {
        return false;
      }
    }
    return true;
  }

  if (fits(1)) return (c1: c1, c2: c2);
  var lower = 0.0;
  var upper = 1.0;
  // Eight bounded iterations give sub-percent handle precision without an
  // unbounded optimizer on the pointer hot path.
  for (var iteration = 0; iteration < 8; iteration++) {
    final middle = (lower + upper) / 2;
    if (fits(middle)) {
      lower = middle;
    } else {
      upper = middle;
    }
  }
  return (
    c1: Offset.lerp(p0, c1, lower)!,
    c2: Offset.lerp(p1, c2, lower)!,
  );
}

double _distanceToChordSegment(Offset point, Offset start, Offset end) {
  final chord = end - start;
  final lengthSquared = chord.dx * chord.dx + chord.dy * chord.dy;
  if (lengthSquared <= .000001) return (point - start).distance;
  final t = (((point - start).dx * chord.dx + (point - start).dy * chord.dy) /
          lengthSquared)
      .clamp(0.0, 1.0);
  return (point - (start + chord * t)).distance;
}

Offset _projectToReferenceHalfPlane({
  required Offset point,
  required Offset lineStart,
  required Offset lineEnd,
  required Offset reference,
  double allowance = 0,
}) {
  final line = lineEnd - lineStart;
  final lengthSquared = line.dx * line.dx + line.dy * line.dy;
  if (lengthSquared <= .000001) return point;
  double cross(Offset value) => line.dx * value.dy - line.dy * value.dx;
  final referenceCross = cross(reference - lineStart);
  final pointCross = cross(point - lineStart);
  if (referenceCross.abs() <= .000001 ||
      pointCross.abs() <= .000001 ||
      referenceCross.sign == pointCross.sign) {
    return point;
  }
  final projection =
      ((point - lineStart).dx * line.dx + (point - lineStart).dy * line.dy) /
          lengthSquared;
  final boundedProjection = projection.clamp(0.0, 1.0);
  final projected = lineStart + line * boundedProjection;
  if (allowance <= .000001) return projected;
  final lineLength = math.sqrt(lengthSquared);
  final leftNormal = Offset(-line.dy / lineLength, line.dx / lineLength);
  return projected + leftNormal * (pointCross.sign * allowance);
}

Offset _normalized(Offset value, {required Offset fallback}) {
  final length = value.distance;
  if (!length.isFinite || length <= .000001) return fallback;
  return Offset(value.dx / length, value.dy / length);
}

Offset _cubicPoint(
  Offset start,
  Offset control1,
  Offset control2,
  Offset end,
  double t,
) {
  final oneMinusT = 1 - t;
  return start * (oneMinusT * oneMinusT * oneMinusT) +
      control1 * (3 * oneMinusT * oneMinusT * t) +
      control2 * (3 * oneMinusT * t * t) +
      end * (t * t * t);
}

Offset _cubicDerivative(
  Offset start,
  Offset control1,
  Offset control2,
  Offset end,
  double t,
) {
  final oneMinusT = 1 - t;
  return (control1 - start) * (3 * oneMinusT * oneMinusT) +
      (control2 - control1) * (6 * oneMinusT * t) +
      (end - control2) * (3 * t * t);
}

Offset _cubicSecondDerivative(
  Offset start,
  Offset control1,
  Offset control2,
  Offset end,
  double t,
) =>
    (control2 - control1 * 2 + start) * (6 * (1 - t)) +
    (end - control2 * 2 + control1) * (6 * t);
