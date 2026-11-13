import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show debugPrint, debugPrintStack, kIsWasm;
import 'package:web/web.dart' as web;

import 'pointer_input_diagnostics.dart';

const String _flutterVersion = '3.44.8';
const String _dartVersion = '3.12.2';

bool _actualEventSeen = false;
bool _actualCoalescedCallable = false;
bool _actualPredictedCallable = false;
bool _pointerRawUpdateSupported = false;
PawPointerDiagnosticsStatus _diagnosticsStatus =
    PawPointerDiagnosticsStatus.notStarted;
String? _diagnosticsReason;

bool get pawCoalescedInputSupported =>
    _actualEventSeen && _actualCoalescedCallable;
bool get pawPointerRawUpdateSupported =>
    _actualEventSeen && _pointerRawUpdateSupported;
PawPointerDiagnosticsStatus get pawPointerDiagnosticsStatus =>
    _diagnosticsStatus;
String? get pawPointerDiagnosticsReason => _diagnosticsReason;

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

class _DomSample {
  const _DomSample({
    required this.pointerId,
    required this.timestampMicros,
    required this.x,
    required this.y,
    required this.sequence,
  });

  final int pointerId;
  final int timestampMicros;
  final double x;
  final double y;
  final int sequence;
}

final List<_DomSample> _pendingDomSamples = <_DomSample>[];
final List<int> _coalescedCounts = <int>[];
final List<int> _effectiveIntervals = <int>[];
final Map<int, int> _lastEffectiveTimestampByPointer = <int, int>{};
final Map<int, int> _lastMatchedSequenceByPointer = <int, int>{};
final Set<String> _matchedFlutterSignatures = <String>{};
final _pointerIdentityMap = PawPointerIdentityMap();
final List<Map<String, Object>> _rawDomPath = <Map<String, Object>>[];
final List<Map<String, Object>> _flutterDeliveredPath = <Map<String, Object>>[];
final List<Map<String, Object>> _pawDoodleAcceptedPath =
    <Map<String, Object>>[];
final List<Map<String, Object>> _modeledCenterlinePath =
    <Map<String, Object>>[];

JSFunction? _pointerMoveListener;
bool _bridgeInstalled = false;
int _domSequence = 0;
int _domDispatchedEvents = 0;
int _domCoalescedEvents = 0;
int _domPredictedEvents = 0;
int _flutterPointerMoveSamples = 0;
int _acceptedHardwareSamples = 0;
int _missingSampleCount = 0;
int _duplicateSampleCount = 0;
int _reorderedSampleCount = 0;

/// Installs a diagnostics-only listener. This function is intentionally
/// fail-open and must be called only after the Flutter shell's first frame.
/// No browser capability is probed until a real PointerEvent reaches it.
void pawEnsurePointerInputBridge() {
  if (_bridgeInstalled ||
      _diagnosticsStatus == PawPointerDiagnosticsStatus.failed) {
    return;
  }
  try {
    _pointerMoveListener = ((web.Event rawEvent) {
      try {
        _handlePointerMove(rawEvent);
      } catch (error, stackTrace) {
        _diagnosticsStatus = PawPointerDiagnosticsStatus.failed;
        _diagnosticsReason = error.toString();
        debugPrint('Paw pointer diagnostics unavailable: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }).toJS;
    web.document.addEventListener('pointermove', _pointerMoveListener);
    _bridgeInstalled = true;
    _diagnosticsStatus = PawPointerDiagnosticsStatus.ready;
  } catch (error, stackTrace) {
    _diagnosticsStatus = PawPointerDiagnosticsStatus.failed;
    _diagnosticsReason = error.toString();
    debugPrint('Paw pointer diagnostics failed to install: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

void _handlePointerMove(web.Event rawEvent) {
  if (rawEvent is! web.PointerEvent) return;
  _actualEventSeen = true;
  _domDispatchedEvents++;
  final eventObject = rawEvent as JSObject;
  _actualCoalescedCallable =
      eventObject.getProperty<JSAny?>('getCoalescedEvents'.toJS) is JSFunction;
  _actualPredictedCallable =
      eventObject.getProperty<JSAny?>('getPredictedEvents'.toJS) is JSFunction;
  _pointerRawUpdateSupported =
      web.document.hasProperty('onpointerrawupdate'.toJS).toDart;

  final expanded = _actualCoalescedCallable
      ? _eventArray(eventObject, 'getCoalescedEvents')
      : <web.PointerEvent>[];
  final coalescedCount = expanded.length;
  if (expanded.isEmpty) expanded.add(rawEvent);
  _coalescedCounts.add(coalescedCount);
  _domCoalescedEvents += coalescedCount;
  if (_actualPredictedCallable) {
    _domPredictedEvents +=
        _eventArray(eventObject, 'getPredictedEvents').length;
  }

  final pointerId = rawEvent.pointerId;
  for (final event in expanded) {
    final timestampMicros = (event.timeStamp * 1000).round();
    final previous = _lastEffectiveTimestampByPointer[pointerId];
    if (previous != null && timestampMicros > previous) {
      _effectiveIntervals.add(timestampMicros - previous);
    }
    _lastEffectiveTimestampByPointer[pointerId] = timestampMicros;
    _pendingDomSamples.add(_DomSample(
      pointerId: pointerId,
      timestampMicros: timestampMicros,
      x: event.clientX.toDouble(),
      y: event.clientY.toDouble(),
      sequence: _domSequence++,
    ));
    _appendPathPoint(_rawDomPath, <String, Object>{
      'pointer_id': pointerId,
      't_us': timestampMicros,
      'x': event.clientX.toDouble(),
      'y': event.clientY.toDouble(),
    });
  }
  if (_pendingDomSamples.length > 1024) {
    final overflow = _pendingDomSamples.length - 1024;
    _missingSampleCount += overflow;
    _pendingDomSamples.removeRange(0, overflow);
  }
  if (_coalescedCounts.length > 2048) {
    _coalescedCounts.removeRange(0, _coalescedCounts.length - 2048);
  }
  if (_effectiveIntervals.length > 4096) {
    _effectiveIntervals.removeRange(0, _effectiveIntervals.length - 4096);
  }
}

List<web.PointerEvent> _eventArray(JSObject event, String methodName) {
  final method = event.getProperty<JSAny?>(methodName.toJS);
  if (method is! JSFunction) return <web.PointerEvent>[];
  final result = method.callAsFunction(event);
  if (result is! JSArray) return <web.PointerEvent>[];
  return <web.PointerEvent>[
    for (final value in result.toDart)
      if (value is web.PointerEvent) value,
  ];
}

/// Flutter Web is the sole production input owner. DOM samples are retained
/// only for delivery parity diagnostics and are never appended to a stroke.
List<PawBrowserCoalescedSample> pawTakeCoalescedInputSamples() =>
    const <PawBrowserCoalescedSample>[];

void pawRecordFlutterPointerSample({
  required int pointerId,
  required int timestampMicros,
  required double x,
  required double y,
  required bool accepted,
}) {
  _flutterPointerMoveSamples++;
  if (accepted) _acceptedHardwareSamples++;
  final point = <String, Object>{
    'pointer_id': pointerId,
    't_us': timestampMicros,
    'x': x,
    'y': y,
  };
  _appendPathPoint(_flutterDeliveredPath, point);
  if (accepted) _appendPathPoint(_pawDoodleAcceptedPath, point);
  final signature = '$pointerId:$timestampMicros:${x.toStringAsFixed(2)}:'
      '${y.toStringAsFixed(2)}';
  if (!_matchedFlutterSignatures.add(signature)) _duplicateSampleCount++;
  if (_matchedFlutterSignatures.length > 2048) {
    _matchedFlutterSignatures.clear();
  }

  var bestIndex = -1;
  var bestScore = double.infinity;
  for (var index = 0; index < _pendingDomSamples.length; index++) {
    final candidate = _pendingDomSamples[index];
    if (!_pointerIdentityMap.canMatch(pointerId, candidate.pointerId)) continue;
    final dt = (candidate.timestampMicros - timestampMicros).abs();
    final dx = candidate.x - x;
    final dy = candidate.y - y;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (dt > 3000 || distance > 2.5) continue;
    final score = dt + distance * 500;
    if (score < bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  if (bestIndex < 0) {
    _missingSampleCount++;
    return;
  }
  final matched = _pendingDomSamples.removeAt(bestIndex);
  _pointerIdentityMap.bind(pointerId, matched.pointerId);
  final previousSequence = _lastMatchedSequenceByPointer[pointerId];
  if (previousSequence != null && matched.sequence < previousSequence) {
    _reorderedSampleCount++;
  }
  _lastMatchedSequenceByPointer[pointerId] = matched.sequence;
}

void pawRecordModeledCenterlineSample({
  required int timestampMicros,
  required double x,
  required double y,
  required int revision,
}) {
  _appendPathPoint(_modeledCenterlinePath, <String, Object>{
    't_us': timestampMicros,
    'x': x,
    'y': y,
    'revision': revision,
  });
}

void _appendPathPoint(
  List<Map<String, Object>> target,
  Map<String, Object> point,
) {
  if (target.length >= 4096) target.removeAt(0);
  target.add(Map<String, Object>.unmodifiable(point));
}

void pawResetInputDeliveryDiagnostics() {
  _pendingDomSamples.clear();
  _coalescedCounts.clear();
  _effectiveIntervals.clear();
  _lastEffectiveTimestampByPointer.clear();
  _lastMatchedSequenceByPointer.clear();
  _matchedFlutterSignatures.clear();
  _pointerIdentityMap.clear();
  _rawDomPath.clear();
  _flutterDeliveredPath.clear();
  _pawDoodleAcceptedPath.clear();
  _modeledCenterlinePath.clear();
  _domSequence = 0;
  _domDispatchedEvents = 0;
  _domCoalescedEvents = 0;
  _domPredictedEvents = 0;
  _flutterPointerMoveSamples = 0;
  _acceptedHardwareSamples = 0;
  _missingSampleCount = 0;
  _duplicateSampleCount = 0;
  _reorderedSampleCount = 0;
}

PawWebInputEnvironment pawWebInputEnvironment() {
  try {
    final userAgent = web.window.navigator.userAgent;
    return PawWebInputEnvironment(
      isSecureContext: web.window.isSecureContext,
      locationProtocol: web.window.location.protocol,
      locationOrigin: web.window.location.origin,
      userAgent: userAgent,
      platform: web.window.navigator.platform,
      navigatorVendor: web.window.navigator.vendor,
      browserVersion: _browserVersion(userAgent),
      flutterVersion: _flutterVersion,
      dartVersion: _dartVersion,
      wasmOrJs: kIsWasm ? 'wasm' : 'js',
      renderer: web.document.querySelector('flt-glass-pane') == null
          ? 'unknown'
          : 'flutter-web',
      actualEventSeen: _actualEventSeen,
      actualPointerEventHasGetCoalescedEvents: _actualCoalescedCallable,
      actualPointerEventHasGetPredictedEvents: _actualPredictedCallable,
      syntheticEventHasGetCoalescedEvents: false,
      pointerRawUpdateSupported: pawPointerRawUpdateSupported,
      diagnosticsStatus: _diagnosticsStatus,
      diagnosticsReason: _diagnosticsReason,
    );
  } catch (error) {
    _diagnosticsStatus = PawPointerDiagnosticsStatus.failed;
    _diagnosticsReason = error.toString();
    return PawWebInputEnvironment(
      isSecureContext: false,
      locationProtocol: 'unknown:',
      locationOrigin: '',
      userAgent: '',
      platform: 'web',
      navigatorVendor: '',
      browserVersion: 'unavailable',
      flutterVersion: _flutterVersion,
      dartVersion: _dartVersion,
      wasmOrJs: kIsWasm ? 'wasm' : 'js',
      renderer: 'unknown',
      actualEventSeen: _actualEventSeen,
      actualPointerEventHasGetCoalescedEvents: false,
      actualPointerEventHasGetPredictedEvents: false,
      syntheticEventHasGetCoalescedEvents: false,
      pointerRawUpdateSupported: false,
      diagnosticsStatus: PawPointerDiagnosticsStatus.failed,
      diagnosticsReason: _diagnosticsReason,
    );
  }
}

PawInputDeliveryParityDiagnostics pawInputDeliveryParityDiagnostics() =>
    PawInputDeliveryParityDiagnostics(
      domDispatchedEvents: _domDispatchedEvents,
      domCoalescedEvents: _domCoalescedEvents,
      domPredictedEvents: _domPredictedEvents,
      flutterPointerMoveSamples: _flutterPointerMoveSamples,
      pawDoodleAcceptedHardwareSamples: _acceptedHardwareSamples,
      missingSampleCount: _missingSampleCount + _pendingDomSamples.length,
      duplicateSampleCount: _duplicateSampleCount,
      reorderedSampleCount: _reorderedSampleCount,
      coalescedEventsPerPointerEvent: _distribution(_coalescedCounts),
      effectiveHardwareSampleIntervalMicros: _distribution(_effectiveIntervals),
      customBridgeProductionIngestion: false,
      predictionOwner: 'PawStreamingCenterlineModeler',
    );

PawInputLayerPathBoard pawInputLayerPathBoard() => PawInputLayerPathBoard(
      rawDom: List<Map<String, Object>>.unmodifiable(_rawDomPath),
      flutterDelivered:
          List<Map<String, Object>>.unmodifiable(_flutterDeliveredPath),
      pawDoodleAccepted:
          List<Map<String, Object>>.unmodifiable(_pawDoodleAcceptedPath),
      modeledCenterline:
          List<Map<String, Object>>.unmodifiable(_modeledCenterlinePath),
    );

Map<String, num> _distribution(List<int> input) {
  if (input.isEmpty) {
    return const <String, num>{
      'min': 0,
      'p50': 0,
      'p95': 0,
      'p99': 0,
      'max': 0,
    };
  }
  final values = List<int>.of(input)..sort();
  int percentile(double p) => values[((values.length - 1) * p).round()];
  return <String, num>{
    'min': values.first,
    'p50': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
    'max': values.last,
  };
}

String _browserVersion(String userAgent) {
  final safari = RegExp(r'Version/([0-9.]+).*Safari/').firstMatch(userAgent);
  if (safari != null) return 'Safari ${safari.group(1)}';
  final chrome = RegExp(r'(?:Chrome|CriOS)/([0-9.]+)').firstMatch(userAgent);
  if (chrome != null) return 'Chrome ${chrome.group(1)}';
  final firefox = RegExp(r'(?:Firefox|FxiOS)/([0-9.]+)').firstMatch(userAgent);
  if (firefox != null) return 'Firefox ${firefox.group(1)}';
  return 'unparsed';
}
