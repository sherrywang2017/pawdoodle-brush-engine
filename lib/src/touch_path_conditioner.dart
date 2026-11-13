import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'smooth_stroke.dart';

/// Removes subpixel transverse stair steps without delaying the visible tip.
/// Raw samples remain untouched. Only the short, replaceable spline tail uses
/// these positions; a bounded spatial neighbourhood supports each settled knot.
class PawTouchPathConditioner {
  static Offset position(List<DrawingInputSample> raw, int index) {
    final sample = raw[index];
    final p = sample.position;
    if (sample.deviceKind != PointerDeviceKind.touch ||
        index == 0 ||
        index == raw.length - 1) {
      return p;
    }
    var first = index, last = index;
    while (first > 0 &&
        index - first < 7 &&
        (raw[first - 1].position - p).distance <= 24 &&
        (sample.timestamp - raw[first - 1].timestamp).inMicroseconds <= 40000) {
      first--;
    }
    while (last + 1 < raw.length &&
        last - index < 7 &&
        (raw[last + 1].position - p).distance <= 24 &&
        (raw[last + 1].timestamp - sample.timestamp).inMicroseconds <= 40000) {
      last++;
    }
    double supportCosine() {
      final a = p - raw[first].position, b = raw[last].position - p;
      final denominator = a.distance * b.distance;
      return denominator < 1e-9
          ? -1
          : (a.dx * b.dx + a.dy * b.dy) / denominator;
    }

    // A wide support straddling a rounded U-turn is not a cusp. Reduce the
    // support to the local bend before deciding whether to preserve an angle.
    // A true corner remains angular even at the immediate neighbouring legs.
    while (supportCosine() < .8 && (first < index - 1 || last > index + 1)) {
      if (first < index - 1 &&
          (last == index + 1 ||
              (p - raw[first].position).distance >
                  (raw[last].position - p).distance)) {
        first++;
      } else {
        last--;
      }
    }
    final before = p - raw[first].position;
    final after = raw[last].position - p;
    // Sparse delivery and deliberate corners are not quantization noise.
    if (before.distance < 1 ||
        after.distance < 1 ||
        before.distance > 24 ||
        after.distance > 24 ||
        (sample.timestamp - raw[first].timestamp).inMilliseconds > 50 ||
        (raw[last].timestamp - sample.timestamp).inMilliseconds > 50) {
      return p;
    }
    final cosine = (before.dx * after.dx + before.dy * after.dy) /
        (before.distance * after.distance);
    // The support now spans a spatial neighbourhood rather than two tiny
    // legs: a smooth bend can accumulate substantial turning over it.
    final strength = ((cosine - .5) / .4).clamp(0.0, 1.0);
    if (strength == 0) return p;
    final chord = raw[last].position - raw[first].position;
    final axis = chord / chord.distance;
    final normal = Offset(-axis.dy, axis.dx);
    final moments = List<double>.filled(5, 0);
    final values = List<double>.filled(3, 0);
    for (var i = first; i <= last; i++) {
      final delta = raw[i].position - p;
      final u = (delta.dx * axis.dx + delta.dy * axis.dy) / 24;
      final v = delta.dx * normal.dx + delta.dy * normal.dy;
      final w = math.exp(-u * u * 2);
      var power = 1.0;
      for (var j = 0; j < 5; j++) {
        moments[j] += w * power;
        if (j < 3) values[j] += w * power * v;
        power *= u;
      }
    }
    // A quadratic reproduces local curvature across integer-coordinate
    // plateaus. A linear fit (or short moving average) preserves a long flat
    // plateau in the middle of a measured arc. Scale coordinates for a stable
    // tiny least-squares solve and keep the same subpixel displacement limit.
    final matrix = [
      for (var row = 0; row < 3; row++)
        [for (var col = 0; col < 3; col++) moments[row + col], values[row]]
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var row = col + 1; row < 3; row++) {
        if (matrix[row][col].abs() > matrix[pivot][col].abs()) pivot = row;
      }
      if (matrix[pivot][col].abs() < 1e-9) return p;
      final swap = matrix[col];
      matrix[col] = matrix[pivot];
      matrix[pivot] = swap;
      final scale = matrix[col][col];
      for (var j = col; j < 4; j++) {
        matrix[col][j] /= scale;
      }
      for (var row = 0; row < 3; row++) {
        if (row == col) continue;
        final factor = matrix[row][col];
        for (var j = col; j < 4; j++) {
          matrix[row][j] -= factor * matrix[col][j];
        }
      }
    }
    final correction = matrix[0][3].clamp(-.75, .75) * strength;
    return p + normal * correction;
  }
}

/// A revision-local, lazily evaluated view. Evidence queries and knot creation
/// reuse each fit; the original samples and their diagnostics stay untouched.
class PawConditionedTouchSamples extends ListBase<DrawingInputSample> {
  PawConditionedTouchSamples(this.raw);
  final List<DrawingInputSample> raw;
  final _cache = <int, DrawingInputSample>{};
  @override
  int get length => raw.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only geometry');
  @override
  void operator []=(int index, DrawingInputSample value) =>
      throw UnsupportedError('Read-only geometry');
  @override
  DrawingInputSample operator [](int index) => _cache.putIfAbsent(index, () {
        final sample = raw[index];
        final p = PawTouchPathConditioner.position(raw, index);
        if (p == sample.position) return sample;
        return DrawingInputSample(
            x: p.dx,
            y: p.dy,
            timestamp: sample.timestamp,
            pressure: sample.pressure,
            pressureMin: sample.pressureMin,
            pressureMax: sample.pressureMax,
            deviceKind: sample.deviceKind);
      });
}
