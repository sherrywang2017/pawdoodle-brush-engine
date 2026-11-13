import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_preset.dart';
import 'package:pawdoodle_brush_engine/src/smooth_stroke.dart';
import 'package:pawdoodle_brush_engine/src/streaming_dab_brush.dart';
import 'package:pawdoodle_brush_engine/src/brush_studio_settings.dart';

Future<int> paintedPixels(PawCompiledBrushPreset preset, double size) async {
  await PawDabResource.prepareAsync(preset.definition,
      rasterProgram: preset.rasterProgram);
  final stroke = preset.createStroke(
      seed: const PawStrokeTextureSeed(71),
      color: const Color(0xff202020),
      baseSize: size);
  for (var i = 0; i <= 40; i++) {
    stroke.appendSample(DrawingInputSample(
        x: 40 + i * 4,
        y: 64,
        timestamp: Duration(milliseconds: i * 8),
        pressure: .5,
        pressureMin: 0,
        pressureMax: 1,
        deviceKind: PointerDeviceKind.touch));
  }
  stroke.freeze();
  final cache = PawStreamingDabRenderCache(logicalSize: const Size(256, 128));
  final recorder = PictureRecorder();
  const PawStreamingDabRenderer().paint(
      canvas: Canvas(recorder),
      outputSize: const Size(256, 128),
      logicalSize: const Size(256, 128),
      physicalTargetRasterScale: 1,
      stroke: stroke,
      renderCache: cache);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 128);
  try {
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    var count = 0;
    for (var i = 3; i < bytes.length; i += 4) {
      if (bytes[i] > 32) count++;
    }
    return count;
  } finally {
    image.dispose();
    picture.dispose();
    cache.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final tip in PawStudioTip.values) {
    test(
        'authored ${tip.name} delivers canvas and Studio size into actual pixels',
        () async {
      PawCompiledBrushPreset compile(double scale) =>
          PawBrushProgramCompiler.compileUserV2(
              PawStudioSettings(tip: tip, size: scale, pressure: 0)
                  .toPreset('size-${tip.name}', 1));
      final small = await paintedPixels(compile(1), 8);
      final large = await paintedPixels(compile(1), 24);
      final authored = await paintedPixels(compile(2), 8);
      expect(small, greaterThan(0));
      expect(large, greaterThan(small * 1.8));
      expect(authored, greaterThan(small * 1.3));
    });
  }
}
