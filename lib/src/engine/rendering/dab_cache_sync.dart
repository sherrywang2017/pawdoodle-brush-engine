part of '../../streaming_dab_brush.dart';

extension _DabCacheSync on PawStreamingDabRenderCache {
  void _syncImpl(PawDabEmissionSource stroke) {
    if (identical(_syncedEmissionIdentity, stroke.emissionIdentity) &&
        _syncedRevision == stroke.revision) {
      return;
    }
    if (stroke.environment.unifiedProgram?.compiledRenderPlan
            .needsSweptCoverage ==
        true) {
      _syncSweptCoverage(stroke);
      _syncedEmissionIdentity = stroke.emissionIdentity;
      _syncedRevision = stroke.revision;
      return;
    }
    _materialFrames.clear();
    _contactFrames.clear();
    _contactGeometryFrames.clear();
    _hairDirectionKnots.clear();
    _materialKnots.clear();
    // Index source arcs once per sync, not once per four-DAB command.
    _sourceSegments = stroke.emissionSegments.toList(growable: false);
    final replacementEpoch = stroke.centerlineReplacementEpoch;
    final observedEpoch = _observedCenterlineReplacementEpoch;
    if (observedEpoch == null) {
      _observedCenterlineReplacementEpoch = replacementEpoch;
    } else if (replacementEpoch != observedEpoch) {
      _discardRenderedMaterialForCenterlineReplacement();
      _observedCenterlineReplacementEpoch = replacementEpoch;
      centerlineReplacementRebuildCount++;
    }
    _lastPictureRecordingMicros = 0;
    lastMutableTailCommandBuildMicros = 0;
    lastStablePictureRecordMicros = 0;
    lastStablePicturePlaybackMicros = 0;
    lastPlannedDabMicros = 0;
    lastBodyMeshMicros = 0;
    lastAtlasBatchMicros = 0;
    lastVerticesBatchMicros = 0;
    lastStampInstanceBuildMicros = 0;
    lastTypedBufferPackMicros = 0;
    lastPreparedStampSubmitMicros = 0;
    lastPreparedStampInstances = 0;
    lastMutableTailWorkUnits = 0;
    lastFreshAllocationProxy = 0;
    // Whole-DAB dry-media coverage is sampled from provisional point/arc
    // geometry. A new centerline revision invalidates those bucket scalars;
    // sealed pictures already own their resolved pixels and never read this
    // map again. Keeping stale tail values causes incremental/fresh mismatch
    // precisely when a pending corner replaces its earlier smooth preview.
    _dryMediaCoverageByDab.clear();
    _lastVisibleDabExclusive = stroke.renderEndArc <= 0
        ? (stroke.strokeStartPosition == null ? 0 : 1)
        : PawStreamingDabRenderCache._emissionPlanner
            .endExclusiveForVisibleArc(stroke);
    _lastSealedEndArc = stroke.sealedEndArc;
    _lastCausalStableEndArc = stroke.causalStableEndArc;
    _lastRenderEndArc = stroke.renderEndArc;
    final d = stroke.definition;
    if (_resource == null) {
      final creationsBefore = PawDabResource._creationCount;
      final acquired = PawDabResource.acquirePrepared(
        d,
        rasterProgram: stroke.environment.rasterProgram,
      );
      final expectedKey = '${d.id}|${d.revision}';
      if (acquired.key != expectedKey) {
        acquired.dispose();
        throw StateError(
          'A Dab render cache cannot be reused across resources.',
        );
      }
      _resource = acquired;
      _resourceDefinitionId = d.id;
      _resourceDefinitionRevision = d.revision;
      _resourceCreationsDuringSync +=
          PawDabResource._creationCount - creationsBefore;
    } else if (_resourceDefinitionId != d.id ||
        _resourceDefinitionRevision != d.revision) {
      throw StateError('A Dab render cache cannot be reused across resources.');
    }
    final spacing =
        PawStreamingDabRenderCache._emissionPlanner.spacingFor(stroke);
    // The positive index-local offset can place a globally indexed dab just
    // beyond its nominal arc. Keep it in the replay range without changing
    // the number or order of emitted indices.
    final offsetMargin = PawStreamingDabRenderCache._emissionPlanner
        .positiveOffsetMarginFor(stroke);
    // A root owns its complete finite fiber. Do not seal a root batch until
    // even its maximum possible tip is in the immutable centerline prefix.
    final program = stroke.environment.unifiedProgram;
    final endpointTailArc =
        stroke.brushSize * (program?.endpoint?.endTaperBrushLengths ?? 0);
    final filamentSafetyArc = math.max(
      PawStreamingDabRenderCache._materialDependencyArc(stroke),
      endpointTailArc,
    );
    final safeDabExclusiveRaw = ((math.min(
                    stroke.sealedEndArc,
                    stroke is PawStreamingDabStroke
                        ? stroke.settledMaterialEndArc
                        : stroke.sealedEndArc) -
                offsetMargin -
                filamentSafetyArc) /
            spacing)
        .floor();
    final safeDabExclusive =
        safeDabExclusiveRaw < 0 ? 0 : math.min(safeDabExclusiveRaw, 1 << 30);
    // Promotion changes ownership only. Each visible chunk is recorded while
    // provisional and retained as long as the global-DAB oracle is identical;
    // becoming sealed never requires a same-frame burst of _recordRange work.
    final targetExclusive =
        safeDabExclusive ~/ d.maximumDabsPerChunk * d.maximumDabsPerChunk;
    // Ownership is transferred in complete global-DAB chunks. Expose the
    // promotable safe frontier rather than the incomplete residual chunk so
    // promotion_backlog measures actual delayed work.
    lastSafeDabExclusive = targetExclusive;
    lastNewChunkCount = 0;
    lastRecordedDabChunkCount = 0;
    lastSegmentLookupCount = 0;
    lastFilamentRootCount = 0;
    lastFilamentLaneCount = 0;
    lastFilamentArcSampleCount = 0;
    lastFilamentSegmentCount = 0;
    lastPersistentLaneCount = 0;
    lastPersistentArcSampleCount = 0;
    lastPersistentLaneSegmentCount = 0;
    lastPersistentLaneVertexCount = 0;
    // Promotion is an ownership transfer, not a paced rendering queue. A
    // per-frame chunk ceiling allowed the safe frontier to outrun ownership
    // by hundreds of DABs on Safari. Every already-safe retained chunk moves
    // in this sync; unchanged pictures are transferred without re-recording.
    final promotionExclusive = targetExclusive;
    lastNewImmutableDabCount =
        math.max(0, promotionExclusive - _nextSealedDabIndex);
    final selectedBehavior = stroke.environment.unifiedProgram?.behavior ??
        PawBrushBehaviorRegistry.forBrushId(d.id);
    final softBehavior =
        selectedBehavior is PawSoftBehavior ? selectedBehavior : null;
    final wetMediaEnabled = d.wetMedia.enabled &&
        (stroke.environment.unifiedProgram?.compiledRenderPlan
                .needsWetMediaTiles ??
            false);
    final mutableCommandDabs = PawStreamingDabRenderCache._commandDabs(stroke);
    for (var start = _nextSealedDabIndex;
        start < promotionExclusive;
        start += d.maximumDabsPerChunk) {
      final end = start + d.maximumDabsPerChunk;
      final promotedCommands = <_PawRetainedDabChunk>[];
      var allCommandsReused = true;
      var geometry = const PawBrushGeometryPayloadProxy.zero();
      for (var commandStart = start;
          commandStart < end;
          commandStart += mutableCommandDabs) {
        final commandEnd = math.min(end, commandStart + mutableCommandDabs);
        final identities = _plannedIdentities(stroke, commandStart, commandEnd);
        final segmentIdentities =
            _segmentIdentities(stroke, commandStart, commandEnd, spacing);
        final retained = _retainedDabChunks.remove(commandStart);
        final softPrefixSignature =
            (softBehavior == null ? 0 : _softSealedDensity.signature) ^
                (wetMediaEnabled ? _wetSealedMedia.signature : 0);
        final retainedMatches = retained?.matches(
              commandEnd,
              identities,
              segmentIdentities,
              softPrefixSignature,
            ) ==
            true;
        final chunk = retainedMatches
            ? retained!
            : _replaceRetainedChunk(
                previous: retained,
                stroke: stroke,
                start: commandStart,
                endExclusive: commandEnd,
                spacing: spacing,
                identities: identities,
                segmentIdentities: segmentIdentities,
                softPrefixSignature: softPrefixSignature,
                softAccumulator:
                    softBehavior == null ? null : _softSealedDensity,
                wetAccumulator: wetMediaEnabled ? _wetSealedMedia : null,
              );
        if (softBehavior != null && retainedMatches) {
          _accumulateSoftRange(
            stroke: stroke,
            start: commandStart,
            endExclusive: commandEnd,
            accumulator: _softSealedDensity,
            behavior: softBehavior,
          );
        }
        if (wetMediaEnabled && retainedMatches) {
          _accumulateWetRange(
            stroke: stroke,
            start: commandStart,
            endExclusive: commandEnd,
            accumulator: _wetSealedMedia,
          );
        }
        allCommandsReused = allCommandsReused && retainedMatches;
        geometry += chunk.geometryPayloadProxy;
        promotedCommands.add(chunk);
      }
      final picture = _measureStablePictureRecording(
        () => _recordDirectCommands(
          promotedCommands.map((chunk) => chunk.command),
        ),
      );
      totalRecordedPictureCount++;
      _sealedPictures.add(picture);
      Rect? pictureBounds = Rect.zero;
      for (final chunk in promotedCommands) {
        final bounds = chunk.command.bounds;
        if (bounds == null) {
          pictureBounds = null;
          break;
        }
        if (!bounds.isEmpty) {
          pictureBounds = pictureBounds!.isEmpty
              ? bounds
              : pictureBounds.expandToInclude(bounds);
        }
      }
      _sealedPictureBounds.add(pictureBounds);
      _sealedGeometryPayloadProxies.add(geometry);
      if (allCommandsReused) {
        stableChunksReused++;
      } else {
        stableChunksCreated++;
      }
      for (final chunk in promotedCommands) {
        chunk.dispose();
      }
      lastNewChunkCount++;
    }
    _nextSealedDabIndex = promotionExclusive;
    _dryMediaCoverageByDab.removeWhere(
      (bucket, _) =>
          bucket <
          _nextSealedDabIndex ~/ PawStreamingDabRenderCache._dryMediaDabStride,
    );
    // Raster compaction changes anti-aliased pixels at the ownership boundary
    // even when centerline and planned DABs are identical. It is therefore an
    // explicit diagnostic/legacy cache mode, never a PointerUp operation.
    if (compactSealedPictures &&
        stroke.acceptedEndArc < stroke.renderEndArc - .001) {
      _compact(d);
    }
    if (softBehavior != null) {
      _softWorkingDensity.resetOverlayFrom(_softSealedDensity);
    }
    if (wetMediaEnabled) {
      _wetWorkingMedia.resetOverlayFrom(_wetSealedMedia);
    }
    _syncRetainedVisibleChunks(
      stroke,
      spacing,
      softBehavior: softBehavior,
      wetMediaEnabled: wetMediaEnabled,
    );
    _hairRootNoise.removeWhere((key, _) =>
        key.$1 < _nextSealedDabIndex || key.$1 >= _lastVisibleDabExclusive);
    assert(
      _hasExactVisibleOwnership(stroke),
      'Every visible global DAB index must have exactly one sealed, retained, '
      'or mutable owner.',
    );
    _syncedEmissionIdentity = stroke.emissionIdentity;
    _syncedRevision = stroke.revision;
  }

  /// A Hold assist replaces the complete centerline, including the prefix
  /// whose pixels may already be sealed. Keep the prepared atlas lease, but
  /// atomically discard every material owner derived from the old geometry so
  /// the next sync rebuilds global DAB identity from zero.
  void _discardRenderedMaterialForCenterlineReplacement() {
    _hairRootNoise.clear();
    _contactSurface.clear();
    _unpaintedContactBounds.clear();
    _lastContactTapBounds = null;
    for (final image in _flattenedSealedImages.values) {
      image.dispose();
    }
    _flattenedSealedImages.clear();
    _tailPicture?.dispose();
    _tailPicture = null;
    for (final picture in _sealedPictures) {
      picture.dispose();
    }
    _sealedPictures.clear();
    _sealedPictureBounds.clear();
    _sealedGeometryPayloadProxies.clear();
    for (final chunk in _retainedDabChunks.values) {
      chunk.dispose();
    }
    _retainedDabChunks.clear();
    _dryMediaCoverageByDab.clear();
    _softWorkingDensity.clear();
    _softSealedDensity.clear();
    _wetWorkingMedia.clear();
    _wetSealedMedia.clear();
    _tailGeometryPayloadProxy = const PawBrushGeometryPayloadProxy.zero();
    _tailRevision = -1;
    _nextSealedDabIndex = 0;
    _previousTailStartIndex = 0;
    _previousTailEndExclusive = 0;
    _lastVisibleDabExclusive = 0;
    _lastSealedEndArc = 0;
    _lastCausalStableEndArc = 0;
    _lastRenderEndArc = 0;
  }

  bool _hasExactVisibleOwnership(PawDabEmissionSource stroke) {
    if (stroke.renderEndArc <= 0) {
      return _nextSealedDabIndex == 0 &&
          _retainedDabChunks.isEmpty &&
          ((_lastVisibleDabExclusive == 0 && _tailPicture == null) ||
              (_lastVisibleDabExclusive == 1 && _tailPicture != null));
    }
    var expectedStart = _nextSealedDabIndex;
    final starts = _retainedDabChunks.keys.toList()..sort();
    for (final start in starts) {
      final chunk = _retainedDabChunks[start]!;
      if (start != expectedStart || chunk.endExclusive <= start) return false;
      expectedStart = chunk.endExclusive;
    }
    return _tailPicture == null && expectedStart == _lastVisibleDabExclusive;
  }

  List<_PawPlannedDabIdentity> _plannedIdentities(
    PawDabEmissionSource stroke,
    int start,
    int endExclusive,
  ) =>
      <_PawPlannedDabIdentity>[
        for (final dab in PawStreamingDabRenderCache._emissionPlanner.planRange(
          source: stroke,
          startIndex: start,
          endExclusive: endExclusive,
        ))
          _PawPlannedDabIdentity(
            dab,
            // Prepared Soft stamps also fade at the live tip. Their point can
            // remain unchanged while the tip advances, so geometry alone is
            // insufficient to retain the old (lighter) stamp.
            endpointProgress:
                stroke.environment.unifiedProgram?.endpoint?.progressAt(
                      closed: stroke.isClosed,
                      absoluteArc: dab.absoluteArc,
                      renderEndArc: stroke.renderEndArc,
                      brushSize: stroke.brushSize,
                    ) ??
                    1,
            // Hair lift and young wet material remain mutable. Wet age also
            // covers the following section boundary, so a settled last DAB
            // cannot retain a still-changing end cross-section.
            materialTailUnit: stroke.environment.unifiedProgram?.kernelKind ==
                    PawBrushKernelKind.bristleFilament
                ? ((stroke.renderEndArc - dab.absoluteArc) /
                        math.max(
                          .0001,
                          stroke.brushSize *
                              (stroke.environment.unifiedProgram?.endpoint
                                      ?.endTaperBrushLengths ??
                                  0),
                        ))
                    .clamp(0.0, 1.0)
                    .toDouble()
                : stroke is PawStreamingDabStroke
                    ? stroke.settlementAtArc(dab.absoluteArc +
                        PawStreamingDabRenderCache._emissionPlanner
                            .spacingFor(stroke))
                    : 1,
          ),
      ];

  List<_PawEmissionSegmentIdentity> _segmentIdentities(
    PawDabEmissionSource stroke,
    int start,
    int endExclusive,
    double spacing,
  ) {
    // Prepared stamps depend on their DAB samples alone. Contact surfaces and
    // transported hairs additionally read surrounding source segments; those
    // dependencies stay mutable until the entire guide window is stable.
    final renderPlan = stroke.environment.unifiedProgram?.compiledRenderPlan;
    if (renderPlan?.needsPreparedTip == true &&
        renderPlan?.needsCanvasContact == false &&
        renderPlan?.needsCarrier == false &&
        renderPlan?.needsPersistentBristles == false &&
        renderPlan?.needsStreamingHairs == false) {
      return const <_PawEmissionSegmentIdentity>[];
    }
    final carrier = stroke.environment.unifiedProgram?.carrier;
    final safetyArc = math.max(
      PawStreamingDabRenderCache._materialDependencyArc(stroke),
      carrier == null
          ? 0
          : stroke.brushSize * carrier.maximumSegmentLengthFactor,
    );
    final minimumArc = math.max(0.0, start * spacing - safetyArc);
    final maximumArc = endExclusive * spacing + safetyArc;
    var low = 0, high = _sourceSegments.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_sourceSegments[middle].arcEnd < minimumArc) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return <_PawEmissionSegmentIdentity>[
      for (var i = low;
          i < _sourceSegments.length &&
              _sourceSegments[i].arcStart <= maximumArc;
          i++)
        _PawEmissionSegmentIdentity(_sourceSegments[i]),
    ];
  }

  _PawRetainedDabChunk _replaceRetainedChunk({
    required _PawRetainedDabChunk? previous,
    required PawDabEmissionSource stroke,
    required int start,
    required int endExclusive,
    required double spacing,
    required List<_PawPlannedDabIdentity> identities,
    required List<_PawEmissionSegmentIdentity> segmentIdentities,
    required int softPrefixSignature,
    PawSoftTileDensityAccumulator? softAccumulator,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    if (previous != null) {
      final shared = math.min(previous.identities.length, identities.length);
      for (var index = 0; index < shared; index++) {
        if (previous.identities[index] == identities[index]) {
          lastRerecordedUnchangedDabCount++;
        }
      }
      final oldBounds = previous.command.body?.bounds;
      if (oldBounds != null &&
          PawDabResource._usesContactPixelTransfer(stroke.definition,
              rasterProgram: stroke.environment.rasterProgram)) {
        _unpaintedContactBounds.add(oldBounds);
      }
      previous.dispose();
    }
    final geometryCounter =
        performanceCapture == null ? null : _PawGeometryPayloadCounter();
    final command = _measureMutableCommandBuild(
      () => _buildRangeCommand(
        stroke,
        start,
        endExclusive,
        spacing,
        geometryCounter: geometryCounter,
        softAccumulator: softAccumulator,
        wetAccumulator: wetAccumulator,
      ),
    );
    if (command.body != null) {
      _commandBatchCount++;
      _commandKinds.add(PawDabBatchCommandKind.drawVertices);
    }
    if (command.atlas != null) {
      _commandBatchCount++;
      _commandKinds.add(PawDabBatchCommandKind.drawAtlas);
    }
    if (command.carrier != null) {
      _commandBatchCount++;
      _commandKinds.add(PawDabBatchCommandKind.drawVertices);
    }
    if (command.preparedStamp != null) {
      _commandBatchCount++;
      _commandKinds.add(PawDabBatchCommandKind.drawPreparedStamp);
    }
    lastRecordedDabChunkCount++;
    return _PawRetainedDabChunk(
      endExclusive: endExclusive,
      command: command,
      identities: List<_PawPlannedDabIdentity>.unmodifiable(identities),
      segmentIdentities:
          List<_PawEmissionSegmentIdentity>.unmodifiable(segmentIdentities),
      softPrefixSignature: softPrefixSignature,
      geometryPayloadProxy: geometryCounter?.snapshot ??
          const PawBrushGeometryPayloadProxy.zero(),
    );
  }

  void _syncRetainedVisibleChunks(
    PawDabEmissionSource stroke,
    double spacing, {
    PawSoftBehavior? softBehavior,
    bool wetMediaEnabled = false,
  }) {
    lastRerecordedUnchangedDabCount = 0;
    if (stroke.renderEndArc <= 0) {
      for (final chunk in _retainedDabChunks.values) {
        final oldBounds = chunk.command.body?.bounds;
        if (oldBounds != null &&
            PawDabResource._usesContactPixelTransfer(stroke.definition,
                rasterProgram: stroke.environment.rasterProgram)) {
          _unpaintedContactBounds.add(oldBounds);
        }
        chunk.dispose();
      }
      _retainedDabChunks.clear();
      if (_tailRevision != stroke.revision) {
        _tailPicture?.dispose();
        final geometryCounter =
            performanceCapture == null ? null : _PawGeometryPayloadCounter();
        _tailPicture = _measurePictureRecording(
          () => _recordTap(
            stroke,
            geometryCounter: geometryCounter,
            softAccumulator: softBehavior == null ? null : _softWorkingDensity,
            wetAccumulator: wetMediaEnabled ? _wetWorkingMedia : null,
          ),
        );
        _tailGeometryPayloadProxy = geometryCounter?.snapshot ??
            const PawBrushGeometryPayloadProxy.zero();
        totalRecordedPictureCount++;
      }
      lastTailDabCount = stroke.strokeStartPosition == null ? 0 : 1;
      _previousTailStartIndex = 0;
      _previousTailEndExclusive = lastTailDabCount;
    } else {
      _tailPicture?.dispose();
      _tailPicture = null;
      _tailGeometryPayloadProxy = const PawBrushGeometryPayloadProxy.zero();
      final retainedStarts = <int>{};
      final mutableCommandDabs =
          PawStreamingDabRenderCache._commandDabs(stroke);
      for (var start = _nextSealedDabIndex;
          start < _lastVisibleDabExclusive;
          start += mutableCommandDabs) {
        retainedStarts.add(start);
        final end = math.min(
          start + mutableCommandDabs,
          _lastVisibleDabExclusive,
        );
        final identities = _plannedIdentities(stroke, start, end);
        final segmentIdentities =
            _segmentIdentities(stroke, start, end, spacing);
        final previous = _retainedDabChunks[start];
        final softPrefixSignature =
            (softBehavior == null ? 0 : _softWorkingDensity.signature) ^
                (wetMediaEnabled ? _wetWorkingMedia.signature : 0);
        if (previous?.matches(
              end,
              identities,
              segmentIdentities,
              softPrefixSignature,
            ) ==
            true) {
          if (softBehavior != null) {
            _accumulateSoftRange(
              stroke: stroke,
              start: start,
              endExclusive: end,
              accumulator: _softWorkingDensity,
              behavior: softBehavior,
            );
          }
          if (wetMediaEnabled) {
            _accumulateWetRange(
              stroke: stroke,
              start: start,
              endExclusive: end,
              accumulator: _wetWorkingMedia,
            );
          }
          continue;
        }
        _retainedDabChunks[start] = _replaceRetainedChunk(
          previous: previous,
          stroke: stroke,
          start: start,
          endExclusive: end,
          spacing: spacing,
          identities: identities,
          segmentIdentities: segmentIdentities,
          softPrefixSignature: softPrefixSignature,
          softAccumulator: softBehavior == null ? null : _softWorkingDensity,
          wetAccumulator: wetMediaEnabled ? _wetWorkingMedia : null,
        );
      }
      final obsolete = _retainedDabChunks.keys
          .where((start) => !retainedStarts.contains(start))
          .toList(growable: false);
      for (final start in obsolete) {
        final old = _retainedDabChunks.remove(start);
        final oldBounds = old?.command.body?.bounds;
        if (oldBounds != null &&
            PawDabResource._usesContactPixelTransfer(stroke.definition,
                rasterProgram: stroke.environment.rasterProgram)) {
          _unpaintedContactBounds.add(oldBounds);
        }
        old?.dispose();
      }
      lastTailDabCount =
          math.max(0, _lastVisibleDabExclusive - _nextSealedDabIndex);
      _previousTailStartIndex = _nextSealedDabIndex;
      _previousTailEndExclusive = _lastVisibleDabExclusive;
    }
    lastTailGeometryVertexCount = _retainedDabChunks.values.fold<int>(
          0,
          (total, chunk) => total + chunk.geometryPayloadProxy.vertexCountProxy,
        ) +
        _tailGeometryPayloadProxy.vertexCountProxy;
    lastCarrierVertexCount = _retainedDabChunks.values.fold<int>(
      0,
      (total, chunk) => total + chunk.command.carrierVertexCount,
    );
    lastPreparedStampVertexCount = _retainedDabChunks.values.fold<int>(
      0,
      (total, chunk) => total + chunk.command.preparedStampVertexCount,
    );
    lastTailPersistentLaneVertexCount = lastPersistentLaneVertexCount;
    lastMutableTailWorkUnits = _retainedDabChunks.values.fold<int>(
      0,
      (total, chunk) => total + chunk.command.workUnits,
    );
    _tailRevision = stroke.revision;
  }
}
