part of '../../streaming_stroke_modeler.dart';

extension _CenterlineInput on PawStreamingCenterlineModeler {
  bool _appendBoundedCausalSpline(DrawingInputSample sample) {
    final previousRaw = _lastRawSample;
    if (previousRaw != null && sample.timestamp < previousRaw.timestamp) {
      return false;
    }
    if (previousRaw != null &&
        (sample.position - previousRaw.position).distance < .02) {
      return false;
    }

    if (previousRaw != null) {
      _largestInputGapMicros = math.max(
        _largestInputGapMicros,
        sample.timestamp.inMicroseconds - previousRaw.timestamp.inMicroseconds,
      );
      _largestInputDistance = math.max(
        _largestInputDistance,
        (sample.position - previousRaw.position).distance,
      );
    }
    _rawInputSampleCount++;
    _recordRawSample(sample);
    _penultimateRawSample = previousRaw;
    _lastRawSample = sample;
    _fixedClock = sample.timestamp;
    _fixedPosition = sample.position;
    lastModelStepCount = 1;
    totalModelStepCount++;
    _acceptModeledSample(sample);

    if (previousRaw == null) {
      _fixedVelocity = Offset.zero;
      _speculativeSample = sample;
      lastTipGap = 0;
    } else {
      final elapsedMicros = math.max(
        1,
        sample.timestamp.inMicroseconds - previousRaw.timestamp.inMicroseconds,
      );
      final velocity = (sample.position - previousRaw.position) /
          (elapsedMicros / Duration.microsecondsPerSecond);
      _fixedVelocity = velocity;
      final parameters = fixedStep;
      final basePredictionSeconds =
          // After a stalled input interval, velocity is an average over an
          // unseen path. Extending it paints a false tip that jumps back on
          // the next event; do not speculate from that stale velocity.
          predictionHorizon <= 0 || elapsedMicros > 50000
              ? 0.0
              : (parameters?.predictionMilliseconds ?? 0) / 1000;
      final curvaturePrediction = _curvatureAwarePrediction(
        samples: _rawPolyline,
        velocity: velocity,
        baseHorizonSeconds: basePredictionSeconds,
      );
      final predictionSeconds = curvaturePrediction.horizonSeconds;
      var prediction = curvaturePrediction.offset;
      lastPredictionHorizonMicros =
          (predictionSeconds * Duration.microsecondsPerSecond).round();
      lastPredictionAngularVelocity = curvaturePrediction.signedAngularVelocity;
      lastPredictionCurvatureConfidence = curvaturePrediction.confidence;
      final maximumPredictionDistance = math.min(
        parameters?.maximumPredictionDistance ?? predictionHorizon,
        predictionHorizon,
      );
      if (prediction.distance > maximumPredictionDistance) {
        prediction = prediction *
            (maximumPredictionDistance /
                math.max(.000001, prediction.distance));
      }
      final predictedPosition = sample.position + prediction;
      _speculativeSample = DrawingInputSample(
        x: predictedPosition.dx,
        y: predictedPosition.dy,
        timestamp: sample.timestamp +
            Duration(
              microseconds:
                  (predictionSeconds * Duration.microsecondsPerSecond).round(),
            ),
        pressure: sample.pressure,
        pressureMin: sample.pressureMin,
        pressureMax: sample.pressureMax,
        deviceKind: sample.deviceKind,
      );
      lastTipGap = prediction.distance;
    }

    // Rebuild only the bounded visible tail. A new real sample invalidates
    // the previous prediction before any geometry is made.
    _tailSegments.clear();
    _rebuildTail();
    if (previousRaw != null && _rawInputSampleCount >= 4) {
      // The first three raw points can estimate a start tangent, but they do
      // not yet distinguish a distributed curve from one isolated turn. Keep
      // both bootstrap intervals replaceable until a fourth real point gives
      // the first join outgoing support.
      // Touch conditioning retains up to seven outgoing samples within its
      // spatial/time support. All intervals are visible now;
      // only ownership waits, bounded by maximumMutableTipArc below.
      final stableThrough = sample.deviceKind == PointerDeviceKind.touch &&
              _rawPolyline.length >= 8
          ? _rawPolyline[_rawPolyline.length - 8].timestamp
          : sample.deviceKind == PointerDeviceKind.touch
              ? _rawPolyline.first.timestamp
              : previousRaw.timestamp;
      _sealCompletedRawIntervals(stableThrough);
      // A raw interval can span hundreds of pixels after main-thread input
      // starvation. Its entire already-painted length must not remain mutable
      // until the next event. Bound corrections spatially as well as causally.
      _sealStablePrefix();
    }
    _revision++;
    return true;
  }

  bool _appendDirect(DrawingInputSample sample) {
    if (_recentSamples.isNotEmpty &&
        (sample.position - _recentSamples.last.position).distance < .08) {
      return false;
    }
    _recordRawSample(sample);
    _acceptModeledSample(sample);
    _finishAppend();
    return true;
  }

  bool _appendFixedStep(
    DrawingInputSample sample,
    PawFixedStepModelParameters parameters,
  ) {
    parameters.validate();
    final previousRaw = _lastRawSample;
    if (previousRaw != null && sample.timestamp < previousRaw.timestamp) {
      return false;
    }
    if (previousRaw != null &&
        (sample.position - previousRaw.position).distance < .02) {
      return false;
    }
    _recordRawSample(sample);
    final penultimateRaw = _penultimateRawSample;
    final pendingStartBeforeObservation = _pendingTurnStartMicros;
    final cornerConfidence = penultimateRaw == null
        ? 0.0
        : _cornerConfidence(
            penultimateRaw,
            previousRaw!,
            sample,
          );
    final deferredCorner = _deferredSparseCorner;
    final deferredTurnRadians = _deferredSparseTurnRadians;
    final deferredInvalidationMicros = _deferredSparseInvalidationMicros;
    final deferredCornerConfidence = _deferredSparseCornerConfidence;
    final deferredContinuationTurn =
        deferredCorner == null || previousRaw == null
            ? math.pi
            : _signedTurnRadians(
                _deferredSparseOutgoing,
                sample.position - previousRaw.position,
              );
    final alternatingSharpTurn =
        deferredTurnRadians * deferredContinuationTurn < 0 &&
            deferredContinuationTurn.abs() >= 35 * math.pi / 180;
    final confirmedDeferredCorner = deferredCorner != null &&
        (deferredContinuationTurn.abs() <= 12 * math.pi / 180 ||
            alternatingSharpTurn);
    _deferredSparseCorner = null;
    _deferredSparseOutgoing = Offset.zero;
    _deferredSparseTurnRadians = 0;
    _deferredSparseInvalidationMicros = null;
    _deferredSparseCornerConfidence = 0;
    _deferredSparseAlternatingEvidence = false;
    final episode = _observeTurnEpisode(sample);
    final incomingRaw = penultimateRaw == null || previousRaw == null
        ? Offset.zero
        : previousRaw.position - penultimateRaw.position;
    final outgoingRaw = previousRaw == null
        ? Offset.zero
        : sample.position - previousRaw.position;
    final immediateSignedTurn = _signedTurnRadians(incomingRaw, outgoingRaw);
    final immediateTurn = immediateSignedTurn.abs();
    final continuesDistributedSparseCurve = (deferredCorner != null &&
            deferredTurnRadians * deferredContinuationTurn > 0 &&
            (deferredTurnRadians.abs() - deferredContinuationTurn.abs())
                    .abs() <=
                15 * math.pi / 180) ||
        (_sparseSmoothTurnRadians * immediateSignedTurn > 0 &&
            (_sparseSmoothTurnRadians.abs() - immediateTurn).abs() <=
                15 * math.pi / 180);
    // Three sparse samples cannot distinguish a deliberate cusp from a
    // constant-curvature arc. Wait for one outgoing evidence sample before
    // publishing a C0 corner; otherwise the beginning of a fast circle is
    // repeatedly frozen into polygon vertices.
    final immediateCorner = _turnEpisodeSamples.length >= 4 &&
        !confirmedDeferredCorner &&
        cornerConfidence >= _cornerPreservationThreshold &&
        lastTurnEpisodeSignificantTurnCount <= 1 &&
        immediateTurn >= 45 * math.pi / 180;
    final chainedAlternatingCorner =
        confirmedDeferredCorner && alternatingSharpTurn;
    final deferSparseCorner = !episode.confirmedCusp &&
        (!immediateCorner || chainedAlternatingCorner) &&
        previousRaw != null &&
        penultimateRaw != null &&
        cornerConfidence >= _cornerPreservationThreshold &&
        (lastTurnEpisodeSignificantTurnCount <= 1 ||
            chainedAlternatingCorner) &&
        immediateTurn >= 45 * math.pi / 180;
    if (deferSparseCorner) {
      _deferredSparseCorner = previousRaw;
      _deferredSparseOutgoing = _normalized(
        outgoingRaw,
        fallback: Offset.zero,
      );
      _deferredSparseTurnRadians = immediateSignedTurn;
      _deferredSparseInvalidationMicros =
          penultimateRaw.timestamp.inMicroseconds;
      _deferredSparseCornerConfidence = cornerConfidence;
      _deferredSparseAlternatingEvidence = chainedAlternatingCorner;
      _beginPendingTurn(
        evidenceStartMicros: penultimateRaw.timestamp.inMicroseconds,
        vertexMicros: previousRaw.timestamp.inMicroseconds,
      );
    }
    if (continuesDistributedSparseCurve) {
      // Sparse circles may retain only one turn in the bounded arc window.
      // Two consecutive, same-sign heading steps of similar magnitude are
      // nevertheless causal distributed-curvature evidence. Release and
      // rebuild the pending tail instead of alternating straight polygons.
      _sparseSmoothTurnRadians = immediateSignedTurn;
      _confirmedSmoothUntilMicros = sample.timestamp.inMicroseconds + 45000;
      _deferredSparseCorner = null;
      _deferredSparseOutgoing = Offset.zero;
      _deferredSparseTurnRadians = 0;
      _deferredSparseInvalidationMicros = null;
      _deferredSparseCornerConfidence = 0;
      _deferredSparseAlternatingEvidence = false;
      _unresolvedCornerCandidateMicros = null;
      _resolvePendingAsSmooth();
      lastTurnEpisodeState = 'confirmedSmooth';
    } else if (_sparseSmoothTurnRadians * immediateSignedTurn <= 0 ||
        (_sparseSmoothTurnRadians.abs() - immediateTurn).abs() >
            22 * math.pi / 180) {
      _sparseSmoothTurnRadians = 0;
    }
    final immediateCornerInvalidationMicros =
        immediateCorner ? penultimateRaw?.timestamp.inMicroseconds : null;
    if (confirmedDeferredCorner) {
      _completeImmediateCorner(deferredCorner, sample);
    } else if (immediateCorner && previousRaw != null) {
      _completeImmediateCorner(previousRaw, sample);
    }
    final preserveCorner =
        confirmedDeferredCorner || immediateCorner || episode.confirmedCusp;
    final conservativeTurn = preserveCorner || pendingTurnActive;
    final cornerSample = confirmedDeferredCorner
        ? deferredCorner
        : episode.confirmedCusp
            ? episode.inferredCorner
            : immediateCorner
                ? previousRaw
                : null;
    final effectiveCornerConfidence =
        confirmedDeferredCorner ? deferredCornerConfidence : cornerConfidence;
    lastCornerConfidence = effectiveCornerConfidence;
    // Cubic tangents need one future raw point. Geometry through the sample
    // before [previousRaw] may be published, while the most recent complete
    // raw interval remains replaceable until this new sample supplies its
    // outgoing tangent. This also lets point three curve the initial chord.
    _causalSealBarrierMicros = penultimateRaw?.timestamp.inMicroseconds;
    _penultimateRawSample = previousRaw;
    _lastRawSample = sample;
    lastModelStepCount = 0;
    if (previousRaw == null) {
      _fixedPosition = sample.position;
      _fixedVelocity = Offset.zero;
      _fixedClock = sample.timestamp;
      _acceptModeledSample(sample);
      _speculativeSample = sample;
      lastTipGap = 0;
      _finishAppend();
      return true;
    }
    final hasOutgoingCurvatureEvidence = penultimateRaw != null;
    final bootstrappingThirdRaw =
        hasOutgoingCurvatureEvidence && _recentSamples.length == 1;
    if (bootstrappingThirdRaw) {
      // The first raw interval was presentation-only while only two points
      // existed. Promote its real endpoint now that point three supplies an
      // outgoing direction, allowing the rebuilt cubic to curve that initial
      // interval instead of retaining a sampled straight chord.
      _acceptModeledSample(previousRaw);
      _fixedPosition = previousRaw.position;
    }
    final rawElapsedMicros =
        sample.timestamp.inMicroseconds - previousRaw.timestamp.inMicroseconds;
    final elapsedMicros = rawElapsedMicros > 0 ? rawElapsedMicros : 16667;
    final intervalStartTime = rawElapsedMicros > 0
        ? previousRaw.timestamp
        : _fixedClock + Duration(microseconds: _fixedRemainderMicros);
    final stepMicros = (1000000 / parameters.stepRateHz).round();
    final totalMicros = _fixedRemainderMicros + elapsedMicros;
    final requestedSteps = totalMicros ~/ stepMicros;
    final steps = math.min(requestedSteps, parameters.maximumStepsPerAppend);
    final dt = stepMicros / 1000000;
    final omega = parameters.responsePerSecond;
    var position = _fixedPosition ?? previousRaw.position;
    var velocity = _fixedVelocity;
    if (preserveCorner && cornerSample != null) {
      // A deliberate cusp is C0-continuous but is not required to be C1.
      // A distributed episode may confirm after its inferred vertex. Its
      // candidate barrier guarantees this portion is still provisional, so
      // rebuild only that tail before installing the fitted C0 anchor.
      _recentSamples.removeWhere(
        (modeled) => modeled.timestamp >= cornerSample.timestamp,
      );
      // A newly confirmed cusp changes the tangent of the whole incoming raw
      // interval, not only geometry at/after the vertex. Reusing the curved
      // part immediately before the vertex leaves a small hook outside the
      // intended wedge. The observation retains that causal interval start
      // even though its turn window is reset after confirmation.
      _tailInvalidationMicros = immediateCornerInvalidationMicros ??
          (confirmedDeferredCorner ? deferredInvalidationMicros : null) ??
          episode.invalidationStartMicros ??
          pendingStartBeforeObservation ??
          cornerSample.timestamp.inMicroseconds;
      _preservedCornerMicros.add(cornerSample.timestamp.inMicroseconds);
      _unresolvedCornerCandidateMicros = null;
      _clearPendingTurn();
      _acceptModeledSample(cornerSample);
      lastPreservedCornerPosition = cornerSample.position;
      final deferredOutgoingAnchor = confirmedDeferredCorner &&
              previousRaw.timestamp > cornerSample.timestamp
          ? previousRaw
          : null;
      if (deferredOutgoingAnchor != null) {
        // Alternating rapid corners confirm one raw event late. Retain the
        // intervening raw vertex before integrating the current interval;
        // otherwise the fitter aims from the old cusp directly into the next
        // leg and halves the visible turn angle.
        _acceptModeledSample(deferredOutgoingAnchor);
      }
      if (chainedAlternatingCorner && penultimateRaw != null) {
        // One burst can both confirm the previous zig-zag vertex and reveal
        // the next one. Keep that new vertex pending after installing the
        // earlier C0 anchor, otherwise tail tangent averaging rounds every
        // second corner for one frame.
        _beginPendingTurn(
          evidenceStartMicros: penultimateRaw.timestamp.inMicroseconds,
          vertexMicros: previousRaw.timestamp.inMicroseconds,
        );
      }
      position = deferredOutgoingAnchor?.position ?? cornerSample.position;
      final outgoing = _normalized(
        sample.position - position,
        fallback: Offset.zero,
      );
      final outgoingSpeed = math.max(
        0.0,
        velocity.dx * outgoing.dx + velocity.dy * outgoing.dy,
      );
      velocity =
          outgoing * outgoingSpeed * (1 - effectiveCornerConfidence * .72);
      _fixedRemainderMicros = 0;
    }
    final firstStepOffset = _fixedRemainderMicros == 0
        ? stepMicros
        : stepMicros - _fixedRemainderMicros;
    final skippedSteps = requestedSteps - steps;
    if (skippedSteps > 0) {
      // Spend the fixed budget across the whole curved raw interval. A chord
      // fast-forward here permanently removes curvature from the sealed path.
      final adaptiveDt = elapsedMicros / steps / 1000000;
      for (var step = 0; step < steps; step++) {
        final fraction = (step + 1) / steps;
        final target = _fixedIntervalTarget(
          penultimateRaw: penultimateRaw,
          previousRaw: previousRaw,
          sample: sample,
          fraction: fraction,
          curvedIntervalTargets: curvedIntervalTargets,
          conservativeTarget: conservativeTurn,
          curvedTargetMaxHandleFactor: curvedTargetMaxHandleFactor,
        );
        velocity = (target - position) / adaptiveDt;
        position = target;
        final modeled = DrawingInputSample(
          x: position.dx,
          y: position.dy,
          timestamp: intervalStartTime +
              Duration(microseconds: (elapsedMicros * fraction).round()),
          pressure: previousRaw.pressure +
              (sample.pressure - previousRaw.pressure) * fraction,
          pressureMin: sample.pressureMin,
          pressureMax: sample.pressureMax,
          deviceKind: sample.deviceKind,
        );
        if (hasOutgoingCurvatureEvidence &&
            !bootstrappingThirdRaw &&
            (step == steps - 1 ||
                _recentSamples.isEmpty ||
                (modeled.position - _recentSamples.last.position).distance >=
                    parameters.minimumOutputDistance)) {
          _acceptModeledSample(modeled);
        }
        lastModelStepCount++;
      }
      totalModelStepCount += lastModelStepCount;
      _fixedPosition = sample.position;
      _fixedVelocity = velocity;
      _fixedRemainderMicros = totalMicros % stepMicros;
      _fixedClock = intervalStartTime +
          Duration(microseconds: elapsedMicros - _fixedRemainderMicros);
      _acceptRawEndpointIfNeeded(sample);
      _speculativeSample = sample;
      lastTipGap = 0;
      _finishAppend();
      return true;
    }
    final needsSpatialCatchUp = steps == 0 &&
        (sample.position - position).distance >=
            parameters.minimumOutputDistance;
    if (needsSpatialCatchUp) {
      // Sub-step burst delivery must not turn the entire raw interval into a
      // speculative bridge. Accept one bounded causal endpoint so only the
      // prediction beyond the newest event remains mutable.
      final seconds = elapsedMicros / Duration.microsecondsPerSecond;
      velocity = (sample.position - position) / math.max(.000001, seconds);
      position = sample.position;
      if (hasOutgoingCurvatureEvidence && !bootstrappingThirdRaw) {
        _acceptModeledSample(sample);
      }
      lastModelStepCount = 1;
      totalModelStepCount++;
      _fixedPosition = position;
      _fixedVelocity = velocity;
      _fixedRemainderMicros = 0;
      _fixedClock = sample.timestamp;
    } else {
      for (var step = 0; step < steps; step++) {
        final intervalOffset = math.min(
          elapsedMicros,
          firstStepOffset + step * stepMicros,
        );
        final fraction = intervalOffset / elapsedMicros;
        final target = _fixedIntervalTarget(
          penultimateRaw: penultimateRaw,
          previousRaw: previousRaw,
          sample: sample,
          fraction: fraction,
          curvedIntervalTargets: curvedIntervalTargets,
          conservativeTarget: conservativeTurn,
          curvedTargetMaxHandleFactor: curvedTargetMaxHandleFactor,
        );
        if (conservativeTurn) {
          // Once raw angular evidence owns this interval, a second-order lag
          // can itself create a visible shortcut even when its target is a
          // chord. Follow the bounded one-sided target exactly until the local
          // episode resolves; only this provisional tail may later be curved.
          velocity = (target - position) / dt;
          position = target;
        } else {
          final acceleration = (target - position) * (omega * omega) -
              velocity * (2 * parameters.dampingRatio * omega);
          velocity += acceleration * dt;
          position += velocity * dt;
        }
        if (!position.dx.isFinite || !position.dy.isFinite) {
          position = target;
          velocity = Offset.zero;
        }
        final timestamp =
            intervalStartTime + Duration(microseconds: intervalOffset);
        final modeled = DrawingInputSample(
          x: position.dx,
          y: position.dy,
          timestamp: timestamp,
          pressure: previousRaw.pressure +
              (sample.pressure - previousRaw.pressure) * fraction,
          pressureMin: previousRaw.pressureMin +
              (sample.pressureMin - previousRaw.pressureMin) * fraction,
          pressureMax: previousRaw.pressureMax +
              (sample.pressureMax - previousRaw.pressureMax) * fraction,
          deviceKind: sample.deviceKind,
        );
        if (hasOutgoingCurvatureEvidence &&
            !bootstrappingThirdRaw &&
            (_recentSamples.isEmpty ||
                (modeled.position - _recentSamples.last.position).distance >=
                    parameters.minimumOutputDistance)) {
          _acceptModeledSample(modeled);
        }
        lastModelStepCount++;
      }
      totalModelStepCount += lastModelStepCount;
      _fixedPosition = position;
      _fixedVelocity = velocity;
      _fixedRemainderMicros = totalMicros % stepMicros;
      _fixedClock = intervalStartTime +
          Duration(microseconds: elapsedMicros - _fixedRemainderMicros);
    }
    if (bootstrappingThirdRaw) {
      final seconds = elapsedMicros / Duration.microsecondsPerSecond;
      velocity =
          (sample.position - previousRaw.position) / math.max(.000001, seconds);
      position = sample.position;
      _acceptModeledSample(sample);
      _fixedPosition = position;
      _fixedVelocity = velocity;
      _fixedRemainderMicros = 0;
      _fixedClock = sample.timestamp;
    }
    _acceptRawEndpointIfNeeded(sample);
    final predictionSeconds = parameters.predictionMilliseconds / 1000;
    var prediction = velocity * predictionSeconds;
    if (conservativeTurn) {
      final outgoing = _normalized(
        sample.position - previousRaw.position,
        fallback: Offset.zero,
      );
      final compatibleDistance = math.max(
        0.0,
        prediction.dx * outgoing.dx + prediction.dy * outgoing.dy,
      );
      final confidence = preserveCorner
          ? math.max(effectiveCornerConfidence, lastTurnEpisodeConcentration)
          : math.max(.65, lastTurnEpisodeConcentration);
      prediction = outgoing *
          compatibleDistance *
          (1 - confidence * .82).clamp(.08, .35);
    }
    final maximumPredictionDistance = math.min(
      parameters.maximumPredictionDistance,
      predictionHorizon,
    );
    final predictionDistance = prediction.distance;
    if (predictionDistance > maximumPredictionDistance) {
      prediction =
          prediction * (maximumPredictionDistance / predictionDistance);
    }
    var predictedPosition = position + prediction;
    final rawTipOffset = predictedPosition - sample.position;
    final rawTipDistance = rawTipOffset.distance;
    if (rawTipDistance > maximumPredictionDistance) {
      predictedPosition = sample.position +
          rawTipOffset * (maximumPredictionDistance / rawTipDistance);
    }
    _speculativeSample = DrawingInputSample(
      x: predictedPosition.dx,
      y: predictedPosition.dy,
      timestamp: _fixedClock +
          Duration(
            microseconds: (parameters.predictionMilliseconds * 1000).round(),
          ),
      pressure: sample.pressure,
      pressureMin: sample.pressureMin,
      pressureMax: sample.pressureMax,
      deviceKind: sample.deviceKind,
    );
    lastTipGap = (sample.position - predictedPosition).distance;
    _finishAppend();
    return true;
  }
}
