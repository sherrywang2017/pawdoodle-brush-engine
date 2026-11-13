import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// One section of a continuous brush contact, already evaluated by its kernel.
class PawSweepSection {
  const PawSweepSection(this.point, this.radius, this.load,
      {this.arc = 0, this.opacity = 1});
  final Offset point;
  final double radius;
  final double load;
  final double arc;
  final double opacity;
}

/// Level sets turn variable-width, translucent contact into a union rather
/// than a translucent triangle strip. Every contour has the same winding:
/// folds, U-turns and adjacent segments cannot multiply the pigment dose.
/// Discrete strokes still composite normally on the document.
class PawSweptCoverage {
  PawSweptCoverage(
      {required List<PawSweepSection> sections,
      required double hardness,
      required double capRoundness,
      required Color color,
      required double coverageCeiling,
      bool tangentCaps = false,
      Path? exactCenterline,
      this.aspect = 1,
      this.rotation = 0}) {
    final c = math.cos(rotation), s = math.sin(rotation);
    if (rotation != 0) {
      sections = [
        for (final section in sections)
          PawSweepSection(
              Offset(section.point.dx * c + section.point.dy * s,
                  -section.point.dx * s + section.point.dy * c),
              section.radius,
              section.load,
              arc: section.arc,
              opacity: section.opacity)
      ];
      exactCenterline = exactCenterline?.transform(Float64List.fromList(
          [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    }
    if (aspect != 1) {
      sections = [
        for (final s in sections)
          PawSweepSection(
              Offset(s.point.dx / aspect, s.point.dy), s.radius, s.load,
              arc: s.arc, opacity: s.opacity)
      ];
      exactCenterline = exactCenterline?.transform(Float64List.fromList(
          [1 / aspect, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    }
    if (sections.isEmpty) return;
    final peak = sections.fold<double>(0, (v, s) => math.max(v, s.load));
    if (peak <= 0) return;
    if (sections.any((s) => s.opacity < .99999)) {
      // Opacity is a continuous longitudinal field, not a stack of shortened
      // contacts. Thresholding load gives every threshold its own end cap,
      // producing visible concentric crescents even on a constant-width tip.
      _buildLoadField(sections);
    }
    final uniform = sections.every((s) =>
        (s.radius - sections.first.radius).abs() < .00001 &&
        (s.load - peak).abs() < .00001);
    // Native cubic stroking avoids both stamp scallops and flattening error
    // on uniform round lines. Variable width uses the same union semantics.
    if (uniform &&
        hardness >= .999 &&
        capRoundness >= .999 &&
        exactCenterline != null &&
        sections.length > 1) {
      _layers.add((
        exactCenterline,
        Paint()
          ..color = color.withValues(alpha: peak)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sections.first.radius * 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..isAntiAlias = true
      ));
      return;
    }
    final increment = coverageCeiling / 12;
    if (increment <= 0) return;
    final count = (peak / increment + .5).floor().clamp(1, 12);
    var accumulated = 0.0;
    for (var level = 0; level < count; level++) {
      // The thresholds belong to the authored brush, not the largest pressure
      // observed so far. A later hard press cannot recolor the stable prefix.
      final threshold = increment * (level + .5);
      final path = Path()..fillType = PathFillType.nonZero;
      double radius(PawSweepSection section) {
        if (section.load < threshold) return 0;
        // Inverse linear shoulder. The level-set union integrates coverage,
        // independently of input cadence, dab spacing and triangle topology.
        final radial =
            hardness + (1 - hardness) * (1 - threshold / section.load);
        return section.radius * radial;
      }

      final useCubic = uniform &&
          capRoundness >= .999 &&
          exactCenterline != null &&
          sections.length > 1;
      if (!useCubic) {
        // A level can start/end inside the stroke as pressure or the endpoint
        // envelope changes. Interpolate its crossing before constructing the
        // contact union; a zero-radius strip would slice that contact in half.
        final active = <PawSweepSection>[];
        void flush() {
          if (active.isNotEmpty) {
            _outline(path, active, radius, capRoundness, tangentCaps);
            active.clear();
          }
        }

        for (var i = 0; i < sections.length; i++) {
          final current = sections[i];
          if (i > 0) {
            final previous = sections[i - 1];
            if ((previous.load < threshold) != (current.load < threshold)) {
              final t =
                  (threshold - previous.load) / (current.load - previous.load);
              active.add(PawSweepSection(
                  Offset.lerp(previous.point, current.point, t)!,
                  previous.radius + (current.radius - previous.radius) * t,
                  threshold));
              if (current.load < threshold) flush();
            }
          }
          if (current.load >= threshold) active.add(current);
        }
        flush();
      }
      final alpha = (increment / (1 - accumulated)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..isAntiAlias = true;
      if (useCubic) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius(sections.first) * 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round;
      }
      _layers.add((useCubic ? exactCenterline : path, paint));
      accumulated += increment;
    }
  }
  final double aspect;
  final double rotation;
  final _layers = <(Path, Paint)>[];
  Vertices? _loadField;
  Rect? _loadBounds;
  int get layerCount => _layers.length;

  void _buildLoadField(List<PawSweepSection> sections) {
    if (sections.length < 2) return;
    final positions = <Offset>[], colors = <Color>[];
    final reach = sections.fold<double>(0, (r, s) => math.max(r, s.radius)) + 2;
    Offset direction(int a, int b) {
      final delta = sections[b].point - sections[a].point;
      return delta.distance > .000001
          ? delta / delta.distance
          : const Offset(1, 0);
    }

    Offset side(int index) {
      final incoming =
          direction(math.max(0, index - 1), index == 0 ? 1 : index);
      final outgoing = direction(
          index == sections.length - 1 ? index - 1 : index,
          math.min(sections.length - 1, index + 1));
      final sum = incoming + outgoing;
      final d = sum.distance > .000001 ? sum / sum.distance : outgoing;
      final cosine = math.max(.25, d.dx * outgoing.dx + d.dy * outgoing.dy);
      return Offset(-d.dy, d.dx) * (reach / cosine);
    }

    for (var i = 1; i < sections.length; i++) {
      final a = sections[i - 1], b = sections[i];
      final delta = b.point - a.point;
      if (delta.distance < .000001) continue;
      final d = delta / delta.distance;
      final na = side(i - 1), nb = side(i);
      void quad(
          Offset p, Offset q, Offset pn, Offset qn, double from, double to) {
        final corners = [p - pn, q - qn, q + qn, p + pn];
        for (final j in const [0, 1, 2, 0, 2, 3]) {
          positions.add(corners[j]);
          final v =
              ((j == 0 || j == 3 ? from : to) * 255).round().clamp(0, 255);
          colors.add(Color.fromARGB(255, v, v, v));
        }
      }

      quad(a.point, b.point, na, nb, a.opacity, b.opacity);
      if (i == 1) {
        quad(a.point - d * reach, a.point, na, na, a.opacity, a.opacity);
      }
      if (i == sections.length - 1) {
        quad(b.point, b.point + d * reach, nb, nb, b.opacity, b.opacity);
      }
    }
    if (positions.isEmpty) return;
    _loadField = Vertices(VertexMode.triangles, positions, colors: colors);
    var bounds = Rect.fromCircle(center: sections.first.point, radius: reach);
    for (final s in sections.skip(1)) {
      bounds = bounds
          .expandToInclude(Rect.fromCircle(center: s.point, radius: reach));
    }
    _loadBounds = bounds;
  }

  static void _outline(
      Path path,
      List<PawSweepSection> sections,
      double Function(PawSweepSection) radius,
      double capRoundness,
      bool tangentCaps) {
    if (capRoundness > 0 && !tangentCaps) {
      // Union finite contacts, including intermediate pressure/opacity peaks.
      // Connecting only their transverse sections loses the backwards-facing
      // half of an increasing contact and leaves a pale hemisphere at attack.
      // Common tangents and exposed circular arcs form one envelope per run.
      // Do not submit a disk at every sample: tessellating thousands of
      // overlapping ovals at each load level stalls long looping strokes.
      void contact(Offset point, Offset d, double r) {
        if (r <= 0) return;
        if (capRoundness == 1) {
          path.addOval(Rect.fromCircle(center: point, radius: r));
          return;
        }
        final n = Offset(-d.dy, d.dx);
        path.addPath(Path()..addOval(Rect.fromLTRB(-r, -r, r, r)), Offset.zero,
            matrix4: Float64List.fromList([
              d.dx * capRoundness,
              d.dy * capRoundness,
              0,
              0,
              n.dx,
              n.dy,
              0,
              0,
              0,
              0,
              1,
              0,
              point.dx,
              point.dy,
              0,
              1,
            ]));
      }

      if (sections.length == 1) {
        contact(
            sections.first.point, const Offset(1, 0), radius(sections.first));
        return;
      }
      final edges = <_SweepEdge>[];
      double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
      void flush() {
        if (edges.isEmpty) return;
        final outline = Path();
        void trace(bool reverse) {
          final ordered = reverse ? edges.reversed.toList() : edges;
          Offset start(_SweepEdge e) =>
              reverse ? e.b + e.left * e.rb : e.a + e.right * e.ra;
          Offset end(_SweepEdge e) =>
              reverse ? e.a + e.left * e.ra : e.b + e.right * e.rb;
          Offset normal(_SweepEdge e) => reverse ? e.left : e.right;
          final first = start(ordered.first);
          if (reverse) {
            outline.lineTo(first.dx, first.dy);
          } else {
            outline.moveTo(first.dx, first.dy);
          }
          for (var i = 1; i < ordered.length; i++) {
            final previous = ordered[i - 1], next = ordered[i];
            final center = reverse ? previous.a : previous.b;
            final r = reverse ? previous.ra : previous.rb;
            final n1 = normal(previous), n2 = normal(next);
            final angle =
                math.atan2(cross(n1, n2), n1.dx * n2.dx + n1.dy * n2.dy);
            final a = end(previous), b = start(next);
            if (angle > .000001) {
              final cosine = math.cos(angle * .5);
              if (cosine > 0 && r * (1 / cosine - 1) <= .05) {
                // A tiny exposed arc can use its tangent intersection with
                // <= .05 logical px outward error. This keeps ordinary curved
                // runs linear-sized polygons; only visible arcs need conics.
                final midpoint =
                    center + (n1 + n2) * (r / (2 * cosine * cosine));
                outline.lineTo(midpoint.dx, midpoint.dy);
              } else {
                outline.lineTo(a.dx, a.dy);
                outline.arcTo(Rect.fromCircle(center: center, radius: r),
                    math.atan2(n1.dy, n1.dx), angle, false);
              }
            } else {
              final d1 = end(previous) - start(previous),
                  d2 = end(next) - start(next);
              final denominator = cross(d1, d2);
              final intersection = denominator.abs() > .00000001
                  ? a + d1 * (cross(b - a, d2) / denominator)
                  : (a + b) * .5;
              if ((intersection - center).distance <= r * 3 + .01) {
                outline.lineTo(intersection.dx, intersection.dy);
              } else {
                outline.lineTo(a.dx, a.dy);
                outline.lineTo(b.dx, b.dy);
                path.addOval(Rect.fromCircle(center: center, radius: r));
              }
            }
          }
          final last = end(ordered.last);
          outline.lineTo(last.dx, last.dy);
        }

        trace(false);
        trace(true);
        outline.close();
        path.addPath(outline, Offset.zero);
        contact(edges.first.a, edges.first.direction, edges.first.ra);
        contact(edges.last.b, edges.last.direction, edges.last.rb);
        edges.clear();
      }

      for (var i = 1; i < sections.length; i++) {
        final a = sections[i - 1], b = sections[i];
        final ra = radius(a), rb = radius(b);
        final delta = b.point - a.point;
        final length = delta.distance;
        final d = length > .000001 ? delta / length : const Offset(1, 0);
        // If one disk contains the other, it already covers the whole sweep.
        if (length <= (rb - ra).abs() || length < .000001) {
          flush();
          path.addOval(Rect.fromCircle(
              center: ra >= rb ? a.point : b.point, radius: math.max(ra, rb)));
          continue;
        }
        if (edges.isNotEmpty) {
          final previous = edges.last;
          final dot =
              d.dx * previous.direction.dx + d.dy * previous.direction.dy;
          if (dot < .5 ||
              ra * math.sqrt(math.max(0, 2 * (1 - dot))) >
                  math.min(length, previous.length) * .65) {
            flush();
            path.addOval(Rect.fromCircle(center: a.point, radius: ra));
          }
        }
        final slope = (ra - rb) / length;
        final side = math.sqrt(math.max(0, 1 - slope * slope));
        final along = d * slope;
        final normal = Offset(-d.dy, d.dx) * side;
        edges.add(_SweepEdge(a.point, b.point, ra, rb, along - normal,
            along + normal, d, length));
      }
      flush();
      return;
    }
    final left = <Offset>[], right = <Offset>[];
    if (sections.length == 1) {
      final r = radius(sections.first);
      final bounds = Rect.fromCircle(center: sections.first.point, radius: r);
      if (capRoundness > 0) {
        path.addOval(bounds);
      } else {
        path.addRect(bounds);
      }
      return;
    }
    void flush() {
      if (left.length > 1) path.addPolygon([...right, ...left.reversed], true);
      left.clear();
      right.clear();
    }

    Offset direction(int a, int b) {
      final d = sections[b].point - sections[a].point;
      return d.distanceSquared > .000001 ? d / d.distance : const Offset(1, 0);
    }

    void cap(Offset p, Offset d, double r, double aspect) {
      if (r <= 0 || aspect <= 0) return;
      final oval = Path()
        ..addOval(Rect.fromLTRB(-r * aspect, -r, r * aspect, r));
      path.addPath(oval, Offset.zero,
          matrix4: Float64List.fromList([
            d.dx,
            d.dy,
            0,
            0,
            -d.dy,
            d.dx,
            0,
            0,
            0,
            0,
            1,
            0,
            p.dx,
            p.dy,
            0,
            1
          ]));
    }

    for (var i = 0; i < sections.length; i++) {
      final s = sections[i], r = radius(s);
      // A zero-width endpoint is still a polygon vertex: dropping it turns a
      // requested point into a blunt cut at the next sampled section.
      final incoming = direction(
          math.max(0, i - 1), i == 0 ? math.min(1, sections.length - 1) : i);
      final outgoing = direction(
          i == sections.length - 1 ? math.max(0, i - 1) : i,
          math.min(sections.length - 1, i + 1));
      final dot = (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy)
          .clamp(-1.0, 1.0);
      final sum = incoming + outgoing;
      final d = sum.distanceSquared > .000001 ? sum / sum.distance : outgoing;
      final normal = Offset(-d.dy, d.dx);
      final leg =
          i > 0 ? (s.point - sections[i - 1].point).distance : double.infinity;
      // Offset cusps occur when the contact radius exceeds local curvature
      // radius. End that contour before it folds and unite a round join.
      final cusp =
          dot < .5 || r * math.sqrt(math.max(0, 2 * (1 - dot))) > leg * .65;
      if (cusp && i > 0 && i < sections.length - 1) {
        final n = Offset(-incoming.dy, incoming.dx) * r;
        left.add(s.point + n);
        right.add(s.point - n);
        flush();
        cap(s.point, outgoing, r, 1);
        final next = Offset(-outgoing.dy, outgoing.dx) * r;
        left.add(s.point + next);
        right.add(s.point - next);
      } else {
        final extent = normal * (r / math.sqrt(math.max(.5, (1 + dot) * .5)));
        left.add(s.point + extent);
        right.add(s.point - extent);
      }
      if ((i == 0 || i == sections.length - 1) && capRoundness > 0 && r > 0) {
        final next = sections[i == 0 ? 1 : i - 1];
        final delta = next.point - s.point;
        final length = delta.distance;
        final inward = length > .000001 ? delta / length : d;
        final slope = length > .000001 ? (radius(next) - r) / length : 0.0;
        // The cap is only the exposed circular segment tangent to the side
        // rails. Its center shifts inward as the opening angle increases.
        // A full disk would protrude through the authored taper, swallowing a
        // zero-width tip or forming the small round knob reported in Studio.
        final center = s.point + inward * (r * slope);
        final circleRadius = r * math.sqrt(1 + slope * slope);
        final angle =
            math.atan2(inward.dy, inward.dx) + math.pi / 2 + math.atan(slope);
        final capPath = Path()
          ..arcTo(Rect.fromCircle(center: center, radius: circleRadius), angle,
              math.pi - 2 * math.atan(slope), true)
          ..close();
        path.addPath(capPath, Offset.zero);
      }
    }
    flush();
  }

  void paint(Canvas canvas) {
    canvas.save();
    canvas.rotate(rotation);
    canvas.scale(aspect, 1);
    if (_loadField != null) canvas.saveLayer(_loadBounds, Paint());
    for (final layer in _layers) {
      canvas.drawPath(layer.$1, layer.$2);
    }
    if (_loadField case final field?) {
      // Opaque grayscale lets lighten select the maximum at self-overlaps
      // without accumulating pigment. Convert that continuous field to alpha
      // once when applying it to the independent geometric coverage.
      canvas.saveLayer(
          _loadBounds,
          Paint()
            ..blendMode = BlendMode.dstIn
            ..colorFilter = const ColorFilter.matrix([
              0,
              0,
              0,
              0,
              255,
              0,
              0,
              0,
              0,
              255,
              0,
              0,
              0,
              0,
              255,
              1,
              0,
              0,
              0,
              0,
            ]));
      canvas.drawVertices(
          field,
          BlendMode.src,
          Paint()
            ..blendMode = BlendMode.lighten
            ..isAntiAlias = false);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  void dispose() => _loadField?.dispose();
}

class _SweepEdge {
  const _SweepEdge(this.a, this.b, this.ra, this.rb, this.right, this.left,
      this.direction, this.length);
  final Offset a, b, right, left, direction;
  final double ra, rb, length;
}
