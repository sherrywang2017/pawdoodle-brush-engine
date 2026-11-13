import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_preset.dart';
import 'package:pawdoodle_brush_engine/src/smooth_stroke.dart';
import 'package:pawdoodle_brush_engine/src/streaming_dab_brush.dart';
import 'package:pawdoodle_brush_engine/src/brush_studio_settings.dart';
import 'package:pawdoodle_brush_engine/src/swept_coverage.dart';

Future<Uint8List> renderStudio(
    PawStudioSettings settings, List<Offset> controls, String name) async {
  final preset =
      PawBrushProgramCompiler.compileUserV2(settings.toPreset('topology', 1));
  await PawDabResource.prepareAsync(preset.definition,
      rasterProgram: preset.rasterProgram);
  final stroke = preset.createStroke(
      seed: const PawStrokeTextureSeed(71),
      color: const Color(0xff476b50),
      baseSize: 34);
  var time = 0;
  for (var i = 1; i < controls.length; i++) {
    final a = controls[i - 1], b = controls[i];
    final steps = ((b - a).distance / 3).ceil();
    for (var j = i == 1 ? 0 : 1; j <= steps; j++) {
      final p = Offset.lerp(a, b, j / steps)!;
      stroke.appendSample(DrawingInputSample(
          x: p.dx,
          y: p.dy,
          timestamp: Duration(milliseconds: time),
          pressure: .5,
          pressureMin: 0,
          pressureMax: 1,
          deviceKind: PointerDeviceKind.touch));
      time += 8;
    }
  }
  stroke.freeze();
  final cache = PawStreamingDabRenderCache(logicalSize: const Size(512, 320));
  final recorder = PictureRecorder();
  const PawStreamingDabRenderer().paint(
      canvas: Canvas(recorder),
      outputSize: const Size(512, 320),
      logicalSize: const Size(512, 320),
      physicalTargetRasterScale: 1,
      stroke: stroke,
      renderCache: cache);
  final picture = recorder.endRecording();
  final image = await picture.toImage(512, 320);
  try {
    if (Platform.environment['PAW_EXPORT_STUDIO'] case final String dir) {
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(
          (await image.toByteData(format: ImageByteFormat.png))!
              .buffer
              .asUint8List());
    }
    return (await image.toByteData())!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    cache.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a short zero-size Round tip is not swallowed by a body contact',
      () async {
    final pixels = await renderStudio(
        const PawStudioSettings(
            tipRoundness: 0,
            startTaper: .15,
            endTaper: .15,
            pressure: 0,
            softness: 0),
        const [Offset(100, 120), Offset(400, 120)],
        'short-point');
    for (var y = 90; y < 150; y++) {
      expect(pixels[(y * 512 + 98) * 4 + 3], 0);
      expect(pixels[(y * 512 + 401) * 4 + 3], 0);
    }
    expect(pixels[(120 * 512 + 102) * 4 + 3], greaterThan(80));
  });
  test('taper opens without a neck and becomes tangent to the body', () {
    const endpoint = PawUnifiedBrushEndpointProfile(
        startTaperBrushLengths: 2, minimumSizeFactor: .4, tangentSize: true);
    double width(double x) =>
        endpoint.sizeScaleAt(absoluteArc: x, renderEndArc: 300, brushSize: 30);
    var previousSlope = double.infinity;
    for (var x = 0; x < 60; x++) {
      final slope = width(x + 1) - width(x.toDouble());
      expect(slope, greaterThanOrEqualTo(0));
      expect(slope, lessThanOrEqualTo(previousSlope + .000001));
      previousSlope = slope;
    }
    expect(width(60) - width(59.99), lessThan(.000001));
  });
  test('endpoint opacity is continuous across a full-width round tip',
      () async {
    final coverage = PawSweptCoverage(
        sections: [
          for (var x = 100; x <= 400; x++)
            PawSweepSection(Offset(x.toDouble(), 80), 24, .8,
                opacity: .6 + .4 * ((x - 100) / 80).clamp(0, 1))
        ],
        hardness: 1,
        capRoundness: 1,
        color: const Color(0xff26362a),
        coverageCeiling: .8);
    final recorder = PictureRecorder();
    coverage.paint(Canvas(recorder));
    final picture = recorder.endRecording();
    final image = await picture.toImage(512, 160);
    final pixels = (await image.toByteData())!.buffer.asUint8List();
    int alpha(int x) => pixels[(80 * 512 + x) * 4 + 3];
    expect(alpha(90), closeTo(122, 2));
    expect(alpha(190), closeTo(204, 2));
    for (var x = 101; x < 180; x++) {
      expect((alpha(x) - alpha(x - 1)).abs(), lessThanOrEqualTo(3));
    }
    image.dispose();
    picture.dispose();
    coverage.dispose();
  });
  test('Flat keeps a straight cut at every tip aspect and endpoint size',
      () async {
    for (final aspect in [.1, .91, 1.0]) {
      for (final size in [0.0, .4, 1.0]) {
        final pixels = await renderStudio(
            PawStudioSettings(
                tip: PawStudioTip.flat,
                tipAspect: aspect,
                tipRoundness: size,
                pressure: 0,
                softness: 0),
            const [Offset(100, 120), Offset(400, 120)],
            'flat-$aspect-$size');
        for (var y = 90; y < 150; y++) {
          expect(pixels[(y * 512 + 98) * 4 + 3], 0);
          expect(pixels[(y * 512 + 401) * 4 + 3], 0);
        }
        if (size == 1) {
          for (var y = 110; y <= 130; y++) {
            expect(pixels[(y * 512 + 100) * 4 + 3], greaterThan(100));
          }
        }
      }
    }
  });
  const loop = [
    Offset(80, 160),
    Offset(90, 210),
    Offset(220, 215),
    Offset(400, 125),
    Offset(230, 90),
    Offset(210, 200),
    Offset(340, 140),
    Offset(380, 260),
    Offset(410, 190)
  ];
  test('tip size changes actual endpoint widths continuously', () async {
    int widthAt(Uint8List pixels, int x) {
      var count = 0;
      for (var y = 80; y < 160; y++) {
        if (pixels[(y * 512 + x) * 4 + 3] > 50) count++;
      }
      return count;
    }

    for (final tip in [PawStudioTip.round, PawStudioTip.flat]) {
      final widths = <int>[];
      for (final roundness in [0.0, .5, 1.0]) {
        final pixels = await renderStudio(
            PawStudioSettings(
                tip: tip,
                pressure: 0,
                tipRoundness: roundness,
                startTaper: 1.5,
                endTaper: 1.5),
            const [Offset(100, 120), Offset(400, 120)],
            'tip-${tip.name}-$roundness');
        widths.add(widthAt(pixels, 105));
        expect(widthAt(pixels, 250), greaterThan(24));
      }
      expect(widths[1], greaterThan(widths[0] + 3));
      expect(widths[2], greaterThan(widths[1] + 3));
    }
  });
  for (final tip in [PawStudioTip.round, PawStudioTip.flat]) {
    for (final grain in [PawStudioGrain.paper, PawStudioGrain.fibers]) {
      test(
          '${tip.name} ${grain.name} contact does not darken into triangles at folds',
          () async {
        final settings =
            PawStudioSettings(tip: tip, grain: grain, pressure: 0, flow: .6);
        final pixels = await renderStudio(
            settings, loop, '${tip.name}-${grain.name}-loop');
        var peak = 0;
        for (var i = 3; i < pixels.length; i += 4) {
          if (pixels[i] > peak) peak = pixels[i];
        }
        // One translucent stroke has one coverage ceiling, even at a fold.
        expect(peak, lessThanOrEqualTo(156));
      });
    }
  }
}
