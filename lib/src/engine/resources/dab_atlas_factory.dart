part of '../../streaming_dab_brush.dart';

abstract final class _DabAtlasFactory {
  static _PawDabCachedAtlas _createAtlas(PawDabBrushDefinition definition) {
    final recording = _DabAtlasFactory._recordAtlas(definition);
    try {
      return _PawDabCachedAtlas(
        image: recording.picture.toImageSync(
          recording.width,
          recording.height,
        ),
        variantRects: recording.variantRects,
        pixelsPerLogicalUnit: recording.pixelsPerLogicalUnit,
        textureTile: _DabGrainTexture._createTextureTile(definition),
      );
    } finally {
      recording.picture.dispose();
    }
  }

  static Future<_PawDabCachedAtlas> _createAtlasAsync(
    PawDabBrushDefinition definition,
  ) async {
    final recording = _DabAtlasFactory._recordAtlas(definition);
    ui.Image? image;
    try {
      image = await recording.picture.toImage(
        recording.width,
        recording.height,
      );
      final textureTile =
          await _DabGrainTexture._createTextureTileAsync(definition);
      return _PawDabCachedAtlas(
        image: image,
        variantRects: recording.variantRects,
        pixelsPerLogicalUnit: recording.pixelsPerLogicalUnit,
        textureTile: textureTile,
      );
    } catch (_) {
      image?.dispose();
      rethrow;
    } finally {
      recording.picture.dispose();
    }
  }

  static _PawDabAtlasRecording _recordAtlas(
    PawDabBrushDefinition definition,
  ) {
    final variants = definition.emission.variantCount;
    final columns = math.min(variants, PawDabResource._atlasMaximumColumns);
    final rows = (variants / columns).ceil();
    final logicalExtent = definition.template.logicalExtent;
    final scale = PawDabResource._atlasCellPixels / logicalExtent;
    final rects = <Rect>[];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var variant = 0; variant < variants; variant++) {
      final column = variant % columns;
      final row = variant ~/ columns;
      final left = column * PawDabResource._atlasCellStride +
          PawDabResource._atlasGutterPixels;
      final top = row * PawDabResource._atlasCellStride +
          PawDabResource._atlasGutterPixels;
      rects.add(Rect.fromLTWH(
        left.toDouble(),
        top.toDouble(),
        PawDabResource._atlasCellPixels.toDouble(),
        PawDabResource._atlasCellPixels.toDouble(),
      ));
    }
    // Prepared Full Tip brushes own their complete stamp-local footprint in
    // this resource. Contact/hybrid brushes retain the legacy positive-detail
    // atlas because their base coverage still depends on canvas-local fields.
    for (var variant = 0; variant < variants; variant++) {
      final column = variant % columns;
      final row = variant ~/ columns;
      final left = column * PawDabResource._atlasCellStride +
          PawDabResource._atlasGutterPixels;
      final top = row * PawDabResource._atlasCellStride +
          PawDabResource._atlasGutterPixels;
      canvas.save();
      canvas.translate(left + PawDabResource._atlasCellPixels / 2,
          top + PawDabResource._atlasCellPixels / 2);
      canvas.scale(scale);
      // Isolate each prepared tip before applying subtractive material masks.
      // Skia can otherwise resolve dstOut against the transparent recording
      // surface instead of the preceding base operations in the same cell.
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: logicalExtent,
          height: logicalExtent,
        ),
        Paint(),
      );
      if (definition.preparedFullTip) {
        _DabTipPainter._paintPreparedFullTipBase(canvas, definition, variant);
        _DabTipPainter._paintPreparedFullTipMaterial(
            canvas, definition, variant);
      }
      _DabTipPainter._paintPositiveTemplateDetails(canvas, definition, variant);
      canvas.restore();
      canvas.restore();
    }
    return _PawDabAtlasRecording(
      picture: recorder.endRecording(),
      width: columns * PawDabResource._atlasCellStride,
      height: rows * PawDabResource._atlasCellStride,
      variantRects: List<Rect>.unmodifiable(rects),
      pixelsPerLogicalUnit: scale,
    );
  }
}
