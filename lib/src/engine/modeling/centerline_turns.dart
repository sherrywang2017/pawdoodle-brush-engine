part of '../../streaming_stroke_modeler.dart';

extension _CenterlineTurns on PawStreamingCenterlineModeler {
  _TurnEpisodeObservation _observeTurnEpisode(DrawingInputSample sample) {
    _turnEpisodeSamples.add(sample);
    _currentCornerCandidateMicros = null;
    const maximumDuration = Duration(milliseconds: 90);
    final maximumArc = maximumTurnEvidenceArc;
    while (_turnEpisodeSamples.length > 2 &&
        (_turnEpisodeSamples.length > 12 ||
            sample.timestamp - _turnEpisodeSamples.first.timestamp >
                maximumDuration ||
            _polylineArc(_turnEpisodeSamples) > maximumArc)) {
      _turnEpisodeSamples.removeAt(0);
    }
    _expireCandidateEvidenceBefore(
      _turnEpisodeSamples.first.timestamp.inMicroseconds,
    );
    if (_turnEpisodeSamples.length < 3) {
      // Fewer than three points cannot own turn evidence. In particular, a
      // candidate from the window before a confirmed cusp must not leak into
      // the newly reset two-point episode.
      _unresolvedCornerCandidateMicros = null;
      lastTurnEpisodeState = 'idle';
      return const _TurnEpisodeObservation();
    }

    final turns = <double>[];
    final legLengths = <double>[];
    for (var index = 0; index < _turnEpisodeSamples.length - 1; index++) {
      legLengths.add((_turnEpisodeSamples[index + 1].position -
              _turnEpisodeSamples[index].position)
          .distance);
    }
    for (var index = 0; index < legLengths.length - 1; index++) {
      turns.add(_signedTurnRadians(
        _turnEpisodeSamples[index + 1].position -
            _turnEpisodeSamples[index].position,
        _turnEpisodeSamples[index + 2].position -
            _turnEpisodeSamples[index + 1].position,
      ));
    }
    final totalHeading = turns.fold<double>(0, (sum, value) => sum + value);
    final absoluteHeading =
        turns.fold<double>(0, (sum, value) => sum + value.abs());
    final peak =
        turns.fold<double>(0, (value, turn) => math.max(value, turn.abs()));
    final turnSignCoherence = absoluteHeading <= .0001
        ? 0.0
        : (totalHeading.abs() / absoluteHeading).clamp(0.0, 1.0);
    final turnLocalization = _localizedTurnFraction(
      turns: turns,
      legLengths: legLengths,
      points: <Offset>[
        for (final value in _turnEpisodeSamples) value.position,
      ],
      absoluteHeading: absoluteHeading,
      totalArc: legLengths.fold<double>(0, (sum, value) => sum + value),
    );
    final duration = sample.timestamp - _turnEpisodeSamples.first.timestamp;
    final arc = legLengths.fold<double>(0, (sum, value) => sum + value);
    lastTurnEpisodeHeadingRadians = totalHeading;
    lastTurnEpisodePeakRadians = peak;
    // Keep the legacy diagnostic name while callers migrate to the semantic
    // names below. This value is sign coherence, not spatial concentration.
    lastTurnEpisodeConcentration = turnSignCoherence;
    lastTurnSignCoherence = turnSignCoherence;
    lastTurnLocalization = turnLocalization;
    lastTurnEpisodeArc = arc;
    lastTurnEpisodeDuration = duration;

    const significantTurn = 3 * math.pi / 180;
    final significantIndices = <int>[
      for (var index = 0; index < turns.length; index++)
        if (turns[index].abs() >= significantTurn) index,
    ];
    lastTurnEpisodeSignificantTurnCount = significantIndices.length;
    var turningArc = 0.0;
    if (significantIndices.isNotEmpty) {
      for (var index = significantIndices.first + 1;
          index <= significantIndices.last;
          index++) {
        turningArc += legLengths[index];
      }
    }
    final significantMagnitudes = <double>[
      for (final index in significantIndices) turns[index].abs(),
    ];
    final minimumSignificantTurn = significantMagnitudes.isEmpty
        ? 0.0
        : significantMagnitudes.reduce(math.min);
    final maximumSignificantTurn = significantMagnitudes.isEmpty
        ? 0.0
        : significantMagnitudes.reduce(math.max);
    // Three or more similarly sized, same-sign angular-velocity samples are
    // distributed curvature, even when sparse delivery makes every local
    // heading step large. A localized cusp has straight legs and therefore
    // cannot keep this ratio across three significant intervals.
    final uniformDistributedSmooth = significantIndices.length >= 3 &&
        turnSignCoherence >= .94 &&
        minimumSignificantTurn / math.max(.0001, maximumSignificantTurn) >= .72;
    final gradualSmooth = peak < 7 * math.pi / 180 &&
            ((totalHeading.abs() >= 7 * math.pi / 180 &&
                    significantIndices.length >= 2) ||
                (totalHeading.abs() >= 18 * math.pi / 180 && arc >= 30)) ||
        (peak < 12 * math.pi / 180 &&
            significantIndices.length >= 3 &&
            turningArc >= 16 &&
            duration >= const Duration(milliseconds: 40)) ||
        uniformDistributedSmooth;
    if (gradualSmooth) {
      _confirmedSmoothUntilMicros = sample.timestamp.inMicroseconds + 45000;
    }
    final smoothHysteresis = _confirmedSmoothUntilMicros != null &&
        sample.timestamp.inMicroseconds <= _confirmedSmoothUntilMicros! &&
        (peak < 12 * math.pi / 180 || uniformDistributedSmooth);
    // The real continuous-circle trace clusters below .40 once both local
    // legs are visible. Existing distributed-fast corner fixtures can be
    // lower (.28-.38), but establish their complete turn within 31 ms. Keep
    // that causal short-episode path without allowing a long same-sign arc to
    // masquerade as localized evidence.
    final localizedCornerEvidence = lastTurnLocalization >= .40 ||
        (lastTurnLocalization >= .15 &&
            duration <= const Duration(milliseconds: 40) &&
            totalHeading.abs() >= 18 * math.pi / 180);
    final isCandidate = !smoothHysteresis &&
        totalHeading.abs() >= 3.5 * math.pi / 180 &&
        turnSignCoherence >= .68 &&
        localizedCornerEvidence &&
        significantIndices.isNotEmpty;
    if (isCandidate) {
      final firstVertexIndex = significantIndices.first + 1;
      _currentCornerCandidateMicros =
          _turnEpisodeSamples[firstVertexIndex].timestamp.inMicroseconds;
      _ownCurrentCornerEvidence(
        currentCandidateMicros: _currentCornerCandidateMicros!,
        evidenceStartMicros: _turnEpisodeSamples.first.timestamp.inMicroseconds,
      );
      _beginPendingTurn(
        evidenceStartMicros:
            _turnEpisodeSamples[firstVertexIndex - 1].timestamp.inMicroseconds,
        vertexMicros: _currentCornerCandidateMicros!,
      );
      lastTurnEpisodeState = 'candidate';
    } else if (smoothHysteresis || lastTurnEpisodeState == 'candidate') {
      _unresolvedCornerCandidateMicros = null;
      _resolvePendingAsSmooth();
      lastTurnEpisodeState = 'confirmedSmooth';
    } else {
      // No current local candidate means there is no evidence owner. An old
      // timestamp must not survive an idle frame as a publication barrier.
      _unresolvedCornerCandidateMicros = null;
      _resolvePendingAsSmooth();
      lastTurnEpisodeState = 'idle';
    }

    if (!isCandidate || significantIndices.isEmpty) {
      return const _TurnEpisodeObservation();
    }
    final firstTurn = significantIndices.first;
    final lastTurn = significantIndices.last;
    final turnArc = turningArc;
    final stableOutgoing = turns.last.abs() <= 2.5 * math.pi / 180;
    final enoughDistributedEvidence =
        significantIndices.length >= 2 || peak >= 18 * math.pi / 180;
    final confirmed = enoughDistributedEvidence &&
        totalHeading.abs() >= 18 * math.pi / 180 &&
        peak >= 7 * math.pi / 180 &&
        turnSignCoherence >= .82 &&
        turnArc <= math.max(32.0, geometryCorrectionHorizon * 2.2) &&
        stableOutgoing;
    if (!confirmed) return const _TurnEpisodeObservation();

    final inferred = _inferEpisodeCorner(
      firstTurn: firstTurn,
      lastTurn: lastTurn,
    );
    final invalidationStartMicros = _minimumMicros(
      _pendingTurnStartMicros,
      _turnEpisodeSamples[firstTurn].timestamp.inMicroseconds,
    );
    _unresolvedCornerCandidateMicros = null;
    _clearPendingTurn();
    _sparseSmoothTurnRadians = 0;
    lastTurnEpisodeState = 'confirmedCusp';
    _turnEpisodeSamples.removeRange(
      0,
      math.max(0, _turnEpisodeSamples.length - 2),
    );
    return _TurnEpisodeObservation(
      confirmedCusp: true,
      inferredCorner: inferred,
      invalidationStartMicros: invalidationStartMicros,
    );
  }

  void _expireCandidateEvidenceBefore(int evidenceStartMicros) {
    final unresolved = _unresolvedCornerCandidateMicros;
    if (unresolved != null && unresolved < evidenceStartMicros) {
      // Expired samples are no longer available to confirm a cusp. They are
      // therefore smooth immutable history, while only the retained local
      // window may remain provisional.
      _unresolvedCornerCandidateMicros = evidenceStartMicros;
    }
  }

  void _ownCurrentCornerEvidence({
    required int currentCandidateMicros,
    required int evidenceStartMicros,
  }) {
    final localStart = math.max(currentCandidateMicros, evidenceStartMicros);
    final previous = _unresolvedCornerCandidateMicros;
    // The publication barrier is monotonic: a later frame can release old
    // evidence, but can never reclaim already accepted history.
    _unresolvedCornerCandidateMicros =
        previous == null ? localStart : math.max(previous, localStart);
  }

  DrawingInputSample _inferEpisodeCorner({
    required int firstTurn,
    required int lastTurn,
  }) {
    final vertexIndex = firstTurn + 1;
    final incomingStart = _turnEpisodeSamples[math.max(0, vertexIndex - 2)];
    final incomingEnd = _turnEpisodeSamples[vertexIndex];
    final outgoingStart = _turnEpisodeSamples[math.min(
      _turnEpisodeSamples.length - 2,
      lastTurn + 1,
    )];
    final outgoingEnd = _turnEpisodeSamples.last;
    final intersection = _lineIntersection(
      incomingStart.position,
      incomingEnd.position,
      outgoingStart.position,
      outgoingEnd.position,
    );
    final fallback = _turnEpisodeSamples[vertexIndex].position;
    final position = intersection != null &&
            (intersection - fallback).distance <=
                math.max(32.0, geometryCorrectionHorizon * 2.2)
        ? intersection
        : fallback;
    final source = _turnEpisodeSamples[vertexIndex];
    return DrawingInputSample(
      x: position.dx,
      y: position.dy,
      timestamp: source.timestamp,
      pressure: source.pressure,
      pressureMin: source.pressureMin,
      pressureMax: source.pressureMax,
      deviceKind: source.deviceKind,
    );
  }

  void _completeImmediateCorner(
    DrawingInputSample corner,
    DrawingInputSample outgoing,
  ) {
    _unresolvedCornerCandidateMicros = null;
    _clearPendingTurn();
    _sparseSmoothTurnRadians = 0;
    lastTurnEpisodeState = 'confirmedCusp';
    _turnEpisodeSamples
      ..clear()
      ..add(corner)
      ..add(outgoing);
  }

  void _beginPendingTurn({
    required int evidenceStartMicros,
    required int vertexMicros,
  }) {
    final previousStart = _pendingTurnStartMicros;
    final start = previousStart == null
        ? evidenceStartMicros
        : math.min(previousStart, evidenceStartMicros);
    _pendingTurnStartMicros = start;
    _pendingTurnVertexMicros = _pendingTurnVertexMicros == null
        ? vertexMicros
        : math.min(_pendingTurnVertexMicros!, vertexMicros);
    _tailInvalidationMicros = _minimumMicros(_tailInvalidationMicros, start);
  }

  void _resolvePendingAsSmooth() {
    final start = _pendingTurnStartMicros;
    if (start == null) return;
    // Smooth evidence may replace only the still-provisional local episode.
    _tailInvalidationMicros = _minimumMicros(_tailInvalidationMicros, start);
    _clearPendingTurn();
  }

  void _clearPendingTurn() {
    _pendingTurnStartMicros = null;
    _pendingTurnVertexMicros = null;
  }

  bool _finalizePendingCornerGeometry() {
    final finalRaw = _lastRawSample;
    if (finalRaw == null) return false;
    final deferredCorner = _deferredSparseCorner;
    DrawingInputSample? corner;
    var invalidationMicros = _pendingTurnStartMicros;

    if (deferredCorner != null) {
      final strongImmediateCusp = _deferredSparseCornerConfidence >= .6 &&
          _deferredSparseTurnRadians.abs() >= 45 * math.pi / 180;
      if (_deferredSparseAlternatingEvidence || strongImmediateCusp) {
        corner = deferredCorner;
        invalidationMicros = _minimumMicros(
          invalidationMicros,
          _deferredSparseInvalidationMicros ??
              deferredCorner.timestamp.inMicroseconds,
        );
      }
    }
    corner ??= _strongPendingEpisodeCorner();
    if (corner != null && corner.timestamp <= _anchorTime && _anchorArc > 0) {
      // The semantic candidate has already left the mutable-tip ownership
      // window. PointerUp may not reclaim or refit that visible history.
      corner = null;
    }

    if (corner != null) {
      final preserved = corner;
      _recentSamples.removeWhere(
        (sample) => sample.timestamp >= preserved.timestamp,
      );
      _tailInvalidationMicros = _minimumMicros(
        _tailInvalidationMicros,
        invalidationMicros ?? preserved.timestamp.inMicroseconds,
      );
      _preservedCornerMicros.add(preserved.timestamp.inMicroseconds);
      _acceptModeledSample(preserved);
      if (finalRaw.timestamp > preserved.timestamp) {
        _acceptModeledSample(finalRaw);
      }
      lastPreservedCornerPosition = preserved.position;
      lastTurnEpisodeState = 'confirmedCusp';
      _clearPendingTurn();
    } else if (_pendingTurnStartMicros != null) {
      // Pointer-up without enough evidence is deliberately conservative. The
      // pending interval remains exact-line for this final local rebuild; it
      // is not promoted to a semantic cusp merely to obtain safe geometry.
      _tailInvalidationMicros = _minimumMicros(
        _tailInvalidationMicros,
        _pendingTurnStartMicros!,
      );
    }

    _deferredSparseCorner = null;
    _deferredSparseOutgoing = Offset.zero;
    _deferredSparseTurnRadians = 0;
    _deferredSparseInvalidationMicros = null;
    _deferredSparseCornerConfidence = 0;
    _deferredSparseAlternatingEvidence = false;
    return corner != null;
  }

  DrawingInputSample? _strongPendingEpisodeCorner() {
    if (_pendingTurnVertexMicros == null || _turnEpisodeSamples.length < 3) {
      return null;
    }
    final strongLocalizedHeading =
        lastTurnEpisodeHeadingRadians.abs() >= 32 * math.pi / 180 &&
            lastTurnSignCoherence >= .82 &&
            lastTurnLocalization >= .4 &&
            lastTurnEpisodeSignificantTurnCount <= 2;
    if (!strongLocalizedHeading) return null;
    for (final sample in _turnEpisodeSamples) {
      if (sample.timestamp.inMicroseconds == _pendingTurnVertexMicros) {
        return sample;
      }
    }
    return null;
  }
}
