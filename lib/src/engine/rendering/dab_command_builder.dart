part of '../../streaming_dab_brush.dart';

extension _DabCommandBuilder on PawStreamingDabRenderCache {
  T _measureMutableCommandBuild<T>(T Function() callback) {
    final watch = Stopwatch()..start();
    try {
      return callback();
    } finally {
      watch.stop();
      lastMutableTailCommandBuildMicros += watch.elapsedMicroseconds;
    }
  }

  T _measureStablePictureRecording<T>(T Function() callback) {
    final watch = Stopwatch()..start();
    try {
      return callback();
    } finally {
      watch.stop();
      final elapsed = watch.elapsedMicroseconds;
      lastStablePictureRecordMicros += elapsed;
      _lastPictureRecordingMicros += elapsed;
    }
  }

  T _measurePictureRecording<T>(T Function() callback) {
    if (performanceCapture == null) return callback();
    final watch = Stopwatch()..start();
    try {
      return callback();
    } finally {
      watch.stop();
      _lastPictureRecordingMicros += watch.elapsedMicroseconds;
    }
  }

  ui.Picture _recordDirectCommands(
    Iterable<_PawDabDirectCommand> commands,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final command in commands) {
      command.paint(canvas, _resource!);
    }
    return recorder.endRecording();
  }

  _PawDabDirectCommand _buildRangeCommand(
    PawDabEmissionSource stroke,
    int start,
    int end,
    double spacing, {
    _PawGeometryPayloadCounter? geometryCounter,
    PawSoftTileDensityAccumulator? softAccumulator,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    assert(end - start <= stroke.definition.maximumDabsPerChunk);
    return _buildRangeBatch(
      stroke,
      start,
      end,
      spacing,
      geometryCounter: geometryCounter,
      softAccumulator: softAccumulator,
      wetAccumulator: wetAccumulator,
    );
  }

  static Rect _positionsBounds(List<Offset> positions) {
    var left = double.infinity, top = double.infinity;
    var right = double.negativeInfinity, bottom = double.negativeInfinity;
    for (final point in positions) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return positions.isEmpty
        ? Rect.zero
        : Rect.fromLTRB(left, top, right, bottom);
  }

  void _evaluateKernelInto({
    required PawDabEmissionSource stroke,
    required PawBrushBehaviorDab dab,
    required Offset previousTangent,
    required Offset followingTangent,
    bool preserveFurDirectionDiscontinuity = false,
    required PawBrushBehavior? behavior,
    required PawBrushKernel kernel,
    PawSoftTileDensityAccumulator? softAccumulator,
  }) {
    final unifiedProgram = stroke.environment.unifiedProgram;
    if (unifiedProgram != null) {
      unifiedProgram.evaluateKernelInto(
        dab: dab,
        input: _kernelInputScratch,
        output: _kernelOutputScratch,
        brushSize: stroke.brushSize,
        flow: stroke.opacity,
        previousTangent: previousTangent,
        followingTangent: followingTangent,
        preserveFurDirectionDiscontinuity: preserveFurDirectionDiscontinuity,
        fiberClusterGenerator: _fiberClusterGenerator,
        fiberCluster: _fiberClusterScratch,
        inkResponse: _inkResponseScratch,
        softAccumulator: softAccumulator,
      );
      return;
    }
    final input = _kernelInputScratch
      ..reset()
      ..brushSize = stroke.brushSize;
    if (behavior case final PawInkBehavior ink) {
      ink.evaluateInto(dab, _inkResponseScratch);
      input
        ..widthScale = _inkResponseScratch.widthScale
        ..opacityScale = _inkResponseScratch.opacityScale
        ..overlapDarkening = _inkResponseScratch.overlapDarkening
        ..velocityThinning = _inkResponseScratch.velocityThinning;
    } else if (behavior case final PawFurBehavior fur) {
      assert(identical(_fiberClusterGenerator.behavior, fur));
      // The renderer consumes the coherent cluster aggregate only. A zero
      // fiber count preserves the flow calculation without producing line
      // geometry or touching the preallocated fiber slots.
      _fiberClusterGenerator.generateInto(
        dab: dab,
        previousTangent: previousTangent,
        followingTangent: followingTangent,
        preserveDirectionDiscontinuity: preserveFurDirectionDiscontinuity,
        brushSize: stroke.brushSize,
        fiberCount: 0,
        output: _fiberClusterScratch,
      );
      input
        ..spread = _fiberClusterScratch.spread
        ..lengthScale = _fiberClusterScratch.length
        ..density = _fiberClusterScratch.density
        ..tipFade = _fiberClusterScratch.tipFade
        ..directionX = _fiberClusterScratch.direction.dx
        ..directionY = _fiberClusterScratch.direction.dy;
    } else if (behavior case final PawSoftBehavior soft) {
      final accumulator = softAccumulator;
      if (accumulator == null) {
        throw StateError('Soft behavior requires the render-cache density.');
      }
      final density = soft.accumulate(
        dab: dab,
        brushSize: stroke.brushSize,
        accumulator: accumulator,
        flow: stroke.opacity,
      );
      input
        ..accumulatedDensity = density
        ..opacityScale = soft.opacityScaleForDensity(density);
    }
    kernel.evaluateInto(
      dab: dab,
      input: input,
      output: _kernelOutputScratch,
    );
  }

  _PawDabDirectCommand _buildRangeBatch(
    PawDabEmissionSource stroke,
    int start,
    int end,
    double spacing, {
    _PawGeometryPayloadCounter? geometryCounter,
    PawSoftTileDensityAccumulator? softAccumulator,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    final resource = _resource!;
    final program = stroke.environment.unifiedProgram;
    final renderPlan = program?.compiledRenderPlan ??
        PawCompiledBrushRenderPlan(
          needsCanvasContact: true,
          needsPersistentBristles:
              stroke.definition.template.persistentLaneLayers.isNotEmpty,
          needsStreamingHairs:
              stroke.definition.template.streamingFilamentLayers.isNotEmpty,
        );
    final usesPreparedStamp = renderPlan.needsPreparedTip &&
        (stroke.definition.preparedFullTip ||
            stroke.definition.template.hasPositiveDetails);
    final usesBodyGeometry = renderPlan.needsCanvasContact ||
        renderPlan.needsPersistentBristles ||
        renderPlan.needsStreamingHairs;
    final hairMesh = renderPlan.needsStreamingHairs &&
            program?.behavior is PawFurBehavior &&
            !renderPlan.needsCanvasContact &&
            !renderPlan.needsPersistentBristles
        ? _prepareHairVertices(stroke)
        : null;
    // These lists become cache-owned command payloads. They are allocated
    // only when a bounded mutable identity changes, then replayed directly on
    // every frame until replacement or immutable promotion.
    lastFreshAllocationProxy += usesPreparedStamp ? 0 : 10;
    final transforms = usesPreparedStamp ? null : <ui.RSTransform>[];
    final rects = usesPreparedStamp ? null : <Rect>[];
    final colors = usesPreparedStamp ? null : <Color>[];
    final bodyPositions = usesBodyGeometry ? <Offset>[] : null;
    final bodyTextureCoordinates = usesBodyGeometry ? <Offset>[] : null;
    final bodyColors = usesBodyGeometry ? <Color>[] : null;
    final bodyIndices = usesBodyGeometry ? <int>[] : null;
    final carrierPositions =
        renderPlan.needsCarrier || renderPlan.needsPersistentBristles
            ? <Offset>[]
            : null;
    final carrierTextureCoordinates =
        carrierPositions == null ? null : <Offset>[];
    final carrierColors = carrierPositions == null ? null : <Color>[];
    final carrierIndices = carrierPositions == null ? null : <int>[];
    final plannedWatch = Stopwatch()..start();
    final needsPlannedDabs = usesPreparedStamp ||
        stroke.definition.template.hasPositiveDetails ||
        renderPlan.needsStreamingHairs ||
        renderPlan.needsPersistentBristles ||
        renderPlan.needsCarrier ||
        wetAccumulator != null ||
        softAccumulator != null;
    final plannedDabs = !needsPlannedDabs
        ? <PawPlannedDab>[]
        : PawStreamingDabRenderCache._emissionPlanner.planRange(
            source: stroke,
            startIndex: start,
            endExclusive: end,
          );
    if (wetAccumulator != null) {
      final wet = stroke.definition.wetMedia;
      for (final dab in plannedDabs) {
        wetAccumulator.deposit(
          dab: dab,
          flow: stroke.opacity,
          dilution: wet.dilution,
          charge: wet.charge,
          diffusion: wet.diffusionRadius,
        );
      }
    }
    plannedWatch.stop();
    lastPlannedDabMicros += plannedWatch.elapsedMicroseconds;
    final stampBuffer = usesPreparedStamp
        ? _stampBufferArena.acquire(plannedDabs.length)
        : null;
    final behavior = program?.behavior;
    final kernelKind = program?.kernelKind ??
        stroke.environment.kernelKind ??
        PawBrushKernelKind.dabDry;
    final kernel =
        program?.kernel ?? PawBrushKernelRegistry.forKind(kernelKind);
    final bristleProgram =
        program?.kernelKind == PawBrushKernelKind.bristleFilament;
    lastSegmentLookupCount += plannedDabs.length;
    final bodyWatch =
        renderPlan.needsCanvasContact ? (Stopwatch()..start()) : null;
    for (var dabIndex = 0; dabIndex < plannedDabs.length; dabIndex++) {
      final planned = plannedDabs[dabIndex];
      // Continuous contact materials are evaluated on the stroke ribbon
      // below. Evaluating the same kernel again for every emission dab was
      // pure main-thread work and, for Crayon/Ink, was followed by a dense
      // radial mesh that multiplied geometry by the dab count.
      final needsPerDabInstance = usesPreparedStamp ||
          (renderPlan.needsCanvasContact &&
              stroke.definition.template.hasPositiveDetails);
      if (!needsPerDabInstance) continue;
      final furDirectionWindow = math.max(spacing * 2, stroke.brushSize * .62);
      var previousTangent = behavior is! PawFurBehavior
          ? planned.tangent
          : (_centerlineSampleAtArc(
                stroke,
                math.max(0.0, planned.absoluteArc - furDirectionWindow),
              )?.direction ??
              planned.tangent);
      var followingTangent = behavior is! PawFurBehavior
          ? planned.tangent
          : (_centerlineSampleAtArc(
                stroke,
                math.min(
                  stroke.renderEndArc,
                  planned.absoluteArc + furDirectionWindow,
                ),
              )?.direction ??
              planned.tangent);
      var preserveFurDirectionDiscontinuity = false;
      if (behavior is PawFurBehavior) {
        final previousSegmentIndex = _centerlineSampleAtArc(
              stroke,
              math.max(0.0, planned.absoluteArc - furDirectionWindow),
            )?.segmentIndex ??
            planned.segmentIndex;
        final followingSegmentIndex = _centerlineSampleAtArc(
              stroke,
              math.min(
                stroke.renderEndArc,
                planned.absoluteArc + furDirectionWindow,
              ),
            )?.segmentIndex ??
            planned.segmentIndex;
        final crossesIncomingCusp =
            previousSegmentIndex != planned.segmentIndex &&
                _DabInstanceEvaluator._directionTurnRadians(
                        previousTangent, planned.tangent) >=
                    32 * math.pi / 180;
        final crossesOutgoingCusp =
            followingSegmentIndex != planned.segmentIndex &&
                _DabInstanceEvaluator._directionTurnRadians(
                        planned.tangent, followingTangent) >=
                    32 * math.pi / 180;
        preserveFurDirectionDiscontinuity =
            crossesIncomingCusp || crossesOutgoingCusp;
      }
      _evaluateKernelInto(
        stroke: stroke,
        dab: planned,
        previousTangent: previousTangent,
        followingTangent: followingTangent,
        preserveFurDirectionDiscontinuity: preserveFurDirectionDiscontinuity,
        behavior: behavior,
        kernel: kernel,
        softAccumulator: softAccumulator,
      );
      if (bristleProgram && stroke.renderEndArc > 0) {
        final endpoint = program?.endpoint;
        final endpointSize = endpoint?.sizeScaleAt(
              closed: stroke.isClosed,
              absoluteArc: planned.absoluteArc,
              renderEndArc: stroke.renderEndArc,
              brushSize: stroke.brushSize,
            ) ??
            1;
        final endpointOpacity = endpoint?.opacityScaleAt(
              closed: stroke.isClosed,
              absoluteArc: planned.absoluteArc,
              renderEndArc: stroke.renderEndArc,
              brushSize: stroke.brushSize,
            ) ??
            1;
        // The prepared crossing-bristle atlas keeps exactly the same angle.
        // Only its finite hair length grows away from the head and shrinks
        // into the live tail. The renderer identity above tracks this bounded
        // tail response so old short hairs cannot flash to full length later.
        _kernelOutputScratch
          ..widthScale *= endpointSize
          ..lengthScale *= endpointSize
          ..opacityScale *= endpointOpacity;
      }
      if (usesPreparedStamp) {
        final instanceWatch = Stopwatch()..start();
        _DabInstanceEvaluator._fillStampInstance(
          stroke: stroke,
          resource: resource,
          index: planned.globalDabIndex,
          arc: planned.absoluteArc,
          point: planned.point,
          motion: planned.motion,
          kernelOutput: _kernelOutputScratch,
          output: _stampInstanceScratch,
        );
        instanceWatch.stop();
        lastStampInstanceBuildMicros += instanceWatch.elapsedMicroseconds;
        final packWatch = Stopwatch()..start();
        stampBuffer!.append(
          _stampInstanceScratch,
          stroke.definition.template,
        );
        packWatch.stop();
        lastTypedBufferPackMicros += packWatch.elapsedMicroseconds;
        lastPreparedStampInstances++;
        if (!renderPlan.needsCanvasContact) continue;
      }
      if (!renderPlan.needsCanvasContact ||
          !stroke.definition.template.hasPositiveDetails) {
        continue;
      }
      final instance = _DabInstanceEvaluator._dabInstance(
        stroke: stroke,
        resource: resource,
        index: planned.globalDabIndex,
        arc: planned.absoluteArc,
        point: planned.point,
        motion: planned.motion,
        kernelOutput: _kernelOutputScratch,
      );
      if (stroke.definition.template.hasPositiveDetails) {
        transforms!.add(instance.transform);
        rects!.add(instance.sourceRect);
        colors!.add(instance.color);
      }
    }
    if (renderPlan.needsCanvasContact) {
      _appendContactRibbon(
        positions: bodyPositions!,
        textureCoordinates: bodyTextureCoordinates!,
        colors: bodyColors!,
        indices: bodyIndices!,
        stroke: stroke,
        startArc: start * spacing,
        endArc: end * spacing,
        behavior: behavior,
        kernel: kernel,
        wetAccumulator: wetAccumulator,
      );
    }
    if (renderPlan.needsStreamingHairs) {
      if (behavior is PawFurBehavior) {
        _appendFurClusters(
          positions: bodyPositions!,
          textureCoordinates: bodyTextureCoordinates!,
          colors: bodyColors!,
          indices: bodyIndices!,
          stroke: stroke,
          plannedDabs: plannedDabs,
          behavior: behavior,
          spacing: spacing,
          mesh: hairMesh,
        );
      } else {
        _appendStreamingFilaments(
          positions: bodyPositions!,
          textureCoordinates: bodyTextureCoordinates!,
          colors: bodyColors!,
          indices: bodyIndices!,
          stroke: stroke,
          startArc: start * spacing,
          endArc: end * spacing,
        );
      }
    }
    if (renderPlan.needsCarrier) {
      _appendHybridCarrier(
        positions: carrierPositions!,
        textureCoordinates: carrierTextureCoordinates!,
        colors: carrierColors!,
        indices: carrierIndices!,
        stroke: stroke,
        startArc: start * spacing,
        endArc: end * spacing,
        behavior: behavior,
        kernel: kernel,
        profile: program!.carrier!,
      );
    }
    bodyWatch?.stop();
    lastBodyMeshMicros += bodyWatch?.elapsedMicroseconds ?? 0;
    if (renderPlan.needsPersistentBristles) {
      final persistentVerticesBefore =
          bodyPositions!.length + carrierPositions!.length;
      _appendPersistentLanes(
        positions: bodyPositions,
        textureCoordinates: bodyTextureCoordinates!,
        colors: bodyColors!,
        indices: bodyIndices!,
        carrierPositions: carrierPositions,
        carrierTextureCoordinates: carrierTextureCoordinates!,
        carrierColors: carrierColors!,
        carrierIndices: carrierIndices!,
        stroke: stroke,
        startArc: start * spacing,
        endArc: end * spacing,
      );
      lastPersistentLaneVertexCount += bodyPositions.length +
          carrierPositions.length -
          persistentVerticesBefore;
    }
    geometryCounter?.add(
      vertices: (hairMesh?.vertexCount ?? bodyPositions?.length ?? 0) +
          (carrierPositions?.length ?? 0) +
          (stampBuffer?.count ?? 0) * 4,
      indices: (hairMesh?.indexCount ?? bodyIndices?.length ?? 0) +
          (carrierIndices?.length ?? 0) +
          (stampBuffer?.count ?? 0) * 6,
      atlasInstances: (transforms?.length ?? 0) + (stampBuffer?.count ?? 0),
    );
    final verticesWatch = Stopwatch()..start();
    if (bodyPositions != null &&
        bodyPositions.isNotEmpty &&
        PawDabResource._usesContactPixelTransfer(stroke.definition,
            rasterProgram: stroke.environment.rasterProgram)) {
      final bounds = _DabCommandBuilder._positionsBounds(bodyPositions);
      _unpaintedContactBounds.add(bounds);
    }
    final body = hairMesh != null && hairMesh.vertexCount > 0
        ? _PawDabVerticesBatch(
            vertices: hairMesh.build(),
            bounds: hairMesh.bounds,
            applyTexture: stroke.definition.grain.isEnabled,
            isAntiAlias: false)
        : bodyPositions == null || bodyPositions.isEmpty
            ? null
            : _PawDabVerticesBatch(
                bounds: _DabCommandBuilder._positionsBounds(bodyPositions),
                vertices: ui.Vertices(
                  ui.VertexMode.triangles,
                  bodyPositions,
                  colors: bodyColors,
                  textureCoordinates: bodyTextureCoordinates,
                  indices: bodyIndices,
                ),
                applyTexture: (renderPlan.needsCanvasContact ||
                        (renderPlan.needsStreamingHairs &&
                            stroke.definition.grain.isEnabled)) &&
                    !PawDabResource._usesContactPixelTransfer(stroke.definition,
                        rasterProgram: stroke.environment.rasterProgram),
                // A contact ribbon already carries its analytic coverage fringe.
                // Antialiasing each retained mesh independently makes their shared
                // cross-section an edge twice, producing either a pale cut or a
                // dark band at every cache chunk. Coverage belongs to the ribbon,
                // so internal mesh edges must be rasterized exactly once.
                isAntiAlias: !renderPlan.needsCanvasContact &&
                    !renderPlan.needsStreamingHairs &&
                    !renderPlan.needsPersistentBristles,
              );
    final carrier = carrierPositions == null || carrierPositions.isEmpty
        ? null
        : _PawDabVerticesBatch(
            vertices: ui.Vertices(
              ui.VertexMode.triangles,
              carrierPositions,
              colors: carrierColors,
              textureCoordinates: carrierTextureCoordinates,
              indices: carrierIndices,
            ),
            applyTexture: false,
          );
    verticesWatch.stop();
    lastVerticesBatchMicros += verticesWatch.elapsedMicroseconds;
    final atlasWatch = Stopwatch()..start();
    final atlas = transforms == null || transforms.isEmpty
        ? null
        : _PawDabAtlasBatch(
            transforms: transforms,
            rects: rects!,
            colors: colors!,
          );
    atlasWatch.stop();
    lastAtlasBatchMicros += atlasWatch.elapsedMicroseconds;
    _PawPreparedStampBatch? preparedStamp;
    if (stampBuffer != null) {
      final preparedWatch = Stopwatch()..start();
      try {
        preparedStamp = _PawPreparedStampBatch(
          vertices: ui.Vertices.raw(
            ui.VertexMode.triangles,
            stampBuffer.positions,
            colors: stampBuffer.colors,
            textureCoordinates: stampBuffer.textureCoordinates,
            indices: stampBuffer.indices,
          ),
          instanceCount: stampBuffer.count,
          buffer: stampBuffer,
          arena: _stampBufferArena,
        );
      } catch (_) {
        _stampBufferArena.release(stampBuffer);
        rethrow;
      } finally {
        preparedWatch.stop();
        lastTypedBufferPackMicros += preparedWatch.elapsedMicroseconds;
      }
    }
    return _PawDabDirectCommand(
      body: body,
      atlas: atlas,
      carrier: carrier,
      preparedStamp: preparedStamp,
      carrierVertexCount: carrierPositions?.length ?? 0,
      preparedStampVertexCount: (stampBuffer?.count ?? 0) * 4,
    );
  }
}
