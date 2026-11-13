import 'pointer_input_diagnostics.dart';

bool get pawCoalescedInputSupported => false;
bool get pawPointerRawUpdateSupported => false;
PawPointerDiagnosticsStatus get pawPointerDiagnosticsStatus =>
    PawPointerDiagnosticsStatus.unsupported;
String? get pawPointerDiagnosticsReason => 'not-web';

class PawBrowserCoalescedSample {
  const PawBrowserCoalescedSample({
    required this.clientX,
    required this.clientY,
    required this.relativeTimestampMicros,
    required this.pressure,
    required this.pointerType,
  });

  final double clientX;
  final double clientY;
  final int relativeTimestampMicros;
  final double pressure;
  final String pointerType;
}

void pawEnsurePointerInputBridge() {}
List<PawBrowserCoalescedSample> pawTakeCoalescedInputSamples() =>
    const <PawBrowserCoalescedSample>[];

void pawRecordFlutterPointerSample({
  required int pointerId,
  required int timestampMicros,
  required double x,
  required double y,
  required bool accepted,
}) {}

void pawRecordModeledCenterlineSample({
  required int timestampMicros,
  required double x,
  required double y,
  required int revision,
}) {}

void pawResetInputDeliveryDiagnostics() {}

PawWebInputEnvironment pawWebInputEnvironment() => const PawWebInputEnvironment(
      isSecureContext: false,
      locationProtocol: 'native:',
      locationOrigin: '',
      userAgent: '',
      platform: 'native',
      navigatorVendor: '',
      browserVersion: 'not-web',
      flutterVersion: '3.44.8',
      dartVersion: '3.12.2',
      wasmOrJs: 'native',
      renderer: 'native',
      actualEventSeen: false,
      actualPointerEventHasGetCoalescedEvents: false,
      actualPointerEventHasGetPredictedEvents: false,
      syntheticEventHasGetCoalescedEvents: false,
      pointerRawUpdateSupported: false,
      diagnosticsStatus: PawPointerDiagnosticsStatus.unsupported,
      diagnosticsReason: 'not-web',
    );

PawInputDeliveryParityDiagnostics pawInputDeliveryParityDiagnostics() =>
    const PawInputDeliveryParityDiagnostics(
      domDispatchedEvents: 0,
      domCoalescedEvents: 0,
      domPredictedEvents: 0,
      flutterPointerMoveSamples: 0,
      pawDoodleAcceptedHardwareSamples: 0,
      missingSampleCount: 0,
      duplicateSampleCount: 0,
      reorderedSampleCount: 0,
      coalescedEventsPerPointerEvent: <String, num>{
        'min': 0,
        'p50': 0,
        'p95': 0,
        'p99': 0,
        'max': 0,
      },
      effectiveHardwareSampleIntervalMicros: <String, num>{
        'min': 0,
        'p50': 0,
        'p95': 0,
        'p99': 0,
        'max': 0,
      },
      customBridgeProductionIngestion: false,
      predictionOwner: 'PawStreamingCenterlineModeler',
    );

PawInputLayerPathBoard pawInputLayerPathBoard() => const PawInputLayerPathBoard(
      rawDom: <Map<String, Object>>[],
      flutterDelivered: <Map<String, Object>>[],
      pawDoodleAccepted: <Map<String, Object>>[],
      modeledCenterline: <Map<String, Object>>[],
    );
