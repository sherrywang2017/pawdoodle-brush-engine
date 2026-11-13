import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_preset.dart';
import 'package:pawdoodle_brush_engine/src/brush_raster_resource.dart';
import 'package:pawdoodle_brush_engine/src/drawing_raster.dart';
import 'package:pawdoodle_brush_engine/src/smooth_stroke.dart';
import 'package:pawdoodle_brush_engine/src/streaming_dab_brush.dart';

void main() {
  test('V2 hair filtering and curve fields round-trip with legacy defaults',
      () {
    const authored = PawUserBrushPresetV2(
      presetId: 'textured-hair',
      revision: 2,
      textureSeed: 73,
      bristleLayout: PawUserBristleLayout.crossing,
      bristleDensity: .8,
      bristleSoftness: .025,
      bristleClumpScale: .24,
      bristleBendBias: -.6,
      bristleTurnCompliance: .7,
    );
    final json = authored.toJson();
    expect(PawUserBrushPresetV2.fromJson(json).toJson(), json);
    for (final key in [
      'softness',
      'clumpScale',
      'bendBias',
      'turnCompliance'
    ]) {
      (json['bristle'] as Map).remove(key);
    }
    final legacy = PawUserBrushPresetV2.fromJson(json);
    expect(legacy.bristleSoftness, 0);
    expect(legacy.bristleClumpScale, 1.6);
    expect(legacy.bristleBendBias, 0);
    expect(legacy.bristleTurnCompliance, 0);
    for (final entry in <String, double>{
      'softness': double.nan,
      'clumpScale': 0,
      'bendBias': 1.01,
      'turnCompliance': 1.01,
    }.entries) {
      final invalid = authored.toJson();
      (invalid['bristle'] as Map)[entry.key] = entry.value;
      expect(() => PawUserBrushPresetV2.fromJson(invalid),
          entry.value.isFinite ? throwsArgumentError : throwsFormatException);
    }
  });

  test('V2 guard controls change outer hairs while retaining the core', () {
    const authored = PawUserBrushPresetV2(
      presetId: 'loose-outer-hair',
      revision: 1,
      textureSeed: 51,
      bristleLayout: PawUserBristleLayout.crossing,
      bristleDensity: .9,
      bristleLength: 1.5,
      bristleShearRadians: .7,
      bristleGuardLength: 1.7,
      bristleGuardBend: 2.3,
      bristleGuardDensity: .5,
      bristleGuardSpread: 1.3,
    );
    final decoded = PawUserBrushPresetV2.fromJson(authored.toJson());
    expect(decoded.toJson(), authored.toJson());
    final oldJson = authored.toJson();
    final bristle = oldJson['bristle'] as Map;
    for (final key in [
      'guardLength',
      'guardBend',
      'guardDensity',
      'guardSpread'
    ]) {
      bristle.remove(key);
    }
    final old = PawUserBrushPresetV2.fromJson(oldJson);
    final oldLayers = PawBrushProgramCompiler.compileUserV2(old)
        .definition
        .template
        .streamingFilamentLayers;
    final layers = PawBrushProgramCompiler.compileUserV2(decoded)
        .definition
        .template
        .streamingFilamentLayers;
    expect(layers.first.lengthFactors.maximum,
        oldLayers.first.lengthFactors.maximum);
    expect(layers.last.lengthFactors.maximum,
        closeTo(oldLayers.last.lengthFactors.maximum * 1.7, .00001));
    expect(layers.last.countPerRoot, lessThan(oldLayers.last.countPerRoot));
    expect(layers.last.bendFactor, greaterThan(oldLayers.last.bendFactor));
  });

  test('V2 authors wet, wax and crossing hairs without a production brush ID',
      () {
    final authored = PawUserBrushPresetV2(
      presetId: 'authored-wet',
      revision: 1,
      textureSeed: 372,
      wetMedia: PawDabBrushDefinitions.ink.wetMedia,
      grainStructure: PawDabGrainStructure.absorbentWash,
      grainMode: PawUnifiedBrushGrainMode.canvasFixed,
      grainStrength: .7,
      capRoughness: .12,
    );
    final decoded = PawUserBrushPresetV2.fromJson(authored.toJson());
    expect(decoded.toJson(), authored.toJson());
    final compiled = PawBrushProgramCompiler.compileUserV2(decoded);
    expect(compiled.definition.wetMedia.settlingDuration,
        const Duration(milliseconds: 240));
    expect(compiled.unifiedProgram!.compiledRenderPlan.needsTemporalContact,
        isTrue);
    expect(
        compiled.unifiedProgram!.compiledRenderPlan.needsSweptCoverage, isTrue);
    expect(
        compiled.unifiedProgram!.compiledRenderPlan.needsPreparedTip, isFalse);
    final oldJson = authored.toJson();
    (oldJson['material'] as Map).remove('wet');
    (oldJson['material'] as Map).remove('wax');
    (oldJson['bristle'] as Map).remove('layout');
    (oldJson['bristle'] as Map).remove('bend');
    final old = PawUserBrushPresetV2.fromJson(oldJson);
    expect(old.wetMedia.enabled, isFalse);
    expect(old.bristleLayout, PawUserBristleLayout.mixed);
    final hair =
        PawBrushProgramCompiler.compileUserV2(const PawUserBrushPresetV2(
      presetId: 'authored-hair',
      revision: 1,
      textureSeed: 391,
      bristleLayout: PawUserBristleLayout.crossing,
      bristleDensity: .96,
      bristleLength: 2,
      bristleWidth: .05,
      bristleShearRadians: .94,
      bristleGrooming: .72,
      spacing: .06,
    ));
    expect(hair.definition.template.streamingFilamentLayers, hasLength(2));
    expect(hair.definition.template.persistentLaneLayers, isEmpty);
    expect(hair.definition.template.filamentLayers, isEmpty);
    for (final layer in hair.definition.template.streamingFilamentLayers) {
      expect(layer.grooming.lookBehindArcFactor, .72);
      expect(layer.grooming.inertia, .72);
    }
    const wax = PawUserBrushPresetV2(
        presetId: 'authored-wax',
        revision: 1,
        textureSeed: 419,
        dryWax: PawDabDryWaxParameters.physicalCrayon,
        deposition: PawUnifiedBrushDepositionModel.dryMedia,
        grainStructure: PawDabGrainStructure.waxAggregate,
        grainStrength: .6);
    expect(PawUserBrushPresetV2.fromJson(wax.toJson()).toJson(), wax.toJson());
    expect(PawBrushProgramCompiler.compileUserV2(wax).definition.dryWax.enabled,
        isTrue);
    final oldWaxJson = wax.toJson();
    final waxData = (oldWaxJson['material'] as Map)['wax'] as Map;
    for (final key in ['dragStrength', 'dragLength', 'dragWidth']) {
      waxData.remove(key);
    }
    final oldWax = PawUserBrushPresetV2.fromJson(oldWaxJson).dryWax;
    expect(oldWax.dragStrength, 0);
    expect(oldWax.dragLength, .22);
    expect(oldWax.dragWidth, .025);
    const airbrush = PawUserBrushPresetV2(
      presetId: 'authored-airbrush',
      revision: 1,
      textureSeed: 421,
      deposition: PawUnifiedBrushDepositionModel.airbrushDensity,
      grainStrength: 0,
      tipHardness: .5,
    );
    final soft = PawBrushProgramCompiler.compileUserV2(airbrush);
    expect(soft.definition.preparedFullTip, isTrue);
    expect(soft.unifiedProgram!.compiledRenderPlan.needsPreparedTip, isTrue);
    expect(
        soft.unifiedProgram!.compiledRenderPlan.needsStatefulDensity, isTrue);
    expect(soft.definition.template.footprint.centerCoverage,
        greaterThan(soft.definition.template.footprint.edgeCoverage));
  });

  const userPreset = PawUserBrushPresetV1(
    presetId: 'shared-pencil',
    revision: 3,
    textureSeed: 31415,
    sizeScale: 1.25,
    opacity: .8,
    spacing: .2,
    flow: .7,
    tipAspect: .6,
    tipHardness: .75,
    edgeRoughness: .08,
    grainStrength: .4,
    grainScale: .8,
    pressureSizeMinimum: .3,
    pressureFlowMinimum: .2,
    speedFlow: -.5,
    sizeJitter: .1,
    opacityJitter: .12,
    scatter: .15,
  );

  test('Brush Preset Schema v1 round-trips and compiles bounded public data',
      () {
    final decoded = PawUserBrushPresetV1.fromJson(userPreset.toJson());
    expect(decoded.toJson(), userPreset.toJson());

    final compiled = PawBrushPresetCompiler.compile(decoded);
    expect(compiled.definition.id, 'user:shared-pencil');
    expect(compiled.definition.revision, 3);
    expect(compiled.definition.emission.spacingFactor, .2);
    expect(compiled.definition.grain.coarseStrength, .4);
    final stroke = compiled.createStroke(
      seed: const PawStrokeTextureSeed(9),
      color: const Color(0xFF123456),
      baseSize: 20,
    );
    expect(stroke.brushSize, 25);
    expect(stroke.opacity, .8);
    expect(stroke.definition.validate, returnsNormally);
  });

  test('schema rejects unknown versions, engines, fields, and invalid values',
      () {
    Map<String, Object?> changed(String key, Object value) =>
        <String, Object?>{...userPreset.toJson(), key: value};

    expect(
      () => PawUserBrushPresetV1.fromJson(changed('schemaVersion', 2)),
      throwsFormatException,
    );
    expect(
      () => PawUserBrushPresetV1.fromJson(changed('engine', 'other')),
      throwsFormatException,
    );
    expect(
      () => PawUserBrushPresetV1.fromJson(
        <String, Object?>{...userPreset.toJson(), 'renderMode': 'special'},
      ),
      throwsFormatException,
    );
    final invalidStroke = Map<String, Object?>.from(
      userPreset.toJson()['stroke']! as Map<String, Object>,
    )..['spacing'] = double.nan;
    expect(
      () => PawUserBrushPresetV1.fromJson(
        <String, Object?>{...userPreset.toJson(), 'stroke': invalidStroke},
      ),
      throwsFormatException,
    );
  });

  test('production tools resolve definition size and opacity from one catalog',
      () {
    final expected = <DrawingTool, PawDabBrushDefinition>{
      DrawingTool.roundBrush: PawDabBrushDefinitions.round,
      DrawingTool.crayon: PawDabBrushDefinitions.crayon,
      DrawingTool.marker: PawDabBrushDefinitions.marker,
      DrawingTool.softBrush: PawDabBrushDefinitions.soft,
      DrawingTool.inkBrush: PawDabBrushDefinitions.ink,
      DrawingTool.furBrush: PawDabBrushDefinitions.fur,
      DrawingTool.eraser: PawDabBrushDefinitions.eraser,
    };
    for (final tool in DrawingTool.values) {
      final preset = PawBrushPresetCatalog.forTool(tool);
      expect(preset.definition, same(expected[tool]), reason: tool.name);
      expect(preset.sizeScale, greaterThan(0), reason: tool.name);
      expect(preset.opacity, inInclusiveRange(0, 1), reason: tool.name);
    }
  });

  test('preset content edits require a new resource revision', () {
    final original = PawBrushPresetCompiler.compile(userPreset);
    final editedJson = Map<String, Object?>.from(userPreset.toJson())
      ..['revision'] = userPreset.revision + 1;
    final edited = PawBrushPresetCompiler.compile(
      PawUserBrushPresetV1.fromJson(editedJson),
    );
    expect(original.definition.id, edited.definition.id);
    expect(edited.definition.revision, original.definition.revision + 1);
    expect(
      '${original.definition.id}|${original.definition.revision}',
      isNot('${edited.definition.id}|${edited.definition.revision}'),
    );
  });

  test('Brush Preset Schema v2 carries material grain structure', () {
    const preset = PawUserBrushPresetV2(
      presetId: 'fibrous-wash',
      revision: 2,
      textureSeed: 91,
      grainMode: PawUnifiedBrushGrainMode.strokeFollowing,
      grainStructure: PawDabGrainStructure.absorbentWash,
      grainStrength: .46,
      deposition: PawUnifiedBrushDepositionModel.buildUp,
    );
    final decoded = PawUserBrushPresetV2.fromJson(preset.toJson());
    expect(decoded.grainStructure, PawDabGrainStructure.absorbentWash);
    expect(
      PawBrushPresetCompiler.compileV2(decoded).definition.grain.structure,
      PawDabGrainStructure.absorbentWash,
    );

    final legacyJson = Map<String, Object?>.from(preset.toJson());
    final legacyGrain = Map<String, Object?>.from(
      legacyJson['grain']! as Map<String, Object>,
    )..remove('structure');
    legacyJson['grain'] = legacyGrain;
    expect(
      PawUserBrushPresetV2.fromJson(legacyJson).grainStructure,
      PawDabGrainStructure.generic,
    );
  });

  test('Brush Preset Schema v2 round-trips the endpoint response', () {
    const preset = PawUserBrushPresetV2(
      presetId: 'tapered-ink',
      revision: 4,
      textureSeed: 27,
      startTaperBrushLengths: 1.25,
      endTaperBrushLengths: 2.5,
      minimumEndpointSize: .2,
      minimumEndpointOpacity: .35,
      endpointTaperExponent: 1.6,
      capRoundness: .72,
      capRoughness: .08,
    );

    final decoded = PawUserBrushPresetV2.fromJson(preset.toJson());
    expect(decoded.toJson(), preset.toJson());

    final endpoint =
        PawBrushPresetCompiler.compileV2(decoded).unifiedProgram!.endpoint!;
    expect(endpoint.startTaperBrushLengths, 1.25);
    expect(endpoint.endTaperBrushLengths, 2.5);
    expect(endpoint.minimumSizeFactor, .2);
    expect(endpoint.minimumOpacityFactor, .35);
    expect(endpoint.taperExponent, 1.6);
    expect(endpoint.capRoundness, .72);
    expect(endpoint.capRoughness, .08);
  });

  test('Brush Preset Schema v2 keeps legacy endpoint defaults', () {
    const preset = PawUserBrushPresetV2(
      presetId: 'legacy-v2',
      revision: 1,
      textureSeed: 8,
    );
    final legacyJson = Map<String, Object?>.from(preset.toJson())
      ..remove('endpoint');

    final decoded = PawUserBrushPresetV2.fromJson(legacyJson);
    expect(decoded.startTaperBrushLengths, 0);
    expect(decoded.endTaperBrushLengths, 0);
    expect(decoded.minimumEndpointSize, 1);
    expect(decoded.minimumEndpointOpacity, 1);
    expect(decoded.endpointTaperExponent, 1);
    expect(decoded.capRoundness, 1);
    expect(decoded.capRoughness, 0);
    expect(
      PawBrushPresetCompiler.compileV2(decoded)
          .unifiedProgram!
          .endpoint!
          .isIdentity,
      isTrue,
    );
  });

  test('unified endpoint response is symmetric and separates size from opacity',
      () {
    const endpoint = PawUnifiedBrushEndpointProfile(
      startTaperBrushLengths: 2,
      endTaperBrushLengths: 2,
      minimumSizeFactor: .25,
      minimumOpacityFactor: .1,
    );

    double progress(double arc) => endpoint.progressAt(
          absoluteArc: arc,
          renderEndArc: 100,
          brushSize: 10,
        );
    double size(double arc) => endpoint.sizeScaleAt(
          absoluteArc: arc,
          renderEndArc: 100,
          brushSize: 10,
        );
    double opacity(double arc) => endpoint.opacityScaleAt(
          absoluteArc: arc,
          renderEndArc: 100,
          brushSize: 10,
        );

    expect(progress(0), 0);
    expect(progress(10), closeTo(.5, 1e-12));
    expect(progress(50), 1);
    expect(progress(90), closeTo(progress(10), 1e-12));
    expect(progress(100), progress(0));
    expect(size(0), .25);
    expect(size(10), closeTo(.625, 1e-12));
    expect(size(50), 1);
    expect(size(90), closeTo(size(10), 1e-12));
    expect(opacity(0), .1);
    expect(opacity(10), closeTo(.55, 1e-12));
    expect(opacity(50), 1);
    expect(opacity(90), closeTo(opacity(10), 1e-12));
  });

  test('Brush Program compiles reusable shape grain and paper roles', () {
    PawBrushRasterResource resource({
      required String id,
      required PawBrushRasterSourceType sourceType,
      required PawBrushRasterCoordinateSpace coordinateSpace,
    }) {
      final samples = Float32List.fromList(<double>[.1, .3, .7, .9]);
      if (sourceType == PawBrushRasterSourceType.bundledAsset) {
        return PawBrushRasterResource.bundledAsset(
          resourceId: id,
          width: 2,
          height: 2,
          samples: samples,
          metadata: const PawBrushRasterResourceMetadata(
            source: 'test fixture',
            author: 'PawDoodle',
            license: 'PawDoodle-owned',
            commercialUse: true,
            attribution: 'None',
          ),
          coordinateSpace: coordinateSpace,
        );
      }
      return PawBrushRasterResource.generated(
        resourceId: id,
        width: 2,
        height: 2,
        samples: samples,
        coordinateSpace: coordinateSpace,
      );
    }

    final program = PawBrushRasterProgram(<PawBrushRasterRoleBinding>[
      PawBrushRasterRoleBinding(
        bindingId: 'shape',
        role: PawBrushRasterRoleKind.shape,
        resource: resource(
          id: 'shape',
          sourceType: PawBrushRasterSourceType.bundledAsset,
          coordinateSpace: PawBrushRasterCoordinateSpace.brushLocal,
        ),
        coordinateSpace: PawBrushRasterCoordinateSpace.brushLocal,
        cyclesPerCoordinateUnit: 1,
      ),
      PawBrushRasterRoleBinding(
        bindingId: 'grain',
        role: PawBrushRasterRoleKind.grain,
        resource: resource(
          id: 'grain',
          sourceType: PawBrushRasterSourceType.generated,
          coordinateSpace: PawBrushRasterCoordinateSpace.strokeFollowing,
        ),
        coordinateSpace: PawBrushRasterCoordinateSpace.strokeFollowing,
        cyclesPerCoordinateUnit: .25,
      ),
      PawBrushRasterRoleBinding(
        bindingId: 'paper',
        role: PawBrushRasterRoleKind.paper,
        resource: resource(
          id: 'paper',
          sourceType: PawBrushRasterSourceType.bundledAsset,
          coordinateSpace: PawBrushRasterCoordinateSpace.canvasFixed,
        ),
        coordinateSpace: PawBrushRasterCoordinateSpace.canvasFixed,
        cyclesPerCoordinateUnit: 1 / 48,
        detailCarrier: true,
        detailCoverageFloor: .25,
      ),
    ]);
    final prepared = program.prepare();
    expect(prepared.hasHighFrequencyCoverage, isTrue);
    expect(
      prepared.sampleHighFrequencyCoverage(
        canvasX: 12,
        canvasY: 18,
      ),
      inInclusiveRange(0, 1),
    );
    for (final role in PawBrushRasterRoleKind.values) {
      expect(prepared.hasRole(role), isTrue);
      expect(
        prepared.sample(
          role: role,
          canvasX: 12,
          canvasY: 18,
          absoluteArc: 24,
          signedNormal: 3,
          brushWidth: 20,
        ),
        inInclusiveRange(0, 1),
      );
    }
    expect(prepared.cache.loadCount, 3);
    expect(prepared.cache.cacheMisses, 0);
    expect(prepared.cache.assetDecodeDuringPointer, 0);
    expect(
      prepared.highFrequencyCoordinateSpace,
      PawBrushRasterCoordinateSpace.canvasFixed,
    );
    final fixedSample = prepared.sampleHighFrequencyCoverage(
      canvasX: 12,
      canvasY: 18,
      absoluteArc: 4,
      signedNormal: -2,
      brushWidth: 12,
    );
    expect(
      prepared.sampleHighFrequencyCoverage(
        canvasX: 12,
        canvasY: 18,
        absoluteArc: 900,
        signedNormal: 30,
        brushWidth: 80,
      ),
      fixedSample,
      reason: 'the stroke-following grain role must not change the declared '
          'canvas-fixed paper carrier coordinates',
    );
  });

  test(
      'Crayon catalog keeps paper tooth fixed while wax dragging follows the stroke',
      () {
    final first = PawBrushPresetCatalog.forTool(DrawingTool.crayon);
    final second = PawBrushPresetCatalog.forTool(DrawingTool.crayon);
    expect(first.kernelKind, PawBrushKernelKind.dabDry);
    expect(first.definition.template.coverageVoidLayers, isEmpty);
    expect(first.definition.preparedFullTip, isFalse);
    expect(first.definition.emission.variantCount, 1);
    expect(first.rasterProgram, isNull);
    expect(second.unifiedProgram, same(first.unifiedProgram));
    expect(
      first.unifiedProgram!.renderRepresentation,
      PawUnifiedBrushRenderRepresentation.contactMesh,
    );
    expect(first.unifiedProgram!.compiledRenderPlan.needsPreparedTip, isFalse);
    expect(
      first.unifiedProgram!.compiledRenderPlan.needsDryMediaContact,
      isTrue,
    );
    expect(first.unifiedProgram!.compiledRenderPlan.needsCanvasContact, isTrue);
    expect(
      first.unifiedProgram!.compiledRenderPlan.needsCanvasFixedGrain,
      isTrue,
    );
    expect(
      first.unifiedProgram!.grainMode,
      PawUnifiedBrushGrainMode.canvasFixed,
    );
    expect(first.definition.dryWax.enabled, isTrue);
    expect(
      first.definition.dryWax.waxCoverageResponse(
        paperContact: .8,
        pressure: .2,
        waxGrainAndScrape: .7,
      ),
      lessThan(first.definition.dryWax.waxCoverageResponse(
        paperContact: .8,
        pressure: .9,
        waxGrainAndScrape: .7,
      )),
    );
    expect(
      first.definition.dryWax.waxThicknessResponse(
        sourceAlpha: .8,
        pressure: .2,
      ),
      lessThan(first.definition.dryWax.waxThicknessResponse(
        sourceAlpha: .8,
        pressure: .9,
      )),
    );
    final stroke = first.createStroke(
      seed: const PawStrokeTextureSeed(7),
      color: const Color(0xFFFF3152),
      baseSize: 24,
    );
    expect(stroke.environment.rasterProgram, isNull);
    expect(stroke.environment.unifiedProgram, same(first.unifiedProgram));
  });
}
