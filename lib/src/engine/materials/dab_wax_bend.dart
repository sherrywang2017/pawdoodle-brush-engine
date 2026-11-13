part of '../../streaming_dab_brush.dart';

/// A modeled cusp may be a short pair of tangent-continuous cubics instead of
/// a tangent jump. A wax tip wider than that bend still presents a worn face.
/// Keep the original curve and deform only its outer contact cross-sections.
class _PawWaxBend {
  const _PawWaxBend(this.start, this.end, this.turn);
  final double start, end;
  final _PawContactTurn turn;

  double progressAt(Offset direction) {
    final angle = math.atan2(
        turn.incoming.dx * direction.dy - turn.incoming.dy * direction.dx,
        turn.incoming.dx * direction.dx + turn.incoming.dy * direction.dy);
    return (angle / turn.radians).clamp(0.0, 1.0);
  }
}

List<_PawWaxBend> _waxBendsInRange(List<PawBrushEmissionSegment> segments,
    double start, double end, double brushSize) {
  final reach = brushSize * .3;
  var low = 0, high = segments.length;
  while (low < high) {
    final middle = (low + high) >> 1;
    if (segments[middle].arcEnd < start - reach) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  final bends = <_PawWaxBend>[];
  for (var i = low; i + 1 < segments.length; i++) {
    final before = segments[i], after = segments[i + 1];
    if (before.arcStart > end) break;
    if (after.arcEnd < start ||
        before.arcLength > reach ||
        after.arcLength > reach ||
        before.arcLength < .000001 ||
        after.arcLength < .000001 ||
        (before.p1 - after.p0).distanceSquared > .000001) {
      continue;
    }
    final arriving = _contactTangent(
        before.p1 - before.c2, before.p1 - before.c1, before.p1 - before.p0);
    final departing = _contactTangent(
        after.c1 - after.p0, after.c2 - after.p0, after.p1 - after.p0);
    // A real tangent jump already owns a contact fan. Applying the curved
    // bend deformation as well made its boundary crossbars disagree.
    if (_DabInstanceEvaluator._directionTurnRadians(arriving, departing) >
        .12) {
      continue;
    }
    // Match the derivatives at the deformation's endpoints, not their chords.
    // Chords differ on a cubic and used to leave a notch where the bend ended.
    final incoming = _contactTangent(
        before.c1 - before.p0, before.c2 - before.p0, before.p1 - before.p0);
    final outgoing = _contactTangent(
        after.p1 - after.c2, after.p1 - after.c1, after.p1 - after.p0);
    final angle = math.atan2(
        incoming.dx * outgoing.dy - incoming.dy * outgoing.dx,
        incoming.dx * outgoing.dx + incoming.dy * outgoing.dy);
    // Broad curves and ordinary bends keep their modeled footprint. Only a
    // reversal concentrated inside the finite tip needs the corner face.
    if (angle.abs() < 2.2) continue;
    bends.add(_PawWaxBend(before.arcStart, after.arcEnd,
        _PawContactTurn(before.p1, incoming, outgoing, angle)));
  }
  return bends;
}
