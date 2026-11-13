import 'package:flutter/foundation.dart';

enum PawPointerDiagnosticsStatus {
  notStarted,
  ready,
  unsupported,
  failed,
}

/// Flutter allocates a new sequence number at down; the DOM owns a different
/// pointer-id namespace. Bind them only after a timestamp/position match.
class PawPointerIdentityMap {
  final _domByFlutter = <int, int>{};
  final _flutterByDom = <int, int>{};

  bool canMatch(int flutterId, int domId) =>
      (_domByFlutter[flutterId] == null || _domByFlutter[flutterId] == domId) &&
      (_flutterByDom[domId] == null || _flutterByDom[domId] == flutterId);

  void bind(int flutterId, int domId) {
    _domByFlutter[flutterId] = domId;
    _flutterByDom[domId] = flutterId;
  }

  void clear() {
    _domByFlutter.clear();
    _flutterByDom.clear();
  }
}

@immutable
class PawWebInputEnvironment {
  const PawWebInputEnvironment({
    required this.isSecureContext,
    required this.locationProtocol,
    required this.locationOrigin,
    required this.userAgent,
    required this.platform,
    required this.navigatorVendor,
    required this.browserVersion,
    required this.flutterVersion,
    required this.dartVersion,
    required this.wasmOrJs,
    required this.renderer,
    required this.actualEventSeen,
    required this.actualPointerEventHasGetCoalescedEvents,
    required this.actualPointerEventHasGetPredictedEvents,
    required this.syntheticEventHasGetCoalescedEvents,
    required this.pointerRawUpdateSupported,
    required this.diagnosticsStatus,
    this.diagnosticsReason,
  });

  final bool isSecureContext;
  final String locationProtocol;
  final String locationOrigin;
  final String userAgent;
  final String platform;
  final String navigatorVendor;
  final String browserVersion;
  final String flutterVersion;
  final String dartVersion;
  final String wasmOrJs;
  final String renderer;
  final bool actualEventSeen;
  final bool actualPointerEventHasGetCoalescedEvents;
  final bool actualPointerEventHasGetPredictedEvents;
  final bool syntheticEventHasGetCoalescedEvents;
  final bool pointerRawUpdateSupported;
  final PawPointerDiagnosticsStatus diagnosticsStatus;
  final String? diagnosticsReason;

  String get coalescedCapability => !actualEventSeen
      ? 'unknown'
      : actualPointerEventHasGetCoalescedEvents
          ? 'supported'
          : 'unsupported';

  String get predictedCapability => !actualEventSeen
      ? 'unknown'
      : actualPointerEventHasGetPredictedEvents
          ? 'supported'
          : 'unsupported';

  Map<String, Object> toJson() => <String, Object>{
        'is_secure_context': isSecureContext,
        'http_or_https': locationProtocol.replaceAll(':', ''),
        'location_protocol': locationProtocol,
        'location_origin': locationOrigin,
        'user_agent': userAgent,
        'platform': platform,
        'navigator_vendor': navigatorVendor,
        'browser_version_if_parseable': browserVersion,
        'flutter_version': flutterVersion,
        'dart_version': dartVersion,
        'wasm_or_js': wasmOrJs,
        'renderer': renderer,
        'actual_pointer_event_seen': actualEventSeen,
        'actual_pointer_event_has_getCoalescedEvents':
            actualPointerEventHasGetCoalescedEvents,
        'actual_pointer_event_has_getPredictedEvents':
            actualPointerEventHasGetPredictedEvents,
        'synthetic_event_has_getCoalescedEvents':
            syntheticEventHasGetCoalescedEvents,
        'pointerrawupdate': pointerRawUpdateSupported,
        'pointer_diagnostics_status': diagnosticsStatus.name,
        'pointer_diagnostics_reason': diagnosticsReason ?? '',
        'coalesced_capability': coalescedCapability,
        'predicted_capability': predictedCapability,
      };
}

@immutable
class PawInputDeliveryParityDiagnostics {
  const PawInputDeliveryParityDiagnostics({
    required this.domDispatchedEvents,
    required this.domCoalescedEvents,
    required this.domPredictedEvents,
    required this.flutterPointerMoveSamples,
    required this.pawDoodleAcceptedHardwareSamples,
    required this.missingSampleCount,
    required this.duplicateSampleCount,
    required this.reorderedSampleCount,
    required this.coalescedEventsPerPointerEvent,
    required this.effectiveHardwareSampleIntervalMicros,
    required this.customBridgeProductionIngestion,
    required this.predictionOwner,
  });

  final int domDispatchedEvents;
  final int domCoalescedEvents;
  final int domPredictedEvents;
  final int flutterPointerMoveSamples;
  final int pawDoodleAcceptedHardwareSamples;
  final int missingSampleCount;
  final int duplicateSampleCount;
  final int reorderedSampleCount;
  final Map<String, num> coalescedEventsPerPointerEvent;
  final Map<String, num> effectiveHardwareSampleIntervalMicros;
  final bool customBridgeProductionIngestion;
  final String predictionOwner;

  bool get inputStarved {
    final p95 = effectiveHardwareSampleIntervalMicros['p95'] ?? 0;
    return flutterPointerMoveSamples > 4 && p95 > 25000;
  }

  Map<String, Object> toJson() => <String, Object>{
        'dom_dispatched_events': domDispatchedEvents,
        'dom_coalesced_events': domCoalescedEvents,
        'dom_predicted_events': domPredictedEvents,
        'flutter_pointer_move_samples': flutterPointerMoveSamples,
        'pawdoodle_accepted_hardware_samples': pawDoodleAcceptedHardwareSamples,
        'missing_sample_count': missingSampleCount,
        'duplicate_sample_count': duplicateSampleCount,
        'reordered_sample_count': reorderedSampleCount,
        'coalesced_events_per_pointer_event': coalescedEventsPerPointerEvent,
        'effective_hardware_sample_interval_us':
            effectiveHardwareSampleIntervalMicros,
        'custom_bridge_production_ingestion': customBridgeProductionIngestion,
        'prediction_owner': predictionOwner,
        'input_starved': inputStarved,
        'delivery_starved': inputStarved,
      };
}

@immutable
class PawInputLayerPathBoard {
  const PawInputLayerPathBoard({
    required this.rawDom,
    required this.flutterDelivered,
    required this.pawDoodleAccepted,
    required this.modeledCenterline,
  });

  final List<Map<String, Object>> rawDom;
  final List<Map<String, Object>> flutterDelivered;
  final List<Map<String, Object>> pawDoodleAccepted;
  final List<Map<String, Object>> modeledCenterline;

  Map<String, Object> toJson() => <String, Object>{
        'schema': 'pawdoodle.input-path-board.v1',
        'raw_dom_hardware_evidence': rawDom,
        'flutter_delivered': flutterDelivered,
        'pawdoodle_accepted': pawDoodleAccepted,
        'modeled_centerline': modeledCenterline,
      };
}
