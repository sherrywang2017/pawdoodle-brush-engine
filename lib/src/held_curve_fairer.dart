import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'smooth_stroke.dart';

@immutable
class PawHeldCurveFairingMetrics {
  const PawHeldCurveFairingMetrics({
    required this.lambda,
    required this.rmsDisplacement,
    required this.maximumDisplacement,
    required this.curvatureNoiseBefore,
    required this.curvatureNoiseAfter,
    required this.tangentJitterBefore,
    required this.tangentJitterAfter,
    required this.beautificationGain,
    required this.turnSignPreserved,
    required this.extremaPreserved,
    required this.newSelfIntersections,
    required this.arcLengthRatio,
    required this.score,
    this.targetBeautificationGain = 0,
    this.limitedByFidelity = false,
    this.lowFrequencyShapeDrift = 0,
  });

  final double lambda;
  final double rmsDisplacement;
  final double maximumDisplacement;
  final double curvatureNoiseBefore;
  final double curvatureNoiseAfter;
  final double tangentJitterBefore;
  final double tangentJitterAfter;
  final double beautificationGain;
  final bool turnSignPreserved;
  final bool extremaPreserved;
  final int newSelfIntersections;
  final double arcLengthRatio;
  final double score;
  final double targetBeautificationGain;
  final bool limitedByFidelity;
  final double lowFrequencyShapeDrift;

  double get highFrequencyNoiseBefore =>
      curvatureNoiseBefore + tangentJitterBefore;
  double get highFrequencyNoiseAfter =>
      curvatureNoiseAfter + tangentJitterAfter;

  PawHeldCurveFairingMetrics withIntent({
    required double target,
    required bool limited,
  }) =>
      PawHeldCurveFairingMetrics(
        lambda: lambda,
        rmsDisplacement: rmsDisplacement,
        maximumDisplacement: maximumDisplacement,
        curvatureNoiseBefore: curvatureNoiseBefore,
        curvatureNoiseAfter: curvatureNoiseAfter,
        tangentJitterBefore: tangentJitterBefore,
        tangentJitterAfter: tangentJitterAfter,
        beautificationGain: beautificationGain,
        turnSignPreserved: turnSignPreserved,
        extremaPreserved: extremaPreserved,
        newSelfIntersections: newSelfIntersections,
        arcLengthRatio: arcLengthRatio,
        score: score,
        targetBeautificationGain: target,
        limitedByFidelity: limited,
        lowFrequencyShapeDrift: lowFrequencyShapeDrift,
      );

  Map<String, Object> toJson() => <String, Object>{
        'lambda': lambda,
        'rms_displacement': rmsDisplacement,
        'maximum_displacement': maximumDisplacement,
        'curvature_noise_before': curvatureNoiseBefore,
        'curvature_noise_after': curvatureNoiseAfter,
        'tangent_jitter_before': tangentJitterBefore,
        'tangent_jitter_after': tangentJitterAfter,
        'beautification_gain': beautificationGain,
        'turn_sign_preserved': turnSignPreserved,
        'extrema_preserved': extremaPreserved,
        'new_self_intersections': newSelfIntersections,
        'arc_length_ratio': arcLengthRatio,
        'score': score,
        'target_beautification_gain': targetBeautificationGain,
        'limited_by_fidelity': limitedByFidelity,
        'high_frequency_noise_before': highFrequencyNoiseBefore,
        'high_frequency_noise_after': highFrequencyNoiseAfter,
        'low_frequency_shape_drift': lowFrequencyShapeDrift,
      };
}

@immutable
class PawHeldCurveFairingResult {
  const PawHeldCurveFairingResult({
    required this.samples,
    required this.metrics,
    required this.candidateMetrics,
  });

  final List<DrawingInputSample> samples;
  final PawHeldCurveFairingMetrics metrics;
  final List<PawHeldCurveFairingMetrics> candidateMetrics;
}

/// Deterministic regularized held-curve fairing.
///
/// The bounded Gauss-Seidel solve minimizes fidelity plus discrete second
/// derivative energy. Endpoints and salient cusps are locked. Candidates that
/// create intersections, extrema, or incompatible turn-sign topology are
/// rejected before scoring.
class PawHeldCurveFairer {
  const PawHeldCurveFairer({
    this.candidateLambdas = const <double>[
      0,
      .18,
      .45,
      .7,
      1,
      1.35,
      1.8,
      2.6,
      8,
    ],
    this.iterations = 28,
  });

  final List<double> candidateLambdas;
  final int iterations;

  PawHeldCurveFairingResult fair(
    List<DrawingInputSample> input, {
    required double maximumDisplacement,
  }) {
    final samples = input.where((sample) => sample.hasFinitePosition).toList();
    if (samples.length < 5) {
      final metrics = _metrics(
        samples.map((sample) => sample.position).toList(),
        samples.map((sample) => sample.position).toList(),
        lambda: 0,
        maximumAllowedDisplacement: maximumDisplacement,
      );
      return PawHeldCurveFairingResult(
        samples: List<DrawingInputSample>.unmodifiable(samples),
        metrics: metrics,
        candidateMetrics: <PawHeldCurveFairingMetrics>[metrics],
      );
    }
    final source = samples.map((sample) => sample.position).toList();
    final locked = _salientCuspIndices(source);
    final beforeNoise =
        _frequencyTangentJitter(source) + _frequencyCurvatureNoise(source);
    final targetGain = _targetBeautificationGain(beforeNoise);
    final allMetrics = <PawHeldCurveFairingMetrics>[];
    final valid =
        <({PawHeldCurveFairingMetrics metrics, List<Offset> points})>[];
    for (final lambda in candidateLambdas) {
      final unconstrained = lambda <= 0
          ? List<Offset>.of(source)
          : _frequencyAwareCandidate(source, locked, lambda);
      final candidate = _boundToDisplacementCorridor(
        source,
        unconstrained,
        maximumDisplacement,
      );
      final metrics = _metrics(
        source,
        candidate,
        lambda: lambda,
        maximumAllowedDisplacement: maximumDisplacement,
      );
      allMetrics.add(metrics);
      // A salient intentional cusp is already the correct local feature. The
      // current fairing contract does not couple separate spans across it;
      // retain the raw samples so the existing fitter emits a true C0 split.
      if (locked.length > 2 && lambda > 0) continue;
      if (!metrics.turnSignPreserved ||
          !metrics.extremaPreserved ||
          metrics.newSelfIntersections > 0 ||
          metrics.maximumDisplacement > maximumDisplacement + .0001) {
        continue;
      }
      valid.add((metrics: metrics, points: candidate));
    }
    var selected = valid.isEmpty
        ? (metrics: allMetrics.first, points: source)
        : valid.first;
    final reaching = valid
        .where(
            (value) => value.metrics.beautificationGain + .000001 >= targetGain)
        .toList();
    if (targetGain <= 0) {
      selected = valid.reduce((left, right) =>
          right.metrics.maximumDisplacement < left.metrics.maximumDisplacement
              ? right
              : left);
    } else if (reaching.isNotEmpty) {
      selected = reaching.reduce((left, right) {
        final displacement = right.metrics.maximumDisplacement -
            left.metrics.maximumDisplacement;
        if (displacement < -.001) return right;
        if (displacement > .001) return left;
        final drift = right.metrics.lowFrequencyShapeDrift -
            left.metrics.lowFrequencyShapeDrift;
        if (drift < -.001) return right;
        if (drift > .001) return left;
        return right.metrics.score < left.metrics.score ? right : left;
      });
    } else if (valid.isNotEmpty) {
      selected = valid.reduce((left, right) {
        final gain = right.metrics.beautificationGain
            .compareTo(left.metrics.beautificationGain);
        if (gain > 0) return right;
        if (gain < 0) return left;
        return right.metrics.maximumDisplacement <
                left.metrics.maximumDisplacement
            ? right
            : left;
      });
    }
    final limited = targetGain > 0 &&
        selected.metrics.beautificationGain + .000001 < targetGain;
    final selectedMetrics = selected.metrics.withIntent(
      target: targetGain,
      limited: limited,
    );
    final selectedPoints = selected.points;
    final output = <DrawingInputSample>[
      for (var index = 0; index < samples.length; index++)
        DrawingInputSample(
          x: selectedPoints[index].dx,
          y: selectedPoints[index].dy,
          timestamp: samples[index].timestamp,
          pressure: samples[index].pressure,
          pressureMin: samples[index].pressureMin,
          pressureMax: samples[index].pressureMax,
          deviceKind: samples[index].deviceKind,
        ),
    ];
    return PawHeldCurveFairingResult(
      samples: List<DrawingInputSample>.unmodifiable(output),
      metrics: selectedMetrics,
      candidateMetrics:
          List<PawHeldCurveFairingMetrics>.unmodifiable(allMetrics),
    );
  }

  /// Filters only the high-frequency residual in an arc-length parameter.
  ///
  /// Physical pointer samples are not spatially uniform. Applying a discrete
  /// derivative directly to their indices makes a long legitimate interval
  /// look like wobble and can destabilize the solve. The candidate is built
  /// on a uniform arc grid, then sampled back at the original arc fractions so
  /// timestamps and endpoint identity stay untouched.
  List<Offset> _frequencyAwareCandidate(
    List<Offset> source,
    Set<int> locked,
    double lambda,
  ) {
    final sourceFractions = _arcFractions(source);
    final uniformFractions = <double>[
      for (var index = 0; index < source.length; index++)
        index / (source.length - 1),
    ];
    final uniformSource = <Offset>[
      for (final fraction in uniformFractions)
        _pointAtArcFraction(source, sourceFractions, fraction),
    ];
    var filtered = List<Offset>.of(uniformSource);
    final lockedUniform = <int>{
      for (final index in locked)
        (sourceFractions[index] * (source.length - 1)).round(),
    };
    final strength = (lambda / (lambda + .55)).clamp(0.0, 1.0);
    final passes = lambda < .5
        ? 1
        : lambda < 2
            ? 2
            : 3;
    for (var pass = 0; pass < passes; pass++) {
      final previous = filtered;
      final next = List<Offset>.of(previous);
      for (var index = 1; index < previous.length - 1; index++) {
        if (lockedUniform.contains(index)) continue;
        final p0 = previous[math.max(0, index - 2)];
        final p1 = previous[index - 1];
        final p2 = previous[index];
        final p3 = previous[index + 1];
        final p4 = previous[math.min(previous.length - 1, index + 2)];
        final baseline = (p0 + p1 * 2 + p2 * 3 + p3 * 2 + p4) / 9;
        next[index] = Offset.lerp(p2, baseline, strength * .72)!;
      }
      next.first = source.first;
      next.last = source.last;
      filtered = next;
    }
    final correction = <Offset>[
      for (var index = 0; index < filtered.length; index++)
        filtered[index] - uniformSource[index],
    ];
    final result = <Offset>[
      for (var index = 0; index < source.length; index++)
        source[index] +
            _pointAtUniformFraction(correction, sourceFractions[index]),
    ];
    result.first = source.first;
    result.last = source.last;
    return result;
  }

  Set<int> _salientCuspIndices(List<Offset> points) {
    final locked = <int>{0, points.length - 1};
    for (var index = 2; index < points.length - 2; index++) {
      final center = _turn(points[index - 1], points[index], points[index + 1]);
      final before = _turn(points[index - 2], points[index - 1], points[index]);
      final after = _turn(points[index], points[index + 1], points[index + 2]);
      if (center.abs() >= .72 &&
          center.abs() >= before.abs() * 1.7 &&
          center.abs() >= after.abs() * 1.7) {
        locked.add(index);
      }
    }
    return locked;
  }

  PawHeldCurveFairingMetrics _metrics(
    List<Offset> source,
    List<Offset> candidate, {
    required double lambda,
    required double maximumAllowedDisplacement,
  }) {
    var squared = 0.0;
    var maximum = 0.0;
    for (var index = 0; index < source.length; index++) {
      final distance = (candidate[index] - source[index]).distance;
      squared += distance * distance;
      maximum = math.max(maximum, distance);
    }
    final tangentBefore = _frequencyTangentJitter(source);
    final tangentAfter = _frequencyTangentJitter(candidate);
    final curvatureBefore = _frequencyCurvatureNoise(source);
    final curvatureAfter = _frequencyCurvatureNoise(candidate);
    final beforeNoise = tangentBefore + curvatureBefore;
    final afterNoise = tangentAfter + curvatureAfter;
    final gain = beforeNoise <= 1e-6
        ? 0.0
        : (1 - afterNoise / beforeNoise).clamp(-1.0, 1.0);
    final originalIntersections = _selfIntersections(source);
    final candidateIntersections = _selfIntersections(candidate);
    final turnPreserved =
        _turnSignChanges(candidate) <= _turnSignChanges(source) &&
            _dominantTurnSign(candidate) == _dominantTurnSign(source);
    final extremaPreserved = _extremaCount(candidate) <= _extremaCount(source);
    final originalLength = _length(source);
    final arcRatio =
        originalLength <= .001 ? 1.0 : _length(candidate) / originalLength;
    final displacementUnit = maximumAllowedDisplacement <= .001
        ? maximum
        : maximum / maximumAllowedDisplacement;
    const noiseFloor = .018;
    final noiseRatio = beforeNoise <= noiseFloor
        ? 1.0
        : (afterNoise / beforeNoise).clamp(0.0, 2.0);
    final beautificationNeed =
        ((beforeNoise - noiseFloor) / .16).clamp(0.0, 1.0);
    final lowFrequencyDrift = _lowFrequencyDrift(source, candidate) /
        math.max(.001, maximumAllowedDisplacement);
    final noBeautificationPenalty = lambda == 0 ? beautificationNeed * .3 : 0;
    final score = noiseRatio * .58 +
        displacementUnit * .16 +
        lowFrequencyDrift * .14 +
        (1 - arcRatio).abs() * .18 +
        noBeautificationPenalty;
    return PawHeldCurveFairingMetrics(
      lambda: lambda,
      rmsDisplacement: math.sqrt(squared / source.length),
      maximumDisplacement: maximum,
      curvatureNoiseBefore: curvatureBefore,
      curvatureNoiseAfter: curvatureAfter,
      tangentJitterBefore: tangentBefore,
      tangentJitterAfter: tangentAfter,
      beautificationGain: gain,
      turnSignPreserved: turnPreserved,
      extremaPreserved: extremaPreserved,
      newSelfIntersections:
          math.max(0, candidateIntersections - originalIntersections),
      arcLengthRatio: arcRatio,
      score: score,
      lowFrequencyShapeDrift: lowFrequencyDrift,
    );
  }

  double _targetBeautificationGain(double highFrequencyNoise) {
    if (highFrequencyNoise <= .025) return 0;
    final need = ((highFrequencyNoise - .04) / .1).clamp(0.0, 1.0);
    return .18 + need * .15;
  }

  List<Offset> _boundToDisplacementCorridor(
    List<Offset> source,
    List<Offset> candidate,
    double maximumDisplacement,
  ) {
    var maximum = 0.0;
    for (var index = 0; index < source.length; index++) {
      maximum = math.max(maximum, (candidate[index] - source[index]).distance);
    }
    if (maximum <= maximumDisplacement || maximum <= .000001) {
      return candidate;
    }
    final scale = maximumDisplacement / maximum;
    final result = <Offset>[
      for (var index = 0; index < source.length; index++)
        source[index] + (candidate[index] - source[index]) * scale,
    ];
    result.first = source.first;
    result.last = source.last;
    return result;
  }

  double _frequencyTangentJitter(List<Offset> points) {
    final uniform = _uniformArcPoints(points);
    if (uniform.length < 5) return 0;
    final angles = <double>[];
    for (var index = 1; index < uniform.length; index++) {
      final delta = uniform[index] - uniform[index - 1];
      var angle = math.atan2(delta.dy, delta.dx);
      if (angles.isNotEmpty) {
        while (angle - angles.last > math.pi) {
          angle -= math.pi * 2;
        }
        while (angle - angles.last < -math.pi) {
          angle += math.pi * 2;
        }
      }
      angles.add(angle);
    }
    var squared = 0.0;
    var count = 0;
    for (var index = 0; index < angles.length; index++) {
      final baseline = _windowBaseline(angles, index);
      final residual = angles[index] - baseline;
      squared += residual * residual;
      count++;
    }
    return math.sqrt(squared / math.max(1, count));
  }

  double _frequencyCurvatureNoise(List<Offset> points) {
    final uniform = _uniformArcPoints(points);
    if (uniform.length < 6) return 0;
    final turns = <double>[
      for (var index = 1; index < uniform.length - 1; index++)
        _turn(uniform[index - 1], uniform[index], uniform[index + 1]),
    ];
    var squared = 0.0;
    for (var index = 0; index < turns.length; index++) {
      final residual = turns[index] - _windowBaseline(turns, index);
      squared += residual * residual;
    }
    return math.sqrt(squared / math.max(1, turns.length));
  }

  double _windowBaseline(List<double> values, int index) {
    var weighted = 0.0;
    var total = 0.0;
    for (var offset = -2; offset <= 2; offset++) {
      final sample = values[(index + offset).clamp(0, values.length - 1)];
      final weight = 3 - offset.abs();
      weighted += sample * weight;
      total += weight;
    }
    return weighted / total;
  }

  List<Offset> _uniformArcPoints(List<Offset> points) {
    if (points.length < 2) return List<Offset>.of(points);
    final fractions = _arcFractions(points);
    return <Offset>[
      for (var index = 0; index < points.length; index++)
        _pointAtArcFraction(points, fractions, index / (points.length - 1)),
    ];
  }

  List<double> _arcFractions(List<Offset> points) {
    final result = List<double>.filled(points.length, 0);
    for (var index = 1; index < points.length; index++) {
      result[index] =
          result[index - 1] + (points[index] - points[index - 1]).distance;
    }
    final total = result.last;
    if (total <= .000001) return result;
    for (var index = 1; index < result.length; index++) {
      result[index] /= total;
    }
    return result;
  }

  Offset _pointAtArcFraction(
    List<Offset> points,
    List<double> fractions,
    double fraction,
  ) {
    if (fraction <= 0) return points.first;
    if (fraction >= 1) return points.last;
    var index = 1;
    while (index < fractions.length && fractions[index] < fraction) {
      index++;
    }
    final start = fractions[index - 1];
    final end = fractions[index];
    final amount = end <= start ? 0.0 : (fraction - start) / (end - start);
    return Offset.lerp(points[index - 1], points[index], amount)!;
  }

  Offset _pointAtUniformFraction(List<Offset> points, double fraction) {
    final position = fraction.clamp(0.0, 1.0) * (points.length - 1);
    final first = position.floor().clamp(0, points.length - 1);
    final second = math.min(points.length - 1, first + 1);
    return Offset.lerp(points[first], points[second], position - first)!;
  }

  double _lowFrequencyDrift(List<Offset> source, List<Offset> candidate) {
    final sourceUniform = _uniformArcPoints(source);
    final candidateUniform = _uniformArcPoints(candidate);
    var maximum = 0.0;
    for (var index = 0; index < sourceUniform.length; index += 3) {
      final sourceBase = _pointWindowBaseline(sourceUniform, index);
      final candidateBase = _pointWindowBaseline(candidateUniform, index);
      maximum = math.max(maximum, (candidateBase - sourceBase).distance);
    }
    return maximum;
  }

  Offset _pointWindowBaseline(List<Offset> values, int index) {
    var weighted = Offset.zero;
    var total = 0.0;
    for (var offset = -2; offset <= 2; offset++) {
      final sample = values[(index + offset).clamp(0, values.length - 1)];
      final weight = (3 - offset.abs()).toDouble();
      weighted += sample * weight;
      total += weight;
    }
    return weighted / total;
  }

  int _turnSignChanges(List<Offset> points) {
    var previous = 0;
    var changes = 0;
    for (var index = 1; index < points.length - 1; index++) {
      final value = _turn(points[index - 1], points[index], points[index + 1]);
      if (value.abs() < .04) continue;
      final sign = value.sign.toInt();
      if (previous != 0 && sign != previous) changes++;
      previous = sign;
    }
    return changes;
  }

  int _dominantTurnSign(List<Offset> points) {
    var total = 0.0;
    for (var index = 1; index < points.length - 1; index++) {
      total += _turn(points[index - 1], points[index], points[index + 1]);
    }
    return total.abs() < .04 ? 0 : total.sign.toInt();
  }

  int _extremaCount(List<Offset> points) =>
      _axisExtrema(points.map((point) => point.dx).toList()) +
      _axisExtrema(points.map((point) => point.dy).toList());

  int _axisExtrema(List<double> values) {
    var previous = 0;
    var result = 0;
    for (var index = 1; index < values.length; index++) {
      final delta = values[index] - values[index - 1];
      if (delta.abs() < .05) continue;
      final sign = delta.sign.toInt();
      if (previous != 0 && sign != previous) result++;
      previous = sign;
    }
    return result;
  }

  int _selfIntersections(List<Offset> points) {
    var result = 0;
    for (var first = 1; first < points.length; first++) {
      for (var second = first + 2; second < points.length; second++) {
        if (first == 1 && second == points.length - 1) continue;
        if (_segmentsIntersect(
          points[first - 1],
          points[first],
          points[second - 1],
          points[second],
        )) {
          result++;
        }
      }
    }
    return result;
  }

  bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double cross(Offset p, Offset q, Offset r) =>
        (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
    final abC = cross(a, b, c);
    final abD = cross(a, b, d);
    final cdA = cross(c, d, a);
    final cdB = cross(c, d, b);
    return abC * abD < -1e-6 && cdA * cdB < -1e-6;
  }

  double _turn(Offset a, Offset b, Offset c) {
    final incoming = b - a;
    final outgoing = c - b;
    if (incoming.distance <= 1e-6 || outgoing.distance <= 1e-6) return 0;
    return math.atan2(
      incoming.dx * outgoing.dy - incoming.dy * outgoing.dx,
      incoming.dx * outgoing.dx + incoming.dy * outgoing.dy,
    );
  }

  double _length(List<Offset> points) {
    var result = 0.0;
    for (var index = 1; index < points.length; index++) {
      result += (points[index] - points[index - 1]).distance;
    }
    return result;
  }
}
