part of '../../streaming_dab_brush.dart';

abstract final class _DabRasterTexture {
  static ui.Image _createRasterTexture({
    required ui.Image baseTexture,
    required PawPreparedBrushRasterProgram rasterProgram,
  }) {
    final rasterWidth = rasterProgram.highFrequencyRasterWidth ?? 64;
    final rasterHeight = rasterProgram.highFrequencyRasterHeight ?? 64;
    final picture = _DabRasterTexture._recordRasterTexture(
      baseTexture: baseTexture,
      rasterProgram: rasterProgram,
    );
    try {
      return picture.toImageSync(rasterWidth, rasterHeight);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image> _createRasterTextureAsync({
    required ui.Image baseTexture,
    required PawPreparedBrushRasterProgram rasterProgram,
  }) async {
    final rasterWidth = rasterProgram.highFrequencyRasterWidth ?? 64;
    final rasterHeight = rasterProgram.highFrequencyRasterHeight ?? 64;
    final picture = _DabRasterTexture._recordRasterTexture(
      baseTexture: baseTexture,
      rasterProgram: rasterProgram,
    );
    try {
      return await picture.toImage(rasterWidth, rasterHeight);
    } finally {
      picture.dispose();
    }
  }

  static ui.Picture _recordRasterTexture({
    required ui.Image baseTexture,
    required PawPreparedBrushRasterProgram rasterProgram,
  }) {
    final rasterWidth = rasterProgram.highFrequencyRasterWidth ?? 64;
    final rasterHeight = rasterProgram.highFrequencyRasterHeight ?? 64;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final baseShader = ui.ImageShader(
      baseTexture,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.none,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, rasterWidth.toDouble(), rasterHeight.toDouble()),
      Paint()..shader = baseShader,
    );
    baseShader.dispose();
    final coveragePoints = <List<Offset>>[
      for (var alpha = 0; alpha < 256; alpha++) <Offset>[],
    ];
    final maskPaint = Paint()
      ..isAntiAlias = false
      ..blendMode = BlendMode.dstIn
      ..strokeWidth = 1;
    for (var y = 0; y < rasterHeight; y++) {
      final canvasPeriod = rasterProgram.highFrequencyCanvasPeriod ?? 64;
      final canvasY = (y + .5) / rasterHeight * canvasPeriod;
      for (var x = 0; x < rasterWidth; x++) {
        final canvasX = (x + .5) / rasterWidth * canvasPeriod;
        final coverage = rasterProgram.sampleHighFrequencyCoverage(
          canvasX: canvasX,
          canvasY: canvasY,
        );
        final alpha = (coverage * 255).round().clamp(0, 255);
        coveragePoints[alpha].add(Offset(x + .5, y + .5));
      }
    }
    for (var alpha = 0; alpha < coveragePoints.length; alpha++) {
      final points = coveragePoints[alpha];
      if (points.isEmpty) continue;
      maskPaint.color = Colors.white.withAlpha(alpha);
      canvas.drawPoints(ui.PointMode.points, points, maskPaint);
    }
    return recorder.endRecording();
  }
}
