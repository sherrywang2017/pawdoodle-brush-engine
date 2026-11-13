import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_preset.dart';
import 'package:pawdoodle_brush_engine/src/brush_raster_resource.dart';
import 'package:pawdoodle_brush_engine/src/drawing_raster.dart';
import 'package:pawdoodle_brush_engine/src/held_stroke_assist.dart';
import 'package:pawdoodle_brush_engine/src/smooth_stroke.dart';
import 'package:pawdoodle_brush_engine/src/streaming_brush_backend.dart';
import 'package:pawdoodle_brush_engine/src/streaming_brush_engine.dart';
import 'package:pawdoodle_brush_engine/src/streaming_dab_brush.dart';

DrawingInputSample _touch((int, double, double) value) => DrawingInputSample(
      x: value.$2,
      y: value.$3,
      timestamp: Duration(microseconds: value.$1),
      pressure: 0,
      pressureMin: 0,
      pressureMax: 1,
      deviceKind: PointerDeviceKind.touch,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ByteData> renderAuthoredHair({
    double hardness = 1,
    double bend = 0,
    double shear = 0,
    double softness = 0,
    double grain = 0,
    double clumpScale = 1.6,
    double bendBias = 0,
    double wander = 0,
    double turnCompliance = 0,
    bool corner = false,
  }) async {
    final preset = PawBrushProgramCompiler.compileUserV2(PawUserBrushPresetV2(
      presetId:
          'hair-$hardness-$bend-$shear-$softness-$grain-$clumpScale-$bendBias-$wander-$turnCompliance',
      revision: 1,
      textureSeed: 193,
      bristleLayout: PawUserBristleLayout.crossing,
      bristleDensity: .8,
      bristleLength: 2,
      bristleSpread: 2,
      bristleJitter: 0,
      bristleBend: bend,
      bristleShearRadians: shear,
      bristleSoftness: softness,
      bristleClumpScale: clumpScale,
      bristleBendBias: bendBias,
      bristleWander: wander,
      bristleTurnCompliance: turnCompliance,
      grainMode: grain == 0
          ? PawUnifiedBrushGrainMode.none
          : PawUnifiedBrushGrainMode.strokeFollowing,
      grainStrength: grain,
      tipHardness: hardness,
      flow: .4,
      spacing: .08,
    ));
    final stroke = preset.createStroke(
        seed: const PawStrokeTextureSeed(31),
        color: const Color(0xff171717),
        baseSize: 22);
    final cache = PawStreamingDabRenderCache(logicalSize: const Size(256, 128));
    try {
      for (var i = 0; i <= 24; i++) {
        stroke.appendSample(DrawingInputSample(
          x: 20 + (corner ? math.min(i, 14) : i) * 9.0,
          y: corner ? 32 + math.max(0, i - 14) * 7.0 : 64,
          timestamp: Duration(microseconds: i * 16000),
          pressure: .68,
          pressureMin: 0,
          pressureMax: 1,
          deviceKind: PointerDeviceKind.stylus,
        ));
      }
      stroke.freeze();
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
      picture.dispose();
      try {
        return (await image.toByteData(format: ImageByteFormat.rawRgba))!;
      } finally {
        image.dispose();
      }
    } finally {
      cache.dispose();
    }
  }

  test('authored crossing hardness softens the shoulder independently',
      () async {
    final hard = await renderAuthoredHair(shear: -.6);
    final soft = await renderAuthoredHair(hardness: 0, shear: -.6);
    double dose(ByteData pixels, int inner, int outer) {
      var sum = 0;
      for (var x = 90; x < 166; x++) {
        for (var y = 0; y < 128; y++) {
          final distance = (y - 64).abs();
          if (distance >= inner && distance <= outer) {
            sum += pixels.getUint8((y * 256 + x) * 4 + 3);
          }
        }
      }
      return sum.toDouble();
    }

    final centerRatio = dose(soft, 0, 3) / dose(hard, 0, 3);
    final shoulderRatio = dose(soft, 12, 24) / dose(hard, 12, 24);
    expect(centerRatio, greaterThan(.8));
    expect(shoulderRatio, lessThan(centerRatio - .1),
        reason:
            'Hardness must execute transverse falloff, not global opacity.');
  });

  test('authored crossing bend remains active with zero shear', () async {
    final straight = await renderAuthoredHair();
    final bent = await renderAuthoredHair(bend: .5);
    var alphaDifference = 0;
    for (var i = 3; i < straight.lengthInBytes; i += 4) {
      alphaDifference += (straight.getUint8(i) - bent.getUint8(i)).abs();
    }
    expect(alphaDifference, greaterThan(1000),
        reason: 'A zero shear angle must not silently disable authored bend.');
  });

  test('authored hair softness filters strand contrast without erasing pigment',
      () async {
    final sharp = await renderAuthoredHair(shear: -.6);
    final soft = await renderAuthoredHair(shear: -.6, softness: .08);
    (double, double) measure(ByteData pixels) {
      var mass = 0.0, variation = 0.0;
      for (var y = 1; y < 127; y++) {
        for (var x = 70; x < 186; x++) {
          final a = pixels.getUint8((y * 256 + x) * 4 + 3);
          mass += a;
          variation += (a - pixels.getUint8(((y + 1) * 256 + x) * 4 + 3)).abs();
        }
      }
      return (mass, variation / mass);
    }

    final a = measure(sharp), b = measure(soft);
    expect(b.$1 / a.$1, inInclusiveRange(.9, 1.2));
    expect(b.$2, lessThan(a.$2 * .85));
  });

  test('crossing hairs execute grain and independent intrinsic shape controls',
      () async {
    final base = await renderAuthoredHair(shear: -.6, bend: .3);
    for (final changed in [
      await renderAuthoredHair(shear: -.6, bend: .3, grain: .9),
      await renderAuthoredHair(shear: -.6, bend: .3, clumpScale: .15),
      await renderAuthoredHair(shear: -.6, bend: .3, bendBias: 1),
      await renderAuthoredHair(shear: -.6, bend: .3, wander: .1),
    ]) {
      var difference = 0;
      for (var i = 3; i < base.lengthInBytes; i += 4) {
        difference += (base.getUint8(i) - changed.getUint8(i)).abs();
      }
      expect(difference, greaterThan(1000),
          reason:
              'Serialized authoring controls must affect continuous pixels.');
    }
  });

  test(
      'authored turn compliance changes curved hairs while preserving straight material',
      () async {
    final straight = await renderAuthoredHair(shear: -.6, bend: .3);
    final compliantStraight =
        await renderAuthoredHair(shear: -.6, bend: .3, turnCompliance: 1);
    expect(compliantStraight.buffer.asUint8List(),
        orderedEquals(straight.buffer.asUint8List()));
    final rigid = await renderAuthoredHair(shear: -.6, bend: .3, corner: true);
    final compliant = await renderAuthoredHair(
        shear: -.6, bend: .3, corner: true, turnCompliance: 1);
    var difference = 0;
    for (var i = 3; i < rigid.lengthInBytes; i += 4) {
      difference += (rigid.getUint8(i) - compliant.getUint8(i)).abs();
    }
    expect(difference, greaterThan(1000),
        reason: 'Turn compliance must execute in authored crossing geometry.');
  });

  test('authored dense crossing hairs render beyond eight fibers per root', () {
    final preset =
        PawBrushProgramCompiler.compileUserV2(const PawUserBrushPresetV2(
      presetId: 'dense-crossing-hairs',
      revision: 1,
      textureSeed: 193,
      bristleLayout: PawUserBristleLayout.crossing,
      bristleDensity: 1,
      bristleGuardDensity: 2,
      bristleGrooming: .8,
      bristleBend: .4,
      spacing: .08,
    ));
    final stroke = preset.createStroke(
        seed: const PawStrokeTextureSeed(31),
        color: const Color(0xff171717),
        baseSize: 18);
    final cache = PawStreamingDabRenderCache(logicalSize: const Size(256, 128));
    try {
      for (var i = 0; i <= 24; i++) {
        stroke.appendSample(_touch((
          i * 16000,
          32 + math.min(i, 16) * 9.0,
          35 + math.max(0, i - 16) * 8.0
        )));
        final recorder = PictureRecorder();
        const PawStreamingDabRenderer().paint(
            canvas: Canvas(recorder),
            outputSize: const Size(256, 128),
            logicalSize: const Size(256, 128),
            physicalTargetRasterScale: 1,
            stroke: stroke,
            renderCache: cache);
        recorder.endRecording().dispose();
      }
      expect(cache.lastFilamentLaneCount, greaterThan(0));
      expect(cache.lastPreparedStampVertexCount, 0);
    } finally {
      cache.dispose();
    }
  });

  test('authored raster grain remains visible on a wax contact brush',
      () async {
    final builtin = PawBrushPresetCatalog.forTool(DrawingTool.crayon);
    Future<int> pigment(double grain) async {
      final raster = PawBrushRasterProgram([
        PawBrushRasterRoleBinding(
          bindingId: 'authored-paper',
          role: PawBrushRasterRoleKind.paper,
          resource: PawBrushRasterResource.generated(
              resourceId: 'authored-paper-$grain',
              width: 2,
              height: 2,
              samples: Float32List.fromList(List.filled(4, grain))),
          coordinateSpace: PawBrushRasterCoordinateSpace.canvasFixed,
          cyclesPerCoordinateUnit: 1 / 32,
          detailCarrier: true,
        )
      ]).prepare();
      final preset = PawCompiledBrushPreset(
          definition: builtin.definition,
          sizeScale: builtin.sizeScale,
          opacity: builtin.opacity,
          kernelKind: builtin.kernelKind,
          rasterProgram: raster);
      final stroke = preset.createStroke(
          seed: const PawStrokeTextureSeed(19),
          color: const Color(0xff000000),
          baseSize: 35);
      final cache =
          PawStreamingDabRenderCache(logicalSize: const Size(256, 128));
      try {
        for (var i = 0; i <= 20; i++) {
          stroke.appendSample(_touch((i * 16000, 30 + i * 9.0, 64)));
        }
        stroke.freeze();
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
        picture.dispose();
        try {
          final bytes =
              (await image.toByteData(format: ImageByteFormat.rawRgba))!;
          var total = 0;
          for (var i = 3; i < bytes.lengthInBytes; i += 4) {
            total += bytes.getUint8(i);
          }
          expect(cache.contactRasterBytes, 0);
          return total;
        } finally {
          image.dispose();
        }
      } finally {
        cache.dispose();
      }
    }

    // This raster role is paper height: high tooth removes contact coverage.
    final sparse = await pigment(.95);
    final dense = await pigment(.05);
    expect(dense, greaterThan(sparse + 10000),
        reason: 'Procedural transfer must not hide an authored grain source.');
  });

  test('physical iPhone near-loop becomes one exactly closed ellipse', () {
    // pawdoodle_1788271766828000-2, up to the hold snapshot. This is the
    // physical gesture that previously ranked FREEFORM_SMOOTH first even
    // though its one-turn closure topology had passed.
    const trace = <(int, double, double)>[
      (0, 349.89655172413796, 166.44),
      (34000, 329.7586206896552, 157.68),
      (42000, 322.2068965517241, 155.73333333333335),
      (50000, 313.3965517241379, 153.7866666666667),
      (67000, 292, 153.7866666666667),
      (84000, 264.3103448275862, 153.7866666666667),
      (100000, 227.81034482758622, 160.6),
      (117000, 188.79310344827587, 174.22666666666666),
      (134000, 152.29310344827587, 191.74666666666667),
      (150000, 118.3103448275862, 213.16),
      (167000, 94.39655172413794, 234.57333333333332),
      (184000, 83.06896551724138, 255.01333333333335),
      (200000, 79.29310344827586, 273.5066666666667),
      (217000, 80.55172413793103, 289.08),
      (234000, 93.13793103448276, 301.73333333333335),
      (250000, 113.27586206896552, 310.49333333333334),
      (267000, 140.9655172413793, 314.38666666666666),
      (284000, 178.7241379310345, 315.36),
      (300000, 222.77586206896552, 313.4133333333333),
      (317000, 268.0862068965517, 306.6),
      (334000, 314.65517241379314, 297.84),
      (350000, 354.93103448275866, 288.1066666666666),
      (367000, 391.4310344827586, 275.4533333333333),
      (384000, 420.37931034482756, 262.8),
      (400000, 438, 250.14666666666668),
      (417000, 450.58620689655174, 238.46666666666667),
      (434000, 455.62068965517244, 226.78666666666666),
      (450000, 458.1379310344828, 213.16),
      (467000, 458.1379310344828, 198.56),
      (484000, 454.3620689655172, 182.98666666666665),
      (500000, 441.7758620689655, 171.30666666666667),
      (517000, 421.6379310344828, 163.52),
      (534000, 398.98275862068965, 159.62666666666667),
      (550000, 373.8103448275862, 158.65333333333334),
      (567000, 353.67241379310343, 158.65333333333334),
      (584000, 336.05172413793105, 159.62666666666667),
      (600000, 325.9827586206897, 161.57333333333332),
      (617000, 322.2068965517241, 163.52),
    ];

    final result = const PawHeldStrokeRefiner().refine(
      trace.map(_touch).toList(growable: false),
      configuration: const PawStrokeHoldAssistConfiguration(),
    );

    expect(result.kind, PawStrokeAssistKind.ellipse,
        reason: result.candidateScores.toString());
    expect(result.refinedSegments, hasLength(4));
    expect(
      (result.refinedSegments.first.p0 - result.refinedSegments.last.p1)
          .distance,
      lessThan(1e-6),
    );
  });

  test('production brushes compile to their declared material primitives', () {
    for (final tool in DrawingTool.values) {
      final preset = PawBrushPresetCatalog.forTool(tool);
      final plan = preset.unifiedProgram!.compiledRenderPlan;
      expect(plan.needsCarrier, isFalse, reason: tool.name);
      expect(plan.needsPersistentBristles, isFalse, reason: tool.name);
      switch (tool) {
        case DrawingTool.roundBrush || DrawingTool.marker:
          expect(plan.needsSweptCoverage, isTrue, reason: tool.name);
          expect(plan.needsPreparedTip, isFalse, reason: tool.name);
        case DrawingTool.crayon || DrawingTool.inkBrush:
          expect(preset.definition.preparedFullTip, isFalse, reason: tool.name);
          expect(plan.needsPreparedTip, isFalse, reason: tool.name);
          expect(plan.needsCanvasContact, isTrue, reason: tool.name);
          expect(plan.needsStreamingHairs, isFalse, reason: tool.name);
        case DrawingTool.furBrush:
          expect(preset.definition.preparedFullTip, isFalse, reason: tool.name);
          expect(plan.needsPreparedTip, isFalse, reason: tool.name);
          expect(plan.needsCanvasContact, isFalse, reason: tool.name);
          expect(plan.needsStreamingHairs, isTrue, reason: tool.name);
        default:
          expect(preset.definition.preparedFullTip, isTrue, reason: tool.name);
          expect(plan.needsPreparedTip, isTrue, reason: tool.name);
          expect(plan.needsCanvasContact, isFalse, reason: tool.name);
          expect(plan.needsStreamingHairs, isFalse, reason: tool.name);
      }
    }
  });

  test('fast circles submit geometry through each compiled material path', () {
    final samples = <DrawingInputSample>[
      for (var index = 0; index <= 72; index++)
        DrawingInputSample(
          x: 256 + math.cos(index / 72 * math.pi * 2) * 150,
          y: 256 + math.sin(index / 72 * math.pi * 2) * 150,
          timestamp: Duration(microseconds: index * 13889),
          pressure: .68,
          pressureMin: 0,
          pressureMax: 1,
          deviceKind: PointerDeviceKind.touch,
        ),
    ];

    for (final tool in DrawingTool.values) {
      PawDabStreamingBackend.prepareTool(tool);
      final backend = PawDabStreamingBackend(tool);
      final started = backend.start(
        seed: const PawStrokeTextureSeed(0x71),
        color: const Color(0xff6b3927),
        baseSize: 18,
        logicalSize: const Size.square(512),
        rasterScale: 1,
        initialSample: samples.first,
        compositeOperation: tool == DrawingTool.eraser
            ? PawStreamingCompositeOperation.erase
            : PawStreamingCompositeOperation.paint,
        capturePerformance: true,
      );
      final interaction = started.interaction
          as PawStreamingBrushInteractionBinding<PawStreamingDabStroke,
              PawStreamingDabRenderCache>;
      final appendTimes = <int>[];
      final paintTimes = <int>[];
      var maximumVertices = 0;
      for (final sample in samples.skip(1)) {
        final watch = Stopwatch()..start();
        interaction.appendSample(sample);
        appendTimes.add(watch.elapsedMicroseconds);
        watch.reset();
        final recorder = PictureRecorder();
        interaction.paint(
          canvas: Canvas(recorder),
          outputSize: const Size.square(512),
          logicalSize: const Size.square(512),
          physicalTargetRasterScale: 1,
        );
        recorder.endRecording().dispose();
        paintTimes.add(watch.elapsedMicroseconds);
        watch.stop();
        maximumVertices = math.max(maximumVertices,
            interaction.activeRenderCache.lastTailGeometryVertexCount);
      }
      if (Platform.environment['PAW_MEASURE_BRUSH_CPU'] == '1') {
        appendTimes.sort();
        paintTimes.sort();
        final p95 = (paintTimes.length * .95).ceil() - 1;
        // Reports CPU model/command construction, excluding GPU presentation.
        // This is a measurement, not a timing-sensitive test assertion.
        // ignore: avoid_print
        print('BRUSH_CPU ${tool.name}: append_p95_us=${appendTimes[p95]} '
            'paint_p50_us=${paintTimes[paintTimes.length ~/ 2]} '
            'paint_p95_us=${paintTimes[p95]} paint_max_us=${paintTimes.last} '
            'max_tail_vertices=$maximumVertices '
            'contact_raster_bytes=${interaction.activeRenderCache.contactRasterBytes} '
            'last_contact_tiles=${interaction.activeRenderCache.lastUpdatedContactTileCount}');
      }

      final cache = interaction.activeRenderCache;
      if (PawBrushPresetCatalog.forTool(tool)
          .unifiedProgram!
          .compiledRenderPlan
          .needsSweptCoverage) {
        expect(cache.lastSweepSectionCount, greaterThan(0));
        expect(cache.sweepLayerCount, inInclusiveRange(1, 12));
        expect(cache.lastPreparedStampVertexCount, 0);
        expect(cache.ownershipDiagnostics.hasExactVisibleOwnership, isTrue);
        if (tool == DrawingTool.inkBrush) {
          expect(cache.contactRasterBytes, greaterThan(0));
        }
        final observation =
            cache.performanceCapture!.finish().frameObservations.last;
        expect(observation['sweep_sections'], cache.lastSweepSectionCount);
        interaction.dispose();
        continue;
      }
      expect(cache.lastTailGeometryVertexCount, greaterThan(0),
          reason: 'Geometry counters must be enabled for ${tool.name}');
      switch (tool) {
        case DrawingTool.crayon || DrawingTool.inkBrush:
          expect(cache.lastPreparedStampVertexCount, 0, reason: tool.name);
          expect(cache.lastBodyMeshMicros, greaterThan(0), reason: tool.name);
          expect(cache.lastFilamentLaneCount, 0, reason: tool.name);
          // The real-device failure produced 58k-339k vertices for a short
          // five-event stroke because every DAB owned a dense radial mesh.
          // Contact geometry must remain a length-bounded ribbon.
          expect(
            cache.lastTailGeometryVertexCount,
            lessThanOrEqualTo(math.max(64, cache.lastTailDabCount * 32)),
            reason: tool.name,
          );
          if (tool == DrawingTool.inkBrush) {
            expect(cache.wetMediaTileCount, greaterThan(0));
          }
          final observed =
              cache.performanceCapture!.finish().frameObservations.last;
          expect(
              observed['contact_raster_rgba_bytes'], cache.contactRasterBytes);
          expect(observed['contact_raster_tile_count'], greaterThan(0));
        case DrawingTool.furBrush:
          expect(cache.lastPreparedStampVertexCount, 0, reason: tool.name);
          expect(cache.lastFilamentLaneCount, greaterThan(0),
              reason: tool.name);
        default:
          expect(cache.lastPreparedStampVertexCount, greaterThan(0),
              reason: tool.name);
          expect(cache.lastBodyMeshMicros, 0, reason: tool.name);
          expect(
            cache.lastTailGeometryVertexCount,
            lessThanOrEqualTo(cache.lastTailDabCount * 4),
            reason: tool.name,
          );
      }
      interaction.dispose();
    }
  });

  for (final (tool, gesture) in [
    (DrawingTool.crayon, 'sine'),
    (DrawingTool.inkBrush, 'sine'),
    (DrawingTool.furBrush, 'sine'),
    (DrawingTool.furBrush, 'hard turns'),
  ]) {
    test(
        '${tool.name} retained $gesture matches a fresh render after streaming',
        () async {
      const size = Size(640, 420);
      PawDabStreamingBackend.prepareTool(tool);
      final samples = [
        for (var i = 0; i <= 100; i++)
          DrawingInputSample(
              x: gesture == 'sine'
                  ? 60 + i * 5.2
                  : 80 + math.min(i, 35) * 9.0 - math.max(0, i - 70) * 7,
              y: gesture == 'sine'
                  ? 210 + math.sin(i / 100 * math.pi * 4) * 64
                  : 100 +
                      math.max(0, math.min(i, 70) - 35) * 6.0 -
                      math.max(0, i - 70) * 4,
              timestamp: Duration(milliseconds: i * 16),
              pressure: .72,
              pressureMin: 0,
              pressureMax: 1,
              deviceKind: PointerDeviceKind.stylus),
      ];
      final interaction = PawDabStreamingBackend(tool)
          .start(
              seed: const PawStrokeTextureSeed(71),
              color: const Color(0xffb73468),
              baseSize: 26,
              logicalSize: size,
              rasterScale: 3,
              initialSample: samples.first,
              compositeOperation: PawStreamingCompositeOperation.paint,
              capturePerformance: false)
          .interaction;
      try {
        // The contact image encodes material state. A colored tap must still
        // use the selected pigment, including before the first move sample.
        if (tool != DrawingTool.furBrush) {
          final recorder = PictureRecorder();
          interaction.paint(
              canvas: Canvas(recorder)
                ..drawColor(const Color(0xffffffff), BlendMode.src),
              outputSize: size,
              logicalSize: size,
              physicalTargetRasterScale: 3);
          final picture = recorder.endRecording();
          final tap = await picture.toImage(640, 420);
          picture.dispose();
          try {
            final rgba =
                (await tap.toByteData(format: ImageByteFormat.rawRgba))!;
            const offset = (210 * 640 + 60) * 4;
            expect(rgba.getUint8(offset),
                greaterThan(rgba.getUint8(offset + 1) + 10));
            expect(rgba.getUint8(offset + 2),
                greaterThan(rgba.getUint8(offset + 1) + 5));
          } finally {
            tap.dispose();
          }
        }
        for (final sample in samples.skip(1)) {
          interaction.appendSample(sample);
          final frame = PictureRecorder();
          interaction.paint(
              canvas: Canvas(frame),
              outputSize: size,
              logicalSize: size,
              physicalTargetRasterScale: 3);
          frame.endRecording().dispose();
        }
        interaction.stroke.freeze();
        Future<Image> render(bool retained) async {
          final recorder = PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(const Color(0xffffffff), BlendMode.src)
            ..scale(3);
          if (retained) {
            interaction.paint(
                canvas: canvas,
                outputSize: size,
                logicalSize: size,
                physicalTargetRasterScale: 3);
          } else {
            const PawStreamingDabRenderer().paint(
                canvas: canvas,
                outputSize: size,
                logicalSize: size,
                physicalTargetRasterScale: 3,
                stroke: interaction.stroke as PawStreamingDabStroke);
          }
          final picture = recorder.endRecording();
          try {
            return await picture.toImage(1920, 1260);
          } finally {
            picture.dispose();
          }
        }

        final retained = await render(true);
        final fresh = await render(false);
        try {
          if (Platform.environment['PAW_EXPORT_BRUSH_DIAGNOSTICS'] == '1') {
            for (final entry
                in {'streamed': retained, 'fresh': fresh}.entries) {
              final png =
                  (await entry.value.toByteData(format: ImageByteFormat.png))!;
              await File(
                      'build/brush_diagnostics/${tool.name}_${entry.key}.png')
                  .writeAsBytes(png.buffer.asUint8List());
            }
          }
          final a =
              (await retained.toByteData(format: ImageByteFormat.rawRgba))!;
          final b = (await fresh.toByteData(format: ImageByteFormat.rawRgba))!;
          var mismatchedPixels = 0;
          for (var offset = 0; offset < a.lengthInBytes; offset += 4) {
            if ([0, 1, 2].any((channel) =>
                (a.getUint8(offset + channel) - b.getUint8(offset + channel))
                    .abs() >
                2)) {
              mismatchedPixels++;
            }
          }
          expect(mismatchedPixels, 0,
              reason: 'Retained boundaries must use the same material pose as '
                  'the final path; otherwise streaming leaves white seams.');
        } finally {
          retained.dispose();
          fresh.dispose();
        }
      } finally {
        interaction.dispose();
      }
    });
  }
}
