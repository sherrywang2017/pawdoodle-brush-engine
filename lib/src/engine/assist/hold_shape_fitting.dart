part of '../../held_stroke_assist.dart';

PawCircleFit? _fitCircle(List<Offset> points) {
  if (points.length < 3) return null;
  final matrix =
      List<List<double>>.generate(3, (_) => List<double>.filled(4, 0));
  for (final point in points) {
    final row = <double>[point.dx, point.dy, 1];
    final target = -(point.dx * point.dx + point.dy * point.dy);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        matrix[i][j] += row[i] * row[j];
      }
      matrix[i][3] += row[i] * target;
    }
  }
  final solution = _solve3x3(matrix);
  if (solution == null) return null;
  final center = Offset(-solution[0] / 2, -solution[1] / 2);
  final radiusSquared =
      center.dx * center.dx + center.dy * center.dy - solution[2];
  if (!radiusSquared.isFinite || radiusSquared <= .01) return null;
  final radius = math.sqrt(radiusSquared);
  var squared = 0.0;
  var maximum = 0.0;
  final residuals = <double>[];
  for (final point in points) {
    final residual = ((point - center).distance - radius).abs();
    residuals.add(residual);
    squared += residual * residual;
    maximum = math.max(maximum, residual);
  }
  final endpointResidual = math.max(residuals.first, residuals.last);
  residuals.sort();
  final trimCount = math.max(1, (residuals.length * .9).ceil());
  final trimmedSquared = residuals
      .take(trimCount)
      .fold<double>(0, (sum, value) => sum + value * value);
  final median = residuals[(residuals.length - 1) ~/ 2];
  final p90 = residuals[((residuals.length - 1) * .9).round()];
  final winding = _polarWinding(points, center);
  return PawCircleFit(
    center: center,
    radius: radius,
    rmsResidual: math.sqrt(squared / points.length),
    maximumResidual: maximum,
    signedSweep: winding.sweep,
    signCoherence: winding.coherence,
    medianResidual: median,
    trimmedRmsResidual: math.sqrt(trimmedSquared / trimCount),
    p90Residual: p90,
    angularCoverage: winding.sweep.abs(),
    endpointResidual: endpointResidual,
  );
}

PawEllipseFit? _fitEllipse(List<Offset> points) {
  if (points.length < 6) return null;
  // Touch delivery is time-uniform, not arc-uniform: pauses and slow regions
  // otherwise overweight one side and pull the covariance center away from a
  // nearly closed loop. Fit an arc-length-uniform geometric trace instead.
  final fitPoints = _uniformArcPoints(
    points,
    (points.length * 2).clamp(24, 96).toInt(),
  );
  var cx = 0.0;
  var cy = 0.0;
  for (final point in fitPoints) {
    cx += point.dx;
    cy += point.dy;
  }
  final center = Offset(cx / fitPoints.length, cy / fitPoints.length);
  var xx = 0.0;
  var xy = 0.0;
  var yy = 0.0;
  for (final point in fitPoints) {
    final delta = point - center;
    xx += delta.dx * delta.dx;
    xy += delta.dx * delta.dy;
    yy += delta.dy * delta.dy;
  }
  xx /= fitPoints.length;
  xy /= fitPoints.length;
  yy /= fitPoints.length;
  final trace = xx + yy;
  final discriminant =
      math.sqrt(math.max(0, (xx - yy) * (xx - yy) + 4 * xy * xy));
  final majorVariance = (trace + discriminant) / 2;
  final minorVariance = (trace - discriminant) / 2;
  if (minorVariance <= .001 || majorVariance < minorVariance) return null;
  final rotation = .5 * math.atan2(2 * xy, xx - yy);
  var major = math.sqrt(2 * majorVariance);
  var minor = math.sqrt(2 * minorVariance);
  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);
  // Covariance gives a stable center and axis direction, but sqrt(2 *
  // variance) only recovers radii when samples are uniform in polar angle.
  // Touch traces are resampled by arc length, which biases that estimate for
  // eccentric ellipses. With center and rotation fixed, solve the actual
  // ellipse equation u*x^2 + v*y^2 = 1 for u=1/a^2 and v=1/b^2.
  var x4 = 0.0;
  var x2y2 = 0.0;
  var y4 = 0.0;
  var x2 = 0.0;
  var y2 = 0.0;
  for (final point in fitPoints) {
    final delta = point - center;
    final localX = delta.dx * cosR + delta.dy * sinR;
    final localY = -delta.dx * sinR + delta.dy * cosR;
    final localX2 = localX * localX;
    final localY2 = localY * localY;
    x4 += localX2 * localX2;
    x2y2 += localX2 * localY2;
    y4 += localY2 * localY2;
    x2 += localX2;
    y2 += localY2;
  }
  final determinant = x4 * y4 - x2y2 * x2y2;
  if (determinant.abs() > 1e-9) {
    final inverseMajorSquared = (x2 * y4 - y2 * x2y2) / determinant;
    final inverseMinorSquared = (y2 * x4 - x2 * x2y2) / determinant;
    if (inverseMajorSquared > 1e-12 && inverseMinorSquared > 1e-12) {
      major = 1 / math.sqrt(inverseMajorSquared);
      minor = 1 / math.sqrt(inverseMinorSquared);
    }
  }
  var squared = 0.0;
  var maximum = 0.0;
  for (final point in fitPoints) {
    final delta = point - center;
    final x = delta.dx * cosR + delta.dy * sinR;
    final y = -delta.dx * sinR + delta.dy * cosR;
    final radial = math.sqrt(x * x / (major * major) + y * y / (minor * minor));
    final residual = (radial - 1).abs();
    squared += residual * residual;
    maximum = math.max(maximum, residual);
  }
  final winding = _polarWinding(points, center);
  return PawEllipseFit(
    center: center,
    majorRadius: major,
    minorRadius: minor,
    rotationRadians: rotation,
    rmsRadialResidual: math.sqrt(squared / fitPoints.length),
    maximumRadialResidual: maximum,
    signedSweep: winding.sweep,
    signCoherence: winding.coherence,
  );
}

List<Offset> _uniformArcPoints(List<Offset> points, int targetCount) {
  if (points.length <= 2 || targetCount <= 2) return List<Offset>.of(points);
  final cumulative = List<double>.filled(points.length, 0);
  for (var index = 1; index < points.length; index++) {
    cumulative[index] =
        cumulative[index - 1] + (points[index] - points[index - 1]).distance;
  }
  final total = cumulative.last;
  if (total <= .0001) return List<Offset>.of(points);
  final result = <Offset>[];
  var sourceIndex = 1;
  for (var index = 0; index < targetCount; index++) {
    final target = total * index / (targetCount - 1);
    while (sourceIndex < cumulative.length - 1 &&
        cumulative[sourceIndex] < target) {
      sourceIndex++;
    }
    final startArc = cumulative[sourceIndex - 1];
    final endArc = cumulative[sourceIndex];
    final fraction = endArc <= startArc
        ? 0.0
        : ((target - startArc) / (endArc - startArc)).clamp(0.0, 1.0);
    result.add(Offset.lerp(
      points[sourceIndex - 1],
      points[sourceIndex],
      fraction,
    )!);
  }
  return result;
}

({double sweep, double coherence}) _polarWinding(
  List<Offset> points,
  Offset center,
) {
  var sweep = 0.0;
  var absolute = 0.0;
  for (var index = 1; index < points.length; index++) {
    final first = points[index - 1] - center;
    final second = points[index] - center;
    if (first.distance <= .001 || second.distance <= .001) continue;
    final delta = math.atan2(
      first.dx * second.dy - first.dy * second.dx,
      first.dx * second.dx + first.dy * second.dy,
    );
    sweep += delta;
    absolute += delta.abs();
  }
  return (
    sweep: sweep,
    coherence: absolute <= .001 ? 0 : (sweep.abs() / absolute).clamp(0.0, 1.0),
  );
}

List<double>? _solve3x3(List<List<double>> matrix) {
  for (var column = 0; column < 3; column++) {
    var pivot = column;
    for (var row = column + 1; row < 3; row++) {
      if (matrix[row][column].abs() > matrix[pivot][column].abs()) pivot = row;
    }
    if (matrix[pivot][column].abs() <= 1e-9) return null;
    final swap = matrix[column];
    matrix[column] = matrix[pivot];
    matrix[pivot] = swap;
    final divisor = matrix[column][column];
    for (var value = column; value < 4; value++) {
      matrix[column][value] /= divisor;
    }
    for (var row = 0; row < 3; row++) {
      if (row == column) continue;
      final factor = matrix[row][column];
      for (var value = column; value < 4; value++) {
        matrix[row][value] -= factor * matrix[column][value];
      }
    }
  }
  return <double>[matrix[0][3], matrix[1][3], matrix[2][3]];
}
