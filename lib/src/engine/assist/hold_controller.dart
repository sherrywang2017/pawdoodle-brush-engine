part of '../../held_stroke_assist.dart';

typedef PawStrokeHoldTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

class PawStrokeHoldAssistController {
  PawStrokeHoldAssistController({
    this.configuration = const PawStrokeHoldAssistConfiguration(),
    this.refiner = const PawHeldStrokeRefiner(),
    this.onDiagnostic,
    this.onAssistTriggered,
    this.onAssistUpdated,
    PawStrokeHoldTimerFactory? timerFactory,
  }) : _timerFactory = timerFactory ?? _defaultTimerFactory;

  final PawStrokeHoldAssistConfiguration configuration;
  final PawHeldStrokeRefiner refiner;
  final ValueChanged<PawStrokeAssistDiagnosticEvent>? onDiagnostic;
  final ValueChanged<PawStrokeAssistResult>? onAssistTriggered;
  final ValueChanged<PawStrokeAssistResult>? onAssistUpdated;
  final PawStrokeHoldTimerFactory _timerFactory;
  final List<DrawingInputSample> _rawSamples = <DrawingInputSample>[];

  Timer? _timer;
  PawStrokeHoldAssistState _state = PawStrokeHoldAssistState.inactive;
  bool _pointerDown = false;
  bool _meaningfulDrawing = false;
  bool _candidateDiagnosticEmitted = false;
  double _pathLength = 0;
  Offset? _holdAnchor;
  PawStrokeAssistResult? _result;
  final Stopwatch _timelineClock = Stopwatch();
  bool _assistPresented = false;
  int? _holdTriggeredAtMicros;
  int? _assistGeometryReadyAtMicros;
  int? _assistMaterialReadyAtMicros;
  int _lastMeaningfulSampleIndex = 0;
  HoldInputSnapshot? _holdSnapshot;

  PawStrokeHoldAssistState get state => _state;
  PawStrokeAssistResult? get result => _result;
  List<DrawingInputSample> get rawSamples =>
      List<DrawingInputSample>.unmodifiable(_rawSamples);
  HoldInputSnapshot? get holdSnapshot => _holdSnapshot;

  void pointerDown(DrawingInputSample sample) {
    _timer?.cancel();
    _timer = null;
    _rawSamples
      ..clear()
      ..add(sample);
    _pointerDown = true;
    _meaningfulDrawing = false;
    _candidateDiagnosticEmitted = false;
    _pathLength = 0;
    _holdAnchor = sample.position;
    _result = null;
    _timelineClock
      ..reset()
      ..start();
    _assistPresented = false;
    _holdTriggeredAtMicros = null;
    _assistGeometryReadyAtMicros = null;
    _assistMaterialReadyAtMicros = null;
    _lastMeaningfulSampleIndex = 0;
    _holdSnapshot = null;
    _state = PawStrokeHoldAssistState.tracking;
  }

  void addSample(DrawingInputSample sample) {
    if (!_pointerDown || !sample.hasFinitePosition) return;
    final previous = _rawSamples.isEmpty ? null : _rawSamples.last;
    // Safari/Pencil can redeliver an older coalesced batch. The drawing
    // modeler rejects it; Hold must not turn it into a backwards path or
    // restart its deadline. Identical timestamps cannot describe a new move.
    if (previous != null && sample.timestamp <= previous.timestamp) return;
    if (previous != null) {
      _pathLength += (sample.position - previous.position).distance;
    }
    if (_rawSamples.length < configuration.maximumRawPoints) {
      _rawSamples.add(sample);
    }
    if (_state == PawStrokeHoldAssistState.assistedHolding) {
      final current = _result;
      if (current != null &&
          current.kind == PawStrokeAssistKind.line &&
          previous != null &&
          (sample.position - previous.position).distance >=
              configuration.jitterRadius) {
        _result = refiner.adjustLineEndpoint(current, _rawSamples);
        onAssistUpdated?.call(_result!);
      }
      return;
    }
    if (!_meaningfulDrawing &&
        _pathLength >= configuration.minimumMeaningfulPathLength) {
      _meaningfulDrawing = true;
      _holdAnchor = sample.position;
      _lastMeaningfulSampleIndex = _rawSamples.length - 1;
      _restartDeadline(restarted: false);
      return;
    }
    if (!_meaningfulDrawing) return;
    final anchor = _holdAnchor ?? sample.position;
    if ((sample.position - anchor).distance > configuration.jitterRadius) {
      _holdAnchor = sample.position;
      _lastMeaningfulSampleIndex = _rawSamples.length - 1;
      _restartDeadline(restarted: true);
    } else if (_timer == null) {
      _restartDeadline(restarted: false);
    }
  }

  PawStrokeAssistResult? pointerUp(DrawingInputSample sample) {
    if (_state != PawStrokeHoldAssistState.assistedHolding &&
        _pointerDown &&
        (_rawSamples.isEmpty ||
            sample.timestamp != _rawSamples.last.timestamp ||
            sample.position != _rawSamples.last.position)) {
      addSample(sample);
    }
    _timer?.cancel();
    _timer = null;
    _pointerDown = false;
    _state = PawStrokeHoldAssistState.committed;
    onDiagnostic?.call(PawStrokeAssistDiagnosticEvent(
      'hold_pointer_up',
      <String, Object>{
        'pointer_up_us': _timelineClock.elapsedMicroseconds,
        'assist_presented_before_up': _assistPresented,
      },
    ));
    _timelineClock.stop();
    return _result;
  }

  void recordAssistPublished(int geometryRevision) {
    if (_state != PawStrokeHoldAssistState.assistedHolding) return;
    final now = _timelineClock.elapsedMicroseconds;
    _assistMaterialReadyAtMicros = now;
    onDiagnostic?.call(PawStrokeAssistDiagnosticEvent(
      'hold_assist_published',
      <String, Object>{
        'assist_geometry_revision': geometryRevision,
        'assist_overlay_published_us': now,
        'hold_trigger_to_geometry_us': _elapsedFrom(
          _holdTriggeredAtMicros,
          _assistGeometryReadyAtMicros,
        ),
        'hold_geometry_to_material_us': _elapsedFrom(
          _assistGeometryReadyAtMicros,
          _assistMaterialReadyAtMicros,
        ),
      },
    ));
  }

  void recordAssistGeometryReady(int geometryRevision) {
    if (_state != PawStrokeHoldAssistState.assistedHolding) return;
    _assistGeometryReadyAtMicros = _timelineClock.elapsedMicroseconds;
  }

  void recordAssistPresented() {
    if (_state != PawStrokeHoldAssistState.assistedHolding ||
        _assistPresented) {
      return;
    }
    _assistPresented = true;
    final now = _timelineClock.elapsedMicroseconds;
    onDiagnostic?.call(PawStrokeAssistDiagnosticEvent(
      'hold_assist_presented',
      <String, Object>{
        'assist_first_frame_presented_us': now,
        'hold_trigger_to_present_us': _elapsedFrom(_holdTriggeredAtMicros, now),
      },
    ));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pointerDown = false;
    _state = PawStrokeHoldAssistState.inactive;
    _rawSamples.clear();
    _result = null;
    _timelineClock.stop();
    _pathLength = 0;
    _meaningfulDrawing = false;
    _candidateDiagnosticEmitted = false;
    _holdAnchor = null;
    _lastMeaningfulSampleIndex = 0;
    _holdSnapshot = null;
    _holdTriggeredAtMicros = null;
    _assistGeometryReadyAtMicros = null;
    _assistMaterialReadyAtMicros = null;
  }

  void dispose() => cancel();

  void _restartDeadline({required bool restarted}) {
    _timer?.cancel();
    _state = PawStrokeHoldAssistState.holdCandidate;
    if (!_candidateDiagnosticEmitted) {
      _candidateDiagnosticEmitted = true;
      onDiagnostic?.call(PawStrokeAssistDiagnosticEvent(
        'hold_candidate_started',
        <String, Object>{
          'hold_delay_us': configuration.holdDelay.inMicroseconds,
          'raw_point_count': _rawSamples.length,
          'deadline_restarted': restarted,
          'hold_candidate_started_us': _timelineClock.elapsedMicroseconds,
        },
      ));
    }
    _timer = _timerFactory(configuration.holdDelay, _triggerAssist);
  }

  void _triggerAssist() {
    _timer = null;
    if (!_pointerDown || !_meaningfulDrawing || _rawSamples.length < 2) return;
    final snapshotEnd =
        _lastMeaningfulSampleIndex.clamp(1, _rawSamples.length - 1);
    final snapshotSamples = _rawSamples.sublist(0, snapshotEnd + 1);
    _holdTriggeredAtMicros = _timelineClock.elapsedMicroseconds;
    _holdSnapshot = HoldInputSnapshot(
      samples: snapshotSamples,
      lastMeaningfulMovement: snapshotSamples.last.timestamp,
    );
    final result = refiner.refine(
      snapshotSamples,
      configuration: configuration,
    );
    if (result.refinedSegments.isEmpty) return;
    _result = result;
    _state = PawStrokeHoldAssistState.assistedHolding;
    onAssistTriggered?.call(result);
    onDiagnostic?.call(PawStrokeAssistDiagnosticEvent(
      'hold_assist_triggered',
      <String, Object>{
        ...result.diagnostics(configuration.holdDelay),
        'hold_snapshot_raw_count': snapshotSamples.length,
        'hold_triggered_us': _timelineClock.elapsedMicroseconds,
      },
    ));
  }

  static int _elapsedFrom(int? start, int? end) {
    if (start == null || end == null) return 0;
    return math.max(0, end - start);
  }

  static Timer _defaultTimerFactory(
    Duration delay,
    void Function() callback,
  ) =>
      Timer(delay, callback);
}
