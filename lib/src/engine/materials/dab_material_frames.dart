part of '../../streaming_dab_brush.dart';

extension _DabMaterialFrames on PawStreamingDabRenderCache {
  _PawFilamentArcSample? _filamentSampleAtArc(
    PawDabEmissionSource stroke,
    double arc,
  ) {
    final result = _centerlineSampleAtArc(stroke, arc);
    lastFilamentArcSampleCount++;
    return result;
  }

  _PawFilamentArcSample? _centerlineSampleAtArc(
    PawDabEmissionSource stroke,
    double arc,
  ) {
    arc = stroke.wrapArc(arc);
    final segment = stroke.emissionSegmentAtArc(arc);
    lastSegmentLookupCount++;
    if (segment == null) return null;
    final t = ((arc - segment.arcStart) /
            math.max(.000001, segment.arcEnd - segment.arcStart))
        .clamp(0.0, 1.0);
    final sample = segment.sampleAtArcFraction(t, absoluteArc: arc);
    final direction = sample.tangent;
    return _PawFilamentArcSample(
      segmentIndex: segment.index,
      point: sample.point,
      direction: direction,
      normal: Offset(-direction.dy, direction.dx),
      motion: sample.motion,
    );
  }

  _PawFilamentArcSample? _contactGeometryAtArc(
          PawDabEmissionSource stroke, double arc) =>
      _contactGeometryFrames.putIfAbsent(
          arc, () => _centerlineSampleAtArc(stroke, arc));

  /// Interpolate lifted trajectory angles rather than averaged axial vectors.
  /// Opposing doubled-angle vectors cancel at a right angle and make atan2
  /// spin through the turn in a narrow band. Scalar spline derivatives stay
  /// finite and retain a continuous full-angle frame for intrinsic hair curves.
  (Offset, double) _hairDirectorAtArc(PawDabEmissionSource stroke, double arc,
      _PawFilamentArcSample root, double h) {
    // Decouple the direction filter's physical window from knot spacing.
    // A half-window lattice avoids concentrating an off-grid turn between two
    // instantaneous tangent samples. Its maximum forward reach is 1.75*h,
    // within the existing 2*h material dependency.
    final step = stroke.isClosed
        ? stroke.renderEndArc / (stroke.renderEndArc / (h * .5)).ceil()
        : h * .5;
    final coordinate = arc / step;
    final knot = coordinate.floor();
    final u = coordinate - knot, v = 1 - u;
    final u2 = u * u, u3 = u2 * u;
    final weights = [
      v * v * v / 6,
      (3 * u3 - 6 * u2 + 4) / 6,
      (-3 * u3 + 3 * u2 + 3 * u + 1) / 6,
      u3 / 6
    ];
    final derivatives = [
      -v * v / 2,
      1.5 * u2 - 2 * u,
      -1.5 * u2 + u + .5,
      u2 / 2
    ];
    var angle = 0.0, angularRate = 0.0;
    double? previousAngle;
    for (var i = 0; i < 4; i++) {
      var value = _hairDirectionKnots.putIfAbsent((h, knot + i - 1), () {
        final at = (knot + i - 1) * step;
        final clamped = stroke.isClosed
            ? at
            : at.clamp(0.0, stroke.renderEndArc).toDouble();
        final raw = _centerlineSampleAtArc(stroke, clamped)!;
        // Filter direction over a finite traveled interval before sampling it
        // onto the coarser angle spline. Sampling instantaneous tangents alone
        // aliases a turn between knots into a phase-dependent angle step.
        final before = _centerlineSampleAtArc(
            stroke,
            stroke.isClosed
                ? clamped - h * .75
                : (clamped - h * .75).clamp(0.0, stroke.renderEndArc))!;
        final after = _centerlineSampleAtArc(
            stroke,
            stroke.isClosed
                ? clamped + h * .75
                : (clamped + h * .75).clamp(0.0, stroke.renderEndArc))!;
        final secantDirection = after.point - before.point;
        var direction = secantDirection.distanceSquared > .000001
            ? _DabInstanceEvaluator._normalized(secantDirection)
            : raw.direction;
        if (at != clamped) {
          final insideArc = at < 0
              ? math.min(stroke.renderEndArc, h)
              : math.max(0.0, stroke.renderEndArc - h);
          final inside = _centerlineSampleAtArc(stroke, insideArc)!;
          final secant =
              at < 0 ? inside.point - raw.point : raw.point - inside.point;
          if (secant.distanceSquared > .000001) {
            direction = _DabInstanceEvaluator._normalized(secant);
          }
        }
        return math.atan2(direction.dy, direction.dx);
      });
      if (previousAngle != null) {
        var delta = value - previousAngle;
        delta -= (delta / (2 * math.pi)).round() * (2 * math.pi);
        // Exact reversals have two equivalent lifts. Curvature supplies the
        // turn sense when known; a deterministic positive lift handles a cusp.
        if ((delta.abs() - math.pi).abs() < .000001) {
          final pairMiddle = ((knot + i - 1.5) * step)
              .clamp(0.0, stroke.renderEndArc)
              .toDouble();
          final turn = _centerlineSampleAtArc(stroke, pairMiddle)!
              .motion
              .signedCurvature;
          delta = turn < 0 ? -math.pi : math.pi;
        }
        value = previousAngle + delta;
      }
      previousAngle = value;
      angle += value * weights[i];
      angularRate += value * derivatives[i] / step;
    }
    return (
      Offset(math.cos(angle), math.sin(angle)),
      // Roots sit on the original arc, not on the shortened B-spline pose.
      // Dividing by that pose's near-zero speed at a reversal amplified the
      // bend and suppressed an entire band's hair coverage.
      angularRate
    );
  }

  _PawFilamentArcSample? _materialFrameAtArc(
          PawDabEmissionSource stroke, double arc,
          {required double radius, bool stabilizeExtrapolation = false}) =>
      _materialFrames.putIfAbsent(
          (radius, arc, stabilizeExtrapolation),
          () => _computeMaterialFrame(stroke, arc,
              radius: radius, stabilizeExtrapolation: stabilizeExtrapolation));

  // A sweep uses position and tangent from the same centerline. Pressure/load
  // may be filtered, but must not rotate or collapse its crossbar. Inner folds
  // overlap locally (localDose handles dose); shrinking offsets using a
  // different spline's curvature used to pinch the contact at turns.
  _PawFilamentArcSample? _contactFrameAtArc(
      PawDabEmissionSource stroke, double arc,
      {required double radius}) {
    final pose = _materialFrameAtArc(stroke, arc, radius: radius);
    final raw = _contactGeometryAtArc(stroke, arc);
    if (raw == null || pose == null) return null;
    return _PawFilamentArcSample(
      segmentIndex: raw.segmentIndex,
      point: raw.point,
      direction: raw.direction,
      normal: raw.normal,
      motion: pose.motion,
      arcRate: pose.arcRate,
    );
  }

  _PawFilamentArcSample? _computeMaterialFrame(
      PawDabEmissionSource stroke, double arc,
      {required double radius, required bool stabilizeExtrapolation}) {
    if (radius <= 0 || !radius.isFinite) return null;
    final h = stroke.isClosed
        ? stroke.renderEndArc / (stroke.renderEndArc / radius).ceil()
        : radius;
    final coordinate = arc / h;
    final knot = coordinate.floor();
    final u = coordinate - knot;
    final samples = <_PawFilamentArcSample>[];
    for (var i = -1; i <= 2; i++) {
      final sample =
          _materialKnots.putIfAbsent((h, knot + i, stabilizeExtrapolation), () {
        final at = (knot + i) * h;
        final clamped = stroke.isClosed
            ? at
            : at.clamp(0.0, stroke.renderEndArc).toDouble();
        final raw = _centerlineSampleAtArc(stroke, clamped);
        if (raw == null) return null;
        var extrapolationDirection = raw.direction;
        if (stabilizeExtrapolation && at != clamped) {
          // A single last-event tangent can rotate every exposed hair at once.
          // Use the endpoint secant over the guide's own support instead.
          final insideArc = at < 0
              ? math.min(stroke.renderEndArc, h)
              : math.max(0.0, stroke.renderEndArc - h);
          final inside = _centerlineSampleAtArc(stroke, insideArc);
          if (inside != null) {
            final secant =
                at < 0 ? inside.point - raw.point : raw.point - inside.point;
            if (secant.distanceSquared > .000001) {
              extrapolationDirection =
                  _DabInstanceEvaluator._normalized(secant);
            }
          }
        }
        return _PawFilamentArcSample(
            segmentIndex: raw.segmentIndex,
            point: raw.point + extrapolationDirection * (at - clamped),
            direction: raw.direction,
            normal: raw.normal,
            motion: raw.motion);
      });
      if (sample == null) return null;
      samples.add(sample);
    }
    final u2 = u * u, u3 = u2 * u, v = 1 - u;
    final w = [
      v * v * v / 6,
      (3 * u3 - 6 * u2 + 4) / 6,
      (-3 * u3 + 3 * u2 + 3 * u + 1) / 6,
      u3 / 6
    ];
    final d = [-v * v / 2, 1.5 * u2 - 2 * u, -1.5 * u2 + u + .5, u2 / 2];
    final dd = [v, 3 * u - 2, 1 - 3 * u, u];
    var point = Offset.zero, derivative = Offset.zero, second = Offset.zero;
    var pressure = 0.0, speed = 0.0;
    for (var i = 0; i < 4; i++) {
      point += samples[i].point * w[i];
      derivative += samples[i].point * d[i] / h;
      second += samples[i].point * dd[i] / (h * h);
      pressure += samples[i].motion.pressure * w[i];
      speed += samples[i].motion.speedPixelsPerSecond * w[i];
    }
    final rate = derivative.distance;
    final direction = rate > .000001 ? derivative / rate : samples[1].direction;
    final curvature = rate > .000001
        ? (derivative.dx * second.dy - derivative.dy * second.dx) /
            (rate * rate * rate)
        : 0.0;
    return _PawFilamentArcSample(
      segmentIndex: samples[1].segmentIndex,
      point: point,
      direction: direction,
      normal: Offset(-direction.dy, direction.dx),
      arcRate: rate.clamp(.05, 1.0),
      motion: PawStreamingMotionSample(
          absoluteArc: arc,
          pressure: pressure,
          speedPixelsPerSecond: speed,
          signedCurvature: curvature.clamp(-1.0, 1.0)),
    );
  }
}
