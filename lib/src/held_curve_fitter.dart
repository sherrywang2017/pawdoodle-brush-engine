import 'dart:math' as math;
import 'dart:ui';

import 'smooth_stroke.dart';
import 'streaming_stroke_modeler.dart';

/// One cubic produced by the held-stroke beautifier.
class PawHeldBezierFitSegment {
  const PawHeldBezierFitSegment({
    required this.p0,
    required this.c1,
    required this.c2,
    required this.p1,
    required this.startSampleIndex,
    required this.endSampleIndex,
  });

  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p1;
  final int startSampleIndex;
  final int endSampleIndex;
}

class PawHeldCurveFit {
  const PawHeldCurveFit({
    required this.segments,
    required this.rmsResidual,
    required this.maximumResidual,
    required this.salientCuspIndices,
    required this.sourcePointCount,
  });

  final List<PawHeldBezierFitSegment> segments;
  final double rmsResidual;
  final double maximumResidual;
  final List<int> salientCuspIndices;
  final int sourcePointCount;

  double get segmentReductionRatio =>
      sourcePointCount <= 1 ? 0 : 1 - segments.length / (sourcePointCount - 1);
}

/// Clean Dart implementation of the public algorithm described by Philip J.
/// Schneider, "An Algorithm for Automatically Fitting Digitized Curves",
/// Graphics Gems (1990), pp. 612-626.
///
/// This is not a source port: it independently implements chord-length
/// parameterization, least-squares cubic generation, Newton reparameterization
/// and maximum-error splitting. Recursion and segment count are hard-bounded.
class PawHeldCurveFitter {
  const PawHeldCurveFitter({
    this.maximumSegments = 8,
    this.maximumNewtonIterations = 4,
    this.enablePostFitFairing = true,
  })  : assert(maximumSegments > 0),
        assert(maximumNewtonIterations >= 0);

  final int maximumSegments;
  final int maximumNewtonIterations;
  final bool enablePostFitFairing;

  PawHeldCurveFit fit(
    List<DrawingInputSample> input, {
    required double tolerance,
  }) {
    if (input.length < 2) {
      return PawHeldCurveFit(
        segments: const <PawHeldBezierFitSegment>[],
        rmsResidual: 0,
        maximumResidual: 0,
        salientCuspIndices: const <int>[],
        sourcePointCount: input.length,
      );
    }
    final samples = <DrawingInputSample>[];
    for (final sample in input) {
      if (!sample.hasFinitePosition) continue;
      if (samples.isEmpty ||
          (sample.position - samples.last.position).distance >= .18 ||
          identical(sample, input.last)) {
        samples.add(sample);
      }
    }
    if (samples.length < 2) {
      return PawHeldCurveFit(
        segments: const <PawHeldBezierFitSegment>[],
        rmsResidual: 0,
        maximumResidual: 0,
        salientCuspIndices: const <int>[],
        sourcePointCount: samples.length,
      );
    }
    final points = samples.map((sample) => sample.position).toList();
    final cuspIndices = <int>[];
    for (var index = 1; index < samples.length - 1; index++) {
      final evidence = PawLocalGeometryEvidence.analyze(samples, index);
      if (_isSalientHeldCusp(samples, index, evidence)) {
        cuspIndices.add(index);
      }
    }
    final boundaries = <int>[0, ...cuspIndices, points.length - 1];
    final output = <PawHeldBezierFitSegment>[];
    for (var span = 1; span < boundaries.length; span++) {
      final first = boundaries[span - 1];
      // Reserve one segment for every remaining span. If there are more
      // cusps than the budget, the last segment must still reach the endpoint.
      final remaining = maximumSegments - output.length;
      final last = remaining == 1 ? points.length - 1 : boundaries[span];
      final budget = math.max(1, remaining - (boundaries.length - 1 - span));
      final leftTangent = _normalized(
        points[math.min(first + 1, last)] - points[first],
      );
      final rightTangent = _normalized(
        points[math.max(first, last - 1)] - points[last],
      );
      _fitSpan(
        points,
        first,
        last,
        leftTangent,
        rightTangent,
        tolerance * tolerance,
        output,
        0,
        budget,
      );
      if (last == points.length - 1) break;
    }
    if (output.isEmpty) {
      final delta = points.last - points.first;
      output.add(PawHeldBezierFitSegment(
        p0: points.first,
        c1: points.first + delta / 3,
        c2: points.first + delta * (2 / 3),
        p1: points.last,
        startSampleIndex: 0,
        endSampleIndex: points.length - 1,
      ));
    }
    final merged = enablePostFitFairing
        ? _mergeAdjacentSegments(
            points,
            output,
            cuspIndices.toSet(),
            tolerance,
          )
        : output;
    final faired = enablePostFitFairing
        ? _fairNonCuspJoins(
            points,
            merged,
            cuspIndices.toSet(),
            tolerance,
          )
        : merged;
    final residual = _residuals(points, faired);
    return PawHeldCurveFit(
      segments: List<PawHeldBezierFitSegment>.unmodifiable(faired),
      rmsResidual: residual.rms,
      maximumResidual: residual.maximum,
      salientCuspIndices: List<int>.unmodifiable(cuspIndices),
      sourcePointCount: samples.length,
    );
  }

  List<PawHeldBezierFitSegment> _mergeAdjacentSegments(
    List<Offset> points,
    List<PawHeldBezierFitSegment> input,
    Set<int> cuspIndices,
    double tolerance,
  ) {
    if (input.length < 2) return List<PawHeldBezierFitSegment>.of(input);
    final result = <PawHeldBezierFitSegment>[];
    var index = 0;
    while (index < input.length) {
      var current = input[index];
      while (index + 1 < input.length &&
          !cuspIndices.contains(current.endSampleIndex)) {
        final next = input[index + 1];
        final first = current.startSampleIndex;
        final last = next.endSampleIndex;
        final parameters = _chordLengthParameters(points, first, last);
        final candidate = _generateBezier(
          points,
          first,
          last,
          parameters,
          _normalized(current.c1 - current.p0,
              fallback: current.p1 - current.p0),
          _normalized(next.c2 - next.p1, fallback: next.p0 - next.p1),
        );
        final error = _maximumError(
          points,
          first,
          last,
          candidate,
          parameters,
        );
        if (error.errorSquared > tolerance * tolerance * 1.21) break;
        current = candidate;
        index++;
      }
      result.add(current);
      index++;
    }
    return result;
  }

  List<PawHeldBezierFitSegment> _fairNonCuspJoins(
    List<Offset> points,
    List<PawHeldBezierFitSegment> input,
    Set<int> cuspIndices,
    double tolerance,
  ) {
    if (input.length < 2) return List<PawHeldBezierFitSegment>.of(input);
    final result = List<PawHeldBezierFitSegment>.of(input);
    for (var index = 0; index < result.length - 1; index++) {
      final left = result[index];
      final right = result[index + 1];
      if (cuspIndices.contains(left.endSampleIndex)) continue;
      final join = left.p1;
      final incoming = join - left.c2;
      final outgoing = right.c1 - join;
      if (incoming.distance <= .0001 || outgoing.distance <= .0001) continue;
      final tangent = _normalized(
        _normalized(incoming) + _normalized(outgoing),
        fallback: right.p1 - left.p0,
      );
      final handle = math.sqrt(incoming.distance * outgoing.distance);
      final fairedLeft = PawHeldBezierFitSegment(
        p0: left.p0,
        c1: left.c1,
        c2: join - tangent * handle,
        p1: join,
        startSampleIndex: left.startSampleIndex,
        endSampleIndex: left.endSampleIndex,
      );
      final fairedRight = PawHeldBezierFitSegment(
        p0: join,
        c1: join + tangent * handle,
        c2: right.c2,
        p1: right.p1,
        startSampleIndex: right.startSampleIndex,
        endSampleIndex: right.endSampleIndex,
      );
      final trial = List<PawHeldBezierFitSegment>.of(result)
        ..[index] = fairedLeft
        ..[index + 1] = fairedRight;
      final residual = _residuals(points, trial);
      if (residual.maximum <= tolerance * 1.15) {
        result[index] = fairedLeft;
        result[index + 1] = fairedRight;
      }
    }
    return result;
  }

  bool _isSalientHeldCusp(
    List<DrawingInputSample> samples,
    int index,
    PawLocalGeometryEvidence evidence,
  ) {
    if (evidence.evidenceConfidence < .56 ||
        evidence.turnMagnitude < math.pi * .2) {
      return false;
    }
    if (evidence.localizedCornerLikelihood >= .52) return true;
    if (index < 2 || index > samples.length - 3) return false;

    final center = _turnMagnitude(
      samples[index - 1].position,
      samples[index].position,
      samples[index + 1].position,
    );
    final before = _turnMagnitude(
      samples[index - 2].position,
      samples[index - 1].position,
      samples[index].position,
    );
    final after = _turnMagnitude(
      samples[index].position,
      samples[index + 1].position,
      samples[index + 2].position,
    );
    final localTurn = center + before + after;
    final concentration = localTurn <= .000001 ? 0 : center / localTurn;
    final incoming =
        (samples[index].position - samples[index - 1].position).distance;
    final outgoing =
        (samples[index + 1].position - samples[index].position).distance;
    final chordBalance = math.min(incoming, outgoing) /
        math.max(.000001, math.max(incoming, outgoing));

    // A held curve may approach a cusp along curved spans, so the live
    // centerline's straight-leg residual is intentionally not mandatory here.
    // Require a well-supported, balanced, localized angular impulse instead.
    return center >= math.pi * .35 &&
        concentration >= .62 &&
        before <= center * .55 &&
        after <= center * .55 &&
        chordBalance >= .2;
  }

  double _turnMagnitude(Offset first, Offset vertex, Offset last) {
    final incoming = vertex - first;
    final outgoing = last - vertex;
    final product = incoming.distance * outgoing.distance;
    if (product <= .000001) return 0;
    final cosine = (_dot(incoming, outgoing) / product).clamp(-1.0, 1.0);
    return math.acos(cosine);
  }

  void _fitSpan(
    List<Offset> points,
    int first,
    int last,
    Offset leftTangent,
    Offset rightTangent,
    double errorSquared,
    List<PawHeldBezierFitSegment> output,
    int depth,
    int budget,
  ) {
    final count = last - first + 1;
    if (count <= 2 || depth >= maximumSegments * 2) {
      output.add(_heuristic(points, first, last, leftTangent, rightTangent));
      return;
    }
    var parameters = _chordLengthParameters(points, first, last);
    var curve = _generateBezier(
      points,
      first,
      last,
      parameters,
      leftTangent,
      rightTangent,
    );
    if (budget <= 1) {
      output.add(curve);
      return;
    }
    var maximum = _maximumError(points, first, last, curve, parameters);
    if (maximum.errorSquared <= errorSquared) {
      output.add(curve);
      return;
    }
    if (maximum.errorSquared <= errorSquared * 16) {
      for (var iteration = 0;
          iteration < maximumNewtonIterations;
          iteration++) {
        parameters = _reparameterize(points, first, last, parameters, curve);
        curve = _generateBezier(
          points,
          first,
          last,
          parameters,
          leftTangent,
          rightTangent,
        );
        maximum = _maximumError(points, first, last, curve, parameters);
        if (maximum.errorSquared <= errorSquared) {
          output.add(curve);
          return;
        }
      }
    }
    final split = maximum.index.clamp(first + 1, last - 1);
    final centerTangent = _normalized(
      points[split - 1] - points[split + 1],
      fallback: points[split - 1] - points[split],
    );
    final before = output.length;
    final leftBudget = (budget * (split - first) / (last - first))
        .round()
        .clamp(1, budget - 1);
    _fitSpan(
      points,
      first,
      split,
      leftTangent,
      centerTangent,
      errorSquared,
      output,
      depth + 1,
      leftBudget,
    );
    _fitSpan(
      points,
      split,
      last,
      -centerTangent,
      rightTangent,
      errorSquared,
      output,
      depth + 1,
      budget - (output.length - before),
    );
  }

  PawHeldBezierFitSegment _heuristic(
    List<Offset> points,
    int first,
    int last,
    Offset leftTangent,
    Offset rightTangent,
  ) {
    final distance = (points[last] - points[first]).distance / 3;
    return PawHeldBezierFitSegment(
      p0: points[first],
      c1: points[first] + leftTangent * distance,
      c2: points[last] + rightTangent * distance,
      p1: points[last],
      startSampleIndex: first,
      endSampleIndex: last,
    );
  }

  List<double> _chordLengthParameters(
    List<Offset> points,
    int first,
    int last,
  ) {
    final result = List<double>.filled(last - first + 1, 0);
    for (var index = 1; index < result.length; index++) {
      result[index] = result[index - 1] +
          (points[first + index] - points[first + index - 1]).distance;
    }
    final total = result.last;
    if (total <= .000001) {
      for (var index = 1; index < result.length; index++) {
        result[index] = index / (result.length - 1);
      }
    } else {
      for (var index = 1; index < result.length; index++) {
        result[index] /= total;
      }
    }
    return result;
  }

  PawHeldBezierFitSegment _generateBezier(
    List<Offset> points,
    int first,
    int last,
    List<double> u,
    Offset leftTangent,
    Offset rightTangent,
  ) {
    var c00 = 0.0;
    var c01 = 0.0;
    var c11 = 0.0;
    var x0 = 0.0;
    var x1 = 0.0;
    final p0 = points[first];
    final p3 = points[last];
    for (var index = 0; index < u.length; index++) {
      final t = u[index];
      final mt = 1 - t;
      final b0 = mt * mt * mt;
      final b1 = 3 * t * mt * mt;
      final b2 = 3 * t * t * mt;
      final b3 = t * t * t;
      final a1 = leftTangent * b1;
      final a2 = rightTangent * b2;
      final residual =
          points[first + index] - (p0 * (b0 + b1) + p3 * (b2 + b3));
      c00 += _dot(a1, a1);
      c01 += _dot(a1, a2);
      c11 += _dot(a2, a2);
      x0 += _dot(a1, residual);
      x1 += _dot(a2, residual);
    }
    final determinant = c00 * c11 - c01 * c01;
    var alphaLeft =
        determinant.abs() <= 1e-9 ? 0.0 : (x0 * c11 - x1 * c01) / determinant;
    var alphaRight =
        determinant.abs() <= 1e-9 ? 0.0 : (c00 * x1 - c01 * x0) / determinant;
    final chord = (p3 - p0).distance;
    final minimumAlpha = chord * 1e-6;
    if (!alphaLeft.isFinite ||
        !alphaRight.isFinite ||
        alphaLeft < minimumAlpha ||
        alphaRight < minimumAlpha) {
      alphaLeft = chord / 3;
      alphaRight = chord / 3;
    }
    return PawHeldBezierFitSegment(
      p0: p0,
      c1: p0 + leftTangent * alphaLeft,
      c2: p3 + rightTangent * alphaRight,
      p1: p3,
      startSampleIndex: first,
      endSampleIndex: last,
    );
  }

  ({double errorSquared, int index}) _maximumError(
    List<Offset> points,
    int first,
    int last,
    PawHeldBezierFitSegment curve,
    List<double> u,
  ) {
    var maximum = 0.0;
    var split = (first + last) ~/ 2;
    for (var index = 1; index < last - first; index++) {
      final delta = _point(curve, u[index]) - points[first + index];
      final squared = _dot(delta, delta);
      if (squared >= maximum) {
        maximum = squared;
        split = first + index;
      }
    }
    return (errorSquared: maximum, index: split);
  }

  List<double> _reparameterize(
    List<Offset> points,
    int first,
    int last,
    List<double> parameters,
    PawHeldBezierFitSegment curve,
  ) {
    final result = List<double>.of(parameters);
    for (var index = 0; index <= last - first; index++) {
      final u = parameters[index];
      final q = _point(curve, u);
      final q1 = _firstDerivative(curve, u);
      final q2 = _secondDerivative(curve, u);
      final delta = q - points[first + index];
      final denominator = _dot(q1, q1) + _dot(delta, q2);
      if (denominator.abs() <= 1e-9) continue;
      result[index] = (u - _dot(delta, q1) / denominator).clamp(0.0, 1.0);
    }
    for (var index = 1; index < result.length; index++) {
      if (result[index] <= result[index - 1]) return parameters;
    }
    return result;
  }

  ({double rms, double maximum}) _residuals(
    List<Offset> points,
    List<PawHeldBezierFitSegment> curves,
  ) {
    var squared = 0.0;
    var maximum = 0.0;
    for (var index = 0; index < points.length; index++) {
      var nearest = double.infinity;
      for (final curve in curves) {
        for (var probe = 0; probe <= 24; probe++) {
          nearest = math.min(
              nearest, (_point(curve, probe / 24) - points[index]).distance);
        }
      }
      squared += nearest * nearest;
      maximum = math.max(maximum, nearest);
    }
    return (rms: math.sqrt(squared / points.length), maximum: maximum);
  }

  Offset _point(PawHeldBezierFitSegment curve, double t) {
    final mt = 1 - t;
    return curve.p0 * (mt * mt * mt) +
        curve.c1 * (3 * mt * mt * t) +
        curve.c2 * (3 * mt * t * t) +
        curve.p1 * (t * t * t);
  }

  Offset _firstDerivative(PawHeldBezierFitSegment curve, double t) {
    final mt = 1 - t;
    return (curve.c1 - curve.p0) * (3 * mt * mt) +
        (curve.c2 - curve.c1) * (6 * mt * t) +
        (curve.p1 - curve.c2) * (3 * t * t);
  }

  Offset _secondDerivative(PawHeldBezierFitSegment curve, double t) =>
      (curve.c2 - curve.c1 * 2 + curve.p0) * (6 * (1 - t)) +
      (curve.p1 - curve.c2 * 2 + curve.c1) * (6 * t);

  double _dot(Offset first, Offset second) =>
      first.dx * second.dx + first.dy * second.dy;

  Offset _normalized(Offset value, {Offset fallback = const Offset(1, 0)}) {
    final length = value.distance;
    if (length > .000001 && length.isFinite) return value / length;
    final fallbackLength = fallback.distance;
    return fallbackLength > .000001
        ? fallback / fallbackLength
        : const Offset(1, 0);
  }
}
