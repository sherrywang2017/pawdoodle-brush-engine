import 'dart:typed_data';
import 'dart:ui';

import 'brush_emission_segment.dart';
import 'smooth_stroke.dart';
import 'streaming_stroke_modeler.dart';

enum PawStreamingCompositeOperation { paint, erase }

/// Converts modeled centerline commands into the immutable hand-off shared by
/// the active preview and the final material renderer.
List<PawBrushEmissionSegment> pawBrushEmissionSegmentsFromCommands(
  Iterable<PawStreamingSegmentCommand> commands,
) =>
    List<PawBrushEmissionSegment>.unmodifiable(
      commands.map(PawBrushEmissionSegment.fromCommand),
    );

/// Short alias for call sites that describe the operation as generation.
List<PawBrushEmissionSegment> pawGenerateBrushEmissionSegments(
  Iterable<PawStreamingSegmentCommand> commands,
) =>
    pawBrushEmissionSegmentsFromCommands(commands);

double pawStreamingPhysicalTargetRasterScale({
  required double devicePixelRatio,
  required Size outputSize,
  required Size logicalSize,
}) {
  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) {
    throw ArgumentError.value(
      devicePixelRatio,
      'devicePixelRatio',
      'must be finite and greater than zero',
    );
  }
  if (!outputSize.width.isFinite ||
      !outputSize.height.isFinite ||
      !logicalSize.width.isFinite ||
      !logicalSize.height.isFinite ||
      outputSize.width <= 0 ||
      outputSize.height <= 0 ||
      logicalSize.width <= 0 ||
      logicalSize.height <= 0) {
    throw ArgumentError(
        'Output and logical sizes must be finite and positive.');
  }
  final widthScale = outputSize.width / logicalSize.width;
  final heightScale = outputSize.height / logicalSize.height;
  return devicePixelRatio *
      (widthScale > heightScale ? widthScale : heightScale);
}

abstract interface class PawStreamingBrushStroke {
  PawStrokeTextureSeed get seed;
  Color get color;
  double get brushSize;
  double get opacity;
  int get revision;
  bool get isEmpty;
  bool get isFrozen;
  Rect get bounds;

  bool appendSample(DrawingInputSample sample);

  void freeze();
}

/// Optional finite material evolution. Geometry is never advanced by this
/// clock. Freezing a stroke also freezes the currently displayed material.
abstract interface class PawTemporalBrushStroke {
  bool get hasUnsettledMaterial;
  bool advanceMaterialClock(Duration elapsed);
}

/// Optional causal-model metrics exposed by streaming strokes for diagnostics.
/// The rendering contract does not depend on these counters.
abstract interface class PawStreamingBrushRuntimeMetrics {
  int get lastModelStepCount;
  int get sealedSegmentCount;
  int get provisionalSegmentCount;
}

/// Optional raw-input and ownership diagnostics for the causal runtime.
abstract interface class PawStreamingInputRuntimeMetrics {
  int get rawInputSampleCount;
  bool get inputStarved;
  int get largestInputGapMicros;
  double get largestInputDistance;
  int get stableCenterlineSegmentCount;
  int get mutableCenterlineSegmentCount;
  int get predictionSegmentCount;
}

/// Optional immutable geometry source for the lightweight PointerMove
/// preview. Implementations expose modeled centerline commands only; material
/// execution remains owned by the commit interaction.
abstract interface class PawStreamingBrushPreviewSource {
  Iterable<PawStreamingSegmentCommand> get previewSegments;
  Offset? get previewStartPosition;
}

/// Optional geometry boundary used only after an explicit Draw-and-Hold
/// request. Material renderers continue to consume their existing emission
/// contract and never classify or refine the stroke themselves.
abstract interface class PawHeldStrokeAssistTarget {
  void replaceWithAssistedCenterline(
    Iterable<PawStreamingSegmentCommand> segments,
  );

  void sealAssistedCenterlineAsDisplayed();
}

extension PawStreamingBrushPreviewEmissionSource
    on PawStreamingBrushPreviewSource {
  /// Materializes the immutable preview hand-off without exposing a mutable
  /// modeler or renderer to the presentation layer.
  List<PawBrushEmissionSegment> get previewEmissionSegments =>
      pawBrushEmissionSegmentsFromCommands(previewSegments);
}

abstract interface class PawStreamingBrushRenderCache {
  bool get isDisposed;

  void dispose();
}

class PawStreamingBrushMask {
  const PawStreamingBrushMask({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.alpha,
    this.rgba,
  })  : assert(width >= 0),
        assert(height >= 0),
        assert(alpha.length == width * height),
        assert(rgba == null || rgba.length == width * height * 4);

  final int left;
  final int top;
  final int width;
  final int height;
  final Uint8List alpha;

  /// Exact straight RGBA material pixels when the renderer can provide them.
  /// Erasers consume [alpha]; paint commits prefer this payload so texture and
  /// low-alpha material color are not reconstructed from a generic base color.
  final Uint8List? rgba;
}

/// Shared backend contract for painting and committing streaming strokes.
///
/// [PawStreamingBrushMask.alpha] contains the complete source alpha emitted by
/// the active renderer, including brush and color opacity. Committers must use
/// an opaque source color so that alpha is not multiplied a second time.
abstract interface class PawStreamingBrushRenderer<
    TStroke extends PawStreamingBrushStroke,
    TCache extends PawStreamingBrushRenderCache> {
  void paint({
    required Canvas canvas,
    required Size outputSize,
    required Size logicalSize,
    required double physicalTargetRasterScale,
    required TStroke stroke,
    TCache? renderCache,
    Offset translation = Offset.zero,
  });

  Future<PawStreamingBrushMask> rasterize({
    required TStroke stroke,
    required int canvasWidth,
    required int canvasHeight,
    required double rasterScale,
    TCache? renderCache,
  });
}

abstract interface class PawStreamingBrushInteraction {
  PawStreamingBrushStroke get stroke;
  PawStreamingCompositeOperation get compositeOperation;
  bool get isDisposed;

  bool appendSample(DrawingInputSample sample);

  void paint({
    required Canvas canvas,
    required Size outputSize,
    required Size logicalSize,
    required double physicalTargetRasterScale,
    Offset translation = Offset.zero,
  });

  Future<PawStreamingBrushMask> rasterize({
    required int canvasWidth,
    required int canvasHeight,
    required double rasterScale,
  });

  void dispose();
}

class PawStreamingBrushInteractionBinding<
        TStroke extends PawStreamingBrushStroke,
        TCache extends PawStreamingBrushRenderCache>
    implements PawStreamingBrushInteraction {
  PawStreamingBrushInteractionBinding({
    required this.stroke,
    required this.renderer,
    required this.activeRenderCache,
    this.compositeOperation = PawStreamingCompositeOperation.paint,
  }) {
    if (activeRenderCache.isDisposed) {
      throw StateError('Streaming active render cache is already disposed.');
    }
  }

  @override
  final TStroke stroke;
  final PawStreamingBrushRenderer<TStroke, TCache> renderer;
  final TCache activeRenderCache;
  @override
  final PawStreamingCompositeOperation compositeOperation;
  bool _ownsActiveRenderCache = true;
  bool _disposed = false;

  /// Transfers the exact live presentation cache to a checkpoint interaction.
  ///
  /// The source binding remains safe to dispose, but no longer disposes the
  /// transferred cache. This is a move, not shared ownership or a cache copy.
  TCache transferActiveRenderCache() {
    if (_disposed) {
      throw StateError('Streaming interaction is already disposed.');
    }
    if (!_ownsActiveRenderCache || activeRenderCache.isDisposed) {
      throw StateError('Streaming render cache ownership was already moved.');
    }
    _ownsActiveRenderCache = false;
    return activeRenderCache;
  }

  bool get ownsActiveRenderCache => _ownsActiveRenderCache && !_disposed;

  @override
  bool get isDisposed =>
      _disposed || !_ownsActiveRenderCache || activeRenderCache.isDisposed;

  @override
  bool appendSample(DrawingInputSample sample) {
    _ensureUsable();
    return stroke.appendSample(sample);
  }

  @override
  void paint({
    required Canvas canvas,
    required Size outputSize,
    required Size logicalSize,
    required double physicalTargetRasterScale,
    Offset translation = Offset.zero,
  }) {
    _ensureUsable();
    renderer.paint(
      canvas: canvas,
      outputSize: outputSize,
      logicalSize: logicalSize,
      physicalTargetRasterScale: physicalTargetRasterScale,
      stroke: stroke,
      renderCache: activeRenderCache,
      translation: translation,
    );
  }

  @override
  Future<PawStreamingBrushMask> rasterize({
    required int canvasWidth,
    required int canvasHeight,
    required double rasterScale,
  }) {
    _ensureUsable();
    return renderer.rasterize(
      stroke: stroke,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      rasterScale: rasterScale,
      renderCache: activeRenderCache,
    );
  }

  void _ensureUsable() {
    if (isDisposed) {
      throw StateError(
          'Streaming interaction no longer owns its render cache.');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsActiveRenderCache) activeRenderCache.dispose();
    _ownsActiveRenderCache = false;
  }
}
