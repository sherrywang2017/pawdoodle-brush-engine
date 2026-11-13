import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import 'brush_performance_capture.dart';
import 'brush_preset.dart';
import 'drawing_raster.dart';
import 'pointer_input_capabilities.dart';
import 'smooth_stroke.dart';
import 'streaming_brush_engine.dart';
import 'streaming_dab_brush.dart';

class PawBrushBackendDescriptor {
  const PawBrushBackendDescriptor({
    required this.backendId,
    required this.engineLabel,
    required this.toolLabel,
    required this.programLabel,
    required this.representationFamily,
    required this.material,
    this.overrideLabel,
  });

  final String backendId;
  final String engineLabel;
  final String toolLabel;
  final String programLabel;
  final String representationFamily;
  final String material;
  final String? overrideLabel;
}

class PawStreamingBrushStart {
  const PawStreamingBrushStart({
    required this.interaction,
    this.performanceCapture,
  });

  final PawStreamingBrushInteraction interaction;
  final PawDabPerformanceCapture? performanceCapture;
}

abstract interface class PawStreamingBrushBackend {
  PawBrushBackendDescriptor get descriptor;

  PawStreamingBrushStart start({
    required PawStrokeTextureSeed seed,
    required Color color,
    required double baseSize,
    required Size logicalSize,
    required double rasterScale,
    required DrawingInputSample initialSample,
    required PawStreamingCompositeOperation compositeOperation,
    required bool capturePerformance,
  });

  PawStreamingBrushInteraction checkpoint({
    required PawStreamingBrushInteraction source,
    required Size logicalSize,
    required double rasterScale,
  });
}

enum PawBrushResourcePreparationState { notPrepared, preparing, ready, failed }

@immutable
class PawBrushResourcePreparationStatus {
  const PawBrushResourcePreparationStatus({
    required this.state,
    this.error,
    this.stackTrace,
  });

  const PawBrushResourcePreparationStatus.notPrepared()
    : this(state: PawBrushResourcePreparationState.notPrepared);

  final PawBrushResourcePreparationState state;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isReady => state == PawBrushResourcePreparationState.ready;
  bool get isPreparing => state == PawBrushResourcePreparationState.preparing;
  bool get hasFailed => state == PawBrushResourcePreparationState.failed;
}

typedef PawBrushResourceMaterializer =
    Future<void> Function(PawCompiledBrushPreset preset);

class PawBrushResourcePreparationController extends ChangeNotifier {
  PawBrushResourcePreparationController({
    PawBrushResourceMaterializer? materializer,
  }) : _materializer = materializer ?? _materializePreset;

  static final PawBrushResourcePreparationController shared =
      PawBrushResourcePreparationController();

  final PawBrushResourceMaterializer _materializer;
  final Map<DrawingTool, _PawBrushPreparationEntry> _entries =
      <DrawingTool, _PawBrushPreparationEntry>{};

  PawBrushResourcePreparationStatus statusFor(DrawingTool tool) =>
      _entries[tool]?.status ??
      const PawBrushResourcePreparationStatus.notPrepared();

  Future<void> prepare(DrawingTool tool) {
    final current = _entries[tool];
    if (current?.state == PawBrushResourcePreparationState.preparing) {
      return current!.future!;
    }
    if (statusFor(tool).isReady) return Future<void>.value();

    final preset = PawBrushPresetCatalog.forTool(tool);
    late final Future<void> future;
    future = _prepare(tool, preset);
    _entries[tool] = _PawBrushPreparationEntry.preparing(future);
    notifyListeners();
    return future;
  }

  Future<void> prewarm({DrawingTool? preferredTool}) async {
    final order = <DrawingTool>[
      DrawingTool.roundBrush,
      if (preferredTool != null && preferredTool != DrawingTool.roundBrush)
        preferredTool,
      DrawingTool.inkBrush,
      DrawingTool.crayon,
      DrawingTool.furBrush,
      DrawingTool.softBrush,
      DrawingTool.marker,
      DrawingTool.eraser,
    ];
    final seen = <DrawingTool>{};
    for (final tool in order) {
      if (!seen.add(tool)) continue;
      await Future<void>.value();
      try {
        await prepare(tool);
      } catch (error, stackTrace) {
        debugPrint('Paw brush prewarm failed for ${tool.name}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  void invalidateForHotReload() {
    _entries.clear();
    notifyListeners();
  }

  @visibleForTesting
  void debugReset() => invalidateForHotReload();

  Future<void> _prepare(DrawingTool tool, PawCompiledBrushPreset preset) async {
    try {
      await Future<void>.value();
      await _materializer(preset);
      _entries[tool] = _PawBrushPreparationEntry.ready();
      notifyListeners();
    } catch (error, stackTrace) {
      _entries[tool] = _PawBrushPreparationEntry.failed(error, stackTrace);
      notifyListeners();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static Future<void> _materializePreset(PawCompiledBrushPreset preset) =>
      PawDabResource.prepareAsync(
        preset.definition,
        rasterProgram: preset.rasterProgram,
      );
}

class _PawBrushPreparationEntry {
  _PawBrushPreparationEntry.preparing(this.future)
    : state = PawBrushResourcePreparationState.preparing,
      error = null,
      stackTrace = null;

  _PawBrushPreparationEntry.ready()
    : state = PawBrushResourcePreparationState.ready,
      future = null,
      error = null,
      stackTrace = null;

  _PawBrushPreparationEntry.failed(this.error, this.stackTrace)
    : state = PawBrushResourcePreparationState.failed,
      future = null;

  final PawBrushResourcePreparationState state;
  final Future<void>? future;
  final Object? error;
  final StackTrace? stackTrace;

  PawBrushResourcePreparationStatus get status =>
      PawBrushResourcePreparationStatus(
        state: state,
        error: error,
        stackTrace: stackTrace,
      );
}

class PawDabStreamingBackend implements PawStreamingBrushBackend {
  PawDabStreamingBackend(this.tool) : _authoredPreset = null;

  PawDabStreamingBackend.forPreset(PawCompiledBrushPreset preset)
    : tool = DrawingTool.roundBrush,
      _authoredPreset = preset;

  final DrawingTool tool;
  final PawCompiledBrushPreset? _authoredPreset;
  PawCompiledBrushPreset get _preset =>
      _authoredPreset ?? PawBrushPresetCatalog.forTool(tool);

  static void prepareTool(DrawingTool tool) {
    final preset = PawBrushPresetCatalog.forTool(tool);
    PawDabResource.prepare(
      preset.definition,
      rasterProgram: preset.rasterProgram,
    );
  }

  @override
  PawBrushBackendDescriptor get descriptor {
    final kernelKind = _preset.kernelKind;
    return PawBrushBackendDescriptor(
      backendId: 'prepared-stamp',
      engineLabel: 'PREPARED STAMP',
      toolLabel: _authoredPreset?.definition.id ?? tool.name.toUpperCase(),
      programLabel: 'unified_v1',
      representationFamily: kernelKind.name,
      material: 'production',
    );
  }

  @override
  PawStreamingBrushStart start({
    required PawStrokeTextureSeed seed,
    required Color color,
    required double baseSize,
    required Size logicalSize,
    required double rasterScale,
    required DrawingInputSample initialSample,
    required PawStreamingCompositeOperation compositeOperation,
    required bool capturePerformance,
  }) {
    final preset = _preset;
    final stroke = preset.createStroke(
      seed: seed,
      color: color,
      baseSize: baseSize,
    )..appendSample(initialSample);
    final performanceCapture =
        capturePerformance &&
            PawDabPerformanceCapture.supportedBrushIds.contains(
              stroke.definition.id,
            )
        ? PawDabPerformanceCapture(
            brushId: stroke.definition.id,
            brushRevision: stroke.definition.revision,
            brushSize: stroke.brushSize,
            logicalSize: logicalSize,
            rasterScale: rasterScale,
            initialRevision: stroke.revision,
            resamplingEnabled: GestureBinding.instance.resamplingEnabled,
            samplingOffset: GestureBinding.instance.samplingOffset,
            coalescedInputSupported: pawCoalescedInputSupported,
            pointerRawUpdateSupported: pawPointerRawUpdateSupported,
            runtimeTarget: _pawRuntimeTarget,
          )
        : null;
    return PawStreamingBrushStart(
      interaction:
          PawStreamingBrushInteractionBinding<
            PawStreamingDabStroke,
            PawStreamingDabRenderCache
          >(
            stroke: stroke,
            renderer: const PawStreamingDabRenderer(),
            activeRenderCache: _createCache(
              logicalSize: logicalSize,
              rasterScale: rasterScale,
              performanceCapture: performanceCapture,
            ),
            compositeOperation: compositeOperation,
          ),
      performanceCapture: performanceCapture,
    );
  }

  @override
  PawStreamingBrushInteraction checkpoint({
    required PawStreamingBrushInteraction source,
    required Size logicalSize,
    required double rasterScale,
  }) {
    final stroke = source.stroke;
    if (stroke is! PawStreamingDabStroke ||
        source
            is! PawStreamingBrushInteractionBinding<
              PawStreamingDabStroke,
              PawStreamingDabRenderCache
            >) {
      throw StateError('Prepared-stamp backend received another stroke type.');
    }
    final transferWatch = Stopwatch()..start();
    final cache = source.transferActiveRenderCache();
    transferWatch.stop();
    cache.recordOwnershipTransfer(transferWatch.elapsedMicroseconds);
    return PawStreamingBrushInteractionBinding<
      PawStreamingDabStroke,
      PawStreamingDabRenderCache
    >(
      stroke: stroke,
      renderer: const PawStreamingDabRenderer(),
      activeRenderCache: cache..bindLogicalSize(logicalSize),
      compositeOperation: source.compositeOperation,
    );
  }

  PawStreamingDabRenderCache _createCache({
    required Size logicalSize,
    required double rasterScale,
    PawDabPerformanceCapture? performanceCapture,
  }) => PawStreamingDabRenderCache(
    logicalSize: logicalSize,
    sealedRasterScale: math.max(1.0, rasterScale),
    performanceCapture: performanceCapture,
    compactSealedPictures: false,
  );
}

String get _pawRuntimeTarget => kIsWeb
    ? 'flutter-web'
    : defaultTargetPlatform == TargetPlatform.iOS
    ? 'flutter-native-ios'
    : 'flutter-native-${defaultTargetPlatform.name}';

abstract final class PawBrushBackendCatalog {
  static bool usesPreparedDabBackend(DrawingTool tool, {Object? engineMode}) =>
      true;

  static PawStreamingBrushBackend forTool(
    DrawingTool tool, {
    Object? engineMode,
  }) => PawDabStreamingBackend(tool);
}
