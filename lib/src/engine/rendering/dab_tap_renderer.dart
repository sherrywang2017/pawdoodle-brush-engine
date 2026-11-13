part of '../../streaming_dab_brush.dart';

extension _DabTapRenderer on PawStreamingDabRenderCache {
  ui.Picture? _recordTap(
    PawDabEmissionSource stroke, {
    _PawGeometryPayloadCounter? geometryCounter,
    PawSoftTileDensityAccumulator? softAccumulator,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    final point = stroke.strokeStartPosition;
    if (point == null) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
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
    final kernelKind = program?.kernelKind ??
        stroke.environment.kernelKind ??
        PawBrushKernelKind.dabDry;
    final kernel =
        program?.kernel ?? PawBrushKernelRegistry.forKind(kernelKind);
    final behavior = program?.behavior;
    const tapDirection = Offset(1, 0);
    final tapMotion = stroke.tapMotionSample;
    _tapKernelDabScratch.set(
      point: point,
      tangent: tapDirection,
      hash: PawDabResource._hash(
        stroke.seed.value ^ stroke.definition.identitySalt,
        0,
      ),
      motion: tapMotion,
    );
    if (wetAccumulator != null) {
      final wet = stroke.definition.wetMedia;
      wetAccumulator.deposit(
        dab: _tapKernelDabScratch,
        flow: stroke.opacity,
        dilution: wet.dilution,
        charge: wet.charge,
        diffusion: wet.diffusionRadius,
      );
    }
    _evaluateKernelInto(
      stroke: stroke,
      dab: _tapKernelDabScratch,
      previousTangent: tapDirection,
      followingTangent: tapDirection,
      behavior: behavior,
      kernel: kernel,
      softAccumulator: softAccumulator,
    );
    final instance = _DabInstanceEvaluator._dabInstance(
      stroke: stroke,
      resource: resource,
      index: 0,
      arc: 0,
      point: point,
      motion: tapMotion,
      kernelOutput: _kernelOutputScratch,
    );
    final positions = <Offset>[];
    final textureCoordinates = <Offset>[];
    final colors = <Color>[];
    final indices = <int>[];
    final carrierPositions = <Offset>[];
    final carrierTextureCoordinates = <Offset>[];
    final carrierColors = <Color>[];
    final carrierIndices = <int>[];
    // Dry wax starts with the same contact, paper tooth and endpoint transfer
    // as the moving ribbon. The old generic dab flashed before being replaced.
    if (stroke.definition.dryWax.enabled && renderPlan.needsCanvasContact) {
      _appendContactRibbon(
        positions: positions,
        textureCoordinates: textureCoordinates,
        colors: colors,
        indices: indices,
        stroke: stroke,
        startArc: 0,
        endArc: 0,
        behavior: behavior,
        kernel: kernel,
      );
    } else {
      _appendBodyMesh(
        positions: positions,
        textureCoordinates: textureCoordinates,
        colors: colors,
        indices: indices,
        stroke: stroke,
        point: instance.center,
        direction: instance.direction,
        arc: 0,
        pressureSize: instance.pressureSize,
        kernelOutput: _kernelOutputScratch,
        color: instance.color,
        motion: tapMotion,
        dryMediaCoverage: stroke.definition.useWholeDabDryMediaCoverage
            ? _DabInstanceEvaluator._sampleDryMediaCoverage(
                stroke: stroke,
                point: instance.center,
                arc: 0,
              )
            : 1,
        linearizeOverlap: false,
        wetAccumulator: wetAccumulator,
      );
    }
    if (renderPlan.needsStreamingHairs) {
      _DabStreamingFilaments._appendStreamingFilamentTap(
        positions: positions,
        textureCoordinates: textureCoordinates,
        colors: colors,
        indices: indices,
        stroke: stroke,
        point: instance.center,
        direction: instance.direction,
      );
    }
    if (renderPlan.needsPersistentBristles) {
      _DabPersistentLanes._appendPersistentLaneTap(
        positions: positions,
        textureCoordinates: textureCoordinates,
        colors: colors,
        indices: indices,
        carrierPositions: carrierPositions,
        carrierTextureCoordinates: carrierTextureCoordinates,
        carrierColors: carrierColors,
        carrierIndices: carrierIndices,
        stroke: stroke,
        point: instance.center,
        direction: instance.direction,
      );
    }
    geometryCounter?.add(
      vertices: positions.length + carrierPositions.length,
      indices: indices.length + carrierIndices.length,
      atlasInstances: stroke.definition.template.hasPositiveDetails ? 1 : 0,
    );
    if (positions.isNotEmpty) {
      _paintVertices(
        canvas,
        _PawDabVerticesBatch(
          applyTexture: !PawDabResource._usesContactPixelTransfer(
              stroke.definition,
              rasterProgram: stroke.environment.rasterProgram),
          vertices: ui.Vertices(
            ui.VertexMode.triangles,
            positions,
            colors: colors,
            textureCoordinates: textureCoordinates,
            indices: indices,
          ),
        ),
      );
    }
    if (stroke.definition.template.hasPositiveDetails) {
      _paintBatch(
        canvas,
        _PawDabAtlasBatch(
          transforms: <ui.RSTransform>[instance.transform],
          rects: <Rect>[instance.sourceRect],
          colors: <Color>[instance.color],
        ),
      );
    }
    if (carrierPositions.isNotEmpty) {
      _paintVertices(
        canvas,
        _PawDabVerticesBatch(
          vertices: ui.Vertices(
            ui.VertexMode.triangles,
            carrierPositions,
            colors: carrierColors,
            textureCoordinates: carrierTextureCoordinates,
            indices: carrierIndices,
          ),
          applyTexture: false,
        ),
      );
    }
    return recorder.endRecording();
  }
}
