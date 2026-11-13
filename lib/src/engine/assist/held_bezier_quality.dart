part of '../../held_stroke_assist.dart';

@immutable
class PawHeldBezierQualityMetrics {
  const PawHeldBezierQualityMetrics({
    required this.bezierJoinAngleP50,
    required this.bezierJoinAngleP95,
    required this.curvatureJumpP50,
    required this.curvatureJumpP95,
    required this.curvatureJerkEnergy,
    required this.controlPointCount,
    required this.cubicSegmentCount,
  });

  final double bezierJoinAngleP50;
  final double bezierJoinAngleP95;
  final double curvatureJumpP50;
  final double curvatureJumpP95;
  final double curvatureJerkEnergy;
  final int controlPointCount;
  final int cubicSegmentCount;

  Map<String, Object> toJson() => <String, Object>{
        'bezier_join_angle_p50': bezierJoinAngleP50,
        'bezier_join_angle_p95': bezierJoinAngleP95,
        'curvature_jump_p50': curvatureJumpP50,
        'curvature_jump_p95': curvatureJumpP95,
        'curvature_jerk_energy': curvatureJerkEnergy,
        'control_point_count': controlPointCount,
        'cubic_segment_count': cubicSegmentCount,
      };
}

PawHeldBezierQualityMetrics pawHeldBezierQualityMetrics(
  List<PawStreamingSegmentCommand> segments,
) {
  if (segments.isEmpty) {
    return const PawHeldBezierQualityMetrics(
      bezierJoinAngleP50: 0,
      bezierJoinAngleP95: 0,
      curvatureJumpP50: 0,
      curvatureJumpP95: 0,
      curvatureJerkEnergy: 0,
      controlPointCount: 0,
      cubicSegmentCount: 0,
    );
  }
  final angles = <double>[];
  final jumps = <double>[];
  for (var index = 0; index < segments.length - 1; index++) {
    final left = segments[index];
    final right = segments[index + 1];
    final incoming = left.p1 - left.c2;
    final outgoing = right.c1 - right.p0;
    final product = incoming.distance * outgoing.distance;
    if (product <= .000001) continue;
    angles.add(math.acos(
      ((incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) / product)
          .clamp(-1.0, 1.0),
    ));
    jumps.add(
        (_heldCubicCurvature(left, 1) - _heldCubicCurvature(right, 0)).abs());
  }
  final curvatures = <double>[];
  for (final segment in segments) {
    for (var probe = 0; probe <= 16; probe++) {
      curvatures.add(_heldCubicCurvature(segment, probe / 16));
    }
  }
  var jerk = 0.0;
  for (var index = 1; index < curvatures.length; index++) {
    final delta = curvatures[index] - curvatures[index - 1];
    jerk += delta * delta;
  }
  double percentile(List<double> values, double fraction) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    return sorted[((sorted.length - 1) * fraction).round()];
  }

  return PawHeldBezierQualityMetrics(
    bezierJoinAngleP50: percentile(angles, .5),
    bezierJoinAngleP95: percentile(angles, .95),
    curvatureJumpP50: percentile(jumps, .5),
    curvatureJumpP95: percentile(jumps, .95),
    curvatureJerkEnergy: jerk,
    controlPointCount: segments.length * 3 + 1,
    cubicSegmentCount: segments.length,
  );
}

double _heldCubicCurvature(PawStreamingSegmentCommand segment, double t) {
  final u = 1 - t;
  final first = (segment.c1 - segment.p0) * (3 * u * u) +
      (segment.c2 - segment.c1) * (6 * u * t) +
      (segment.p1 - segment.c2) * (3 * t * t);
  final second = (segment.c2 - segment.c1 * 2 + segment.p0) * (6 * u) +
      (segment.p1 - segment.c2 * 2 + segment.c1) * (6 * t);
  final speed = first.distance;
  if (speed <= .000001) return 0;
  return (first.dx * second.dy - first.dy * second.dx) /
      (speed * speed * speed);
}
