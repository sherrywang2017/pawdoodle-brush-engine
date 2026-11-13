part of '../../streaming_dab_brush.dart';

extension _DabCachePainting on PawStreamingDabRenderCache {
  void _paintBatch(Canvas canvas, _PawDabAtlasBatch batch) {
    _commandBatchCount++;
    _commandKinds.add(batch.kind);
    batch.paint(canvas, _resource!);
  }

  void _paintVertices(Canvas canvas, _PawDabVerticesBatch batch) {
    _commandBatchCount++;
    _commandKinds.add(batch.kind);
    batch.paint(canvas, _resource!);
    batch.dispose();
  }

  void _compact(PawDabBrushDefinition d) {
    while (_sealedPictures.length > d.maximumBatchPictures) {
      final watch = _compactionStopwatch;
      watch
        ?..reset()
        ..start();
      try {
        _compactOneBatch(d);
      } finally {
        if (watch != null) {
          watch.stop();
          performanceCapture?.recordCompactionMicros(watch.elapsedMicroseconds);
        }
      }
    }
  }

  void _compactOneBatch(PawDabBrushDefinition d) {
    final logicalSize =
        _sealedLogicalSize ??= PawStreamingDabRenderCache._defaultLogicalSize;
    final count = math.min(d.compactionBatchSize, _sealedPictures.length);
    final batch = _sealedPictures.sublist(0, count);
    final replacements = <double, ui.Image>{};
    try {
      for (final rasterScale in _sealedRasterScales) {
        final pixelWidth =
            math.max(1, (logicalSize.width * rasterScale).ceil());
        final pixelHeight =
            math.max(1, (logicalSize.height * rasterScale).ceil());
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(rasterScale);
        final previous = _flattenedSealedImages[rasterScale];
        if (previous != null) {
          canvas.drawImageRect(
            previous,
            Rect.fromLTWH(
              0,
              0,
              previous.width.toDouble(),
              previous.height.toDouble(),
            ),
            Offset.zero & logicalSize,
            Paint()
              ..blendMode = BlendMode.src
              ..filterQuality = FilterQuality.none,
          );
        }
        for (final picture in batch) {
          canvas.drawPicture(picture);
        }
        final flatteningPicture = recorder.endRecording();
        try {
          replacements[rasterScale] =
              flatteningPicture.toImageSync(pixelWidth, pixelHeight);
        } finally {
          flatteningPicture.dispose();
        }
      }
    } catch (_) {
      for (final image in replacements.values) {
        image.dispose();
      }
      rethrow;
    }
    final capture = performanceCapture;
    if (capture != null) {
      final currentFlattenedRgbaBytes = _flattenedSealedImages.values.fold(
        0,
        (total, image) => total + image.width * image.height * 4,
      );
      final replacementFlattenedRgbaBytes = replacements.values.fold(
        0,
        (total, image) => total + image.width * image.height * 4,
      );
      final geometry = _retainedGeometryPayloadProxy;
      capture.recordTransientPayloadProxyPeak(
        flattenedRgbaBytes:
            currentFlattenedRgbaBytes + replacementFlattenedRgbaBytes,
        retainedPictureCount:
            _sealedPictures.length + (_tailPicture == null ? 0 : 1),
        geometryPayloadBytesProxy: geometry.payloadBytesProxy,
        geometryVertexCountProxy: geometry.vertexCountProxy,
        geometryIndexCountProxy: geometry.indexCountProxy,
        atlasInstanceCountProxy: geometry.atlasInstanceCountProxy,
      );
    }
    for (final image in _flattenedSealedImages.values) {
      image.dispose();
    }
    _flattenedSealedImages
      ..clear()
      ..addAll(replacements);
    totalRecordedPictureCount += replacements.length;
    for (final picture in batch) {
      picture.dispose();
    }
    _sealedPictures.removeRange(0, count);
    _sealedPictureBounds.removeRange(0, count);
    if (_sealedGeometryPayloadProxies.isNotEmpty) {
      assert(_sealedGeometryPayloadProxies.length >= count);
      _sealedGeometryPayloadProxies.removeRange(0, count);
    }
  }

  double _canonicalRasterScaleFor(double targetRasterScale) {
    if (!targetRasterScale.isFinite || targetRasterScale <= 0) {
      throw ArgumentError.value(
        targetRasterScale,
        'targetRasterScale',
        'must be finite and greater than zero',
      );
    }
    for (final scale in _sealedRasterScales) {
      if (scale >= targetRasterScale) return scale;
    }
    return _sealedRasterScales.last;
  }

  ui.Image? _flattenedImageForScale(double targetRasterScale) {
    if (_flattenedSealedImages.isEmpty) return null;
    return _flattenedSealedImages[_canonicalRasterScaleFor(targetRasterScale)];
  }

  void _paintStrokeMaterial(
      Canvas canvas, PawDabEmissionSource stroke, double targetRasterScale) {
    final definition = stroke.definition;
    if (_sweptCoverage != null && !definition.wetMedia.enabled) {
      final grain = definition.grain;
      if (stroke.environment.unifiedProgram!.renderPlan.needsCanvasContact &&
          (grain.coarseStrength > 0 || grain.fineStrength > 0)) {
        // Resolve coverage once, then apply paper once. Textured triangles
        // used to source-over each other at folds, creating dark wedges.
        _resource ??= PawDabResource.acquirePrepared(definition,
            rasterProgram: stroke.environment.rasterProgram);
        final scale =
            64 * grain.coarseScaleFactor / PawDabResource._textureTilePixels;
        final c = math.cos(grain.rotationRadians) * scale;
        final s = math.sin(grain.rotationRadians) * scale;
        // CanvasKit shaders own the exact image handle given to them. This
        // transformed sampler needs its own clone; sharing the resource's
        // sampler handle lets preview disposal invalidate cached paper.
        _sweptGrainImage ??= _resource!._textureTile.clone();
        _sweptGrainShader ??= ui.ImageShader(
            _sweptGrainImage!,
            ui.TileMode.repeated,
            ui.TileMode.repeated,
            Float64List.fromList(
                [c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
            filterQuality: FilterQuality.low);
        final bounds = _sweptCoverageBounds!.inflate(1);
        canvas.saveLayer(bounds, Paint());
        _sweptCoverage!.paint(canvas);
        if (_sweptGrainCoordinates case final coordinates?) {
          canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
          canvas.drawVertices(
              coordinates,
              BlendMode.src,
              Paint()
                ..shader = _resource!.textureShader
                ..blendMode = BlendMode.src
                ..isAntiAlias = false);
          canvas.restore();
        } else {
          canvas.drawRect(
              bounds,
              Paint()
                ..shader = _sweptGrainShader
                ..blendMode = BlendMode.dstIn
                ..isAntiAlias = false);
        }
        canvas.restore();
        return;
      }
      _sweptCoverage!.paint(canvas);
      return;
    }
    if (!PawDabResource._usesContactPixelTransfer(definition,
        rasterProgram: stroke.environment.rasterProgram)) {
      _paintCachedPictures(canvas, targetRasterScale);
      return;
    }
    if (_lastContactTapBounds != null) {
      _unpaintedContactBounds.add(_lastContactTapBounds!);
      _lastContactTapBounds = null;
    }
    if (_tailPicture != null && stroke.strokeStartPosition != null) {
      final tapBounds = Rect.fromCircle(
          center: stroke.strokeStartPosition!, radius: stroke.brushSize * 2);
      _unpaintedContactBounds.add(tapBounds);
      _lastContactTapBounds = tapBounds;
    }
    final wet = definition.wetMedia;
    final wax = definition.dryWax;
    _contactSurface.paint(
      canvas: canvas,
      revision: stroke.revision,
      targetRasterScale: targetRasterScale,
      logicalSize:
          _sealedLogicalSize ?? PawStreamingDabRenderCache._defaultLogicalSize,
      dirtyBounds: _unpaintedContactBounds,
      cropToContact: _sweptCoverage != null,
      contactBounds: _sweptCoverageBounds,
      settings: PawContactMaterialSettings(
        wet: wet.enabled,
        scale: definition.grain.coarseScaleFactor / (wet.enabled ? 2 : .85),
        strength: definition.grain.coarseStrength,
        density: wax.opticalDensity,
        coverageGain: wax.coverageOpticalGain,
        dilution: wet.dilution,
        bleed: wet.bleed,
        diffusion: wet.diffusionRadius,
        granulation: wet.granulation,
        opacity: stroke.opacity * stroke.color.a,
        color: stroke.color,
        dragStrength: wax.dragStrength,
        dragLength: wax.dragLength * stroke.brushSize,
        dragWidth: wax.dragWidth * stroke.brushSize,
        residue: definition.coverageTransfer.textureFloor,
        seed: stroke.environment.paper.definition.seed ^
            definition.grain.coarseSeed,
        detail: definition.grain.fineStrength,
        rotation: definition.grain.rotationRadians,
        fineScale:
            definition.grain.fineScaleFactor / (wet.enabled ? .14 : .085),
      ),
      paintContact: (target, bounds) => _sweptCoverage != null
          ? _sweptCoverage!.paint(target)
          : _paintCachedPictures(target, targetRasterScale, cullBounds: bounds),
    );
    _unpaintedContactBounds.clear();
    performanceCapture?.recordContactRasterFrame(
      revision: stroke.revision,
      rgbaBytes: _contactSurface.rgbaBytes,
      tileCount: _contactSurface.tileCount,
      updatedTileCount: _contactSurface.lastUpdatedTileCount,
    );
  }

  void _paintCachedPictures(Canvas canvas, double targetRasterScale,
      {Rect? cullBounds}) {
    if (_flattenedImageForScale(targetRasterScale) case final image?) {
      final logicalSize = _sealedLogicalSize!;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          0,
          0,
          image.width.toDouble(),
          image.height.toDouble(),
        ),
        Offset.zero & logicalSize,
        Paint()
          ..filterQuality =
              image.width == (logicalSize.width * targetRasterScale).ceil()
                  ? FilterQuality.none
                  : FilterQuality.low,
      );
    }
    final stableWatch = Stopwatch()..start();
    for (var i = 0; i < _sealedPictures.length; i++) {
      final bounds = _sealedPictureBounds[i];
      if (cullBounds != null &&
          bounds != null &&
          !bounds.overlaps(cullBounds)) {
        continue;
      }
      canvas.drawPicture(_sealedPictures[i]);
    }
    stableWatch.stop();
    lastStablePicturePlaybackMicros = stableWatch.elapsedMicroseconds;
    final retainedStarts = _retainedDabChunks.keys.toList()..sort();
    final directWatch = Stopwatch()..start();
    for (final start in retainedStarts) {
      final command = _retainedDabChunks[start]!.command;
      final bounds = command.bounds;
      if (cullBounds != null &&
          bounds != null &&
          !bounds.overlaps(cullBounds)) {
        continue;
      }
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
        final preparedWatch = Stopwatch()..start();
        command.paint(canvas, _resource!);
        preparedWatch.stop();
        lastPreparedStampSubmitMicros += preparedWatch.elapsedMicroseconds;
      } else {
        command.paint(canvas, _resource!);
      }
    }
    directWatch.stop();
    lastMutableTailDirectSubmitMicros = directWatch.elapsedMicroseconds;
    if (_tailPicture case final picture?) {
      canvas.drawPicture(picture);
    }
  }
}
