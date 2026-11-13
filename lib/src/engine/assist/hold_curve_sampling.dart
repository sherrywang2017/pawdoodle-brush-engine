part of '../../held_stroke_assist.dart';

List<DrawingInputSample> _resampleByArc(
  List<DrawingInputSample> raw,
  double spacing,
) {
  if (raw.length < 2) return List<DrawingInputSample>.from(raw);
  final cumulative = List<double>.filled(raw.length, 0);
  for (var index = 1; index < raw.length; index++) {
    cumulative[index] = cumulative[index - 1] +
        (raw[index].position - raw[index - 1].position).distance;
  }
  final total = cumulative.last;
  if (total <= spacing) return <DrawingInputSample>[raw.first, raw.last];
  final count = math.max(2, (total / spacing).ceil());
  final result = <DrawingInputSample>[];
  var source = 1;
  for (var index = 0; index <= count; index++) {
    final target = total * index / count;
    while (source < cumulative.length - 1 && cumulative[source] < target) {
      source++;
    }
    final start = source - 1;
    final length = cumulative[source] - cumulative[start];
    final amount = length <= .0001
        ? 0.0
        : ((target - cumulative[start]) / length).clamp(0.0, 1.0);
    result.add(_interpolateSample(raw[start], raw[source], amount));
  }
  result[0] = raw.first;
  result[result.length - 1] = raw.last;
  return result;
}

DrawingInputSample _interpolateSample(
  DrawingInputSample first,
  DrawingInputSample second,
  double amount,
) {
  final t = amount.clamp(0.0, 1.0);
  return DrawingInputSample(
    x: first.x + (second.x - first.x) * t,
    y: first.y + (second.y - first.y) * t,
    timestamp: Duration(
      microseconds: first.timestamp.inMicroseconds +
          ((second.timestamp.inMicroseconds - first.timestamp.inMicroseconds) *
                  t)
              .round(),
    ),
    pressure: first.pressure + (second.pressure - first.pressure) * t,
    pressureMin: first.pressureMin,
    pressureMax: first.pressureMax,
    deviceKind: first.deviceKind,
  );
}

List<PawStreamingSegmentCommand> _commandsFromCubics(
  List<_CubicGeometry> cubics,
  List<DrawingInputSample> raw,
) {
  if (raw.length < 2) return const <PawStreamingSegmentCommand>[];
  final result = <PawStreamingSegmentCommand>[];
  var arc = 0.0;
  for (final cubic in cubics) {
    final length = _cubicLength(cubic);
    if (!length.isFinite || length <= .001) continue;
    final startSample = _sampleAtFraction(raw, cubic.startFraction);
    final endSample = _sampleAtFraction(raw, cubic.endFraction);
    result.add(PawStreamingSegmentCommand(
      index: result.length,
      p0: cubic.p0,
      c1: cubic.c1,
      c2: cubic.c2,
      p1: cubic.p1,
      startTangent:
          _normalized(cubic.c1 - cubic.p0, fallback: cubic.p1 - cubic.p0),
      endTangent:
          _normalized(cubic.p1 - cubic.c2, fallback: cubic.p1 - cubic.p0),
      arcStart: arc,
      arcEnd: arc + length,
      startPressure: startSample.normalizedPressure ?? .5,
      endPressure: endSample.normalizedPressure ?? .5,
      startTime: startSample.timestamp,
      endTime: endSample.timestamp,
    ));
    arc += length;
  }
  return result;
}

DrawingInputSample _sampleAtFraction(
  List<DrawingInputSample> raw,
  double fraction,
) {
  final scaled = fraction.clamp(0.0, 1.0) * (raw.length - 1);
  final start = scaled.floor().clamp(0, raw.length - 1);
  final end = scaled.ceil().clamp(0, raw.length - 1);
  if (start == end) return raw[start];
  return _interpolateSample(raw[start], raw[end], scaled - start);
}

double _cubicLength(_CubicGeometry cubic) {
  var length = 0.0;
  var previous = cubic.p0;
  for (var index = 1; index <= 24; index++) {
    final current = _cubicPoint(cubic, index / 24);
    length += (current - previous).distance;
    previous = current;
  }
  return length;
}

double _maximumRefinementDistance(
  List<DrawingInputSample> raw,
  List<PawStreamingSegmentCommand> segments,
) {
  if (raw.isEmpty || segments.isEmpty) return 0;
  final probes = <Offset>[];
  for (final segment in segments) {
    for (var index = 0; index <= 16; index++) {
      probes.add(segment.pointAt(index / 16));
    }
  }
  var maximum = 0.0;
  for (final sample in raw) {
    var nearest = double.infinity;
    for (var index = 1; index < probes.length; index++) {
      nearest = math.min(
        nearest,
        _distanceToLineSegment(
            sample.position, probes[index - 1], probes[index]),
      );
    }
    maximum = math.max(maximum, nearest);
  }
  return maximum;
}

double _distanceToLineSegment(Offset point, Offset start, Offset end) {
  final delta = end - start;
  final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
  if (lengthSquared <= .000001) return (point - start).distance;
  final t = (((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
          lengthSquared)
      .clamp(0.0, 1.0);
  return (point - (start + delta * t)).distance;
}

Offset _cubicPoint(_CubicGeometry cubic, double t) {
  final u = 1 - t;
  return cubic.p0 * (u * u * u) +
      cubic.c1 * (3 * u * u * t) +
      cubic.c2 * (3 * u * t * t) +
      cubic.p1 * (t * t * t);
}

Offset _normalized(Offset value, {Offset fallback = const Offset(1, 0)}) {
  final length = value.distance;
  if (length > .000001) return value / length;
  final fallbackLength = fallback.distance;
  return fallbackLength > .000001
      ? fallback / fallbackLength
      : const Offset(1, 0);
}
