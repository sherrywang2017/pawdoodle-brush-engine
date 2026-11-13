part of '../../brush_preset.dart';

abstract final class PawBrushPresetCompiler {
  static PawCompiledBrushPreset compile(PawUserBrushPresetV1 preset) {
    validate(preset);
    final preparedTip = preset.grainStrength == 0;
    final softness = (1 - preset.tipHardness) * .45;
    final slow = (preset.flow * (1 - preset.speedFlow * .35)).clamp(0.0, 4.0);
    final fast = (preset.flow * (1 + preset.speedFlow * .35)).clamp(0.0, 4.0);
    final definition = PawDabBrushDefinition(
      id: 'user:${preset.presetId}',
      revision: preset.revision,
      fixedStep: PawDabBrushDefinitions.fixedStep,
      template: PawDabTemplateParameters(
        footprint: PawDabFootprintParameters(
          lengthFactor: preset.tipAspect,
          widthFactor: 1,
          shapeExponent: 2 + preset.tipHardness * 2,
          centerCoverage: 1,
          edgeCoverage: preset.tipHardness,
          outerSoftnessFactor: softness,
        ),
      ),
      grain: PawDabGrainParameters(
        coordinate: preset.grainCoordinate,
        coarseStrength: preset.grainStrength,
        coarseScaleFactor: preset.grainScale,
        coarseSeed: preset.textureSeed,
      ),
      preparedFullTip: preparedTip,
      emission: PawDabEmissionParameters(
        spacingFactor: preset.spacing,
        variantCount: 1,
        normalScatterFactor: preset.scatter,
        pressureSizeMinFactor: preset.pressureSizeMinimum,
        pressureSizeMaxFactor: 1,
        pressureOpacityMinFactor: preset.pressureFlowMinimum,
        pressureOpacityMaxFactor: 1,
        footprintEdgeRoughness: preset.edgeRoughness,
        dynamics: PawDabDynamicsParameters(
          slowDepositionScale: slow,
          fastDepositionScale: fast,
          sizeJitterFactor: preset.sizeJitter,
          opacityJitterFactor: preset.opacityJitter,
        ),
      ),
      maximumDabsPerChunk: 48,
      realtimePresentationTailDabBudget: 96,
      maximumBatchPictures: 16,
      compactionBatchSize: 8,
      identitySalt: preset.textureSeed,
    );
    definition.validate();
    final shape = preset.tipAspect == 1
        ? PawBrushShapeField.circle(hardness: preset.tipHardness)
        : PawBrushShapeField.ellipse(
            aspect: preset.tipAspect,
            hardness: preset.tipHardness,
          );
    final grainMode = preset.grainStrength == 0
        ? PawUnifiedBrushGrainMode.none
        : switch (preset.grainCoordinate) {
            PawDabGrainCoordinate.canvasFixed =>
              PawUnifiedBrushGrainMode.canvasFixed,
            PawDabGrainCoordinate.rolling =>
              PawUnifiedBrushGrainMode.strokeFollowing,
          };
    final swept = preparedTip &&
        preset.scatter == 0 &&
        preset.sizeJitter == 0 &&
        preset.opacityJitter == 0 &&
        preset.edgeRoughness == 0;
    final unifiedProgram = PawUnifiedBrushProgram(
      id: 'user:${preset.presetId}',
      revision: preset.revision,
      shape: shape,
      kernelKind: PawBrushKernelKind.dabDry,
      kernel: PawBrushKernelRegistry.dab,
      grainMode: grainMode,
      deposition: preset.grainStrength == 0
          ? PawUnifiedBrushDepositionModel.opaqueUniform
          : PawUnifiedBrushDepositionModel.dryMedia,
      dynamics: PawUnifiedBrushDynamicsProfile(
        pressureToSize: 1 - preset.pressureSizeMinimum,
        pressureToOpacity: 1 - preset.pressureFlowMinimum,
        speedToFlow: preset.speedFlow,
      ),
      renderRepresentation: swept
          ? PawUnifiedBrushRenderRepresentation.sweptCoverage
          : preparedTip
              ? PawUnifiedBrushRenderRepresentation.preparedStamp
              : PawUnifiedBrushRenderRepresentation.contactMesh,
      renderPlan: PawCompiledBrushRenderPlan(
        needsSweptCoverage: swept,
        needsPreparedTip: preparedTip && !swept,
        needsCanvasContact: !preparedTip,
        needsCanvasFixedGrain:
            grainMode == PawUnifiedBrushGrainMode.canvasFixed,
        needsDryMediaContact: preset.grainStrength > 0,
        preparedEdgeAntialiasLogicalPixels: preparedTip && !swept ? .6 : 0,
      ),
    )..validate();
    return PawCompiledBrushPreset(
      definition: definition,
      sizeScale: preset.sizeScale *
          (swept ? _sweptNominalWidthScale(definition, shape) : 1),
      opacity: preset.opacity,
      kernelKind: PawBrushKernelKind.dabDry,
      unifiedProgram: unifiedProgram,
    );
  }

  static PawCompiledBrushPreset compileV2(PawUserBrushPresetV2 preset) {
    validateV2(preset);
    if (preset.bristleLayout == PawUserBristleLayout.boardFur &&
        preset.bristleDensity > 0) {
      return _compileBoardFur(preset);
    }
    final bristle = preset.bristleDensity > 0 ||
        preset.shapeKind == PawBrushShapeKind.proceduralBristle;
    final mixedBristles = preset.bristleLayout == PawUserBristleLayout.mixed;
    final wet = preset.wetMedia.enabled;
    final stateful =
        preset.deposition == PawUnifiedBrushDepositionModel.airbrushDensity;
    final dryMedia =
        preset.deposition == PawUnifiedBrushDepositionModel.dryMedia ||
            preset.dryWax.enabled;
    final buildUp = preset.deposition == PawUnifiedBrushDepositionModel.buildUp;
    final canvasGrain =
        preset.grainMode == PawUnifiedBrushGrainMode.canvasFixed;
    final preparedTip =
        !bristle && !wet && !dryMedia && !buildUp && preset.grainStrength == 0;
    final needsContact = !preparedTip && !bristle;
    // Studio retains inactive controls so switching back can restore them.
    // A disabled scatter value must not route textured contact to a stamp or
    // folded ribbon backend. Scatter applies to independent prepared tips.
    final contactScatter = preparedTip ? preset.scatter : 0.0;
    final grooming = PawPersistentLaneGroomingParameters(
      lookBehindArcFactor: preset.bristleGrooming,
      inertia: preset.bristleGrooming,
      curvatureGain: preset.bristleGrooming,
      outerSplayFactor: preset.bristleGrooming * .5,
      maximumLagAngleRadians: preset.bristleGrooming * .45,
      preferredDirectionOffsetRadians: preset.bristleShearRadians,
    );
    final coreCount =
        bristle ? (8 + preset.bristleDensity * 48).round().clamp(8, 56) : 0;
    final guardCount =
        bristle ? (4 + preset.bristleDensity * 20).round().clamp(4, 24) : 0;
    final crossingHairs = bristle
        ? PawDabCrossingHairBundleParameters(
            density: preset.bristleDensity,
            spreadFactor: preset.bristleSpread,
            lengthFactor: preset.bristleLength,
            widthFactor: preset.bristleWidth,
            crossingAngleRadians: preset.bristleShearRadians,
            angleJitter: preset.bristleJitter,
            clump: preset.bristleClump,
            wander: preset.bristleWander,
            flow: preset.flow,
            tipTaper: preset.bristleTipTaper,
            softnessFactor: (1 - preset.tipHardness) * .12,
          ).compile()
        : const <PawDabFilamentLayer>[];
    final template = PawDabTemplateParameters(
      footprint: PawDabFootprintParameters(
        rectangular: !bristle && preset.shapeKind == PawBrushShapeKind.ellipse,
        lengthFactor: preset.tipAspect,
        widthFactor: 1,
        shapeExponent: stateful ? 2 : 2 + preset.tipHardness * 2,
        centerCoverage: bristle
            ? .08
            : stateful
                ? .985
                : 1,
        edgeCoverage: bristle
            ? 0
            : stateful
                ? .01 + preset.tipHardness * .35
                : preset.tipHardness,
        outerSoftnessFactor: (1 - preset.tipHardness) * .45,
      ),
      filamentLayers: mixedBristles ? crossingHairs : const [],
      persistentLaneLayers: bristle && mixedBristles
          ? <PawDabPersistentLaneLayer>[
              PawDabPersistentLaneLayer(
                laneCount: coreCount,
                spreadFactor: preset.bristleSpread * .72,
                widthFactors: PawDabRange(
                  preset.bristleWidth * .72,
                  preset.bristleWidth * 1.12,
                ),
                coverage: .42 * preset.flow,
                centerDensityExponent: 1.2,
                wanderAmplitudeFactor:
                    preset.bristleWander * preset.bristleJitter,
                clumpCount: math.max(1, (3 + 9 * preset.bristleClump).round()),
                clumpStrength: preset.bristleClump,
                tipFadeArcFactor: preset.bristleLength,
                segmentLengthFactor: .18,
                grooming: grooming,
                minimumPressureDensity: 1 - preset.pressureBristleDensity,
              ),
              PawDabPersistentLaneLayer(
                laneCount: guardCount,
                spreadFactor: preset.bristleSpread,
                widthFactors: PawDabRange(
                  preset.bristleWidth * .42,
                  preset.bristleWidth * .72,
                ),
                coverage: .32 * preset.flow,
                centerDensityExponent: 1.05,
                wanderAmplitudeFactor: preset.bristleWander,
                clumpCount: math.max(1, (2 + 6 * preset.bristleClump).round()),
                clumpStrength: preset.bristleClump * .72,
                tipFadeArcFactor: preset.bristleLength * 1.35,
                segmentLengthFactor: .2,
                grooming: grooming,
                minimumPressureDensity: 1 - preset.pressureBristleDensity,
              ),
            ]
          : const <PawDabPersistentLaneLayer>[],
      streamingFilamentLayers: bristle && !mixedBristles
          ? [
              for (var layer = 0; layer < 2; layer++)
                PawDabStreamingFilamentLayer(
                  countPerRoot: layer == 0
                      ? (2 + 10 * preset.bristleDensity).round()
                      : math.max(
                          1,
                          ((2 + 2 * preset.bristleDensity) *
                                  preset.bristleGuardDensity)
                              .round()),
                  rootSpacingFactor: preset.spacing * (layer == 0 ? 1 : 2),
                  lengthFactors: PawDabRange(
                      preset.bristleLength *
                          (layer == 0
                              ? .86
                              : 1.075 * preset.bristleGuardLength),
                      preset.bristleLength *
                          (layer == 0
                              ? 1.21
                              : 1.375 * preset.bristleGuardLength)),
                  widthFactors: PawDabRange(
                      preset.bristleWidth * (layer == 0 ? .64 : .36),
                      preset.bristleWidth * (layer == 0 ? 1.2 : .76)),
                  spreadFactor: preset.bristleSpread *
                      (layer == 0 ? .5 : 1.1 * preset.bristleGuardSpread),
                  coverage: preset.flow * (layer == 0 ? .7 : .47),
                  centerDensityExponent:
                      layer == 0 ? 1 + preset.bristleClump : 1.06,
                  shearAngleRadians: preset.bristleShearRadians,
                  directionJitterRadians: preset.bristleJitter,
                  bendFactor: preset.bristleBend *
                      (layer == 0 ? 1 : 1.16 * preset.bristleGuardBend),
                  widthTaper: preset.bristleTipTaper,
                  opacityTaper: preset.bristleTipTaper,
                  familyCoherence: preset.bristleClump * .9,
                  softnessFactor: preset.bristleSoftness,
                  clumpScaleFactor: preset.bristleClumpScale,
                  bendBias: preset.bristleBendBias,
                  wanderAmplitudeFactor: preset.bristleWander,
                  turnCompliance: preset.bristleTurnCompliance,
                  grooming: grooming,
                  minimumPressureDensity: 1 - preset.pressureBristleDensity,
                ),
            ]
          : bristle
              ? <PawDabStreamingFilamentLayer>[
                  PawDabStreamingFilamentLayer(
                    countPerRoot:
                        math.max(2, (2 + 5 * preset.bristleDensity).round()),
                    rootSpacingFactor: .42,
                    lengthFactors: PawDabRange(
                      preset.bristleLength * .72,
                      preset.bristleLength * 1.38,
                    ),
                    widthFactors: PawDabRange(
                      preset.bristleWidth * .3,
                      preset.bristleWidth * .55,
                    ),
                    spreadFactor: preset.bristleSpread * 1.08,
                    coverage: .34 * preset.flow,
                    directionJitterRadians: preset.bristleJitter * .45,
                    bendFactor: preset.bristleWander,
                    shearAngleRadians: preset.bristleShearRadians,
                    widthTaper: preset.bristleTipTaper,
                    opacityTaper: preset.bristleTipTaper,
                    segmentLengthFactor: .2,
                    grooming: grooming,
                    familyCoherence: .55,
                    minimumPressureDensity: 1 - preset.pressureBristleDensity,
                  ),
                ]
              : const <PawDabStreamingFilamentLayer>[],
    );
    final definition = PawDabBrushDefinition(
      id: 'user:${preset.presetId}',
      revision: preset.revision,
      fixedStep: PawDabBrushDefinitions.fixedStep,
      template: template,
      preparedFullTip: preparedTip,
      wetMedia: preset.wetMedia,
      dryWax: preset.dryWax.enabled
          ? preset.dryWax
          : dryMedia
              ? PawDabDryWaxParameters.physicalCrayon
              : const PawDabDryWaxParameters(),
      useWholeDabDryMediaCoverage: false,
      paperContact: dryMedia || wet
          ? const PawPaperContactParameters(
              minimumContact: .5,
              maximumContact: .88,
              depositionWeight: .08,
              coarseDepositionStrength: .06)
          : const PawPaperContactParameters(),
      grain: PawDabGrainParameters(
        coordinate: canvasGrain
            ? PawDabGrainCoordinate.canvasFixed
            : PawDabGrainCoordinate.rolling,
        structure: preset.grainStructure,
        coarseStrength: preset.grainStrength,
        coarseScaleFactor: preset.grainScale,
        coarseSeed: preset.textureSeed,
        fineStrength: preset.grainStrength * .6,
        fineScaleFactor: preset.grainScale * .08,
        fineSeed: preset.textureSeed ^ 0x731,
        rotationRadians: preset.grainRotation,
        movement:
            (preset.grainMovement + preset.grainToMotion).clamp(-2.0, 2.0),
      ),
      emission: PawDabEmissionParameters(
        spacingFactor: preset.spacing,
        variantCount: bristle ? 8 : 1,
        normalScatterFactor: contactScatter,
        rotationJitterRadians: preset.rotationJitterRadians,
        baseRotationRadians: preset.tipAngleRadians,
        directionRotationFactor: preset.directionToRotation,
        pressureSizeMinFactor: (1 - preset.pressureToSize).clamp(.05, 1),
        pressureOpacityMinFactor: (1 - preset.pressureToOpacity).clamp(0, 1),
        footprintEdgeRoughness: preset.edgeRoughness,
        dynamics: PawDabDynamicsParameters(
          slowDepositionScale:
              (preset.flow * (1 - preset.speedToFlow * .35)).clamp(0, 4),
          fastDepositionScale:
              (preset.flow * (1 + preset.speedToFlow * .35)).clamp(0, 4),
          pressureDepositionMinFactor: (1 - preset.pressureToFlow).clamp(0, 1),
          speedSpacingFactor: preset.speedToSpacing,
          turnDepositionScale: (1 + preset.curvatureToShape * .5).clamp(0, 2),
        ),
      ),
      maximumDabsPerChunk: 48,
      realtimePresentationTailDabBudget: bristle ? 192 : 96,
      maximumBatchPictures: 16,
      compactionBatchSize: 8,
      identitySalt: preset.textureSeed,
    )..validate();
    final kernelKind = bristle
        ? PawBrushKernelKind.bristleFilament
        : stateful
            ? PawBrushKernelKind.softDensity
            : buildUp || wet
                ? PawBrushKernelKind.inkCoverage
                : PawBrushKernelKind.dabDry;
    final behavior = bristle
        ? PawBrushBehaviorRegistry.fur
        : stateful
            ? PawBrushBehaviorRegistry.soft
            : buildUp || wet
                ? PawBrushBehaviorRegistry.ink
                : null;
    final shape = bristle
        ? PawBrushShapeField.proceduralBristle(
            density: preset.bristleDensity,
            direction: preset.bristleShearRadians,
            length: preset.bristleLength,
            variation: preset.bristleJitter,
            rootTipAttenuation: preset.bristleTipTaper,
            aspect: preset.tipAspect,
            hardness: preset.tipHardness,
          )
        : preset.shapeKind == PawBrushShapeKind.ellipse
            ? PawBrushShapeField.ellipse(
                aspect: preset.tipAspect,
                hardness: preset.tipHardness,
              )
            : PawBrushShapeField.circle(hardness: preset.tipHardness);
    final swept = !bristle &&
        !stateful &&
        !dryMedia &&
        (preparedTip || wet || (!buildUp && preset.grainStrength > 0)) &&
        contactScatter == 0 &&
        preset.rotationJitterRadians == 0 &&
        preset.edgeRoughness == 0;
    final plan = PawCompiledBrushRenderPlan(
      needsSweptCoverage: swept,
      needsPreparedTip: preparedTip && !swept,
      needsCanvasContact: needsContact,
      needsPersistentBristles: bristle && mixedBristles,
      needsStreamingHairs: bristle,
      needsStatefulDensity: stateful,
      needsWetMediaTiles: wet && !swept,
      needsTemporalContact: wet && swept,
      needsCanvasFixedGrain: canvasGrain,
      needsDryMediaContact: dryMedia,
      needsBuildUp: buildUp,
      preparedEdgeAntialiasLogicalPixels: preparedTip && !swept ? .6 : 0,
    );
    final program = PawUnifiedBrushProgram(
      id: 'user:${preset.presetId}',
      revision: preset.revision,
      shape: shape,
      kernelKind: kernelKind,
      kernel: PawBrushKernelRegistry.forKind(kernelKind),
      behavior: behavior,
      grainMode: preset.grainMode,
      deposition: preset.deposition,
      dynamics: PawUnifiedBrushDynamicsProfile(
        pressureToSize: preset.pressureToSize,
        pressureToOpacity: preset.pressureToOpacity,
        speedToFlow: preset.speedToFlow,
        speedToSpacing: preset.speedToSpacing,
        directionToRotation: preset.directionToRotation,
        curvatureToShape: preset.curvatureToShape,
        grainToMotion: preset.grainToMotion,
        bristleSpread: bristle ? preset.bristleSpread : 0,
      ),
      supportsStatefulMaterial: stateful || wet,
      renderRepresentation: swept
          ? PawUnifiedBrushRenderRepresentation.sweptCoverage
          : preparedTip
              ? PawUnifiedBrushRenderRepresentation.preparedStamp
              : PawUnifiedBrushRenderRepresentation.contactMesh,
      renderPlan: plan,
      endpoint: PawUnifiedBrushEndpointProfile(
        tangentSize: !bristle,
        startTaperBrushLengths: preset.startTaperBrushLengths,
        endTaperBrushLengths: preset.endTaperBrushLengths,
        minimumSizeFactor: preset.minimumEndpointSize,
        minimumOpacityFactor: preset.minimumEndpointOpacity,
        taperExponent: preset.endpointTaperExponent,
        capRoundness: !bristle && preset.shapeKind == PawBrushShapeKind.ellipse
            ? 0
            : preset.capRoundness,
        capRoughness: preset.capRoughness,
      ),
    )..validate();
    return PawCompiledBrushPreset(
      definition: definition,
      sizeScale: preset.sizeScale *
          (swept || (!bristle && !stateful && !dryMedia && !buildUp)
              ? _sweptNominalWidthScale(definition, shape)
              : 1),
      opacity: preset.opacity,
      kernelKind: kernelKind,
      unifiedProgram: program,
    );
  }

  /// Studio Fur derives from the actual canvas recipe. Only exposed authoring
  /// controls vary it; hair proportions, guard layers and material dynamics
  /// have one source of truth in the production Fur definition.
  static PawCompiledBrushPreset _compileBoardFur(PawUserBrushPresetV2 p) {
    final base = PawBrushPresetCatalog._compiledForTool(DrawingTool.furBrush);
    final d = base.definition, program = base.unifiedProgram!;
    final layers = [
      for (final hair in d.template.streamingFilamentLayers)
        PawDabStreamingFilamentLayer(
          countPerRoot:
              (hair.countPerRoot * p.bristleDensity / .65).round().clamp(1, 64),
          rootSpacingFactor: hair.rootSpacingFactor * p.spacing / .14,
          lengthFactors: hair.lengthFactors,
          widthFactors: hair.widthFactors,
          spreadFactor: hair.spreadFactor,
          coverage: (hair.coverage * p.flow / .8).clamp(0, 1),
          centerDensityExponent: hair.centerDensityExponent,
          directionJitterRadians: hair.directionJitterRadians,
          shearAngleRadians: hair.shearAngleRadians,
          bendFactor: hair.bendFactor,
          widthTaper: hair.widthTaper,
          opacityTaper: hair.opacityTaper,
          taperExponent: hair.taperExponent,
          rootFadeFraction: hair.rootFadeFraction,
          segmentLengthFactor: hair.segmentLengthFactor,
          grooming: hair.grooming,
          familyCoherence: hair.familyCoherence,
          minimumPressureDensity: hair.minimumPressureDensity,
          softnessFactor:
              (hair.softnessFactor * (1 - p.tipHardness) / .25).clamp(0, .15),
          clumpScaleFactor: hair.clumpScaleFactor,
          bendBias: hair.bendBias,
          wanderAmplitudeFactor: hair.wanderAmplitudeFactor,
          turnCompliance:
              (hair.turnCompliance + p.bristleTurnCompliance - .65).clamp(0, 1),
        )
    ];
    final e = d.emission, g = d.grain;
    final pressure = p.pressureToSize / .45;
    final definition = PawDabBrushDefinition(
      id: 'user:${p.presetId}',
      revision: p.revision,
      fixedStep: d.fixedStep,
      template: PawDabTemplateParameters(
          footprint: d.template.footprint, streamingFilamentLayers: layers),
      grain: PawDabGrainParameters(
          coordinate: g.coordinate,
          coarseStrength: (g.coarseStrength * p.grainStrength / .3).clamp(0, 1),
          coarseScaleFactor: g.coarseScaleFactor * p.grainScale,
          coarseSeed: g.coarseSeed,
          fineStrength: (g.fineStrength * p.grainStrength / .3).clamp(0, 1),
          fineScaleFactor: g.fineScaleFactor * p.grainScale,
          fineSeed: g.fineSeed),
      emission: PawDabEmissionParameters(
          spacingFactor: e.spacingFactor * p.spacing / .14,
          variantCount: e.variantCount,
          pressureSizeMinFactor:
              (1 - (1 - e.pressureSizeMinFactor) * pressure).clamp(.05, 1),
          pressureSizeMaxFactor: 1 + (e.pressureSizeMaxFactor - 1) * pressure,
          pressureOpacityMinFactor:
              (1 - (1 - e.pressureOpacityMinFactor) * pressure).clamp(0, 1),
          pressureOpacityMaxFactor: e.pressureOpacityMaxFactor,
          dynamics: e.dynamics,
          footprintEdgeRoughness: e.footprintEdgeRoughness,
          footprintEdgeRoughnessFrequency: e.footprintEdgeRoughnessFrequency),
      maximumDabsPerChunk: d.maximumDabsPerChunk,
      realtimePresentationTailDabBudget: d.realtimePresentationTailDabBudget,
      maximumBatchPictures: d.maximumBatchPictures,
      compactionBatchSize: d.compactionBatchSize,
      identitySalt: d.identitySalt,
    )..validate();
    return PawCompiledBrushPreset(
        definition: definition,
        sizeScale: base.sizeScale * p.sizeScale,
        opacity: base.opacity * p.opacity,
        kernelKind: base.kernelKind,
        unifiedProgram: PawUnifiedBrushProgram(
          id: 'user:${p.presetId}',
          revision: p.revision,
          shape: program.shape,
          kernelKind: program.kernelKind,
          kernel: program.kernel,
          behavior: program.behavior,
          grainMode: program.grainMode,
          deposition: program.deposition,
          dynamics: program.dynamics,
          renderRepresentation: program.renderRepresentation,
          renderPlan: program.renderPlan,
          endpoint: PawUnifiedBrushEndpointProfile(
              startTaperBrushLengths: p.startTaperBrushLengths,
              endTaperBrushLengths: p.endTaperBrushLengths,
              minimumSizeFactor: p.minimumEndpointSize,
              minimumOpacityFactor: p.minimumEndpointOpacity,
              taperExponent: program.endpoint!.taperExponent),
        )..validate());
  }

  // Neutral pressure (.5), 600 document pixels/s, horizontal half-peak width.
  // Size remains an authoring control; changing hardness or pressure response
  // no longer silently halves the nominal size of an otherwise identical tip.
  static double _sweptNominalWidthScale(
      PawDabBrushDefinition definition, PawBrushShapeField shape) {
    final pressure = (definition.emission.pressureSizeMinFactor +
            definition.emission.pressureSizeMaxFactor) *
        .5;
    final wet = definition.wetMedia.enabled;
    final hardness = wet
        ? definition.template.footprint.edgeCoverage.clamp(.35, .85)
        : shape.hardness;
    final kernelWidth =
        wet ? (.82 + .32 * math.sqrt(.5)) * (1 - .18 * .4) : 1.0;
    return 1 /
        (pressure *
            kernelWidth *
            (.5 + hardness * .5) *
            definition.template.footprint.widthFactor);
  }

  static void validateV2(PawUserBrushPresetV2 p) {
    p.wetMedia.validate();
    p.dryWax.validate();
    if (!_range(p.bristleBend, 0, .5) ||
        !_range(p.bristleGuardLength, .25, 3) ||
        !_range(p.bristleGuardBend, 0, 4) ||
        !_range(p.bristleGuardDensity, .1, 2) ||
        !_range(p.bristleGuardSpread, .1, 3) ||
        !_range(p.bristleSoftness, 0, .15) ||
        !_range(p.bristleClumpScale, .08, 4) ||
        !_range(p.bristleBendBias, -1, 1) ||
        !_range(p.bristleTurnCompliance, 0, 1)) {
      throw ArgumentError('Invalid bristle bend or guard layer.');
    }
    if (p.wetMedia.enabled &&
        (p.bristleDensity > 0 ||
            p.shapeKind == PawBrushShapeKind.proceduralBristle ||
            p.deposition == PawUnifiedBrushDepositionModel.airbrushDensity ||
            p.deposition == PawUnifiedBrushDepositionModel.dryMedia ||
            p.dryWax.enabled)) {
      throw ArgumentError(
          'Wet contact cannot be combined with hair, wax or airbrush deposition.');
    }
    final values = <double>[
      p.sizeScale,
      p.opacity,
      p.flow,
      p.spacing,
      p.tipAspect,
      p.tipHardness,
      p.tipAngleRadians,
      p.rotationJitterRadians,
      p.scatter,
      p.edgeRoughness,
      p.startTaperBrushLengths,
      p.endTaperBrushLengths,
      p.minimumEndpointSize,
      p.minimumEndpointOpacity,
      p.endpointTaperExponent,
      p.capRoundness,
      p.capRoughness,
      p.grainStrength,
      p.grainScale,
      p.grainRotation,
      p.grainMovement,
      p.pressureToSize,
      p.pressureToOpacity,
      p.pressureToFlow,
      p.speedToFlow,
      p.speedToSpacing,
      p.directionToRotation,
      p.curvatureToShape,
      p.grainToMotion,
      p.bristleDensity,
      p.bristleSpread,
      p.bristleLength,
      p.bristleWidth,
      p.bristleShearRadians,
      p.bristleJitter,
      p.bristleClump,
      p.bristleWander,
      p.bristleGrooming,
      p.bristleTipTaper,
      p.pressureBristleDensity,
    ];
    if (p.presetId.isEmpty ||
        p.presetId.length > 80 ||
        p.revision < 1 ||
        p.textureSeed < 0 ||
        values.any((value) => !value.isFinite) ||
        !_range(p.sizeScale, .1, 4) ||
        !_range(p.opacity, 0, 1) ||
        !_range(p.flow, 0, 1) ||
        !_range(p.spacing, .02, 2) ||
        !_range(p.tipAspect, .1, 2) ||
        !_range(p.tipHardness, 0, 1) ||
        !_range(p.tipAngleRadians, -math.pi, math.pi) ||
        !_range(p.rotationJitterRadians, 0, math.pi) ||
        !_range(p.scatter, 0, 4) ||
        !_range(p.edgeRoughness, 0, .25) ||
        !_range(p.startTaperBrushLengths, 0, 4) ||
        !_range(p.endTaperBrushLengths, 0, 4) ||
        !_range(p.minimumEndpointSize, 0, 1) ||
        !_range(p.minimumEndpointOpacity, 0, 1) ||
        !_range(p.endpointTaperExponent, .2, 6) ||
        !_range(p.capRoundness, 0, 1) ||
        !_range(p.capRoughness, 0, .25) ||
        !_range(p.grainStrength, 0, 1) ||
        !_range(p.grainScale, .05, 8) ||
        !_range(p.grainRotation, -math.pi, math.pi) ||
        !_range(p.grainMovement, -1, 1) ||
        !_range(p.pressureToSize, 0, 1) ||
        !_range(p.pressureToOpacity, 0, 1) ||
        !_range(p.pressureToFlow, 0, 1) ||
        !_range(p.speedToFlow, -1, 1) ||
        !_range(p.speedToSpacing, -1, 1) ||
        !_range(p.directionToRotation, -1, 1) ||
        !_range(p.curvatureToShape, -1, 1) ||
        !_range(p.grainToMotion, -1, 1) ||
        !_range(p.bristleDensity, 0, 1) ||
        !_range(p.bristleSpread, .1, 2) ||
        !_range(p.bristleLength, .1, 2) ||
        !_range(p.bristleWidth, .005, .16) ||
        !_range(p.bristleShearRadians, -math.pi / 3, math.pi / 3) ||
        !_range(p.bristleJitter, 0, 1) ||
        !_range(p.bristleClump, 0, 1) ||
        !_range(p.bristleWander, 0, .3) ||
        !_range(p.bristleGrooming, 0, 1) ||
        !_range(p.bristleTipTaper, 0, 1) ||
        !_range(p.pressureBristleDensity, 0, 1)) {
      throw const FormatException('Invalid brush preset value.');
    }
  }

  static void validate(PawUserBrushPresetV1 p) {
    if (p.presetId.isEmpty ||
        p.presetId.length > 80 ||
        p.revision < 1 ||
        p.textureSeed < 0 ||
        !_range(p.sizeScale, .1, 4) ||
        !_range(p.opacity, 0, 1) ||
        !_range(p.spacing, .02, 2) ||
        !_range(p.flow, 0, 1) ||
        !_range(p.tipAspect, .1, 2) ||
        !_range(p.tipHardness, 0, 1) ||
        !_range(p.edgeRoughness, 0, .25) ||
        !_range(p.grainStrength, 0, 1) ||
        !_range(p.grainScale, .05, 8) ||
        !_range(p.pressureSizeMinimum, .05, 1) ||
        !_range(p.pressureFlowMinimum, 0, 1) ||
        !_range(p.speedFlow, -1, 1) ||
        !_range(p.sizeJitter, 0, .8) ||
        !_range(p.opacityJitter, 0, .95) ||
        !_range(p.scatter, 0, 4)) {
      throw const FormatException('Invalid brush preset value.');
    }
  }

  static bool _range(double value, double minimum, double maximum) =>
      value.isFinite && value >= minimum && value <= maximum;
}
