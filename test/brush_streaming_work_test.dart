import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_preset.dart';
import 'package:pawdoodle_brush_engine/src/drawing_raster.dart';
import 'package:pawdoodle_brush_engine/src/smooth_stroke.dart';
import 'package:pawdoodle_brush_engine/src/streaming_dab_brush.dart';

void main() {
  test('sustained Fur input records bounded material work', () async {
    final preset = PawBrushPresetCatalog.forTool(DrawingTool.furBrush);
    await PawDabResource.prepareAsync(preset.definition,
        rasterProgram: preset.rasterProgram);
    final stroke = preset.createStroke(
        seed: const PawStrokeTextureSeed(71),
        color: const Color(0xff202020),
        baseSize: 18);
    final cache = PawStreamingDabRenderCache(logicalSize: const Size(512, 512));
    final timings = <int>[];
    var sections = 0, commands = 0;
    try {
      for (var i = 0; i < 241; i++) {
        final angle = i * math.pi / 120;
        stroke.appendSample(DrawingInputSample(
            x: 256 + 100 * math.cos(angle),
            y: 256 + 100 * math.sin(angle),
            timestamp: Duration(microseconds: i * 8333),
            pressure: .72,
            pressureMin: 0,
            pressureMax: 1,
            deviceKind: PointerDeviceKind.touch));
        final clock = Stopwatch()..start();
        cache.sync(stroke);
        timings.add(clock.elapsedMicroseconds);
        sections += cache.lastFilamentSegmentCount;
        commands += cache.lastRecordedDabChunkCount;
        expect(stroke.predictionSegmentCount, 0);
        if (i > 0) {
          expect(
              (stroke.previewSegments.last.p1 -
                      Offset(256 + 100 * math.cos(angle),
                          256 + 100 * math.sin(angle)))
                  .distance,
              lessThan(1e-6));
        }
      }
      timings.sort();
      // Work and timings are evidence, not device-dependent pass thresholds.
      // ignore: avoid_print
      print(
          'DENSE_FUR median_us=${timings[timings.length ~/ 2]} p95_us=${timings[(timings.length * .95).floor()]} commands=$commands hair_segments=$sections');
    } finally {
      cache.dispose();
    }
  });
}
