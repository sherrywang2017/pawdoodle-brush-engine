import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Packs continuous hair cross-sections directly into native vertex buffers.
/// Three vertices carry the same tent coverage as the list-based emitter.
class PawHairVertexBuffer {
  Float32List _positions = Float32List(3072);
  Float32List _texture = Float32List(3072);
  Int32List _colors = Int32List(1536);
  Uint16List _indices = Uint16List(6144);
  int vertexCount = 0, indexCount = 0;
  double _left = double.infinity, _top = double.infinity;
  double _right = double.negativeInfinity, _bottom = double.negativeInfinity;
  double xx = 0, xy = 0, xa = 0, xn = 0;
  double yx = 0, yy = 0, ya = 0, yn = 0;

  ui.Rect get bounds => vertexCount == 0
      ? ui.Rect.zero
      : ui.Rect.fromLTRB(_left, _top, _right, _bottom);

  void reset() {
    vertexCount = indexCount = 0;
    _left = _top = double.infinity;
    _right = _bottom = double.negativeInfinity;
    xx = xy = xa = xn = yx = yy = ya = yn = 0;
  }

  int _hairStart = 0;

  /// Reserve a complete strand once, then submit its two coverage bands as
  /// indexed strips. Adjacent triangles share indices as well as vertices.
  void beginHair(int sections) {
    final requiredVertices = vertexCount + sections * 3;
    final requiredIndices = indexCount + sections * 4 + 4;
    if (requiredVertices > 65535) {
      throw StateError('Hair command exceeds the native vertex index range');
    }
    _hairStart = vertexCount;
    if (requiredVertices > _colors.length) {
      final capacity =
          math.min(65535, math.max(requiredVertices, _colors.length * 2));
      _positions = Float32List(capacity * 2)
        ..setRange(0, vertexCount * 2, _positions);
      _texture = Float32List(capacity * 2)
        ..setRange(0, vertexCount * 2, _texture);
      _colors = Int32List(capacity)..setRange(0, vertexCount, _colors);
    }
    if (requiredIndices > _indices.length) {
      _indices = Uint16List(math.max(requiredIndices, _indices.length * 2))
        ..setRange(0, indexCount, _indices);
    }
  }

  void endHair() {
    final indices = _indices;
    var at = indexCount;
    for (var band = 0; band < 2; band++) {
      final first = _hairStart + band + 1;
      if (at > 0) {
        indices[at] = indices[at - 1];
        indices[at + 1] = first;
        at += 2;
      }
      for (var row = _hairStart; row < vertexCount; row += 3) {
        // Preserve the original diagonal: previous left -> current right.
        indices[at++] = row + band + 1;
        indices[at++] = row + band;
      }
    }
    indexCount = at;
  }

  void addSection(
      {required double x,
      required double y,
      required double nx,
      required double ny,
      required double width,
      required double softness,
      required double arc,
      required double across,
      required int rgb,
      required double alpha}) {
    final support = width / 2 + .45;
    final half = support + softness;
    final peak = (width / support).clamp(0.0, 1.0) * support / half;
    final centerColor =
        ((alpha * peak * 255).round().clamp(0, 255) << 24) | rgb;
    // A section is a straight crossbar; its two endpoints bound the middle.
    // Update command bounds once instead of twelve min/max calls per section.
    final extentX = (nx * half).abs(), extentY = (ny * half).abs();
    _left = math.min(_left, x - extentX);
    _right = math.max(_right, x + extentX);
    _top = math.min(_top, y - extentY);
    _bottom = math.max(_bottom, y + extentY);
    for (var side = -1; side <= 1; side++) {
      final offset = side * half;
      final vx = x + nx * offset, vy = y + ny * offset;
      final v = vertexCount++, k = v * 2;
      _positions[k] = vx;
      _positions[k + 1] = vy;
      _texture[k] = xx * vx + xy * vy + xa * arc + xn * (across + offset);
      _texture[k + 1] = yx * vx + yy * vy + ya * arc + yn * (across + offset);
      _colors[v] = side == 0 ? centerColor : rgb;
    }
  }

  ui.Vertices build() => ui.Vertices.raw(ui.VertexMode.triangleStrip,
      Float32List.sublistView(_positions, 0, vertexCount * 2),
      textureCoordinates: Float32List.sublistView(_texture, 0, vertexCount * 2),
      colors: Int32List.sublistView(_colors, 0, vertexCount),
      indices: Uint16List.sublistView(_indices, 0, indexCount));
}
