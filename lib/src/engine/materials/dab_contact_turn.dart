part of '../../streaming_dab_brush.dart';

/// A discontinuous tangent still sweeps a finite tip around its contact point.
/// Only these joins interrupt the absolute-arc grid; smooth command boundaries
/// keep their existing tessellation and material samples.
class _PawContactTurn {
  const _PawContactTurn(this.point, this.incoming, this.outgoing, this.radians);

  final Offset point;
  final Offset incoming;
  final Offset outgoing;
  final double radians;

  Offset directionAt(double amount) {
    if (amount == 0) return incoming;
    if (amount == 1) return outgoing;
    final angle = math.atan2(incoming.dy, incoming.dx) + radians * amount;
    return Offset(math.cos(angle), math.sin(angle));
  }

  /// Wax dragged back along the same axis keeps its grain orientation. The
  /// contact crossbar rotates around the corner; the deposited streaks do not
  /// fan through a half-turn with it.
  Offset dragDirectionAt(double amount) {
    final dot = incoming.dx * outgoing.dx + incoming.dy * outgoing.dy;
    return _DabInstanceEvaluator._normalized(
        Offset.lerp(incoming, dot < 0 ? -outgoing : outgoing, amount)!);
  }

  /// The arriving and departing legs overlap behind the fold. Carry their
  /// rubbing contact into the outer face too, with no step at either crossbar.
  /// Count contact here, before the shader resolves optical thickness once.
  double waxContactPassesAt(double amount) {
    final contact = (math.min(amount, 1 - amount) / .16).clamp(0.0, 1.0);
    return 1 + 1.8 * _smoothStep(contact);
  }

  /// Intersect the outer ray with the two offset faces and a bounded bevel.
  /// This keeps the shoulders of a worn wax tip without a circular join or an
  /// unbounded miter at a reversal. Noise only moves the bevel, so the incoming
  /// and outgoing crossbars still match their neighboring ribbon exactly.
  double waxReachAt(double amount, double signedNormal,
      {required double roughness, required int seed}) {
    if (signedNormal * radians >= 0 || amount <= 0 || amount >= 1) return 1;
    final angle = radians.abs();
    final first = math.cos(angle * amount);
    final last = math.cos(angle * (1 - amount));
    final wear = PawDabResource._valueNoise2D(
        point.dx * .043, point.dy * .037, seed ^ 0x6b41);
    final tilt = roughness * (wear * 2 - 1) * 1.2;
    final middle = math.cos(angle * (amount - .5) + tilt);
    final noise = PawDabResource._valueNoise2D(
        amount * 7.3, point.dx * .031 + point.dy * .047, seed);
    final bevel = math.max(math.cos(angle * .5 - tilt.abs()), .78) +
        math.sin(math.pi * amount) * roughness * .45 * (noise * 2 - 1);
    var reach = bevel / math.max(.001, middle);
    if (first > .001) reach = math.min(reach, 1 / first);
    if (last > .001) reach = math.min(reach, 1 / last);
    // A worn wax face yields under pressure. Keep its tilted, uneven shoulders
    // but soften the planar limit; a rigid bevel looked like another flat cut.
    return 1 + (reach - 1) * .55;
  }
}

Map<double, _PawContactTurn> _contactTurnsInRange(
  List<PawBrushEmissionSegment> segments,
  double start,
  double end,
) {
  final turns = <double, _PawContactTurn>{};
  var low = 0, high = segments.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (segments[middle].arcEnd < start - .000001) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  for (var i = low; i + 1 < segments.length; i++) {
    final before = segments[i], after = segments[i + 1];
    final arc = before.arcEnd;
    if (arc > end + .000001) break;
    if (arc < start - .000001 ||
        (arc - after.arcStart).abs() > .000001 ||
        (before.p1 - after.p0).distanceSquared > .000001) {
      continue;
    }
    // Use the one-sided cubic directions, including zero-length endpoint
    // handles. A zero derivative's generic fallback can describe the other end.
    final incoming = _contactTangent(
        before.p1 - before.c2, before.p1 - before.c1, before.p1 - before.p0);
    final outgoing = _contactTangent(
        after.c1 - after.p0, after.c2 - after.p0, after.p1 - after.p0);
    final radians = math.atan2(
        incoming.dx * outgoing.dy - incoming.dy * outgoing.dx,
        incoming.dx * outgoing.dx + incoming.dy * outgoing.dy);
    if (radians.abs() <= .12) continue;
    final key = (arc - start).abs() <= .000001
        ? start
        : (arc - end).abs() <= .000001
            ? end
            : arc;
    turns[key] = _PawContactTurn(before.p1, incoming, outgoing, radians);
  }
  return turns;
}

Offset _contactTangent(Offset first, Offset second, Offset chord) {
  final vector = first.distanceSquared > .000000000001
      ? first
      : second.distanceSquared > .000000000001
          ? second
          : chord;
  return _DabInstanceEvaluator._normalized(vector);
}
