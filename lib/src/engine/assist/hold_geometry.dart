part of '../../held_stroke_assist.dart';

class _LineFit {
  const _LineFit({required this.rmsResidual, required this.maximumResidual});

  final double rmsResidual;
  final double maximumResidual;
}

class _CubicGeometry {
  const _CubicGeometry({
    required this.p0,
    required this.c1,
    required this.c2,
    required this.p1,
    required this.startFraction,
    required this.endFraction,
  });

  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p1;
  final double startFraction;
  final double endFraction;
}

List<DrawingInputSample> _deduplicateSamples(
  List<DrawingInputSample> input,
  double minimumDistance,
) {
  final result = <DrawingInputSample>[];
  for (final sample in input) {
    if (!sample.hasFinitePosition) continue;
    if (result.isEmpty ||
        (sample.position - result.last.position).distance >= minimumDistance ||
        identical(sample, input.last)) {
      result.add(sample);
    }
  }
  return result;
}

double _pointScale(List<Offset> points) {
  if (points.isEmpty) return 0;
  var left = points.first.dx;
  var right = left;
  var top = points.first.dy;
  var bottom = top;
  for (final point in points.skip(1)) {
    left = math.min(left, point.dx);
    right = math.max(right, point.dx);
    top = math.min(top, point.dy);
    bottom = math.max(bottom, point.dy);
  }
  return math
      .sqrt((right - left) * (right - left) + (bottom - top) * (bottom - top));
}

double _polylineLength(List<Offset> points) {
  var result = 0.0;
  for (var index = 1; index < points.length; index++) {
    result += (points[index] - points[index - 1]).distance;
  }
  return result;
}

double _turnVariation(List<Offset> points) {
  if (points.length < 3) return 0;
  final turns = <double>[
    for (var index = 1; index < points.length - 1; index++)
      _turnAngle(points[index - 1], points[index], points[index + 1]),
  ];
  if (turns.isEmpty) return 0;
  final mean =
      turns.fold<double>(0, (sum, value) => sum + value) / turns.length;
  final variance = turns.fold<double>(
        0,
        (sum, value) => sum + (value - mean) * (value - mean),
      ) /
      turns.length;
  return (math.sqrt(variance) / math.pi).clamp(0.0, 1.0);
}

int _salientCornerCount(
  List<DrawingInputSample> samples,
  double scale,
) {
  if (samples.length < 5) return 0;
  final points = samples.map((sample) => sample.position).toList();
  final simplified = _rdpIndices(points, math.max(2.4, scale * .022));
  if (simplified.length < 3) return 0;
  var count = 0;
  var previousAcceptedIndex = -100;
  for (var simplifiedIndex = 1;
      simplifiedIndex < simplified.length - 1;
      simplifiedIndex++) {
    final rawIndex = simplified[simplifiedIndex];
    final turn = _turnAngle(
      points[simplified[simplifiedIndex - 1]],
      points[rawIndex],
      points[simplified[simplifiedIndex + 1]],
    ).abs();
    if (turn < 34 * math.pi / 180) continue;
    final evidence = PawLocalGeometryEvidence.analyze(
      samples,
      rawIndex,
      neighborhoodArc: math.max(48, scale * .2),
    );
    final straightSupported =
        evidence.incomingLineResidual + evidence.outgoingLineResidual <= .11;
    final localized = evidence.localizedCornerLikelihood >= .035 ||
        (turn >= 58 * math.pi / 180 && straightSupported);
    if (!localized) continue;
    // RDP can put two adjacent vertices around one rounded cusp. They describe
    // one turn episode and must not accidentally disable a one-corner stroke.
    if (rawIndex - previousAcceptedIndex <= 2) continue;
    count++;
    previousAcceptedIndex = rawIndex;
    if (count >= 2) return count;
  }
  return count;
}

_LineFit _orthogonalLineFit(List<Offset> points) {
  if (points.length < 2) {
    return const _LineFit(rmsResidual: 0, maximumResidual: 0);
  }
  var cx = 0.0;
  var cy = 0.0;
  for (final point in points) {
    cx += point.dx;
    cy += point.dy;
  }
  cx /= points.length;
  cy /= points.length;
  var xx = 0.0;
  var xy = 0.0;
  var yy = 0.0;
  for (final point in points) {
    final x = point.dx - cx;
    final y = point.dy - cy;
    xx += x * x;
    xy += x * y;
    yy += y * y;
  }
  final angle = .5 * math.atan2(2 * xy, xx - yy);
  final normal = Offset(-math.sin(angle), math.cos(angle));
  var squared = 0.0;
  var maximum = 0.0;
  for (final point in points) {
    final distance = ((point - Offset(cx, cy)).dx * normal.dx +
            (point - Offset(cx, cy)).dy * normal.dy)
        .abs();
    squared += distance * distance;
    maximum = math.max(maximum, distance);
  }
  return _LineFit(
    rmsResidual: math.sqrt(squared / points.length),
    maximumResidual: maximum,
  );
}

double _minimumConfidence(List<double> values) {
  if (values.isEmpty) return 0;
  var minimum = 1.0;
  for (final value in values) {
    minimum = math.min(minimum, value.clamp(0.0, 1.0));
  }
  return minimum;
}

double _averageConfidence(List<double> values) {
  if (values.isEmpty) return 0;
  return (values.fold<double>(
            0,
            (sum, value) => sum + value.clamp(0.0, 1.0),
          ) /
          values.length)
      .clamp(0.0, 1.0);
}

List<int> _rdpIndices(List<Offset> points, double epsilon) {
  if (points.length <= 2) return <int>[0, points.length - 1];
  final keep = <int>{0, points.length - 1};
  void visit(int start, int end) {
    if (end <= start + 1) return;
    var maximum = -1.0;
    var selected = -1;
    for (var index = start + 1; index < end; index++) {
      final distance = _distanceToLineSegment(
        points[index],
        points[start],
        points[end],
      );
      if (distance > maximum) {
        maximum = distance;
        selected = index;
      }
    }
    if (selected >= 0 && maximum > epsilon) {
      keep.add(selected);
      visit(start, selected);
      visit(selected, end);
    }
  }

  visit(0, points.length - 1);
  return keep.toList()..sort();
}

List<int> _openPolylineVertices(List<Offset> points, double scale) {
  final simplified = _rdpIndices(points, math.max(2.0, scale * .028));
  if (simplified.length < 3) return const <int>[];
  for (var index = 1; index < simplified.length - 1; index++) {
    final a = points[simplified[index - 1]];
    final b = points[simplified[index]];
    final c = points[simplified[index + 1]];
    if (_turnAngle(a, b, c).abs() < math.pi / 4) return const <int>[];
  }
  return simplified;
}

double _openPolylineConfidence(
  List<Offset> points,
  List<int> vertices,
  double scale,
) {
  var confidence = 1.0;
  for (var index = 1; index < vertices.length; index++) {
    final start = vertices[index - 1];
    final end = vertices[index];
    if (end <= start) return 0;
    final leg = points.sublist(start, end + 1);
    final length = (leg.last - leg.first).distance;
    if (length < math.max(5, scale * .06)) return 0;
    final fit = _orthogonalLineFit(leg);
    final tolerance = math.max(1.7, length * .035);
    confidence = math.min(
      confidence,
      (1 - fit.rmsResidual / tolerance).clamp(0.0, 1.0),
    );
  }
  return confidence;
}

List<int> _closedPolygonVertices(List<Offset> input, double scale) {
  if (input.length < 4) return const <int>[];
  final points = List<Offset>.from(input);
  points[points.length - 1] = points.first;
  final simplified = _rdpIndices(points, math.max(2.2, scale * .035));
  final vertices =
      simplified.where((index) => index < points.length - 1).toList();
  if (vertices.length < 3 || vertices.length > 4) return const <int>[];
  for (var index = 0; index < vertices.length; index++) {
    final previous =
        points[vertices[(index - 1 + vertices.length) % vertices.length]];
    final current = points[vertices[index]];
    final next = points[vertices[(index + 1) % vertices.length]];
    if (_turnAngle(previous, current, next).abs() < math.pi / 3) {
      return const <int>[];
    }
  }
  return vertices;
}

double _closedPolylineConfidence(
  List<Offset> points,
  List<int> vertices,
  double scale,
) {
  final ordered = <int>[...vertices, points.length - 1];
  var confidence = 1.0;
  for (var index = 1; index < ordered.length; index++) {
    final start = ordered[index - 1];
    final end = ordered[index];
    if (end <= start) continue;
    final leg = points.sublist(start, end + 1);
    final length = (leg.last - leg.first).distance;
    final fit = _orthogonalLineFit(leg);
    final tolerance = math.max(1.8, length * .04);
    confidence = math.min(
      confidence,
      (1 - fit.rmsResidual / tolerance).clamp(0.0, 1.0),
    );
  }
  return confidence;
}

double _turnAngle(Offset a, Offset b, Offset c) {
  final incoming = b - a;
  final outgoing = c - b;
  if (incoming.distance <= .0001 || outgoing.distance <= .0001) return 0;
  return math.atan2(
    incoming.dx * outgoing.dy - incoming.dy * outgoing.dx,
    incoming.dx * outgoing.dx + incoming.dy * outgoing.dy,
  );
}
