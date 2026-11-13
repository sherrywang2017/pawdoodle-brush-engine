part of '../../streaming_dab_brush.dart';

class PawStreamingDabRenderer
    implements
        PawStreamingBrushRenderer<PawStreamingDabStroke,
            PawStreamingDabRenderCache> {
  const PawStreamingDabRenderer();

  @override
  void paint(
      {required Canvas canvas,
      required Size outputSize,
      required Size logicalSize,
      required double physicalTargetRasterScale,
      required PawStreamingDabStroke stroke,
      PawStreamingDabRenderCache? renderCache,
      Offset translation = Offset.zero}) {
    final ownsCache = renderCache == null;
    final cache = renderCache ??
        PawStreamingDabRenderCache(
          logicalSize: logicalSize,
          sealedRasterScale: math.max(1, physicalTargetRasterScale),
        );
    try {
      cache.bindLogicalSize(logicalSize);
      canvas.save();
      try {
        canvas.translate(translation.dx, translation.dy);
        canvas.scale(outputSize.width / logicalSize.width,
            outputSize.height / logicalSize.height);
        cache.paint(
          canvas,
          stroke,
          targetRasterScale: physicalTargetRasterScale,
        );
      } finally {
        canvas.restore();
      }
    } finally {
      if (ownsCache) cache.dispose();
    }
  }

  @override
  Future<PawStreamingBrushMask> rasterize(
      {required PawStreamingDabStroke stroke,
      required int canvasWidth,
      required int canvasHeight,
      required double rasterScale,
      PawStreamingDabRenderCache? renderCache}) async {
    final bounds = stroke.bounds.intersect(Rect.fromLTWH(
        0, 0, canvasWidth / rasterScale, canvasHeight / rasterScale));
    if (bounds.isEmpty) {
      return PawStreamingBrushMask(
          left: 0, top: 0, width: 0, height: 0, alpha: Uint8List(0));
    }
    // Include a physical-pixel halo for antialiasing at the conservative stroke
    // boundary. Geometry and texture coordinates remain in absolute logical
    // canvas space; only the output target is translated to this dirty origin.
    const antialiasHaloPixels = 2;
    final left = math.max(
      0,
      (bounds.left * rasterScale).floor() - antialiasHaloPixels,
    );
    final top = math.max(
      0,
      (bounds.top * rasterScale).floor() - antialiasHaloPixels,
    );
    final right = math.min(
      canvasWidth,
      (bounds.right * rasterScale).ceil() + antialiasHaloPixels,
    );
    final bottom = math.min(
      canvasHeight,
      (bounds.bottom * rasterScale).ceil() + antialiasHaloPixels,
    );
    final dirtyWidth = right - left;
    final dirtyHeight = bottom - top;
    final logicalSize =
        Size(canvasWidth / rasterScale, canvasHeight / rasterScale);
    final ownsCache = renderCache == null;
    final cache = renderCache ??
        PawStreamingDabRenderCache(
          logicalSize: logicalSize,
          sealedRasterScale: math.max(1, rasterScale),
        );
    try {
      final recorder = ui.PictureRecorder();
      ui.Picture? picture;
      ui.Image? image;
      try {
        try {
          // Rasterize at the same full-canvas origin and extent used by the
          // live overlay. A cropped Skia surface can differ by one AA level at
          // identical geometry, which would make the commit carrier visibly
          // non-identical. Crop bytes only after the shared full-frame render.
          final canvas = Canvas(recorder)..scale(rasterScale);
          cache.bindLogicalSize(logicalSize);
          cache.paint(canvas, stroke, targetRasterScale: rasterScale);
        } finally {
          picture = recorder.endRecording();
        }
        image = await picture.toImage(canvasWidth, canvasHeight);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
        if (bytes == null) {
          throw StateError('Dab mask image readback returned no pixel data.');
        }
        final fullRgba = bytes.buffer.asUint8List();
        final rgba = Uint8List(dirtyWidth * dirtyHeight * 4);
        final alpha = Uint8List(dirtyWidth * dirtyHeight);
        for (var localY = 0; localY < dirtyHeight; localY++) {
          final sourceStart = ((top + localY) * canvasWidth + left) * 4;
          final targetStart = localY * dirtyWidth * 4;
          rgba.setRange(
            targetStart,
            targetStart + dirtyWidth * 4,
            fullRgba,
            sourceStart,
          );
          for (var localX = 0; localX < dirtyWidth; localX++) {
            alpha[localY * dirtyWidth + localX] =
                rgba[(localY * dirtyWidth + localX) * 4 + 3];
          }
        }
        return PawStreamingBrushMask(
            left: left,
            top: top,
            width: dirtyWidth,
            height: dirtyHeight,
            alpha: alpha,
            rgba: Uint8List.fromList(rgba));
      } finally {
        image?.dispose();
        picture?.dispose();
      }
    } finally {
      if (ownsCache) cache.dispose();
    }
  }
}
