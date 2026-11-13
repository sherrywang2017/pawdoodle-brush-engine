part of '../../streaming_stroke_modeler.dart';

extension _CenterlineSampling on PawStreamingCenterlineModeler {
  void _acceptModeledSample(DrawingInputSample sample) {
    final constrained = _constrainSampleToRawCorridor(sample);
    if (!_hasAnchor) {
      _anchor = constrained.position;
      _anchorPressure = constrained.normalizedPressure ?? .5;
      _anchorTime = constrained.timestamp;
      _strokeStartPosition = constrained.position;
      _strokeStartPressure = _anchorPressure;
      _hasAnchor = true;
    }
    _recentSamples.add(constrained);
    final maximumRecentSamples =
        fixedStep == null ? 32 : fixedStep!.maximumStepsPerAppend + 8;
    if (_recentSamples.length > maximumRecentSamples) {
      _recentSamples.removeRange(
        0,
        _recentSamples.length - maximumRecentSamples,
      );
    }
  }

  void _finishAppend() {
    _rebuildTail();
    _tailInvalidationMicros = null;
    _sealStablePrefix();
    _revision++;
  }

  void _sealStablePrefix() {
    if (_tailSegments.isEmpty) return;
    // Ownership is spatial and strictly bounded. Pending semantic evidence is
    // intentionally absent: once geometry falls behind this frontier it is
    // immutable even if a later sample confirms a cusp.
    // The speculative source interval may begin before the raw event clock;
    // its early subdivisions can therefore have timestamps <= lastRaw. The
    // last accepted modeled sample is the only safe prediction boundary.
    final realTimestamp =
        _recentSamples.isEmpty ? null : _recentSamples.last.timestamp;
    if (realTimestamp == null) return;
    var realEndArc = _anchorArc;
    for (final segment in _tailSegments) {
      if (segment.endTime > realTimestamp) break;
      realEndArc = segment.arcEnd;
    }
    final sealBeforeArc = realEndArc - maximumMutableTipArc;
    if (sealBeforeArc <= _anchorArc) return;
    var count = 0;
    while (count < _tailSegments.length &&
        _tailSegments[count].arcEnd <= sealBeforeArc + .000001) {
      count++;
    }
    if (count == 0) return;
    final sealedEnd = _tailSegments[count - 1];
    _sealedSegments.addAll(_tailSegments.take(count));
    _tailSegments.removeRange(0, count);
    _anchor = sealedEnd.p1;
    _anchorTangent = sealedEnd.endTangent;
    _anchorArc = sealedEnd.arcEnd;
    if (stableCausalJoins) {
      _anchorPressure = sealedEnd.endPressure;
      _anchorTime = sealedEnd.endTime;
      _anchorPreservesCusp =
          _preservedCornerMicros.contains(_anchorTime.inMicroseconds);
      _nextSegmentIndex = sealedEnd.index + 1;
      _recentSamples.removeWhere((sample) => sample.timestamp <= _anchorTime);
      _preservedCornerMicros.removeWhere(
        (micros) => _anchorPreservesCusp
            ? micros < _anchorTime.inMicroseconds
            : micros <= _anchorTime.inMicroseconds,
      );
    }
  }

  void _sealCompletedRawIntervals(Duration stableThrough) {
    var count = 0;
    while (count < _tailSegments.length &&
        _tailSegments[count].endTime <= stableThrough) {
      count++;
    }
    if (count == 0) return;
    final sealedEnd = _tailSegments[count - 1];
    _sealedSegments.addAll(_tailSegments.take(count));
    _tailSegments.removeRange(0, count);
    _anchor = sealedEnd.p1;
    _anchorTangent = sealedEnd.endTangent;
    _anchorPressure = sealedEnd.endPressure;
    _anchorTime = sealedEnd.endTime;
    _anchorArc = sealedEnd.arcEnd;
    _anchorPreservesCusp = false;
    _nextSegmentIndex = sealedEnd.index + 1;
    _recentSamples.removeWhere((sample) => sample.timestamp <= _anchorTime);
  }

  void _recordRawSample(DrawingInputSample sample) {
    if (_rawPolyline.isNotEmpty &&
        sample.timestamp < _rawPolyline.last.timestamp) {
      return;
    }
    if (_rawPolyline.isNotEmpty &&
        sample.timestamp == _rawPolyline.last.timestamp &&
        sample.position == _rawPolyline.last.position) {
      return;
    }
    _rawPolyline.add(sample);
    if (_rawPolyline.length > 128) {
      _rawPolyline.removeRange(0, _rawPolyline.length - 128);
    }
  }

  void _acceptRawEndpointIfNeeded(DrawingInputSample sample) {
    if (_recentSamples.isNotEmpty &&
        _recentSamples.last.timestamp == sample.timestamp &&
        _recentSamples.last.position == sample.position) {
      return;
    }
    _recentSamples.removeWhere(
      (modeled) => modeled.timestamp >= sample.timestamp,
    );
    _acceptModeledSample(sample);
  }

  DrawingInputSample _constrainSampleToRawCorridor(
    DrawingInputSample sample,
  ) {
    if (_rawPolyline.length < 2) return sample;
    var upper = _rawPolyline.indexWhere(
      (raw) => raw.timestamp >= sample.timestamp,
    );
    if (upper < 1) upper = 1;
    if (upper >= _rawPolyline.length) upper = _rawPolyline.length - 1;
    final start = _rawPolyline[upper - 1].position;
    final end = _rawPolyline[upper].position;
    final position = _constrainPointToChordCorridor(
      sample.position,
      start,
      end,
    );
    if (position == sample.position) return sample;
    return DrawingInputSample(
      x: position.dx,
      y: position.dy,
      timestamp: sample.timestamp,
      pressure: sample.pressure,
      pressureMin: sample.pressureMin,
      pressureMax: sample.pressureMax,
      deviceKind: sample.deviceKind,
    );
  }

  Offset _constrainPointToChordCorridor(
    Offset point,
    Offset start,
    Offset end,
  ) {
    final chord = end - start;
    final lengthSquared = chord.dx * chord.dx + chord.dy * chord.dy;
    final projection = lengthSquared <= .000001
        ? start
        : start +
            chord *
                (((point - start).dx * chord.dx +
                            (point - start).dy * chord.dy) /
                        lengthSquared)
                    .clamp(0.0, 1.0);
    final delta = point - projection;
    final distance = delta.distance;
    if (distance <= rawFidelityCorridor || distance <= .000001) return point;
    return projection + delta * (rawFidelityCorridor / distance);
  }
}
