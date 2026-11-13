part of '../../streaming_dab_brush.dart';

class PawStreamingDabRenderCache implements PawStreamingBrushRenderCache {
  PawStreamingDabRenderCache({
    Size? logicalSize,
    double sealedRasterScale = 1,
    this.performanceCapture,
    this.compactSealedPictures = false,
  })  : _sealedLogicalSize = logicalSize,
        _sealedRasterScale = sealedRasterScale,
        _sealedRasterScales = (<double>{1, sealedRasterScale}.toList()..sort()),
        _syncStopwatch = performanceCapture == null ? null : Stopwatch(),
        _painterSubmitStopwatch =
            performanceCapture == null ? null : Stopwatch(),
        _compactionStopwatch = performanceCapture == null ? null : Stopwatch() {
    if (logicalSize != null) _validateSurface(logicalSize, sealedRasterScale);
    if (!sealedRasterScale.isFinite || sealedRasterScale <= 0) {
      throw ArgumentError.value(
        sealedRasterScale,
        'sealedRasterScale',
        'must be finite and greater than zero',
      );
    }
  }

  static const Size _defaultLogicalSize = Size(512, 512);
  static const PawDabEmissionPlanner _emissionPlanner = PawDabEmissionPlanner();
  static const int _dryMediaDabStride = 4;
  // Four DABs keeps a worst observed 274-DAB Fur tail below 192 direct
  // Canvas work units (body + atlas per command) while making the identity
  // replacement boundary fine enough that unchanged-DAB rebuilds are rare.
  static const int _mutableDirectCommandDabs = 4;

  static int _commandDabs(PawDabEmissionSource stroke) {
    final program = stroke.environment.unifiedProgram;
    final plan = program?.compiledRenderPlan;
    final maximum = stroke.definition.maximumDabsPerChunk;
    if (plan?.needsCanvasContact == true) return maximum;
    if (plan?.needsStreamingHairs == true &&
        program?.behavior is PawFurBehavior &&
        plan?.needsPersistentBristles == false) {
      // A hair has at most 17 cross-sections of three vertices. Pack complete
      // roots up to the native index capacity, while keeping replacement
      // granularity at most 16 DABs. The same rule applies to authored layers.
      final hairs = stroke.definition.template.streamingFilamentLayers
          .fold<int>(0, (sum, layer) => sum + layer.countPerRoot);
      final capacity = math.min(16, 65535 ~/ math.max(1, hairs * 17 * 3));
      for (var count = math.min(maximum, capacity); count > 0; count--) {
        if (maximum % count == 0) return count;
      }
    }
    return math.min(_mutableDirectCommandDabs, maximum);
  }

  static double _contactSectionStep(double brushSize) =>
      math.max(1.1, brushSize * .09);

  static double _contactFrameRadius(double brushSize) =>
      math.max(_contactSectionStep(brushSize) * 1.5, brushSize * .48);

  // A retained command depends on every centerline sample read by its
  // material pose, including samples beyond the command's final cross-section.
  // Use the same reach for invalidation and promotion: sealing only the DAB
  // centers fixes one side of a boundary before its neighbor stops moving.
  static double _materialDependencyArc(PawDabEmissionSource stroke) {
    final program = stroke.environment.unifiedProgram;
    var hairDependency = 0.0;
    final intrinsicHairs =
        program?.compiledRenderPlan.needsStreamingHairs == true &&
            program?.behavior is PawFurBehavior;
    if (intrinsicHairs) {
      final groomingReach = stroke.definition.template.streamingFilamentLayers
          .fold<double>(
              0,
              (reach, layer) => math.max(
                  reach,
                  layer.grooming.lookBehindArcFactor *
                      (.5 + layer.grooming.inertia)));
      final spacing = const PawDabEmissionPlanner().spacingFor(stroke);
      // Intrinsic hair curves read the source only at their root frames.
      // Their projected tips no longer query or twist through future poses.
      hairDependency = math.max(
          2 *
              (_hairFrameRadius(stroke.brushSize, spacing) +
                  stroke.brushSize * groomingReach),
          stroke.brushSize * (program?.endpoint?.endTaperBrushLengths ?? 0));
    }
    return math.max(
      math.max(
          hairDependency,
          // Intrinsic strands read the guide at their roots; their geometric
          // length is not a dependency on future centerline samples. Retain
          // the full length horizon for path-transported filaments and keep
          // the independent persistent-lane horizon for mixed user programs.
          intrinsicHairs
              ? stroke.brushSize *
                  stroke.definition.maximumPersistentTailHorizon
              : stroke.definition
                  .emissionMaterialSafetyHorizonFor(stroke.brushSize)),
      program?.compiledRenderPlan.needsCanvasContact == true
          ? math.max(
              2 * _contactFrameRadius(stroke.brushSize) +
                  (stroke.definition.wetMedia.localOverlapNormalization > 0
                      ? stroke.brushSize * 4
                      : 0) +
                  _contactSectionStep(stroke.brushSize),
              stroke.brushSize * (program?.endpoint?.endTaperBrushLengths ?? 0))
          : 0,
    );
  }

  static double _hairFrameRadius(double brushSize, double spacing) =>
      // Root sampling supplies the anti-aliasing window. The authored
      // grooming look-behind/inertia supplies any additional flow smoothing;
      // a hidden 1.12-brush-width filter both delayed turns and kept dozens of
      // otherwise complete root meshes mutable, even at zero grooming.
      spacing * 3;

  final PawHairVertexBuffer _hairVertices = PawHairVertexBuffer();
  // Subdivision/taper tables depend only on this immutable brush and the
  // quantized bend envelope. Share them across tiny retained commands.
  final _hairTaperSamples = <(int, int, int, int),
      List<
          (
            double,
            double,
            double,
            double,
            double,
            double,
            double,
            double,
            double
          )>>{};
  final _hairRootNoise =
      <(int, int), (double, List<(double, double, double)>)>{};

  final PawFiberClusterGenerator _fiberClusterGenerator =
      const PawFiberClusterGenerator();
  // Match the authored streaming-layer limit without allocating per root.
  final PawFiberCluster _fiberClusterScratch =
      PawFiberCluster(maximumFibers: 64);
  final PawInkDabResponse _inkResponseScratch = PawInkDabResponse();
  final PawBrushKernelInput _kernelInputScratch = PawBrushKernelInput();
  final PawBrushKernelOutput _kernelOutputScratch = PawBrushKernelOutput();
  final PawBrushStamp _brushStampScratch = PawBrushStamp();
  final PawStampInstance _stampInstanceScratch = PawStampInstance();
  final _PawMutableStampBufferArena _stampBufferArena =
      _PawMutableStampBufferArena();
  final PawBrushShapeField _circleShapeField =
      const PawBrushShapeField.circle();
  final PawBrushShapeField _inkShapeField =
      const PawBrushShapeField.ellipse(aspect: .96, hardness: .96);
  final PawBrushShapeField _furShapeField =
      const PawBrushShapeField.proceduralBristle(
    density: .96,
    direction: 0,
    length: .96,
    variation: .38,
    rootTipAttenuation: .94,
    aspect: .68,
    hardness: .76,
  );
  final PawBrushShapeField _softShapeField =
      const PawBrushShapeField.circle(hardness: .58);
  final _PawKernelDabScratch _tapKernelDabScratch = _PawKernelDabScratch();
  final PawSoftTileDensityAccumulator _softSealedDensity =
      PawSoftTileDensityAccumulator();
  final PawSoftTileDensityAccumulator _softWorkingDensity =
      PawSoftTileDensityAccumulator();
  final PawWetMediaTileAccumulator _wetSealedMedia =
      PawWetMediaTileAccumulator();
  final PawWetMediaTileAccumulator _wetWorkingMedia =
      PawWetMediaTileAccumulator();

  final List<ui.Picture> _sealedPictures = <ui.Picture>[];
  final List<Rect?> _sealedPictureBounds = [];
  final List<PawBrushGeometryPayloadProxy> _sealedGeometryPayloadProxies =
      <PawBrushGeometryPayloadProxy>[];
  final Map<int, _PawRetainedDabChunk> _retainedDabChunks =
      <int, _PawRetainedDabChunk>{};
  PawDabResource? _resource;
  String? _resourceDefinitionId;
  int? _resourceDefinitionRevision;
  Size? _sealedLogicalSize;
  final double _sealedRasterScale;
  final List<double> _sealedRasterScales;
  final Map<double, ui.Image> _flattenedSealedImages = <double, ui.Image>{};
  ui.Picture? _tailPicture;
  PawBrushGeometryPayloadProxy _tailGeometryPayloadProxy =
      const PawBrushGeometryPayloadProxy.zero();
  int _tailRevision = -1;
  int? _observedCenterlineReplacementEpoch;
  int _nextSealedDabIndex = 0;
  final Map<int, double> _dryMediaCoverageByDab = <int, double>{};
  bool _disposed = false;
  final PawDabPerformanceCapture? performanceCapture;
  final bool compactSealedPictures;
  final Stopwatch? _syncStopwatch;
  final Stopwatch? _painterSubmitStopwatch;
  final Stopwatch? _compactionStopwatch;
  int _lastSyncMicros = 0;
  int _lastPictureRecordingMicros = 0;
  int _previousTailStartIndex = 0;
  int _previousTailEndExclusive = 0;
  int _lastVisibleDabExclusive = 0;
  double _lastSealedEndArc = 0;
  double _lastCausalStableEndArc = 0;
  double _lastRenderEndArc = 0;

  int lastNewChunkCount = 0;
  int lastRecordedDabChunkCount = 0;
  int lastTailDabCount = 0;
  int get finalMaterialSafetyTailDabCount => lastTailDabCount;
  int lastSafeDabExclusive = 0;
  int lastNewImmutableDabCount = 0;
  int lastRerecordedUnchangedDabCount = 0;
  int lastTailGeometryVertexCount = 0;
  int lastTailPersistentLaneVertexCount = 0;
  int lastSegmentLookupCount = 0;
  int lastFilamentRootCount = 0;
  int lastFilamentLaneCount = 0;
  int lastFilamentArcSampleCount = 0;
  int lastFilamentSegmentCount = 0;
  int lastPersistentLaneCount = 0;
  int lastPersistentArcSampleCount = 0;
  int lastPersistentLaneSegmentCount = 0;
  int lastPersistentLaneVertexCount = 0;
  int totalRecordedPictureCount = 0;
  int ownershipTransferCount = 0;
  int materialOwnershipTransferMicros = 0;
  int stableChunksCreated = 0;
  int stableChunksReused = 0;
  int get stableDabsRecomputed => 0;
  int stablePictureRerecorded = 0;
  int stablePictureIdentityChanged = 0;
  int lastMutableTailDirectSubmitMicros = 0;
  int lastMutableTailCommandBuildMicros = 0;
  int lastStablePictureRecordMicros = 0;
  int lastStablePicturePlaybackMicros = 0;
  int lastPlannedDabMicros = 0;
  int lastBodyMeshMicros = 0;
  int lastAtlasBatchMicros = 0;
  int lastVerticesBatchMicros = 0;
  int lastStampInstanceBuildMicros = 0;
  int lastTypedBufferPackMicros = 0;
  int lastPreparedStampSubmitMicros = 0;
  int lastPreparedStampInstances = 0;
  int lastCarrierVertexCount = 0;
  int lastPreparedStampVertexCount = 0;
  int lastMutableTailWorkUnits = 0;
  int lastFreshAllocationProxy = 0;
  int centerlineReplacementRebuildCount = 0;
  int _commandBatchCount = 0;
  int _resourceCreationsDuringSync = 0;
  final Set<PawDabBatchCommandKind> _commandKinds = <PawDabBatchCommandKind>{};

  int get wetMediaTileCount => _wetWorkingMedia.tileCount;

  final _contactSurface = PawContactMaterialSurface();
  final _unpaintedContactBounds = <Rect>[];
  Rect? _lastContactTapBounds;
  int get contactRasterBytes => _contactSurface.rgbaBytes;
  int get lastUpdatedContactTileCount => _contactSurface.lastUpdatedTileCount;

  PawPreparedStampBufferDiagnostics get preparedStampBufferDiagnostics =>
      _stampBufferArena.diagnostics;

  PawDabRenderCommandDiagnostics get commandDiagnostics =>
      PawDabRenderCommandDiagnostics(
        batchCount: _commandBatchCount,
        kinds: Set<PawDabBatchCommandKind>.unmodifiable(_commandKinds),
        resourceCreationsDuringSync: _resourceCreationsDuringSync,
      );

  /// Records a move-only live-to-checkpoint cache handoff. Pictures, images,
  /// atlas leases, mutable material commands and stable identities stay owned
  /// by this cache instance; no material is regenerated by the handoff.
  void recordOwnershipTransfer(int elapsedMicros) {
    if (_disposed) {
      throw StateError('Cannot transfer a disposed Dab render cache.');
    }
    ownershipTransferCount++;
    materialOwnershipTransferMicros += math.max(0, elapsedMicros);
  }

  PawDabOwnershipDiagnostics get ownershipDiagnostics =>
      PawDabOwnershipDiagnostics(
        visibleDabExclusive: _lastVisibleDabExclusive,
        safeDabExclusive: lastSafeDabExclusive,
        nextSealedDabIndex: _nextSealedDabIndex,
        sealedEndArc: _lastSealedEndArc,
        causalStableEndArc: _lastCausalStableEndArc,
        renderEndArc: _lastRenderEndArc,
        tailStartIndex: _previousTailStartIndex,
        tailEndExclusive: _previousTailEndExclusive,
        tailDabCount: lastTailDabCount,
        newImmutableDabs: lastNewImmutableDabCount,
        newChunkCount: lastNewChunkCount,
        recordedChunkCount: lastRecordedDabChunkCount,
      );

  PawDabSealedCacheDiagnostics get sealedCacheDiagnostics {
    final logicalSize = _sealedLogicalSize ?? _defaultLogicalSize;
    final retainedGeometryPayloadProxy = _retainedGeometryPayloadProxy;
    return PawDabSealedCacheDiagnostics(
      sealedSourcePictureCount: _sealedPictures.length,
      // Retained mutable chunks are direct commands, not Pictures. A tap is
      // the only zero-length compatibility carrier counted here.
      tailPictureCount: _tailPicture == null ? 0 : 1,
      flattenedImageCount: _flattenedSealedImages.length,
      flattenedPixelCount: _flattenedSealedImages.values.fold(
        0,
        (total, image) => total + image.width * image.height,
      ),
      flattenedRasterScales: List<double>.unmodifiable(
        _flattenedSealedImages.keys,
      ),
      logicalSize: logicalSize,
      rasterScale: _sealedRasterScale,
      retainedGeometryPayloadProxy: retainedGeometryPayloadProxy,
    );
  }

  PawBrushGeometryPayloadProxy get _retainedGeometryPayloadProxy =>
      _sealedGeometryPayloadProxies.fold<PawBrushGeometryPayloadProxy>(
        const PawBrushGeometryPayloadProxy.zero(),
        (total, proxy) => total + proxy,
      ) +
      _retainedDabChunks.values.fold<PawBrushGeometryPayloadProxy>(
        const PawBrushGeometryPayloadProxy.zero(),
        (total, chunk) => total + chunk.geometryPayloadProxy,
      ) +
      _tailGeometryPayloadProxy;

  @override
  bool get isDisposed => _disposed;

  static void _validateSurface(Size logicalSize, double rasterScale) {
    if (!logicalSize.width.isFinite ||
        !logicalSize.height.isFinite ||
        logicalSize.width <= 0 ||
        logicalSize.height <= 0) {
      throw ArgumentError.value(
        logicalSize,
        'logicalSize',
        'must have finite positive dimensions',
      );
    }
    if (!rasterScale.isFinite || rasterScale <= 0) {
      throw ArgumentError.value(
        rasterScale,
        'rasterScale',
        'must be finite and greater than zero',
      );
    }
  }

  void bindLogicalSize(Size logicalSize) {
    if (_disposed) return;
    _validateSurface(logicalSize, _sealedRasterScale);
    final current = _sealedLogicalSize;
    if (_flattenedSealedImages.isEmpty) {
      _sealedLogicalSize = logicalSize;
      return;
    }
    if (current != logicalSize) {
      throw StateError(
        'A flattened Dab render cache cannot change logical target size.',
      );
    }
  }

  void sync(PawDabEmissionSource stroke) {
    if (_disposed) return;
    final watch = _syncStopwatch;
    if (watch == null) {
      _syncImpl(stroke);
      return;
    }
    watch
      ..reset()
      ..start();
    try {
      _syncImpl(stroke);
    } finally {
      watch.stop();
      _lastSyncMicros = watch.elapsedMicroseconds;
    }
  }

  /// A C2 material pose on an absolute-arc cubic B-spline. Discrete averaging
  /// of five raw path samples still has five displaced kinks at every sharp
  /// corner. Here position, tangent and curvature are derivatives of the same
  /// continuous polynomial. Extrapolated end knots keep the exposed ends at
  /// the input endpoints without clamping away the derivative.
  final Map<(double, double, bool), _PawFilamentArcSample?> _materialFrames =
      {};
  final Map<(double, int, bool), _PawFilamentArcSample?> _materialKnots = {};
  final Map<(double, int), double> _hairDirectionKnots = {};
  // Shared by all contact chunks for this revision. Local overlap windows
  // repeatedly query the same absolute-arc lattice in adjacent commands.
  final Map<double, _PawFilamentArcSample?> _contactFrames = {};
  final Map<double, _PawFilamentArcSample?> _contactGeometryFrames = {};
  List<PawBrushEmissionSegment> _sourceSegments = const [];
  Object? _syncedEmissionIdentity;
  int _syncedRevision = -1;
  PawSweptCoverage? _sweptCoverage;
  Rect? _sweptCoverageBounds;
  ui.ImageShader? _sweptGrainShader;
  ui.Image? _sweptGrainImage;
  ui.Vertices? _sweptGrainCoordinates;
  final _sweepSections =
      <int, (PawBrushEmissionSegment, List<PawSweepSection>)>{};
  int lastSweepSectionCount = 0;
  int lastSweepRebuiltSectionCount = 0;
  int get sweepLayerCount => _sweptCoverage?.layerCount ?? 0;

  /// Inspect the production field on a fixed source; use one cache per source.
  @visibleForTesting
  (Offset, double) debugHairDirectorAtArc(
      PawDabEmissionSource stroke, double arc,
      {int layerIndex = 0}) {
    final spacing = const PawDabEmissionPlanner().spacingFor(stroke);
    final radius = _hairFrameRadius(stroke.brushSize, spacing);
    final root = _materialFrameAtArc(stroke, arc,
        radius: radius, stabilizeExtrapolation: true)!;
    final grooming =
        stroke.definition.template.streamingFilamentLayers[layerIndex].grooming;
    return _hairDirectorAtArc(
        stroke,
        arc,
        root,
        radius +
            stroke.brushSize *
                grooming.lookBehindArcFactor *
                (.5 + grooming.inertia));
  }

  @visibleForTesting
  Offset? debugContactCenterAtArc(PawDabEmissionSource stroke, double arc) =>
      _contactFrameAtArc(stroke, arc,
              radius: _contactFrameRadius(stroke.brushSize))
          ?.point;

  @visibleForTesting
  double debugCanonicalRasterScaleFor(double targetRasterScale) =>
      _canonicalRasterScaleFor(targetRasterScale);

  void paint(
    Canvas canvas,
    PawDabEmissionSource stroke, {
    required double targetRasterScale,
  }) {
    if (_disposed) return;
    sync(stroke);
    final watch = _painterSubmitStopwatch;
    if (watch == null) {
      _paintStrokeMaterial(canvas, stroke, targetRasterScale);
      return;
    }
    watch
      ..reset()
      ..start();
    try {
      _paintStrokeMaterial(canvas, stroke, targetRasterScale);
    } finally {
      watch.stop();
      final diagnostics = sealedCacheDiagnostics;
      final ownership = ownershipDiagnostics;
      final geometry = diagnostics.retainedGeometryPayloadProxy;
      performanceCapture?.recordPaintedFrame(
        revision: stroke.revision,
        syncMicros: _lastSyncMicros,
        painterSubmitMicros: watch.elapsedMicroseconds,
        pictureRecordingMicros: _lastPictureRecordingMicros,
        mutableTailDirectSubmitMicros: lastMutableTailDirectSubmitMicros,
        mutableTailCommandBuildMicros: lastMutableTailCommandBuildMicros,
        stablePictureRecordMicros: lastStablePictureRecordMicros,
        stablePicturePlaybackMicros: lastStablePicturePlaybackMicros,
        plannedDabMicros: lastPlannedDabMicros,
        bodyMeshMicros: lastBodyMeshMicros,
        atlasBatchMicros: lastAtlasBatchMicros,
        verticesBatchMicros: lastVerticesBatchMicros,
        preparedStampInstances: lastPreparedStampInstances,
        preparedStampBufferCapacity: preparedStampBufferDiagnostics.capacity,
        preparedStampBufferGrowthCount:
            preparedStampBufferDiagnostics.growthCount,
        stampInstanceBuildMicros: lastStampInstanceBuildMicros,
        typedBufferPackMicros: lastTypedBufferPackMicros,
        drawRawAtlasSubmitMicros: 0,
        drawVerticesSubmitMicros: lastPreparedStampSubmitMicros,
        mutableTailWorkUnits: lastMutableTailWorkUnits,
        freshAllocationProxy: lastFreshAllocationProxy,
        stablePictureRerecorded: stablePictureRerecorded,
        stablePictureIdentityChanged: stablePictureIdentityChanged,
        nextSealedDabIndex: _nextSealedDabIndex,
        safeDabExclusive: lastSafeDabExclusive,
        tailDabCount: lastTailDabCount,
        newImmutableDabs: lastNewImmutableDabCount,
        rerecordedUnchangedDabs: lastRerecordedUnchangedDabCount,
        newChunkCount: lastNewChunkCount,
        recordedDabChunks: lastRecordedDabChunkCount,
        tailGeometryVertices: lastTailGeometryVertexCount,
        persistentLaneVertices: lastTailPersistentLaneVertexCount,
        visibleDabExclusive: ownership.visibleDabExclusive,
        sealedEndArc: ownership.sealedEndArc,
        causalStableEndArc: ownership.causalStableEndArc,
        renderEndArc: ownership.renderEndArc,
        tailStartIndex: ownership.tailStartIndex,
        tailEndExclusive: ownership.tailEndExclusive,
        unownedVisibleDabs: ownership.unownedVisibleDabCount,
        doubleOwnedVisibleDabs: ownership.doubleOwnedVisibleDabCount,
        flattenedRgbaBytes: diagnostics.flattenedRgbaByteBudget,
        retainedPictureCount: diagnostics.retainedPictureCount,
        geometryPayloadBytesProxy: geometry.payloadBytesProxy,
        geometryVertexCountProxy: geometry.vertexCountProxy,
        geometryIndexCountProxy: geometry.indexCountProxy,
        atlasInstanceCountProxy: geometry.atlasInstanceCountProxy,
      );
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _contactSurface.dispose();
    _sweptCoverage?.dispose();
    _sweptCoverage = null;
    _sweptCoverageBounds = null;
    _sweptGrainShader?.dispose();
    _sweptGrainShader = null;
    if (!kIsWeb || kIsWasm) _sweptGrainImage?.dispose();
    _sweptGrainImage = null;
    _sweptGrainCoordinates?.dispose();
    _sweptGrainCoordinates = null;
    _sweepSections.clear();
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
    _resource?.dispose();
    _resource = null;
  }
}
