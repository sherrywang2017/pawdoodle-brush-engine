part of '../../streaming_dab_brush.dart';

class _PawDabAtlasBatch {
  const _PawDabAtlasBatch({
    required this.transforms,
    required this.rects,
    required this.colors,
  });

  final List<ui.RSTransform> transforms;
  final List<Rect> rects;
  final List<Color> colors;

  PawDabBatchCommandKind get kind => PawDabBatchCommandKind.drawAtlas;

  void paint(Canvas canvas, PawDabResource resource) {
    canvas.drawAtlas(
      resource.atlas,
      transforms,
      rects,
      colors,
      // drawAtlas treats the atlas image as source and each color as
      // destination. dstIn therefore keeps the stroke RGB and multiplies
      // its alpha by the pre-baked atlas coverage.
      BlendMode.dstIn,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }
}

class _PawDabVerticesBatch {
  const _PawDabVerticesBatch({
    required this.vertices,
    this.applyTexture = true,
    this.isAntiAlias = true,
    this.bounds = Rect.zero,
  });

  final ui.Vertices vertices;
  final bool applyTexture;
  final bool isAntiAlias;
  final Rect bounds;

  PawDabBatchCommandKind get kind => PawDabBatchCommandKind.drawVertices;

  void paint(Canvas canvas, PawDabResource resource) {
    final paint = Paint()..isAntiAlias = isAntiAlias;
    if (applyTexture) paint.shader = resource.textureShader;
    canvas.drawVertices(
      vertices,
      applyTexture ? BlendMode.dstIn : BlendMode.dst,
      paint,
    );
  }

  void dispose() => vertices.dispose();
}
