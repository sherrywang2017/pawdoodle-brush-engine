part of '../../streaming_dab_brush.dart';

/// Runtime identity for one Prepared Full Tip placement.
///
/// The object is cache-owned scratch. Its identity is instance scalars, never
/// a high-density per-DAB vertex payload.
class PawStampInstance {
  int globalDabIndex = 0;
  double centerX = 0;
  double centerY = 0;
  double rotation = 0;
  double scale = 1;
  double widthScale = 1;
  double lengthScale = 1;
  double opacity = 1;
  int color = 0;
  int variant = 0;
  double sourceLeft = 0;
  double sourceTop = 0;
  double sourceWidth = 0;
  double sourceHeight = 0;
  double absoluteArc = 0;
  double pressure = 1;
  double? grainPhase;
  double directionX = 1;
  double directionY = 0;
  double pressureSize = 1;
}

class PawPreparedStampBufferDiagnostics {
  const PawPreparedStampBufferDiagnostics({
    required this.capacity,
    required this.growthCount,
    required this.liveBuffers,
    required this.pooledBuffers,
  });

  final int capacity;
  final int growthCount;
  final int liveBuffers;
  final int pooledBuffers;
}

class _PawMutableStampBatchBuffer {
  _PawMutableStampBatchBuffer(this.capacity)
      : positions = Float32List(capacity * 8),
        textureCoordinates = Float32List(capacity * 8),
        colors = Int32List(capacity * 4),
        indices = Uint16List(capacity * 6);

  final int capacity;
  final Float32List positions;
  final Float32List textureCoordinates;
  final Int32List colors;
  final Uint16List indices;
  int count = 0;

  void reset() => count = 0;

  void append(PawStampInstance instance, PawDabTemplateParameters template) {
    if (count >= capacity) throw StateError('Prepared stamp buffer overflow.');
    // Every source cell was recorded in this square logical domain, including
    // its transparent margin and soft falloff. Mapping a full cell onto just
    // the nominal footprint shrinks Soft by 3.2x and distorts authored ellipses.
    final preparedLength = template.logicalExtent;
    final preparedWidth = template.logicalExtent;
    final halfLength = instance.scale *
        instance.pressureSize *
        preparedLength *
        instance.lengthScale /
        2;
    final halfWidth = instance.scale *
        instance.pressureSize *
        preparedWidth *
        instance.widthScale /
        2;
    final dx = instance.directionX;
    final dy = instance.directionY;
    final nx = -dy;
    final ny = dx;
    final positionBase = count * 8;
    void setPosition(int corner, double along, double normal) {
      final offset = positionBase + corner * 2;
      positions[offset] = instance.centerX + dx * along + nx * normal;
      positions[offset + 1] = instance.centerY + dy * along + ny * normal;
    }

    setPosition(0, -halfLength, -halfWidth);
    setPosition(1, halfLength, -halfWidth);
    setPosition(2, halfLength, halfWidth);
    setPosition(3, -halfLength, halfWidth);

    final textureBase = count * 8;
    final right = instance.sourceLeft + instance.sourceWidth;
    final bottom = instance.sourceTop + instance.sourceHeight;
    textureCoordinates[textureBase] = instance.sourceLeft;
    textureCoordinates[textureBase + 1] = instance.sourceTop;
    textureCoordinates[textureBase + 2] = right;
    textureCoordinates[textureBase + 3] = instance.sourceTop;
    textureCoordinates[textureBase + 4] = right;
    textureCoordinates[textureBase + 5] = bottom;
    textureCoordinates[textureBase + 6] = instance.sourceLeft;
    textureCoordinates[textureBase + 7] = bottom;

    final colorBase = count * 4;
    for (var index = 0; index < 4; index++) {
      colors[colorBase + index] = instance.color;
    }
    final vertexBase = count * 4;
    final indexBase = count * 6;
    indices[indexBase] = vertexBase;
    indices[indexBase + 1] = vertexBase + 1;
    indices[indexBase + 2] = vertexBase + 2;
    indices[indexBase + 3] = vertexBase;
    indices[indexBase + 4] = vertexBase + 2;
    indices[indexBase + 5] = vertexBase + 3;
    count++;
  }
}

class _PawMutableStampBufferArena {
  final Map<int, List<_PawMutableStampBatchBuffer>> _pooled =
      <int, List<_PawMutableStampBatchBuffer>>{};
  int maximumCapacity = 0;
  int growthCount = 0;
  int liveBuffers = 0;

  _PawMutableStampBatchBuffer acquire(int capacity) {
    final safeCapacity = math.max(1, capacity);
    final pool = _pooled[safeCapacity];
    final buffer = pool != null && pool.isNotEmpty
        ? pool.removeLast()
        : _grow(safeCapacity);
    buffer.reset();
    liveBuffers++;
    return buffer;
  }

  _PawMutableStampBatchBuffer _grow(int capacity) {
    maximumCapacity = math.max(maximumCapacity, capacity);
    growthCount++;
    return _PawMutableStampBatchBuffer(capacity);
  }

  void release(_PawMutableStampBatchBuffer buffer) {
    buffer.reset();
    liveBuffers = math.max(0, liveBuffers - 1);
    (_pooled[buffer.capacity] ??= <_PawMutableStampBatchBuffer>[]).add(buffer);
  }

  PawPreparedStampBufferDiagnostics get diagnostics =>
      PawPreparedStampBufferDiagnostics(
        capacity: maximumCapacity,
        growthCount: growthCount,
        liveBuffers: liveBuffers,
        pooledBuffers: _pooled.values.fold<int>(
          0,
          (total, values) => total + values.length,
        ),
      );
}

class _PawPreparedStampBatch {
  _PawPreparedStampBatch({
    required this.vertices,
    required this.instanceCount,
    required _PawMutableStampBatchBuffer buffer,
    required _PawMutableStampBufferArena arena,
  })  : _buffer = buffer,
        _arena = arena;

  final ui.Vertices vertices;
  final int instanceCount;
  final _PawMutableStampBatchBuffer _buffer;
  final _PawMutableStampBufferArena _arena;
  bool _disposed = false;

  PawDabBatchCommandKind get kind => PawDabBatchCommandKind.drawPreparedStamp;

  void paint(Canvas canvas, PawDabResource resource) {
    canvas.drawVertices(
      vertices,
      BlendMode.dstIn,
      Paint()..shader = resource.atlasShader,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    vertices.dispose();
    _arena.release(_buffer);
  }
}
