part of '../../streaming_stroke_modeler.dart';

extension _CenterlineTail on PawStreamingCenterlineModeler {
  void _rebuildTail() {
    if (!stableCausalJoins) {
      _rebuildLegacyTail();
      return;
    }
    // Geometry evidence and spline positions must observe the same signal.
    // Classifying raw pixel stairs after conditioning the knots reintroduces
    // their angular impulses through handle collapse / half-plane projection.
    final geometry = PawConditionedTouchSamples(_rawPolyline);
    final evidenceCache = <int, PawLocalGeometryEvidence>{};
    final previousTail = List<PawStreamingSegmentCommand>.of(_tailSegments);
    final causalSealBarrierMicros = _causalSealBarrierMicros;
    var reusableCount = 0;
    while (reusableCount < previousTail.length) {
      final endMicros = previousTail[reusableCount].endTime.inMicroseconds;
      // Ordinary delivery confirms geometry through the previous raw event.
      // A segment ending exactly there is immutable; the next cubic inherits
      // its end tangent. Corner evidence remains strict because an inferred
      // cusp may still replace geometry at its candidate timestamp.
      final beyondConfirmedRaw = causalSealBarrierMicros == null ||
          endMicros >= causalSealBarrierMicros;
      final reachesExplicitInvalidation = _tailInvalidationMicros != null &&
          endMicros >= _tailInvalidationMicros!;
      if (beyondConfirmedRaw || reachesExplicitInvalidation) {
        break;
      }
      reusableCount++;
    }
    final reusable = previousTail.take(reusableCount).toList(growable: false);
    final localAnchor = reusable.isEmpty ? _anchor : reusable.last.p1;
    var localAnchorTangent =
        reusable.isEmpty ? _anchorTangent : reusable.last.endTangent;
    final localAnchorPressure =
        reusable.isEmpty ? _anchorPressure : reusable.last.endPressure;
    final localAnchorTime =
        reusable.isEmpty ? _anchorTime : reusable.last.endTime;
    final localAnchorArc = reusable.isEmpty ? _anchorArc : reusable.last.arcEnd;
    final localNextSegmentIndex =
        reusable.isEmpty ? _nextSegmentIndex : reusable.last.index + 1;
    _tailSegments
      ..clear()
      ..addAll(reusable);
    final points = <({
      Offset position,
      double pressure,
      Duration time,
      bool preservesCusp,
    })>[
      (
        position: localAnchor,
        pressure: localAnchorPressure,
        time: localAnchorTime,
        preservesCusp: _anchorPreservesCusp ||
            _preservedCornerMicros.contains(localAnchorTime.inMicroseconds),
      ),
    ];
    if (_recentSamples.isEmpty) return;
    for (final sample in _recentSamples) {
      if (sample.timestamp < localAnchorTime) continue;
      final rawIndex =
          _rawPolyline.indexWhere((raw) => raw.timestamp == sample.timestamp);
      final position =
          rawIndex < 0 ? sample.position : geometry[rawIndex].position;
      if ((position - points.last.position).distance > .08) {
        points.add((
          position: position,
          pressure: sample.normalizedPressure ?? points.last.pressure,
          time: sample.timestamp,
          preservesCusp:
              _preservedCornerMicros.contains(sample.timestamp.inMicroseconds),
        ));
      }
    }
    final speculative = _speculativeSample;
    if (speculative != null &&
        speculative.timestamp >= localAnchorTime &&
        (speculative.position - points.last.position).distance > .08) {
      points.add((
        position: speculative.position,
        pressure: speculative.normalizedPressure ?? points.last.pressure,
        time: speculative.timestamp,
        preservesCusp: false,
      ));
    }
    if (points.length < 2) return;
    if (reusable.isEmpty && _sealedSegments.isEmpty && _anchorArc == 0) {
      final firstChord = points[1].position - points[0].position;
      final chordDirection = _normalized(
        firstChord,
        fallback: _anchorTangent,
      );
      // With only two samples the chord is the sole causal estimate. Once the
      // third real sample arrives, the first interval is still provisional and
      // can acquire the tangent of its three-point osculating circle. Keeping
      // the original chord tangent here made every fast initial arc start with
      // a short straight section and a visible kink.
      _anchorTangent = _rawPolyline.length >= 3 && points.length >= 3
          ? _initialCircularTangent(
              points[0].position,
              points[1].position,
              points[2].position,
              fallback: chordDirection,
            )
          : chordDirection;
      localAnchorTangent = _anchorTangent;
    }

    var arc = localAnchorArc;
    var provisionalIndex = localNextSegmentIndex;
    Offset tangentAtPoint(int pointIndex, Offset fallback) {
      if (pointIndex <= 0) {
        return _normalized(
          points[1].position - points[0].position,
          fallback: fallback,
        );
      }
      if (pointIndex >= points.length - 1) {
        return _normalized(
          points.last.position - points[points.length - 2].position,
          fallback: fallback,
        );
      }
      final incoming =
          points[pointIndex].position - points[pointIndex - 1].position;
      final outgoing =
          points[pointIndex + 1].position - points[pointIndex].position;
      final incomingLength = incoming.distance;
      final outgoingLength = outgoing.distance;
      if (incomingLength <= .0001 || outgoingLength <= .0001) return fallback;
      final incomingDirection = incoming / incomingLength;
      final outgoingDirection = outgoing / outgoingLength;
      // Chord-length weights recover the tangent of a sampled circle even
      // when event spacing changes. Square-root weights bias sparse turns
      // toward the longer leg and leave visible flat sections.
      final incomingWeight = outgoingLength;
      final outgoingWeight = incomingLength;
      return _normalized(
        incomingDirection * incomingWeight + outgoingDirection * outgoingWeight,
        fallback: fallback,
      );
    }

    PawLocalGeometryEvidence? evidenceAtPoint(int pointIndex) {
      if (pointIndex < 0 || pointIndex >= points.length) return null;
      final rawIndex = _rawPolyline.indexWhere(
        (sample) => sample.timestamp == points[pointIndex].time,
      );
      if (rawIndex <= 0 || rawIndex >= _rawPolyline.length - 1) return null;
      final evidence = evidenceCache.putIfAbsent(
          rawIndex,
          () => PawLocalGeometryEvidence.analyze(
                geometry,
                rawIndex,
                neighborhoodArc: math.max(48, geometryCorrectionHorizon * 4),
              ));
      lastLocalGeometryEvidence = evidence;
      return evidence;
    }

    double distributedRawCurvature(int pointIndex) {
      final rawIndex = _rawPolyline
          .indexWhere((sample) => sample.timestamp == points[pointIndex].time);
      if (rawIndex < 0) return 0;
      double curvature(int index) {
        if (index < 1 || index + 1 >= _rawPolyline.length) return 0;
        final a = geometry[index].position - geometry[index - 1].position;
        final b = geometry[index + 1].position - geometry[index].position;
        final denominator = a.distance * b.distance * (a + b).distance;
        if (denominator < .0001 || _signedTurnRadians(a, b).abs() > 2.4) {
          return 0;
        }
        return 2 * (a.dx * b.dy - a.dy * b.dx) / denominator;
      }

      var support = 0.0;
      // A fixed arc window may contain no neighbours during fast input. Two
      // consecutive observed turns can still establish distributed curvature.
      // Isolated impulses with straight legs receive no such allowance.
      for (var i = rawIndex - 2; i <= rawIndex + 1; i++) {
        final first = curvature(i), second = curvature(i + 1);
        if (first * second <= 0 ||
            first.abs() < .00001 ||
            second.abs() < .00001) {
          continue;
        }
        final ratio = math.min(first.abs(), second.abs()) /
            math.max(first.abs(), second.abs());
        support = math.max(support, ((ratio - .4) / .4).clamp(0.0, 1.0));
      }
      return support;
    }

    double tangentStrengthAtPoint(int pointIndex) {
      if (points[pointIndex].preservesCusp) return .06;
      if (pointIndex >= points.length - 1) return 1;
      final evidence = evidenceAtPoint(pointIndex);
      if (evidence == null) return pointIndex <= 0 ? 1 : .68;
      if (evidence.insufficientGeometryEvidence) {
        // Missing geometry is not positive cusp evidence. Keep a useful but
        // bounded tangent; the corridor check below prevents shortcuts.
        return evidence.turnMagnitude >= math.pi * .55 ? .46 : .7;
      }
      return (.94 -
              evidence.localizedCornerLikelihood * .88 +
              evidence.distributedSmoothLikelihood * .06)
          .clamp(.06, 1.0);
    }

    double handleAtPoint(
      int pointIndex,
      double segmentDistance,
      double strength,
    ) {
      final incomingLength = pointIndex <= 0
          ? segmentDistance
          : (points[pointIndex].position - points[pointIndex - 1].position)
              .distance;
      final outgoingLength = pointIndex >= points.length - 1
          ? segmentDistance
          : (points[pointIndex + 1].position - points[pointIndex].position)
              .distance;
      final localReach = math.min(incomingLength, outgoingLength) * .32;
      return math.min(segmentDistance * .45, localReach) * strength;
    }

    Offset forwardTangent(Offset tangent, Offset chord, Offset fallback) {
      final dot = tangent.dx * chord.dx + tangent.dy * chord.dy;
      return dot > .0001 ? tangent : fallback;
    }

    var previousOutputTangent = localAnchorTangent;
    for (var index = 0; index < points.length - 1; index++) {
      final segmentStart = points[index];
      final segmentEnd = points[index + 1];
      final chordTangent = _normalized(
        segmentEnd.position - segmentStart.position,
        fallback: localAnchorTangent,
      );
      final startTangent = forwardTangent(
        previousOutputTangent,
        segmentEnd.position - segmentStart.position,
        chordTangent,
      );
      final rawCount = _rawPolyline.length;
      final supportedLiveEnd = rawCount >= 4 &&
          segmentEnd.time == _rawPolyline.last.timestamp &&
          distributedRawCurvature(index + 1) >= .8;
      // Estimate the current endpoint from observed curvature, rather than
      // bending a long real interval toward a short speculative chord. This
      // makes spatial sealing possible without freezing sparse arcs flat.
      final liveEndTangent = supportedLiveEnd
          ? -_initialCircularTangent(
              _rawPolyline[rawCount - 1].position,
              _rawPolyline[rawCount - 2].position,
              _rawPolyline[rawCount - 3].position,
              fallback: -tangentAtPoint(index + 1, startTangent))
          : tangentAtPoint(index + 1, startTangent);
      final endTangent = forwardTangent(
        liveEndTangent,
        segmentEnd.position - segmentStart.position,
        chordTangent,
      );
      final distance = (segmentEnd.position - segmentStart.position).distance;
      var sourceC1 = segmentStart.position +
          startTangent *
              handleAtPoint(
                index,
                distance,
                tangentStrengthAtPoint(index),
              );
      var sourceC2 = segmentEnd.position -
          endTangent *
              handleAtPoint(
                index + 1,
                distance,
                tangentStrengthAtPoint(index + 1),
              );
      final startEvidence = evidenceAtPoint(index);
      final endEvidence = evidenceAtPoint(index + 1);
      final cornerLikelihood = math.max(
        startEvidence?.localizedCornerLikelihood ?? 0,
        endEvidence?.localizedCornerLikelihood ?? 0,
      );
      final smoothLikelihood = math.max(
        startEvidence?.distributedSmoothLikelihood ?? 0,
        endEvidence?.distributedSmoothLikelihood ?? 0,
      );
      final confidence = math.max(
        startEvidence?.evidenceConfidence ?? 0,
        endEvidence?.evidenceConfidence ?? 0,
      );
      final observedTurnMagnitude = math.max(
        startEvidence?.turnMagnitude ?? 0,
        endEvidence?.turnMagnitude ?? 0,
      );
      double coherentCurvature(PawLocalGeometryEvidence? evidence) {
        if (evidence == null) return 0;
        return evidence.signCoherence *
            (1 - evidence.turnConcentration) *
            evidence.evidenceConfidence;
      }

      final coherentCurvatureSupport = math.max(
          math.max(
              coherentCurvature(startEvidence), coherentCurvature(endEvidence)),
          math.max(distributedRawCurvature(index),
              distributedRawCurvature(index + 1)));
      final tangentTurn = _signedTurnRadians(startTangent, endTangent).abs();
      if (coherentCurvatureSupport >= .8 ||
          (coherentCurvatureSupport >= .22 && cornerLikelihood < .2)) {
        final cosine = math.cos(math.min(tangentTurn, math.pi * .9) / 4);
        final circularHandle = distance / (3 * cosine * cosine);
        sourceC1 = segmentStart.position + startTangent * circularHandle;
        sourceC2 = segmentEnd.position - endTangent * circularHandle;
      }
      // Once there is enough local support to distinguish a concentrated
      // turn from distributed curvature, keep endpoint handles in the convex
      // half-planes of the neighbouring raw legs. This is topology
      // containment, not positive corner classification: handle length and
      // C1 continuity remain available, while an UNKNOWN sparse gap cannot
      // hook outside the observed local wedge.
      final previousLeg = index > 0
          ? (points[index].position - points[index - 1].position).distance
          : distance;
      final nextLeg = index + 2 < points.length
          ? (points[index + 2].position - points[index + 1].position).distance
          : distance;
      final shortestLocalLeg =
          math.min(previousLeg, math.min(distance, nextLeg));
      final longestLocalLeg =
          math.max(previousLeg, math.max(distance, nextLeg));
      final sparseSupportImbalance =
          longestLocalLeg > .0001 && shortestLocalLeg / longestLocalLeg <= .36;
      final convexTurnContainment = observedTurnMagnitude >= math.pi * .1 &&
          smoothLikelihood < .25 &&
          coherentCurvatureSupport < .22 &&
          (cornerLikelihood >= .35 || sparseSupportImbalance) &&
          (confidence >= .55 || sparseSupportImbalance);
      final containmentAllowance = confidence >= .55 ? 0.0 : 1.2;
      if (convexTurnContainment) {
        if (index > 0) {
          sourceC1 = _projectToReferenceHalfPlane(
            point: sourceC1,
            lineStart: segmentStart.position,
            lineEnd: segmentEnd.position,
            reference: points[index - 1].position,
            allowance: containmentAllowance,
          );
        } else if (localAnchorArc > .0001) {
          // The preceding point may already be sealed and absent from
          // `points`; the immutable anchor tangent supplies its half-plane.
          sourceC1 = _projectToReferenceHalfPlane(
            point: sourceC1,
            lineStart: segmentStart.position,
            lineEnd: segmentEnd.position,
            reference: segmentStart.position - localAnchorTangent * distance,
            allowance: containmentAllowance,
          );
        }
        if (index + 2 < points.length) {
          sourceC2 = _projectToReferenceHalfPlane(
            point: sourceC2,
            lineStart: segmentStart.position,
            lineEnd: segmentEnd.position,
            reference: points[index + 2].position,
            allowance: containmentAllowance,
          );
        }
      }
      // Missing smooth evidence is UNKNOWN, never positive corner evidence.
      // A narrow corridor is reserved for a localized, sufficiently sampled
      // angular impulse with straight-leg support.
      final rawSharpBoundary = observedTurnMagnitude >= math.pi * .22 &&
          cornerLikelihood >= .35 &&
          confidence >= .35;
      // UNKNOWN is not a localized safety boundary. Large turns caused by a
      // sparse sample gap receive the ordinary bounded-handle/convex corridor
      // overshoot containment below; only positive corner evidence is allowed
      // to narrow the curve toward the raw chord.
      final baseCorridor = cornerLikelihood >= .45 || rawSharpBoundary
          ? rawFidelityCorridor * .55
          : math.min(
              rawFidelityCorridor + .4,
              rawFidelityCorridor +
                  distance *
                      (.035 + smoothLikelihood * .14 + (1 - confidence) * .025),
            );
      // A same-sign turn distributed over neighbouring samples describes a
      // curve, not a polygon corner. Its circular sagitta is allowed outside
      // the narrow raw-chord corridor in proportion to the measured turn and
      // support. A localized cusp has high concentration, so this term
      // naturally collapses and keeps the sharp-corner containment above.
      final curvatureCorridor = distance *
          math.tan(math.min(observedTurnMagnitude, 1.2) / 4) *
          coherentCurvatureSupport *
          1.7;
      final supportedSagitta = distance *
          .5 *
          math.tan(math.min(tangentTurn, math.pi * .9) / 4) *
          coherentCurvatureSupport *
          1.1;
      // Delivery time alone is not geometric corner evidence. A sustained
      // sequence of consistent measured curvatures must keep its interpolation
      // when callbacks slow down. An unsupported jump still uses the narrow
      // chord corridor; forward handles and the .22-chord bound limit overshoot
      // in both cases. This estimates between samples, never beyond the input.
      final deliveryGap = (segmentEnd.time - segmentStart.time).inMicroseconds;
      final adaptiveCorridor =
          deliveryGap > 50000 && coherentCurvatureSupport < .8
              ? rawFidelityCorridor
              : math.max(baseCorridor + curvatureCorridor, supportedSagitta);
      // Half-plane containment can rotate the outgoing handle. The following
      // interval must inherit that actual derivative, including an already
      // sealed anchor, instead of estimating/projecting a different tangent
      // at the same point. Shorten a handle to bound overshoot; do not kink a
      // smooth join. A true reversal still uses forwardTangent's cusp fallback.
      sourceC1 = segmentStart.position +
          startTangent * (sourceC1 - segmentStart.position).distance;
      final constrainedControls = _boundedCubicHandles(
        p0: segmentStart.position,
        c1: sourceC1,
        c2: sourceC2,
        p1: segmentEnd.position,
        corridor: math.min(distance * .22, adaptiveCorridor),
      );
      final subdivisions = math.max(1, (distance / 8).ceil());
      previousOutputTangent = _normalized(
          segmentEnd.position - constrainedControls.c2,
          fallback: endTangent);
      for (var subdivision = 0; subdivision < subdivisions; subdivision++) {
        final startT = subdivision / subdivisions;
        final endT = (subdivision + 1) / subdivisions;
        final p0 = _cubicPoint(
          segmentStart.position,
          constrainedControls.c1,
          constrainedControls.c2,
          segmentEnd.position,
          startT,
        );
        final p1 = _cubicPoint(
          segmentStart.position,
          constrainedControls.c1,
          constrainedControls.c2,
          segmentEnd.position,
          endT,
        );
        final startDerivative = _cubicDerivative(
          segmentStart.position,
          constrainedControls.c1,
          constrainedControls.c2,
          segmentEnd.position,
          startT,
        );
        final endDerivative = _cubicDerivative(
          segmentStart.position,
          constrainedControls.c1,
          constrainedControls.c2,
          segmentEnd.position,
          endT,
        );
        final localStartTangent = _normalized(
          startDerivative,
          fallback: startTangent,
        );
        final localEndTangent = _normalized(
          endDerivative,
          fallback: endTangent,
        );
        final intervalScale = (endT - startT) / 3;
        final c1 = p0 + startDerivative * intervalScale;
        final c2 = p1 - endDerivative * intervalScale;
        final length = _curveLength(p0, c1, c2, p1);
        if (length <= .0001) continue;
        final startPressure = segmentStart.pressure +
            (segmentEnd.pressure - segmentStart.pressure) * startT;
        final endPressure = segmentStart.pressure +
            (segmentEnd.pressure - segmentStart.pressure) * endT;
        final startMicros = segmentStart.time.inMicroseconds +
            ((segmentEnd.time.inMicroseconds -
                        segmentStart.time.inMicroseconds) *
                    startT)
                .round();
        final endMicros = segmentStart.time.inMicroseconds +
            ((segmentEnd.time.inMicroseconds -
                        segmentStart.time.inMicroseconds) *
                    endT)
                .round();
        _tailSegments.add(PawStreamingSegmentCommand(
          index: provisionalIndex++,
          p0: p0,
          c1: c1,
          c2: c2,
          p1: p1,
          startTangent: localStartTangent,
          endTangent: localEndTangent,
          arcStart: arc,
          arcEnd: arc + length,
          startPressure: startPressure,
          endPressure: endPressure,
          startTime: Duration(microseconds: startMicros),
          endTime: Duration(microseconds: endMicros),
        ));
        arc += length;
      }
    }
  }

  void _rebuildLegacyTail() {
    _tailSegments.clear();
    final points = <Offset>[_anchor];
    if (_recentSamples.isEmpty) return;
    var closestIndex = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < _recentSamples.length; index++) {
      final distance = (_recentSamples[index].position - _anchor).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = index;
      }
    }
    for (final sample in _recentSamples.skip(closestIndex)) {
      if ((sample.position - points.last).distance > .08) {
        points.add(sample.position);
      }
    }
    if (points.length < 2) return;
    if (_sealedSegments.isEmpty && _anchorArc == 0) {
      _anchorTangent = _normalized(
        points[1] - points[0],
        fallback: _anchorTangent,
      );
    }

    var arc = _anchorArc;
    for (var index = 0; index < points.length - 1; index++) {
      final segmentStart = points[index];
      final segmentEnd = points[index + 1];
      final previousPoint = index == 0 ? segmentStart : points[index - 1];
      final nextPoint =
          index + 2 >= points.length ? segmentEnd : points[index + 2];
      final startTangent = index == 0
          ? _anchorTangent
          : _normalized(segmentEnd - previousPoint, fallback: _anchorTangent);
      final endTangent = _normalized(
        nextPoint - segmentStart,
        fallback: startTangent,
      );
      final subdivisions = math.max(
        1,
        ((segmentEnd - segmentStart).distance / 8).ceil(),
      );
      for (var subdivision = 0; subdivision < subdivisions; subdivision++) {
        final startT = subdivision / subdivisions;
        final endT = (subdivision + 1) / subdivisions;
        final p1 = _cubicPoint(
          segmentStart,
          segmentStart +
              startTangent * (segmentEnd - segmentStart).distance / 6,
          segmentEnd - endTangent * (segmentEnd - segmentStart).distance / 6,
          segmentEnd,
          startT,
        );
        final p2 = _cubicPoint(
          segmentStart,
          segmentStart +
              startTangent * (segmentEnd - segmentStart).distance / 6,
          segmentEnd - endTangent * (segmentEnd - segmentStart).distance / 6,
          segmentEnd,
          endT,
        );
        final localStartTangent = _normalized(
          _cubicDerivative(
            segmentStart,
            segmentStart +
                startTangent * (segmentEnd - segmentStart).distance / 6,
            segmentEnd - endTangent * (segmentEnd - segmentStart).distance / 6,
            segmentEnd,
            startT,
          ),
          fallback: startTangent,
        );
        final localEndTangent = _normalized(
          _cubicDerivative(
            segmentStart,
            segmentStart +
                startTangent * (segmentEnd - segmentStart).distance / 6,
            segmentEnd - endTangent * (segmentEnd - segmentStart).distance / 6,
            segmentEnd,
            endT,
          ),
          fallback: endTangent,
        );
        final handle = (p2 - p1).distance / 6;
        final c1 = p1 + localStartTangent * handle;
        final c2 = p2 - localEndTangent * handle;
        final length = _curveLength(p1, c1, c2, p2);
        if (length <= .0001) continue;
        _tailSegments.add(PawStreamingSegmentCommand(
          index: _nextSegmentIndex++,
          p0: p1,
          c1: c1,
          c2: c2,
          p1: p2,
          startTangent: localStartTangent,
          endTangent: localEndTangent,
          arcStart: arc,
          arcEnd: arc + length,
        ));
        arc += length;
      }
    }
  }
}
