part of '../../held_stroke_assist.dart';

List<_CubicGeometry> _lineCubics(List<DrawingInputSample> raw) {
  final start = raw.first.position;
  final end = raw.last.position;
  final delta = end - start;
  return <_CubicGeometry>[
    _CubicGeometry(
      p0: start,
      c1: start + delta / 3,
      c2: start + delta * (2 / 3),
      p1: end,
      startFraction: 0,
      endFraction: 1,
    ),
  ];
}

List<_CubicGeometry> _polylineCubics(
  List<DrawingInputSample> raw,
  List<int> vertexIndices, {
  required bool closed,
}) {
  final indices = <int>[...vertexIndices];
  if (indices.isEmpty || indices.first != 0) indices.insert(0, 0);
  if (indices.last != raw.length - 1) indices.add(raw.length - 1);
  final result = <_CubicGeometry>[];
  for (var index = 1; index < indices.length; index++) {
    final startIndex = indices[index - 1];
    final endIndex = indices[index];
    final start = raw[startIndex].position;
    final end = raw[endIndex].position;
    final delta = end - start;
    result.add(_CubicGeometry(
      p0: start,
      c1: start + delta / 3,
      c2: start + delta * (2 / 3),
      p1: end,
      startFraction: startIndex / (raw.length - 1),
      endFraction: endIndex / (raw.length - 1),
    ));
  }
  return result;
}

List<_CubicGeometry> _arcCubics(
  List<DrawingInputSample> raw,
  PawCircleFit fit,
) {
  final direction = fit.signedSweep < 0 ? -1.0 : 1.0;
  final startVector = raw.first.position - fit.center;
  var startAngle = math.atan2(startVector.dy, startVector.dx);
  var sweep = fit.signedSweep;
  if (sweep.abs() > math.pi * 1.85) {
    sweep = direction * math.pi * 1.85;
  }
  final count = math.max(1, (sweep.abs() / (math.pi / 2)).ceil());
  final step = sweep / count;
  final result = <_CubicGeometry>[];
  for (var index = 0; index < count; index++) {
    final a0 = startAngle + step * index;
    final a1 = a0 + step;
    var p0 = fit.center + Offset(math.cos(a0), math.sin(a0)) * fit.radius;
    var p1 = fit.center + Offset(math.cos(a1), math.sin(a1)) * fit.radius;
    if (index == 0) p0 = raw.first.position;
    if (index == count - 1) p1 = raw.last.position;
    final handle = 4 / 3 * math.tan(step.abs() / 4) * fit.radius;
    final tangent0 = Offset(-math.sin(a0), math.cos(a0)) * direction;
    final tangent1 = Offset(-math.sin(a1), math.cos(a1)) * direction;
    result.add(_CubicGeometry(
      p0: p0,
      c1: p0 + tangent0 * handle,
      c2: p1 - tangent1 * handle,
      p1: p1,
      startFraction: index / count,
      endFraction: (index + 1) / count,
    ));
  }
  return result;
}

List<_CubicGeometry> _ellipseCubics(
  List<DrawingInputSample> raw,
  PawEllipseFit fit,
) {
  final cosR = math.cos(fit.rotationRadians);
  final sinR = math.sin(fit.rotationRadians);
  Offset transform(Offset local) =>
      fit.center +
      Offset(
        local.dx * cosR - local.dy * sinR,
        local.dx * sinR + local.dy * cosR,
      );
  Offset derivative(double angle) => Offset(
        -fit.majorRadius * math.sin(angle) * cosR -
            fit.minorRadius * math.cos(angle) * sinR,
        -fit.majorRadius * math.sin(angle) * sinR +
            fit.minorRadius * math.cos(angle) * cosR,
      );
  final first = raw.first.position - fit.center;
  final localX = first.dx * cosR + first.dy * sinR;
  final localY = -first.dx * sinR + first.dy * cosR;
  final start = math.atan2(
    localY / fit.minorRadius,
    localX / fit.majorRadius,
  );
  final direction = fit.signedSweep < 0 ? -1.0 : 1.0;
  final step = direction * math.pi / 2;
  const kappa = .5522847498307936;
  final closingPoint = transform(Offset(
    fit.majorRadius * math.cos(start),
    fit.minorRadius * math.sin(start),
  ));
  final result = <_CubicGeometry>[];
  for (var index = 0; index < 4; index++) {
    final a0 = start + step * index;
    final a1 = a0 + step;
    var p0 = transform(Offset(
      fit.majorRadius * math.cos(a0),
      fit.minorRadius * math.sin(a0),
    ));
    var p1 = transform(Offset(
      fit.majorRadius * math.cos(a1),
      fit.minorRadius * math.sin(a1),
    ));
    // An accepted circle/ellipse is an explicit Hold correction, so its fitted
    // geometry must close even when the raw gesture did not. Snapping the two
    // ends back to raw.first/raw.last re-opened the fitted ellipse and defeated
    // the near-closed classifier contract.
    if (index == 0) p0 = closingPoint;
    if (index == 3) p1 = closingPoint;
    final d0 = derivative(a0) * direction;
    final d1 = derivative(a1) * direction;
    result.add(_CubicGeometry(
      p0: p0,
      c1: p0 + _normalized(d0) * (d0.distance * kappa),
      c2: p1 - _normalized(d1) * (d1.distance * kappa),
      p1: p1,
      startFraction: index / 4,
      endFraction: (index + 1) / 4,
    ));
  }
  return result;
}

List<_CubicGeometry> _curveFitCubics(
  List<DrawingInputSample> raw,
  PawHeldCurveFit fit,
) =>
    <_CubicGeometry>[
      for (final segment in fit.segments)
        _CubicGeometry(
          p0: segment.p0,
          c1: segment.c1,
          c2: segment.c2,
          p1: segment.p1,
          startFraction:
              segment.startSampleIndex / math.max(1, fit.sourcePointCount - 1),
          endFraction:
              segment.endSampleIndex / math.max(1, fit.sourcePointCount - 1),
        ),
    ];

List<_CubicGeometry> _freeformCubics(
  List<DrawingInputSample> raw,
  PawStrokeHoldAssistConfiguration configuration,
) {
  final scale = _pointScale(raw.map((sample) => sample.position).toList());
  final corridor = configuration.fidelityCorridorFor(scale);
  final samples = _resampleByArc(raw, math.max(.8, corridor * .55));
  if (samples.length < 3) return _linearCubics(samples);
  final points = samples.map((sample) => sample.position).toList();
  final simplified = _rdpIndices(points, math.max(1.2, corridor * .65));
  final fitSamples = <DrawingInputSample>[
    for (final index in simplified) samples[index],
  ];
  if (fitSamples.length < 3) return _linearCubics(fitSamples);
  final fitPoints = fitSamples.map((sample) => sample.position).toList();
  final signedTurns = <double>[
    for (var index = 1; index < fitPoints.length - 1; index++)
      _turnAngle(fitPoints[index - 1], fitPoints[index], fitPoints[index + 1]),
  ];
  final cusps = <int>{0, fitSamples.length - 1};
  for (var index = 1; index < fitPoints.length - 1; index++) {
    final turn = signedTurns[index - 1];
    if (turn.abs() < math.pi * .28) continue;
    final previousTurn = index >= 2 ? signedTurns[index - 2] : 0.0;
    final nextTurn = index < fitPoints.length - 2 ? signedTurns[index] : 0.0;
    final neighbouringHeading = previousTurn.abs() + nextTurn.abs();
    final sameSignDistributed = previousTurn * turn > 0 &&
        nextTurn * turn > 0 &&
        neighbouringHeading >= turn.abs() * .7;
    final localization =
        turn.abs() / math.max(.0001, turn.abs() + neighbouringHeading);
    if (!sameSignDistributed && localization >= .55) cusps.add(index);
  }
  final boundaries = cusps.toList()..sort();
  final result = <_CubicGeometry>[];
  for (var span = 1; span < boundaries.length; span++) {
    final start = boundaries[span - 1];
    final end = boundaries[span];
    for (var index = start; index < end; index++) {
      final p0 = fitPoints[index];
      final p1 = fitPoints[index + 1];
      final previous = fitPoints[index == start ? index : index - 1];
      final next = fitPoints[index + 1 == end ? index + 1 : index + 2];
      final startTangent = (p1 - previous) * .5;
      final endTangent = (next - p0) * .5;
      result.add(_CubicGeometry(
        p0: p0,
        c1: p0 + startTangent / 3,
        c2: p1 - endTangent / 3,
        p1: p1,
        startFraction: simplified[index] / (samples.length - 1),
        endFraction: simplified[index + 1] / (samples.length - 1),
      ));
    }
  }
  return result;
}

List<_CubicGeometry> _linearCubics(List<DrawingInputSample> samples) {
  final result = <_CubicGeometry>[];
  for (var index = 1; index < samples.length; index++) {
    final p0 = samples[index - 1].position;
    final p1 = samples[index].position;
    final delta = p1 - p0;
    result.add(_CubicGeometry(
      p0: p0,
      c1: p0 + delta / 3,
      c2: p0 + delta * (2 / 3),
      p1: p1,
      startFraction: (index - 1) / (samples.length - 1),
      endFraction: index / (samples.length - 1),
    ));
  }
  return result;
}
