import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:pawdoodle_brush_engine/pawdoodle_brush_engine.dart';

void main() => runApp(const BrushDemo());

class BrushDemo extends StatelessWidget {
  const BrushDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PawDoodle Brush Engine',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff395d49)),
      scaffoldBackgroundColor: const Color(0xfff4efe7),
    ),
    home: const BrushCanvas(),
  );
}

const _presets = <String, DrawingTool>{
  'Round': DrawingTool.roundBrush,
  'Marker': DrawingTool.marker,
  'Crayon': DrawingTool.crayon,
  'Soft': DrawingTool.softBrush,
  'Ink': DrawingTool.inkBrush,
  'Fur': DrawingTool.furBrush,
};

const _ink = Color(0xff293c34);
const _colors = [_ink, Color(0xffa34e36), Color(0xff375b8b), Color(0xff765287)];

class BrushCanvas extends StatefulWidget {
  const BrushCanvas({super.key});

  @override
  State<BrushCanvas> createState() => _BrushCanvasState();
}

class _BrushCanvasState extends State<BrushCanvas> {
  final _strokes = <PawStreamingBrushInteraction>[];
  late final Future<Map<String, PawCompiledBrushPreset>> _presetsFuture =
      _preparePresets();
  PawStreamingBrushInteraction? _active;
  Timer? _materialTimer;
  int? _pointer;
  int _nextSeed = 71;
  String _selected = 'Crayon';
  Color _color = _ink;
  double _width = 20;

  Future<Map<String, PawCompiledBrushPreset>> _preparePresets() async {
    final presets = {
      for (final entry in _presets.entries)
        entry.key: PawBrushPresetCatalog.forTool(entry.value),
      'Custom': PawBrushProgramCompiler.compileUserV2(
        const PawStudioSettings(
          tip: PawStudioTip.flat,
          flow: .65,
          texture: .55,
        ).toPreset('demo-paper-flat', 1),
      ),
    };
    for (final preset in presets.values) {
      await PawDabResource.prepareAsync(
        preset.definition,
        rasterProgram: preset.rasterProgram,
      );
    }
    return presets;
  }

  PawStreamingBrushInteraction _start(
    PawCompiledBrushPreset preset,
    Color color,
    double width,
    Size size,
    double scale,
    DrawingInputSample first,
  ) => PawDabStreamingBackend.forPreset(preset)
      .start(
        seed: PawStrokeTextureSeed(_nextSeed++),
        color: color,
        baseSize: width,
        logicalSize: size,
        rasterScale: scale,
        initialSample: first,
        compositeOperation: PawStreamingCompositeOperation.paint,
        capturePerformance: false,
      )
      .interaction;

  DrawingInputSample _sample(PointerEvent event) => DrawingInputSample(
    x: event.localPosition.dx,
    y: event.localPosition.dy,
    timestamp: event.timeStamp,
    pressure: event.pressure,
    pressureMin: event.pressureMin,
    pressureMax: event.pressureMax,
    deviceKind: event.kind,
  );

  void _scheduleMaterial(PawStreamingBrushInteraction interaction) {
    final stroke = interaction.stroke;
    if (stroke is! PawTemporalBrushStroke) return;
    final material = stroke as PawTemporalBrushStroke;
    if (!material.hasUnsettledMaterial) return;
    final watch = Stopwatch()..start();
    _materialTimer = Timer(const Duration(milliseconds: 32), () {
      if (material.advanceMaterialClock(watch.elapsed)) setState(() {});
      _scheduleMaterial(interaction);
    });
  }

  void _end({required bool commit}) {
    _materialTimer?.cancel();
    final stroke = _active;
    if (stroke == null) return;
    if (commit) {
      stroke.stroke.freeze();
      _strokes.add(stroke);
    } else {
      stroke.dispose();
    }
    _active = null;
    _pointer = null;
  }

  void _clear() {
    _end(commit: false);
    for (final stroke in _strokes) {
      stroke.dispose();
    }
    _strokes.clear();
  }

  void _showSamples(
    Map<String, PawCompiledBrushPreset> presets,
    Size size,
    double scale,
  ) {
    _clear();
    final names = presets.keys.toList();
    for (var row = 0; row < names.length; row++) {
      final name = names[row];
      DrawingInputSample sample(int i) {
        final t = i / 48;
        return DrawingInputSample(
          x: size.width * (.17 + .66 * t),
          y:
              size.height *
              ((row + 1) / (names.length + 1) +
                  .021 * math.sin(t * 2 * math.pi)),
          timestamp: Duration(milliseconds: i * 16),
          pressure: .35 + .58 * math.sin(math.pi * t),
          pressureMin: 0,
          pressureMax: 1,
          deviceKind: PointerDeviceKind.stylus,
        );
      }

      final width = math.min(name == 'Fur' ? 13.0 : 24.0, size.height / 22);
      final stroke = _start(
        presets[name]!,
        _colors[row % _colors.length],
        width,
        size,
        scale,
        sample(0),
      );
      for (var i = 1; i <= 48; i++) {
        stroke.appendSample(sample(i));
      }
      stroke.stroke.freeze();
      _strokes.add(stroke);
    }
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FutureBuilder(
              future: _presetsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Brushes failed to load. ${snapshot.error}'),
                  );
                }
                final presets = snapshot.data;
                if (presets == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _workspace(context, presets);
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _workspace(
    BuildContext context,
    Map<String, PawCompiledBrushPreset> presets,
  ) {
    final theme = Theme.of(context);
    final scale = MediaQuery.devicePixelRatioOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PawDoodle Brush Engine', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 5),
        const Text('Choose a brush and draw with a mouse, finger, or stylus.'),
        const SizedBox(height: 15),
        Wrap(
          spacing: 6,
          children: [
            for (final name in presets.keys)
              ChoiceChip(
                label: Text(name),
                selected: _selected == name,
                onSelected: (_) => setState(() => _selected = name),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (index, color) in _colors.indexed)
              IconButton(
                tooltip: const ['Forest', 'Terracotta', 'Blue', 'Plum'][index],
                isSelected: _color == color,
                icon: Icon(Icons.circle, color: color),
                selectedIcon: Icon(Icons.check_circle, color: color),
                onPressed: () => setState(() => _color = color),
              ),
            Text('Size ${_width.round()}'),
            SizedBox(
              width: 140,
              child: Slider(
                value: _width,
                min: 3,
                max: 64,
                onChanged: (width) => setState(() => _width = width),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColoredBox(
                  color: const Color(0xfffffdf7),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) {
                              if (_pointer != null ||
                                  (event.kind == PointerDeviceKind.mouse &&
                                      event.buttons != 1))
                                return;
                              setState(() {
                                _pointer = event.pointer;
                                final interaction = _start(
                                  presets[_selected]!,
                                  _color,
                                  _width,
                                  size,
                                  scale,
                                  _sample(event),
                                );
                                _active = interaction;
                                _scheduleMaterial(interaction);
                              });
                            },
                            onPointerMove: (event) {
                              if (_pointer != event.pointer) return;
                              _materialTimer?.cancel();
                              final stroke = _active!;
                              stroke.appendSample(_sample(event));
                              _scheduleMaterial(stroke);
                              setState(() {});
                            },
                            onPointerUp: (event) {
                              if (_pointer != event.pointer) return;
                              _active!.appendSample(_sample(event));
                              setState(() => _end(commit: true));
                            },
                            onPointerCancel: (event) {
                              if (_pointer == event.pointer) {
                                setState(() => _end(commit: false));
                              }
                            },
                            child: RepaintBoundary(
                              child: CustomPaint(
                                painter: _StrokePainter([
                                  ..._strokes,
                                  if (_active != null) _active!,
                                ], scale),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        bottom: 10,
                        child: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => setState(
                                () => _showSamples(presets, size, scale),
                              ),
                              child: const Text('Samples'),
                            ),
                            TextButton(
                              onPressed: _strokes.isEmpty && _active == null
                                  ? null
                                  : () => setState(_clear),
                              child: const Text('Clear'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.strokes, this.scale);

  final List<PawStreamingBrushInteraction> strokes;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final interaction in strokes) {
      interaction.paint(
        canvas: canvas,
        outputSize: size,
        logicalSize: size,
        physicalTargetRasterScale: scale,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokePainter oldDelegate) => true;
}
