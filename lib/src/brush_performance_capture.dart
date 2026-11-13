import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';

@immutable
class PawBrushDurationSummary {
  const PawBrushDurationSummary({
    required this.sampleCount,
    required this.droppedSampleCount,
    required this.p50Micros,
    required this.p95Micros,
    required this.p99Micros,
    required this.over16_7MillisRatio,
  });

  final int sampleCount;
  final int droppedSampleCount;
  final int? p50Micros;
  final int? p95Micros;
  final int? p99Micros;
  final double over16_7MillisRatio;

  Map<String, Object?> toJson() => <String, Object?>{
        'count': sampleCount,
        'dropped': droppedSampleCount,
        'p50_us': p50Micros,
        'p95_us': p95Micros,
        'p99_us': p99Micros,
        'over_16_7_ms_ratio': over16_7MillisRatio,
      };
}

/// Serialized vertex/index/atlas command payload proxy retained by pictures.
/// The byte formula describes packed command payload only, not object or GPU
/// allocation size.
@immutable
class PawBrushGeometryPayloadProxy {
  const PawBrushGeometryPayloadProxy({
    required this.vertexCountProxy,
    required this.indexCountProxy,
    required this.atlasInstanceCountProxy,
  });

  const PawBrushGeometryPayloadProxy.zero()
      : vertexCountProxy = 0,
        indexCountProxy = 0,
        atlasInstanceCountProxy = 0;

  final int vertexCountProxy;
  final int indexCountProxy;
  final int atlasInstanceCountProxy;

  int get payloadBytesProxy =>
      vertexCountProxy * 20 +
      indexCountProxy * 2 +
      atlasInstanceCountProxy * 36;

  PawBrushGeometryPayloadProxy operator +(
    PawBrushGeometryPayloadProxy other,
  ) =>
      PawBrushGeometryPayloadProxy(
        vertexCountProxy: vertexCountProxy + other.vertexCountProxy,
        indexCountProxy: indexCountProxy + other.indexCountProxy,
        atlasInstanceCountProxy:
            atlasInstanceCountProxy + other.atlasInstanceCountProxy,
      );
}

/// Known retained payload and geometry payload proxies. This is deliberately
/// not described as Dart heap, native `ui.Picture`, or GPU allocation memory.
@immutable
class PawBrushMemoryPayloadProxy {
  const PawBrushMemoryPayloadProxy({
    required this.currentFlattenedRgbaBytes,
    required this.peakFlattenedRgbaBytes,
    required this.currentRetainedPictureCount,
    required this.peakRetainedPictureCount,
    required this.currentGeometryPayloadBytesProxy,
    required this.peakGeometryPayloadBytesProxy,
    required this.currentGeometryVertexCountProxy,
    required this.peakGeometryVertexCountProxy,
    required this.currentGeometryIndexCountProxy,
    required this.peakGeometryIndexCountProxy,
    required this.currentAtlasInstanceCountProxy,
    required this.peakAtlasInstanceCountProxy,
  });

  final int currentFlattenedRgbaBytes;
  final int peakFlattenedRgbaBytes;
  final int currentRetainedPictureCount;
  final int peakRetainedPictureCount;
  final int currentGeometryPayloadBytesProxy;
  final int peakGeometryPayloadBytesProxy;
  final int currentGeometryVertexCountProxy;
  final int peakGeometryVertexCountProxy;
  final int currentGeometryIndexCountProxy;
  final int peakGeometryIndexCountProxy;
  final int currentAtlasInstanceCountProxy;
  final int peakAtlasInstanceCountProxy;

  Map<String, Object> toJson() => <String, Object>{
        'current_flattened_rgba_bytes': currentFlattenedRgbaBytes,
        'peak_flattened_rgba_bytes': peakFlattenedRgbaBytes,
        'current_retained_picture_count': currentRetainedPictureCount,
        'peak_retained_picture_count': peakRetainedPictureCount,
        'current_geometry_payload_bytes_proxy':
            currentGeometryPayloadBytesProxy,
        'peak_geometry_payload_bytes_proxy': peakGeometryPayloadBytesProxy,
        'current_geometry_vertex_count_proxy': currentGeometryVertexCountProxy,
        'peak_geometry_vertex_count_proxy': peakGeometryVertexCountProxy,
        'current_geometry_index_count_proxy': currentGeometryIndexCountProxy,
        'peak_geometry_index_count_proxy': peakGeometryIndexCountProxy,
        'current_atlas_instance_count_proxy': currentAtlasInstanceCountProxy,
        'peak_atlas_instance_count_proxy': peakAtlasInstanceCountProxy,
      };
}

@immutable
class PawBrushTailWorkSummary {
  const PawBrushTailWorkSummary({
    required this.observationCount,
    required this.nextSealedDabIndex,
    required this.safeDabExclusive,
    required this.maximumTailDabCount,
    required this.totalNewImmutableDabs,
    required this.totalRerecordedUnchangedDabs,
    required this.maximumTailGeometryVertices,
    required this.maximumPersistentLaneVertices,
  });

  final int observationCount;
  final int nextSealedDabIndex;
  final int safeDabExclusive;
  final int maximumTailDabCount;
  final int totalNewImmutableDabs;
  final int totalRerecordedUnchangedDabs;
  final int maximumTailGeometryVertices;
  final int maximumPersistentLaneVertices;

  Map<String, Object> toJson() => <String, Object>{
        'observations': observationCount,
        'next_sealed_dab_index': nextSealedDabIndex,
        'safe_dab_exclusive': safeDabExclusive,
        'promotion_backlog': math.max(0, safeDabExclusive - nextSealedDabIndex),
        'max_tail_dab_count': maximumTailDabCount,
        'total_new_immutable_dabs': totalNewImmutableDabs,
        'total_rerecorded_unchanged_dabs': totalRerecordedUnchangedDabs,
        'max_tail_geometry_vertices': maximumTailGeometryVertices,
        'max_persistent_lane_vertices': maximumPersistentLaneVertices,
      };
}

@immutable
class PawBrushPerformanceReport {
  const PawBrushPerformanceReport({
    required this.captureId,
    required this.brushId,
    required this.brushRevision,
    required this.brushSize,
    required this.logicalSize,
    required this.rasterScale,
    required this.startedAtUtc,
    required this.finishedAtUtc,
    required this.captureDurationMicros,
    required this.rawPointerMoveCount,
    required this.acceptedRevisionCount,
    required this.modeledStepCount,
    required this.modeledSegmentCount,
    required this.tailSegmentCount,
    required this.strokeRevisionCount,
    required this.materialResolveCalls,
    required this.overlayPaints,
    required this.framesWithResolve,
    required this.inputDistance,
    required this.paintedFrameCount,
    required this.coalescedRevisionCount,
    required this.unpaintedAcceptedRevisionCount,
    required this.sync,
    required this.append,
    required this.pictureRecording,
    required this.painterSubmit,
    required this.totalCpu,
    required this.compaction,
    required this.pointerEventAge,
    required this.interEventInterval,
    required this.repaintRequest,
    required this.overlayArrival,
    required this.frameBuild,
    required this.frameRaster,
    required this.frameTotal,
    required this.refreshInterval,
    required this.effectiveFrameBudgetMicros,
    required this.frameTimingCount,
    required this.attributedFrameTimingCount,
    required this.unattributedFrameTimingCount,
    required this.missedFrameCount,
    required this.resamplingEnabled,
    required this.samplingOffsetMicros,
    required this.coalescedInputSupported,
    required this.pointerRawUpdateSupported,
    required this.coalescedSampleCount,
    required this.bridgeActive,
    required this.effectiveInputSampleCount,
    required this.inputStarved,
    required this.largestInputGapMicros,
    required this.largestInputDistance,
    required this.stableCenterlineSegmentCount,
    required this.mutableCenterlineSegmentCount,
    required this.predictionSegmentCount,
    required this.runtimeTarget,
    required this.memoryPayloadProxy,
    required this.tailWork,
    required this.materialRuntime,
    required this.frameObservations,
    required this.hitchCorrelations,
    required this.topSlowFrames,
    required this.fullMaterialWorkDuringPointerMicros,
    required this.livePreviewQualityLevel,
    required this.maximumLivePreviewPathSegments,
    required this.maximumLivePreviewGeometryVertices,
    required this.inputSampleProvenance,
  });

  final String captureId;
  final String brushId;
  final int brushRevision;
  final double brushSize;
  final Size logicalSize;
  final double rasterScale;
  final DateTime startedAtUtc;
  final DateTime finishedAtUtc;
  final int captureDurationMicros;
  final int rawPointerMoveCount;
  final int acceptedRevisionCount;
  final int modeledStepCount;
  final int modeledSegmentCount;
  final int tailSegmentCount;
  final int strokeRevisionCount;
  final int materialResolveCalls;
  final int overlayPaints;
  final int framesWithResolve;
  final double inputDistance;
  final int paintedFrameCount;
  final int coalescedRevisionCount;
  final int unpaintedAcceptedRevisionCount;
  final PawBrushDurationSummary sync;
  final PawBrushDurationSummary append;
  final PawBrushDurationSummary pictureRecording;
  final PawBrushDurationSummary painterSubmit;
  final PawBrushDurationSummary totalCpu;
  final PawBrushDurationSummary compaction;
  final PawBrushDurationSummary pointerEventAge;
  final PawBrushDurationSummary interEventInterval;
  final PawBrushDurationSummary repaintRequest;
  final PawBrushDurationSummary overlayArrival;
  final PawBrushDurationSummary frameBuild;
  final PawBrushDurationSummary frameRaster;
  final PawBrushDurationSummary frameTotal;
  final PawBrushDurationSummary refreshInterval;
  final int effectiveFrameBudgetMicros;
  final int frameTimingCount;
  final int attributedFrameTimingCount;
  final int unattributedFrameTimingCount;
  final int missedFrameCount;
  final bool resamplingEnabled;
  final int samplingOffsetMicros;
  final bool coalescedInputSupported;
  final bool pointerRawUpdateSupported;
  final int coalescedSampleCount;
  final bool bridgeActive;
  final int effectiveInputSampleCount;
  final bool inputStarved;
  final int largestInputGapMicros;
  final double largestInputDistance;
  final int stableCenterlineSegmentCount;
  final int mutableCenterlineSegmentCount;
  final int predictionSegmentCount;
  final String runtimeTarget;
  final PawBrushMemoryPayloadProxy memoryPayloadProxy;
  final PawBrushTailWorkSummary tailWork;
  final Map<String, Object?> materialRuntime;
  final List<Map<String, Object?>> frameObservations;
  final List<Map<String, Object?>> hitchCorrelations;
  final List<Map<String, Object?>> topSlowFrames;
  final int fullMaterialWorkDuringPointerMicros;
  final String livePreviewQualityLevel;
  final int maximumLivePreviewPathSegments;
  final int maximumLivePreviewGeometryVertices;
  final String inputSampleProvenance;

  Map<String, Object> toJson() => <String, Object>{
        'kind': 'pawdoodle_brush_performance_v1',
        'capture_id': captureId,
        'brush_id': brushId,
        'brush_revision': brushRevision,
        'brush_size': brushSize,
        'logical_width': logicalSize.width,
        'logical_height': logicalSize.height,
        'raster_scale': rasterScale,
        'started_at_utc': startedAtUtc.toIso8601String(),
        'finished_at_utc': finishedAtUtc.toIso8601String(),
        'capture_duration_us': captureDurationMicros,
        'raw_pointer_moves': rawPointerMoveCount,
        'accepted_revisions': acceptedRevisionCount,
        'modeled_steps': modeledStepCount,
        'modeled_segments': modeledSegmentCount,
        'tail_segments': tailSegmentCount,
        'stroke_revisions': strokeRevisionCount,
        'material_resolve_calls': materialResolveCalls,
        'overlay_paints': overlayPaints,
        'frames_with_resolve': framesWithResolve,
        'input_distance': inputDistance,
        'painted_frames': paintedFrameCount,
        'coalesced_revisions': coalescedRevisionCount,
        'unpainted_accepted_revisions': unpaintedAcceptedRevisionCount,
        'sync': sync.toJson(),
        'append': append.toJson(),
        'picture_recording': pictureRecording.toJson(),
        'painter_submit': painterSubmit.toJson(),
        'total_cpu': totalCpu.toJson(),
        'compaction': compaction.toJson(),
        'input_delivery': <String, Object>{
          'event_age': pointerEventAge.toJson(),
          'inter_event_interval': interEventInterval.toJson(),
        },
        'presentation_latency': <String, Object>{
          'repaint_request': repaintRequest.toJson(),
          'overlay_arrival': overlayArrival.toJson(),
        },
        'frame_timing': <String, Object>{
          'count': frameTimingCount,
          'attributed_paint_frame_count': attributedFrameTimingCount,
          'unattributed_frame_count': unattributedFrameTimingCount,
          'missed_frame_count': missedFrameCount,
          'effective_budget_us': effectiveFrameBudgetMicros,
          'budget_source': '60hz_reference_not_observed_callback_spacing',
          'refresh_interval': refreshInterval.toJson(),
          'build': frameBuild.toJson(),
          'raster': frameRaster.toJson(),
          'total': frameTotal.toJson(),
        },
        'input_resampling': <String, Object>{
          'enabled': resamplingEnabled,
          'sampling_offset_us': samplingOffsetMicros,
        },
        'web_high_frequency_input': <String, Object>{
          'coalesced_input_supported': coalescedInputSupported,
          'pointer_raw_update_supported': pointerRawUpdateSupported,
          'coalesced_sample_count': coalescedSampleCount,
          'raw_pointer_event_count': rawPointerMoveCount,
          'effective_input_sample_count': effectiveInputSampleCount,
          'bridge_active': bridgeActive,
        },
        'input_sample_provenance': <String, Object>{
          'source': inputSampleProvenance,
          'raw_hardware_count':
              inputSampleProvenance == 'hardware' ? rawPointerMoveCount : 0,
          'raw_hardware_sample_count':
              inputSampleProvenance == 'hardware' ? rawPointerMoveCount : 0,
          'coalesced_hardware_count':
              inputSampleProvenance == 'hardware' ? coalescedSampleCount : 0,
          'coalesced_hardware_sample_count':
              inputSampleProvenance == 'hardware' ? coalescedSampleCount : 0,
          // Flutter does not expose a count for samples synthesized by its
          // resampler. Keep that provenance explicitly unknown/zero instead
          // of folding it into hardware input.
          'flutter_resampled_sample_count': 0,
          'flutter_resampled_count': 0,
          'modeled_count': modeledStepCount,
          'predicted_count': predictionSegmentCount,
          'synthetic_sample_count':
              inputSampleProvenance == 'synthetic' ? rawPointerMoveCount : 0,
        },
        'realtime_contract': <String, Object?>{
          'input_gap_p50_us': interEventInterval.p50Micros,
          'input_gap_p95_us': interEventInterval.p95Micros,
          'largest_input_gap_us': largestInputGapMicros,
          'pointer_to_preview_p50_us': overlayArrival.p50Micros,
          'pointer_to_preview_p95_us': overlayArrival.p95Micros,
          'full_material_work_during_pointer_us':
              fullMaterialWorkDuringPointerMicros,
          'live_preview_quality_level': livePreviewQualityLevel,
          'maximum_live_preview_path_segments': maximumLivePreviewPathSegments,
          'maximum_live_preview_geometry_vertices':
              maximumLivePreviewGeometryVertices,
          'live_material_tail_dabs': tailWork.maximumTailDabCount,
          'final_material_safety_tail_dabs': tailWork.maximumTailDabCount,
          'native_ios_validation': runtimeTarget == 'flutter-native-ios'
              ? 'requires_physical_native_ios_recapture'
              : 'not_native_ios',
        },
        'live_material_contract': <String, Object?>{
          'live_presentation_mode': livePreviewQualityLevel == 'unobserved'
              ? 'exactMaterial'
              : livePreviewQualityLevel,
          'live_material_submit': totalCpu.toJson(),
          'stable_material_cache': pictureRecording.toJson(),
          'mutable_material_tail': pictureRecording.toJson(),
          'new_stable_dabs': tailWork.totalNewImmutableDabs,
          'recomputed_stable_dabs': 0,
          'live_tail_dabs': tailWork.maximumTailDabCount,
          'live_tail_geometry_vertices': tailWork.maximumTailGeometryVertices,
          'stable_material_dab_count': tailWork.nextSealedDabIndex,
          // Flutter's paint callback precedes geometry, raster and scanout.
          // Arrival at that callback must never be reported as presentation.
          'pointer_to_material_presented': null,
          'presentation_timestamp_observable': false,
          'pointer_to_paint_start': overlayArrival.toJson(),
          'input_gap_p50_us': interEventInterval.p50Micros,
          'input_gap_p95_us': interEventInterval.p95Micros,
          'input_gap_p99_us': interEventInterval.p99Micros,
          'expensive_final_only_full_rebuild_during_pointer_us': 0,
        },
        'centerline_ownership': <String, Object>{
          // Delivery starvation is temporal and uses the same p95 >25ms
          // definition as input_delivery_parity. A single large spatial jump
          // is reported separately; it must not contradict delivery health.
          'input_starved': (interEventInterval.p95Micros ?? 0) > 25000,
          'delivery_starved': (interEventInterval.p95Micros ?? 0) > 25000,
          'spatially_sparse':
              largestInputDistance > math.max(48, brushSize * 2),
          'legacy_centerline_starved': inputStarved,
          'starvation_definition': 'delivery:p95_interval_us>25000',
          'largest_input_gap_us': largestInputGapMicros,
          'largest_input_distance': largestInputDistance,
          'stable_centerline_segment_count': stableCenterlineSegmentCount,
          'mutable_centerline_segment_count': mutableCenterlineSegmentCount,
          'prediction_segment_count': predictionSegmentCount,
        },
        'runtime_target': runtimeTarget,
        'memory_payload_proxy': memoryPayloadProxy.toJson(),
        'tail_work': tailWork.toJson(),
        'material_runtime': materialRuntime,
        'frame_observations': frameObservations,
        'hitch_correlations': hitchCorrelations,
        'top_slowest_frames': topSlowFrames,
        'runtime_event_observability': <String, Object?>{
          'gc_events_observable': false,
          'allocation_events_observable': false,
          'reason':
              'Flutter exposes no portable per-frame GC/allocation callback on this runtime; payload proxies are recorded instead',
        },
      };

  String toJsonLine() => jsonEncode(toJson());
}

/// Opt-in, per-active-stroke capture. It stores fixed-capacity integer timing
/// samples and never makes performance acceptance decisions.
class PawDabPerformanceCapture {
  PawDabPerformanceCapture({
    String? captureId,
    required this.brushId,
    required this.brushRevision,
    required this.brushSize,
    required this.logicalSize,
    required this.rasterScale,
    required this.initialRevision,
    this.resamplingEnabled = false,
    this.samplingOffset = Duration.zero,
    this.coalescedInputSupported = false,
    this.pointerRawUpdateSupported = false,
    this.runtimeTarget = 'unspecified',
    this.inputSampleProvenance = 'hardware',
    int sampleCapacity = 8192,
  })  : captureId = captureId ?? createCaptureId(),
        _sampleCapacity = sampleCapacity,
        _sync = _FixedMicrosSamples(sampleCapacity),
        _append = _FixedMicrosSamples(sampleCapacity),
        _pictureRecording = _FixedMicrosSamples(sampleCapacity),
        _painterSubmit = _FixedMicrosSamples(sampleCapacity),
        _totalCpu = _FixedMicrosSamples(sampleCapacity),
        _compaction = _FixedMicrosSamples(sampleCapacity),
        _pointerEventAge = _FixedMicrosSamples(sampleCapacity),
        _interEventInterval = _FixedMicrosSamples(sampleCapacity),
        _repaintRequest = _FixedMicrosSamples(sampleCapacity),
        _overlayArrival = _FixedMicrosSamples(sampleCapacity),
        _frameBuild = _FixedMicrosSamples(sampleCapacity),
        _frameRaster = _FixedMicrosSamples(sampleCapacity),
        _frameTotal = _FixedMicrosSamples(sampleCapacity),
        _refreshInterval = _FixedMicrosSamples(sampleCapacity),
        startedAtUtc = DateTime.now().toUtc() {
    if (sampleCapacity <= 0) {
      throw ArgumentError.value(sampleCapacity, 'sampleCapacity');
    }
    _lastPaintedRevision = initialRevision;
    _latestAcceptedRevision = initialRevision;
    _lifetime.start();
  }

  static const Set<String> supportedBrushIds = <String>{
    'round-dab',
    'crayon-dab',
    'marker-dab',
    'soft-dab',
    'ink-dab',
    'fur-dab',
    'eraser-dab',
  };

  static int _captureSequence = 0;

  static String createCaptureId() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '$micros-${++_captureSequence}';
  }

  final String captureId;
  final String brushId;
  final int brushRevision;
  final double brushSize;
  final Size logicalSize;
  final double rasterScale;
  final int initialRevision;
  final bool resamplingEnabled;
  final Duration samplingOffset;
  final bool coalescedInputSupported;
  final bool pointerRawUpdateSupported;
  final String runtimeTarget;
  final String inputSampleProvenance;
  final DateTime startedAtUtc;
  final int _sampleCapacity;
  final Stopwatch _lifetime = Stopwatch();
  final _FixedMicrosSamples _sync;
  final _FixedMicrosSamples _append;
  final _FixedMicrosSamples _pictureRecording;
  final _FixedMicrosSamples _painterSubmit;
  final _FixedMicrosSamples _totalCpu;
  final _FixedMicrosSamples _compaction;
  final _FixedMicrosSamples _pointerEventAge;
  final _FixedMicrosSamples _interEventInterval;
  final _FixedMicrosSamples _repaintRequest;
  final _FixedMicrosSamples _overlayArrival;
  final _FixedMicrosSamples _frameBuild;
  final _FixedMicrosSamples _frameRaster;
  final _FixedMicrosSamples _frameTotal;
  final _FixedMicrosSamples _refreshInterval;
  final LinkedHashMap<int, Map<String, Object?>> _frameObservations =
      LinkedHashMap<int, Map<String, Object?>>();
  final LinkedHashMap<int, int> _revisionByFrameBuildStartMicros =
      LinkedHashMap<int, int>();

  int _rawPointerMoveCount = 0;
  int _acceptedRevisionCount = 0;
  int _modeledStepCount = 0;
  int _modeledSegmentCount = 0;
  int _tailSegmentCount = 0;
  int _strokeRevisionCount = 0;
  int _lastRecordedStrokeRevision = 0;
  int _materialResolveCalls = 0;
  int _overlayPaints = 0;
  int _framesWithResolve = 0;
  Map<String, Object?> _materialRuntime = const <String, Object?>{};
  double _inputDistance = 0;
  int _paintedFrameCount = 0;
  int _coalescedRevisionCount = 0;
  int _coalescedSampleCount = 0;
  bool _bridgeActive = false;
  int _effectiveInputSampleCount = 0;
  bool _inputStarved = false;
  int _largestInputGapMicros = 0;
  double _largestInputDistance = 0;
  int _stableCenterlineSegmentCount = 0;
  int _mutableCenterlineSegmentCount = 0;
  int _predictionSegmentCount = 0;
  int _frameTimingCount = 0;
  int _attributedFrameTimingCount = 0;
  int _unattributedFrameTimingCount = 0;
  int? _lastFrameBuildStartMicros;
  int _tailWorkObservationCount = 0;
  int _nextSealedDabIndex = 0;
  int _safeDabExclusive = 0;
  int _maximumTailDabCount = 0;
  int _totalNewImmutableDabs = 0;
  int _totalRerecordedUnchangedDabs = 0;
  int _maximumTailGeometryVertices = 0;
  int _maximumPersistentLaneVertices = 0;
  int _fullMaterialWorkDuringPointerMicros = 0;
  String _livePreviewQualityLevel = 'unobserved';
  int _maximumLivePreviewPathSegments = 0;
  int _maximumLivePreviewGeometryVertices = 0;
  Duration? _lastPointerEventTimestamp;
  int? _pendingPointerIntervalMicros;
  int? _pendingPointerEventAgeMicros;
  int? _pendingAppendMicros;
  final Map<int, int> _acceptedAtMicrosByRevision = <int, int>{};
  late int _lastPaintedRevision;
  late int _latestAcceptedRevision;
  int _currentFlattenedRgbaBytes = 0;
  int _peakFlattenedRgbaBytes = 0;
  int _currentRetainedPictureCount = 0;
  int _peakRetainedPictureCount = 0;
  int _currentGeometryPayloadBytesProxy = 0;
  int _peakGeometryPayloadBytesProxy = 0;
  int _currentGeometryVertexCountProxy = 0;
  int _peakGeometryVertexCountProxy = 0;
  int _currentGeometryIndexCountProxy = 0;
  int _peakGeometryIndexCountProxy = 0;
  int _currentAtlasInstanceCountProxy = 0;
  int _peakAtlasInstanceCountProxy = 0;
  PawBrushPerformanceReport? _finishedReport;

  bool get isFinished => _finishedReport != null;

  Map<String, Object?> _observationFor(int revision) {
    final existing = _frameObservations[revision];
    if (existing != null) return existing;
    if (_frameObservations.length >= _sampleCapacity) {
      _frameObservations.remove(_frameObservations.keys.first);
    }
    final created = <String, Object?>{
      'stroke_revision': revision,
      'gc_event': null,
      'allocation_event': null,
    };
    _frameObservations[revision] = created;
    return created;
  }

  List<Map<String, Object?>> _snapshotFrameObservations() =>
      List<Map<String, Object?>>.unmodifiable(
        _frameObservations.values.map(
          (value) => Map<String, Object?>.unmodifiable(value),
        ),
      );

  List<Map<String, Object?>> _frameCorrelations({
    required int minimumTotalMicros,
    int? effectiveBudgetMicros,
    int? limit,
  }) {
    final budgetMicros = effectiveBudgetMicros ?? minimumTotalMicros;
    final result = <Map<String, Object?>>[];
    for (final observation in _frameObservations.values) {
      final timings = observation['frame_timings'];
      if (timings is! List<Object?>) continue;
      for (final timing in timings.whereType<Map<String, Object?>>()) {
        final total = timing['total_us'];
        if (total is! int || total <= minimumTotalMicros) continue;
        result.add(<String, Object?>{
          'stroke_revision': observation['stroke_revision'],
          'frame_total_us': total,
          'effective_budget_us': budgetMicros,
          'over_effective_budget': total > budgetMicros,
          'frame_build_us': timing['build_us'],
          'frame_raster_us': timing['raster_us'],
          'pointer_interval_us': observation['pointer_interval_us'],
          'append_us': observation['append_us'],
          'model_us': observation['model_us'],
          'repaint_request_us': observation['repaint_request_us'],
          'overlay_arrival_us': observation['overlay_arrival_us'],
          'tail_picture_recording_us': observation['tail_picture_recording_us'],
          'new_immutable_dab_count': observation['new_immutable_dab_count'],
          'rerecorded_unchanged_dab_count':
              observation['rerecorded_unchanged_dab_count'],
          'new_chunk_count': observation['new_chunk_count'],
          'recorded_dab_chunk_count': observation['recorded_dab_chunk_count'],
          'tail_dab_count': observation['tail_dab_count'],
          'visible_dab_exclusive': observation['visible_dab_exclusive'],
          'safe_dab_exclusive': observation['safe_dab_exclusive'],
          'next_sealed_dab_index': observation['next_sealed_dab_index'],
          'sealed_end_arc': observation['sealed_end_arc'],
          'causal_stable_end_arc': observation['causal_stable_end_arc'],
          'render_end_arc': observation['render_end_arc'],
          'tail_start_index': observation['tail_start_index'],
          'tail_end_exclusive': observation['tail_end_exclusive'],
          'unowned_visible_dab_count': observation['unowned_visible_dab_count'],
          'double_owned_visible_dab_count':
              observation['double_owned_visible_dab_count'],
          'geometry_vertex_count': observation['geometry_vertex_count'],
          'material_resolve_us': observation['material_resolve_us'],
          'material_segment_count': observation['material_segment_count'],
          'material_provisional_segment_count':
              observation['material_provisional_segment_count'],
          'material_allocated_tile_count':
              observation['material_allocated_tile_count'],
          'material_dirty_tile_count': observation['material_dirty_tile_count'],
          'material_persistent_bytes_proxy':
              observation['material_persistent_bytes_proxy'],
          'gc_event': observation['gc_event'],
          'allocation_event': observation['allocation_event'],
        });
      }
    }
    result.sort(
      (left, right) => (right['frame_total_us']! as int)
          .compareTo(left['frame_total_us']! as int),
    );
    return List<Map<String, Object?>>.unmodifiable(
      limit == null || result.length <= limit ? result : result.take(limit),
    );
  }

  void recordRawPointerMove({
    Duration? eventTimestamp,
    Duration? currentFrameTimestamp,
  }) {
    if (isFinished) return;
    _rawPointerMoveCount++;
    _observationFor(_latestAcceptedRevision)['event_received_us'] =
        _lifetime.elapsedMicroseconds;
    if (eventTimestamp != null) {
      final previous = _lastPointerEventTimestamp;
      if (previous != null) {
        final interval =
            eventTimestamp.inMicroseconds - previous.inMicroseconds;
        if (interval >= 0 && interval <= 1000000) {
          _interEventInterval.add(interval);
          _pendingPointerIntervalMicros = interval;
        }
      }
      _lastPointerEventTimestamp = eventTimestamp;
      if (currentFrameTimestamp != null) {
        final age = currentFrameTimestamp.inMicroseconds -
            eventTimestamp.inMicroseconds;
        // These clocks are recorded only when they are plausibly aligned.
        // Web engines that expose different epochs remain explicitly empty.
        if (age >= 0 && age <= 1000000) {
          _pointerEventAge.add(age);
          _pendingPointerEventAgeMicros = age;
        }
      }
    }
  }

  void recordAcceptedRevision(int revision) {
    if (isFinished || revision <= _latestAcceptedRevision) return;
    _acceptedRevisionCount++;
    _latestAcceptedRevision = revision;
    if (_acceptedAtMicrosByRevision.length >= _sampleCapacity) {
      _acceptedAtMicrosByRevision
          .remove(_acceptedAtMicrosByRevision.keys.first);
    }
    _acceptedAtMicrosByRevision[revision] = _lifetime.elapsedMicroseconds;
    final observation = _observationFor(revision)
      ..['accepted_at_us'] = _lifetime.elapsedMicroseconds
      ..['pointer_interval_us'] = _pendingPointerIntervalMicros
      ..['pointer_event_age_us'] = _pendingPointerEventAgeMicros
      ..['append_us'] = _pendingAppendMicros
      ..['model_us'] = _pendingAppendMicros;
    observation['model_scope'] = 'interaction.appendSample';
    _pendingPointerIntervalMicros = null;
    _pendingPointerEventAgeMicros = null;
    _pendingAppendMicros = null;
  }

  void recordAppendMicros(int micros) {
    if (!isFinished) {
      _append.add(micros);
      _pendingAppendMicros = micros;
      final end = _lifetime.elapsedMicroseconds;
      _observationFor(_latestAcceptedRevision)
        ..['append_begin_us'] = math.max(0, end - micros)
        ..['append_end_us'] = end;
    }
  }

  /// Records the production active-pointer path. No material sync or picture
  /// recording is permitted here; the final renderer runs only after the
  /// exact centerline has been presented and PointerUp confirms it.
  void recordLivePreviewFrame({
    required int revision,
    required int previewMicros,
    required int pathSegmentCount,
    required int geometryVertexCount,
    required String qualityLevel,
  }) {
    if (isFinished || revision > _latestAcceptedRevision) return;
    final end = _lifetime.elapsedMicroseconds;
    _observationFor(revision)
      ..['preview_begin_us'] = math.max(0, end - previewMicros)
      ..['preview_end_us'] = end
      ..['material_sync_begin_us'] = null
      ..['material_sync_end_us'] = null
      ..['picture_record_begin_us'] = null
      ..['picture_record_end_us'] = null
      ..['live_preview_quality_level'] = qualityLevel
      ..['live_preview_path_segments'] = math.max(0, pathSegmentCount)
      ..['live_preview_geometry_vertices'] = math.max(0, geometryVertexCount);
    _livePreviewQualityLevel = qualityLevel;
    _maximumLivePreviewPathSegments =
        math.max(_maximumLivePreviewPathSegments, pathSegmentCount);
    _maximumLivePreviewGeometryVertices =
        math.max(_maximumLivePreviewGeometryVertices, geometryVertexCount);
    if (revision <= _lastPaintedRevision) return;
    _paintedFrameCount++;
    _coalescedRevisionCount += math.max(0, revision - _lastPaintedRevision - 1);
    _lastPaintedRevision = revision;
    _acceptedAtMicrosByRevision.removeWhere((key, _) => key <= revision);
    _sync.add(0);
    _pictureRecording.add(0);
    _painterSubmit.add(previewMicros);
    _totalCpu.add(previewMicros);
  }

  void recordFramePresented(int revision) {
    if (isFinished) return;
    _observationFor(revision)['frame_presented_us'] =
        _lifetime.elapsedMicroseconds;
  }

  void recordRepaintRequested(int revision) {
    if (isFinished) return;
    final acceptedAt = _acceptedAtMicrosByRevision[revision];
    if (acceptedAt != null) {
      final latency = _lifetime.elapsedMicroseconds - acceptedAt;
      _repaintRequest.add(latency);
      _observationFor(revision)['repaint_request_us'] = latency;
    }
  }

  void recordOverlayPaintInvocation(
    int revision, {
    required int frameBuildStartMicros,
  }) {
    if (isFinished || revision != _latestAcceptedRevision) return;
    _overlayPaints++;
    if (_revisionByFrameBuildStartMicros.length >= _sampleCapacity &&
        !_revisionByFrameBuildStartMicros.containsKey(frameBuildStartMicros)) {
      _revisionByFrameBuildStartMicros
          .remove(_revisionByFrameBuildStartMicros.keys.first);
    }
    _revisionByFrameBuildStartMicros[frameBuildStartMicros] = revision;
    _observationFor(revision)['paint_frame_build_start_us'] =
        frameBuildStartMicros;
    final acceptedAt = _acceptedAtMicrosByRevision[revision];
    if (acceptedAt != null) {
      final latency = _lifetime.elapsedMicroseconds - acceptedAt;
      _overlayArrival.add(latency);
      _observationFor(revision)['overlay_arrival_us'] = latency;
    }
  }

  void recordFrameTiming({
    required int frameBuildStartMicros,
    required int frameNumber,
    required Duration buildDuration,
    required Duration rasterDuration,
    required Duration totalSpan,
  }) {
    if (isFinished) return;
    _frameTimingCount++;
    _frameBuild.add(buildDuration.inMicroseconds);
    _frameRaster.add(rasterDuration.inMicroseconds);
    _frameTotal.add(totalSpan.inMicroseconds);
    final previousFrameStart = _lastFrameBuildStartMicros;
    if (previousFrameStart != null) {
      final interval = frameBuildStartMicros - previousFrameStart;
      if (interval > 0 && interval <= 1000000) _refreshInterval.add(interval);
    }
    _lastFrameBuildStartMicros = frameBuildStartMicros;
    final revision =
        _revisionByFrameBuildStartMicros.remove(frameBuildStartMicros);
    if (revision == null) {
      _unattributedFrameTimingCount++;
      return;
    }
    _attributedFrameTimingCount++;
    final observation = _observationFor(revision);
    final timings = observation.putIfAbsent(
      'frame_timings',
      () => <Map<String, Object?>>[],
    ) as List<Map<String, Object?>>;
    timings.add(<String, Object?>{
      'sequence': _frameTimingCount,
      'frame_number': frameNumber,
      'build_start_us': frameBuildStartMicros,
      'build_us': buildDuration.inMicroseconds,
      'raster_us': rasterDuration.inMicroseconds,
      'total_us': totalSpan.inMicroseconds,
      'over_16_67_ms': totalSpan.inMicroseconds > 16667,
    });
  }

  void recordModeledRuntime({
    required int modeledSteps,
    required int modeledSegments,
    required int tailSegments,
    required int strokeRevision,
  }) {
    if (isFinished) return;
    _modeledStepCount += math.max(0, modeledSteps);
    _modeledSegmentCount += math.max(0, modeledSegments);
    _tailSegmentCount += math.max(0, tailSegments);
    if (strokeRevision > _lastRecordedStrokeRevision) {
      _strokeRevisionCount++;
      _lastRecordedStrokeRevision = strokeRevision;
    }
    _observationFor(strokeRevision)
      ..['modeled_step_count'] = math.max(0, modeledSteps)
      ..['modeled_segment_count'] = math.max(0, modeledSegments)
      ..['tail_segment_count'] = math.max(0, tailSegments);
  }

  void recordCoalescedSamples(int count) {
    if (isFinished || count <= 0) return;
    _coalescedSampleCount += count;
    _bridgeActive = true;
  }

  void recordInputRuntime({
    required int effectiveInputSampleCount,
    required bool inputStarved,
    required int largestInputGapMicros,
    required double largestInputDistance,
    required int stableCenterlineSegmentCount,
    required int mutableCenterlineSegmentCount,
    required int predictionSegmentCount,
  }) {
    if (isFinished) return;
    _effectiveInputSampleCount = math.max(0, effectiveInputSampleCount);
    _inputStarved = inputStarved;
    _largestInputGapMicros = math.max(0, largestInputGapMicros);
    _largestInputDistance =
        largestInputDistance.isFinite ? math.max(0, largestInputDistance) : 0;
    _stableCenterlineSegmentCount = math.max(0, stableCenterlineSegmentCount);
    _mutableCenterlineSegmentCount = math.max(0, mutableCenterlineSegmentCount);
    _predictionSegmentCount = math.max(0, predictionSegmentCount);
  }

  void recordInputDistance(double distance) {
    if (!isFinished && distance.isFinite && distance > 0) {
      _inputDistance += distance;
    }
  }

  void recordMaterialRuntime({
    required int materialResolveCalls,
    required int overlayPaints,
    required int framesWithResolve,
    String? runtimeFamily,
    Map<String, Object>? diagnostics,
  }) {
    if (isFinished) return;
    _materialResolveCalls = math.max(0, materialResolveCalls);
    _overlayPaints = math.max(_overlayPaints, math.max(0, overlayPaints));
    _framesWithResolve = math.max(0, framesWithResolve);
    _materialRuntime = Map<String, Object?>.unmodifiable(<String, Object?>{
      if (runtimeFamily != null) 'family': runtimeFamily,
      'material_resolve_calls': _materialResolveCalls,
      'overlay_paints': _overlayPaints,
      'frames_with_resolve': _framesWithResolve,
      if (diagnostics != null) 'diagnostics': diagnostics,
    });
  }

  void recordCompactionMicros(int micros) {
    if (!isFinished) _compaction.add(micros);
  }

  void recordSweptCoverage(
      {required int revision,
      required int sections,
      required int rebuiltSections,
      required int layers}) {
    if (isFinished) return;
    _observationFor(revision).addAll({
      'sweep_sections': sections,
      'sweep_rebuilt_sections': rebuiltSections,
      'sweep_layers': layers,
    });
  }

  void recordPaintedFrame({
    required int revision,
    required int syncMicros,
    required int painterSubmitMicros,
    required int pictureRecordingMicros,
    int mutableTailDirectSubmitMicros = 0,
    int mutableTailCommandBuildMicros = 0,
    int stablePictureRecordMicros = 0,
    int stablePicturePlaybackMicros = 0,
    int plannedDabMicros = 0,
    int bodyMeshMicros = 0,
    int atlasBatchMicros = 0,
    int verticesBatchMicros = 0,
    int preparedStampInstances = 0,
    int preparedStampBufferCapacity = 0,
    int preparedStampBufferGrowthCount = 0,
    int stampInstanceBuildMicros = 0,
    int typedBufferPackMicros = 0,
    int drawRawAtlasSubmitMicros = 0,
    int drawVerticesSubmitMicros = 0,
    int mutableTailWorkUnits = 0,
    int freshAllocationProxy = 0,
    int stablePictureRerecorded = 0,
    int stablePictureIdentityChanged = 0,
    required int nextSealedDabIndex,
    required int safeDabExclusive,
    required int tailDabCount,
    required int newImmutableDabs,
    required int rerecordedUnchangedDabs,
    required int newChunkCount,
    required int recordedDabChunks,
    required int tailGeometryVertices,
    required int persistentLaneVertices,
    required int visibleDabExclusive,
    required double sealedEndArc,
    required double causalStableEndArc,
    required double renderEndArc,
    required int tailStartIndex,
    required int tailEndExclusive,
    required int unownedVisibleDabs,
    required int doubleOwnedVisibleDabs,
    required int flattenedRgbaBytes,
    required int retainedPictureCount,
    required int geometryPayloadBytesProxy,
    required int geometryVertexCountProxy,
    required int geometryIndexCountProxy,
    required int atlasInstanceCountProxy,
  }) {
    if (isFinished ||
        revision <= _lastPaintedRevision ||
        revision > _latestAcceptedRevision) {
      return;
    }
    _livePreviewQualityLevel = 'exactMaterial';
    _paintedFrameCount++;
    _coalescedRevisionCount += math.max(0, revision - _lastPaintedRevision - 1);
    _lastPaintedRevision = revision;
    _acceptedAtMicrosByRevision.removeWhere((key, _) => key <= revision);
    _sync.add(syncMicros);
    _pictureRecording.add(pictureRecordingMicros);
    _painterSubmit.add(painterSubmitMicros);
    _totalCpu.add(syncMicros + painterSubmitMicros);
    _fullMaterialWorkDuringPointerMicros +=
        math.max(0, syncMicros) + math.max(0, pictureRecordingMicros);
    _observationFor(revision)
      ..['painted_at_us'] = _lifetime.elapsedMicroseconds
      ..['sync_us'] = syncMicros
      ..['painter_submit_us'] = painterSubmitMicros
      ..['tail_picture_recording_us'] = pictureRecordingMicros
      ..['mutable_tail_direct_submit_us'] =
          math.max(0, mutableTailDirectSubmitMicros)
      ..['mutable_tail_command_build_us'] =
          math.max(0, mutableTailCommandBuildMicros)
      ..['stable_picture_record_us'] = math.max(0, stablePictureRecordMicros)
      ..['stable_picture_playback_us'] =
          math.max(0, stablePicturePlaybackMicros)
      ..['planned_dab_us'] = math.max(0, plannedDabMicros)
      ..['body_mesh_us'] = math.max(0, bodyMeshMicros)
      ..['atlas_batch_us'] = math.max(0, atlasBatchMicros)
      ..['vertices_batch_us'] = math.max(0, verticesBatchMicros)
      ..['prepared_stamp_instances'] = math.max(0, preparedStampInstances)
      ..['prepared_stamp_buffer_capacity'] =
          math.max(0, preparedStampBufferCapacity)
      ..['prepared_stamp_buffer_growth_count'] =
          math.max(0, preparedStampBufferGrowthCount)
      ..['body_mesh_vertices_per_dab'] =
          tailDabCount <= 0 ? 0 : tailGeometryVertices / tailDabCount
      ..['stamp_instance_build_us'] = math.max(0, stampInstanceBuildMicros)
      ..['typed_buffer_pack_us'] = math.max(0, typedBufferPackMicros)
      ..['draw_raw_atlas_submit_us'] = math.max(0, drawRawAtlasSubmitMicros)
      ..['draw_vertices_submit_us'] = math.max(0, drawVerticesSubmitMicros)
      ..['mutable_material_total_us'] = math.max(
        0,
        mutableTailCommandBuildMicros + mutableTailDirectSubmitMicros,
      )
      ..['mutable_tail_work_units'] = math.max(0, mutableTailWorkUnits)
      ..['fresh_allocation_proxy'] = math.max(0, freshAllocationProxy)
      ..['stable_picture_rerecorded'] = math.max(0, stablePictureRerecorded)
      ..['stable_picture_identity_changed'] =
          math.max(0, stablePictureIdentityChanged)
      ..['new_immutable_dab_count'] = math.max(0, newImmutableDabs)
      ..['rerecorded_unchanged_dab_count'] =
          math.max(0, rerecordedUnchangedDabs)
      ..['new_chunk_count'] = math.max(0, newChunkCount)
      ..['recorded_dab_chunk_count'] = math.max(0, recordedDabChunks)
      ..['tail_dab_count'] = math.max(0, tailDabCount)
      ..['visible_dab_exclusive'] = math.max(0, visibleDabExclusive)
      ..['safe_dab_exclusive'] = math.max(0, safeDabExclusive)
      ..['next_sealed_dab_index'] = math.max(0, nextSealedDabIndex)
      ..['sealed_end_arc'] = sealedEndArc
      ..['causal_stable_end_arc'] = causalStableEndArc
      ..['render_end_arc'] = renderEndArc
      ..['tail_start_index'] = math.max(0, tailStartIndex)
      ..['tail_end_exclusive'] = math.max(0, tailEndExclusive)
      ..['unowned_visible_dab_count'] = math.max(0, unownedVisibleDabs)
      ..['double_owned_visible_dab_count'] = math.max(0, doubleOwnedVisibleDabs)
      ..['visible_dab_ownership_exact'] =
          unownedVisibleDabs == 0 && doubleOwnedVisibleDabs == 0
      ..['geometry_vertex_count'] = math.max(0, tailGeometryVertices)
      ..['persistent_lane_vertex_count'] = math.max(0, persistentLaneVertices);
    _tailWorkObservationCount++;
    _nextSealedDabIndex = math.max(0, nextSealedDabIndex);
    _safeDabExclusive = math.max(0, safeDabExclusive);
    _maximumTailDabCount = math.max(_maximumTailDabCount, tailDabCount);
    _totalNewImmutableDabs += math.max(0, newImmutableDabs);
    _totalRerecordedUnchangedDabs += math.max(0, rerecordedUnchangedDabs);
    _maximumTailGeometryVertices =
        math.max(_maximumTailGeometryVertices, tailGeometryVertices);
    _maximumPersistentLaneVertices =
        math.max(_maximumPersistentLaneVertices, persistentLaneVertices);
    _recordPayloadProxyObservation(
      flattenedRgbaBytes: flattenedRgbaBytes,
      retainedPictureCount: retainedPictureCount,
      geometryPayloadBytesProxy: geometryPayloadBytesProxy,
      geometryVertexCountProxy: geometryVertexCountProxy,
      geometryIndexCountProxy: geometryIndexCountProxy,
      atlasInstanceCountProxy: atlasInstanceCountProxy,
      updateCurrent: true,
    );
  }

  /// Records a stateful-material frame without pretending its sparse tiles
  /// are DAB chunks or picture-tail geometry.
  void recordMaterialPaintedFrame({
    required int revision,
    required int resolveMicros,
    required int painterSubmitMicros,
    required int materialSegmentCount,
    required int provisionalSegmentCount,
    required int allocatedTileCount,
    required int dirtyTileCount,
    required int persistentBytesProxy,
    required int peakProvisionalBytesProxy,
    required int presentationRgbaBytesProxy,
  }) {
    if (isFinished ||
        revision <= _lastPaintedRevision ||
        revision > _latestAcceptedRevision) {
      return;
    }
    _paintedFrameCount++;
    _coalescedRevisionCount += math.max(0, revision - _lastPaintedRevision - 1);
    _lastPaintedRevision = revision;
    _acceptedAtMicrosByRevision.removeWhere((key, _) => key <= revision);
    _sync.add(resolveMicros);
    _painterSubmit.add(painterSubmitMicros);
    _totalCpu.add(resolveMicros + painterSubmitMicros);
    _observationFor(revision)
      ..['painted_at_us'] = _lifetime.elapsedMicroseconds
      ..['sync_us'] = resolveMicros
      ..['painter_submit_us'] = painterSubmitMicros
      ..['material_resolve_us'] = resolveMicros
      ..['material_segment_count'] = math.max(0, materialSegmentCount)
      ..['material_provisional_segment_count'] =
          math.max(0, provisionalSegmentCount)
      ..['material_allocated_tile_count'] = math.max(0, allocatedTileCount)
      ..['material_dirty_tile_count'] = math.max(0, dirtyTileCount)
      ..['material_persistent_bytes_proxy'] = math.max(0, persistentBytesProxy)
      ..['material_peak_provisional_bytes_proxy'] =
          math.max(0, peakProvisionalBytesProxy)
      ..['material_presentation_rgba_bytes_proxy'] =
          math.max(0, presentationRgbaBytesProxy);
  }

  /// Contact-mask images are separate from legacy flattened-prefix images.
  /// The payload excludes GPU metadata and the shared immutable paper lattice.
  void recordContactRasterFrame({
    required int revision,
    required int rgbaBytes,
    required int tileCount,
    required int updatedTileCount,
  }) {
    if (isFinished) return;
    _observationFor(revision)
      ..['contact_raster_rgba_bytes'] = rgbaBytes
      ..['contact_raster_tile_count'] = tileCount
      ..['contact_raster_updated_tiles'] = updatedTileCount;
  }

  /// Observes a short-lived old-plus-replacement cache state during
  /// compaction. The values are payload proxies, not allocation measurements.
  void recordTransientPayloadProxyPeak({
    required int flattenedRgbaBytes,
    required int retainedPictureCount,
    required int geometryPayloadBytesProxy,
    required int geometryVertexCountProxy,
    required int geometryIndexCountProxy,
    required int atlasInstanceCountProxy,
  }) {
    if (isFinished) return;
    _recordPayloadProxyObservation(
      flattenedRgbaBytes: flattenedRgbaBytes,
      retainedPictureCount: retainedPictureCount,
      geometryPayloadBytesProxy: geometryPayloadBytesProxy,
      geometryVertexCountProxy: geometryVertexCountProxy,
      geometryIndexCountProxy: geometryIndexCountProxy,
      atlasInstanceCountProxy: atlasInstanceCountProxy,
      updateCurrent: false,
    );
  }

  void _recordPayloadProxyObservation({
    required int flattenedRgbaBytes,
    required int retainedPictureCount,
    required int geometryPayloadBytesProxy,
    required int geometryVertexCountProxy,
    required int geometryIndexCountProxy,
    required int atlasInstanceCountProxy,
    required bool updateCurrent,
  }) {
    if (updateCurrent) {
      _currentFlattenedRgbaBytes = flattenedRgbaBytes;
      _currentRetainedPictureCount = retainedPictureCount;
      _currentGeometryPayloadBytesProxy = geometryPayloadBytesProxy;
      _currentGeometryVertexCountProxy = geometryVertexCountProxy;
      _currentGeometryIndexCountProxy = geometryIndexCountProxy;
      _currentAtlasInstanceCountProxy = atlasInstanceCountProxy;
    }
    _peakFlattenedRgbaBytes =
        math.max(_peakFlattenedRgbaBytes, flattenedRgbaBytes);
    _peakRetainedPictureCount =
        math.max(_peakRetainedPictureCount, retainedPictureCount);
    _peakGeometryPayloadBytesProxy = math.max(
      _peakGeometryPayloadBytesProxy,
      geometryPayloadBytesProxy,
    );
    _peakGeometryVertexCountProxy = math.max(
      _peakGeometryVertexCountProxy,
      geometryVertexCountProxy,
    );
    _peakGeometryIndexCountProxy = math.max(
      _peakGeometryIndexCountProxy,
      geometryIndexCountProxy,
    );
    _peakAtlasInstanceCountProxy = math.max(
      _peakAtlasInstanceCountProxy,
      atlasInstanceCountProxy,
    );
  }

  PawBrushPerformanceReport finish() {
    final existing = _finishedReport;
    if (existing != null) return existing;
    _lifetime.stop();
    final frameObservations = _snapshotFrameObservations();
    final refreshInterval = _refreshInterval.summarize();
    // Observed callback spacing includes missed frames and cannot establish
    // display refresh rate. Use a stated 60 Hz reference until the platform
    // supplies a reliable refresh-rate measurement.
    const effectiveFrameBudgetMicros = 16667;
    final hitchCorrelations = _frameCorrelations(
      minimumTotalMicros: effectiveFrameBudgetMicros,
    );
    final topSlowFrames = _frameCorrelations(
      minimumTotalMicros: -1,
      effectiveBudgetMicros: effectiveFrameBudgetMicros,
      limit: 20,
    );
    final report = PawBrushPerformanceReport(
      captureId: captureId,
      brushId: brushId,
      brushRevision: brushRevision,
      brushSize: brushSize,
      logicalSize: logicalSize,
      rasterScale: rasterScale,
      startedAtUtc: startedAtUtc,
      finishedAtUtc: DateTime.now().toUtc(),
      captureDurationMicros: _lifetime.elapsedMicroseconds,
      rawPointerMoveCount: _rawPointerMoveCount,
      acceptedRevisionCount: _acceptedRevisionCount,
      modeledStepCount: _modeledStepCount,
      modeledSegmentCount: _modeledSegmentCount,
      tailSegmentCount: _tailSegmentCount,
      strokeRevisionCount: _strokeRevisionCount,
      materialResolveCalls: _materialResolveCalls,
      overlayPaints: _overlayPaints,
      framesWithResolve: _framesWithResolve,
      inputDistance: _inputDistance,
      paintedFrameCount: _paintedFrameCount,
      coalescedRevisionCount: _coalescedRevisionCount,
      unpaintedAcceptedRevisionCount:
          math.max(0, _latestAcceptedRevision - _lastPaintedRevision),
      sync: _sync.summarize(),
      append: _append.summarize(),
      pictureRecording: _pictureRecording.summarize(),
      painterSubmit: _painterSubmit.summarize(),
      totalCpu: _totalCpu.summarize(),
      compaction: _compaction.summarize(),
      pointerEventAge: _pointerEventAge.summarize(),
      interEventInterval: _interEventInterval.summarize(),
      repaintRequest: _repaintRequest.summarize(),
      overlayArrival: _overlayArrival.summarize(),
      frameBuild: _frameBuild.summarize(),
      frameRaster: _frameRaster.summarize(),
      frameTotal: _frameTotal.summarize(),
      refreshInterval: refreshInterval,
      effectiveFrameBudgetMicros: effectiveFrameBudgetMicros,
      frameTimingCount: _frameTimingCount,
      attributedFrameTimingCount: _attributedFrameTimingCount,
      unattributedFrameTimingCount: _unattributedFrameTimingCount,
      missedFrameCount: _frameTotal.countOver(effectiveFrameBudgetMicros),
      resamplingEnabled: resamplingEnabled,
      samplingOffsetMicros: samplingOffset.inMicroseconds,
      coalescedInputSupported: coalescedInputSupported,
      pointerRawUpdateSupported: pointerRawUpdateSupported,
      coalescedSampleCount: _coalescedSampleCount,
      bridgeActive: _bridgeActive,
      effectiveInputSampleCount: _effectiveInputSampleCount,
      inputStarved: _inputStarved,
      largestInputGapMicros: _largestInputGapMicros,
      largestInputDistance: _largestInputDistance,
      stableCenterlineSegmentCount: _stableCenterlineSegmentCount,
      mutableCenterlineSegmentCount: _mutableCenterlineSegmentCount,
      predictionSegmentCount: _predictionSegmentCount,
      runtimeTarget: runtimeTarget,
      memoryPayloadProxy: PawBrushMemoryPayloadProxy(
        currentFlattenedRgbaBytes: _currentFlattenedRgbaBytes,
        peakFlattenedRgbaBytes: _peakFlattenedRgbaBytes,
        currentRetainedPictureCount: _currentRetainedPictureCount,
        peakRetainedPictureCount: _peakRetainedPictureCount,
        currentGeometryPayloadBytesProxy: _currentGeometryPayloadBytesProxy,
        peakGeometryPayloadBytesProxy: _peakGeometryPayloadBytesProxy,
        currentGeometryVertexCountProxy: _currentGeometryVertexCountProxy,
        peakGeometryVertexCountProxy: _peakGeometryVertexCountProxy,
        currentGeometryIndexCountProxy: _currentGeometryIndexCountProxy,
        peakGeometryIndexCountProxy: _peakGeometryIndexCountProxy,
        currentAtlasInstanceCountProxy: _currentAtlasInstanceCountProxy,
        peakAtlasInstanceCountProxy: _peakAtlasInstanceCountProxy,
      ),
      tailWork: PawBrushTailWorkSummary(
        observationCount: _tailWorkObservationCount,
        nextSealedDabIndex: _nextSealedDabIndex,
        safeDabExclusive: _safeDabExclusive,
        maximumTailDabCount: _maximumTailDabCount,
        totalNewImmutableDabs: _totalNewImmutableDabs,
        totalRerecordedUnchangedDabs: _totalRerecordedUnchangedDabs,
        maximumTailGeometryVertices: _maximumTailGeometryVertices,
        maximumPersistentLaneVertices: _maximumPersistentLaneVertices,
      ),
      materialRuntime: _materialRuntime,
      frameObservations: frameObservations,
      hitchCorrelations: hitchCorrelations,
      topSlowFrames: topSlowFrames,
      fullMaterialWorkDuringPointerMicros: _fullMaterialWorkDuringPointerMicros,
      livePreviewQualityLevel: _livePreviewQualityLevel,
      maximumLivePreviewPathSegments: _maximumLivePreviewPathSegments,
      maximumLivePreviewGeometryVertices: _maximumLivePreviewGeometryVertices,
      inputSampleProvenance: inputSampleProvenance,
    );
    _finishedReport = report;
    return report;
  }
}

class _FixedMicrosSamples {
  _FixedMicrosSamples(int capacity) : _values = Uint32List(capacity);

  static const int _frameBudgetMicros = 16667;
  final Uint32List _values;
  int _length = 0;
  int _dropped = 0;
  int _overBudgetCount = 0;

  void add(int micros) {
    final value = micros.clamp(0, 0xffffffff).toInt();
    if (_length == _values.length) {
      _dropped++;
      return;
    }
    _values[_length++] = value;
    if (value > _frameBudgetMicros) _overBudgetCount++;
  }

  PawBrushDurationSummary summarize() {
    if (_length == 0) {
      return PawBrushDurationSummary(
        sampleCount: 0,
        droppedSampleCount: _dropped,
        p50Micros: null,
        p95Micros: null,
        p99Micros: null,
        over16_7MillisRatio: 0,
      );
    }
    final sorted = <int>[
      for (var index = 0; index < _length; index++) _values[index],
    ]..sort();
    int percentile(double fraction) =>
        sorted[(fraction * sorted.length).ceil().clamp(1, sorted.length) - 1];
    return PawBrushDurationSummary(
      sampleCount: _length,
      droppedSampleCount: _dropped,
      p50Micros: percentile(.5),
      p95Micros: percentile(.95),
      p99Micros: percentile(.99),
      over16_7MillisRatio: _overBudgetCount / _length,
    );
  }

  int countOver(int budgetMicros) {
    var count = 0;
    for (var index = 0; index < _length; index++) {
      if (_values[index] > budgetMicros) count++;
    }
    return count;
  }
}
