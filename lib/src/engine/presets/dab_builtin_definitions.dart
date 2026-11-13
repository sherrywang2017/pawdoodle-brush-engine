// Presets are final rather than const because PawDabTemplateParameters makes
// defensive unmodifiable copies of its layer lists.
// ignore_for_file: prefer_const_constructors,
//   prefer_const_literals_to_create_immutables

part of '../../streaming_dab_brush.dart';

abstract final class PawDabBrushDefinitions {
  static final Map<String, PawDabBrushDefinition> _definitions =
      <String, PawDabBrushDefinition>{};

  static void debugInvalidate() => _definitions.clear();

  static const fixedStep = PawFixedStepModelParameters(
    stepRateHz: 240,
    responsePerSecond: 120,
    dampingRatio: 1,
    predictionMilliseconds: 12,
    maximumPredictionDistance: 12,
    maximumStepsPerAppend: 96,
    minimumOutputDistance: .08,
  );

  static PawDabBrushDefinition get round => _definitions.putIfAbsent(
      'round',
      () => PawDabBrushDefinition(
            id: 'round-dab',
            revision: 6,
            preparedFullTip: true,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: 1,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: 1,
                edgeCoverage: 1,
                outerSoftnessFactor: 0,
              ),
            ),
            emission: PawDabEmissionParameters(
              spacingFactor: .14,
              variantCount: 1,
            ),
            maximumDabsPerChunk: 48,
            realtimePresentationTailDabBudget: 96,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x12ad01,
          ));
  static PawDabBrushDefinition get crayon => _definitions.putIfAbsent(
      'crayon',
      () => PawDabBrushDefinition(
            id: 'crayon-dab',
            revision: 66,
            preparedFullTip: false,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: 1.12,
                widthFactor: 1,
                shapeExponent: 4,
                // One pass leaves visible paper tooth; overlapping passes
                // gradually fill it instead of becoming an opaque marker on
                // the first sweep.
                centerCoverage: .98,
                edgeCoverage: .15,
                outerSoftnessFactor: .025,
                capRoundness: .68,
                capRoughnessFactor: .22,
                edgeResponse: PawDabMultiScaleEdgeResponseParameters(
                  macroInsetFactor: .12,
                  macroArcScaleFactor: 2.6,
                  microInsetFactor: .065,
                  microCanvasScale: 1.35,
                  edgeBandStart: .25,
                  seed: 0x4c3a,
                ),
              ),
            ),
            useWholeDabDryMediaCoverage: false,
            // Paper tooth is stationary; the low-frequency dragged wax
            // response below still follows absolute stroke arc and normal.
            grain: const PawDabGrainParameters(
              coordinate: PawDabGrainCoordinate.canvasFixed,
              structure: PawDabGrainStructure.waxAggregate,
              coarseStrength: .65,
              coarseScaleFactor: 1.05,
              coarseSeed: 0x31c,
              fineStrength: .52,
              fineScaleFactor: .085,
              fineSeed: 0x731,
              poreAspectRatios: PawDabRange(.45, 1.35),
              poreAngleJitterRadians: math.pi,
              strokeAlignedStrength: .12,
              strokeAlignedAlongScaleFactor: .72,
              strokeAlignedNormalScaleFactor: .12,
              strokeAlignedSeed: 0x5b71,
            ),
            paperContact: const PawPaperContactParameters(
              minimumContact: .5,
              maximumContact: .88,
              pressureExponent: .9,
              depositionWeight: .08,
              toothContrast: 1.05,
              transitionSoftness: .08,
              maximumSampleSpacing: .75,
              toothCoarseWeight: .18,
              toothMediumWeight: .55,
              toothFineWeight: .82,
              coarseDepositionStrength: .06,
            ),
            coverageTransfer: const PawDabCoverageTransferParameters(
              paperContactFloor: .18,
              textureFloor: .42,
              expectedDabOverlaps: 6,
            ),
            dryWax: PawDabDryWaxParameters.physicalCrayon,
            emission: PawDabEmissionParameters(
              spacingFactor: .07,
              variantCount: 1,
              arcDensityPeriodFactor: .77,
              arcDensityAmplitude: .025,
              canvasDensityScaleFactor: .72,
              canvasDensityAmplitude: .1,
              footprintEdgeRoughness: 0,
              footprintEdgeRoughnessFrequency: 15,
              dynamics: PawDabDynamicsParameters(
                speedReferencePixelsPerSecond: 720,
                // Dry wax does not acquire extra pigment when slowing down.
                slowDepositionScale: .82,
                fastDepositionScale: .82,
                spacingJitterFactor: .018,
                sizeJitterFactor: 0,
                opacityJitterFactor: .014,
              ),
            ),
            maximumDabsPerChunk: 32,
            realtimePresentationTailDabBudget: 96,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x2700c69,
          ));
  static PawDabBrushDefinition get marker => _definitions.putIfAbsent(
      'marker',
      () => PawDabBrushDefinition(
            id: 'marker-dab',
            revision: 6,
            preparedFullTip: true,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: .45,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: .22,
                edgeCoverage: .22,
                outerSoftnessFactor: 0,
              ),
            ),
            emission: PawDabEmissionParameters(
              spacingFactor: .12,
              variantCount: 1,
              directionRotationFactor: 0,
            ),
            maximumDabsPerChunk: 48,
            realtimePresentationTailDabBudget: 96,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x12ad02,
          ));
  static PawDabBrushDefinition get soft => _definitions.putIfAbsent(
      'soft',
      () => PawDabBrushDefinition(
            id: 'soft-dab',
            revision: 17,
            preparedFullTip: true,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: 1,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: .985,
                edgeCoverage: .12,
                outerSoftnessFactor: .34,
              ),
            ),
            coverageTransfer: const PawDabCoverageTransferParameters(
              expectedDabOverlaps: 12,
            ),
            emission: PawDabEmissionParameters(
              // About 6 DABs per actual radius at the production size scale. This is
              // dense enough for a continuous airbrush trail without the pointer-move
              // cost of the former ~9 DABs per radius.
              spacingFactor: .07,
              variantCount: 1,
              pressureSizeMinFactor: .62,
              pressureSizeMaxFactor: 1.12,
              pressureOpacityMinFactor: .28,
              pressureOpacityMaxFactor: 1,
            ),
            maximumDabsPerChunk: 48,
            realtimePresentationTailDabBudget: 96,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x12ad03,
          ));
  static PawDabBrushDefinition get ink => _definitions.putIfAbsent(
      'ink',
      () => PawDabBrushDefinition(
            id: 'ink-dab',
            revision: 56,
            preparedFullTip: false,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: .86,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: .9,
                edgeCoverage: .24,
                outerSoftnessFactor: .1,
                capRoughnessFactor: .1,
                edgeResponse: PawDabMultiScaleEdgeResponseParameters(
                  macroInsetFactor: .17,
                  macroArcScaleFactor: 3.15,
                  microInsetFactor: .075,
                  microCanvasScale: 1.35,
                  edgeBandStart: .36,
                  seed: 0x1a9e,
                ),
              ),
            ),
            grain: const PawDabGrainParameters(
              coordinate: PawDabGrainCoordinate.canvasFixed,
              structure: PawDabGrainStructure.absorbentWash,
              coarseStrength: .84,
              coarseScaleFactor: 2,
              coarseSeed: 0x1c90,
              fineStrength: .24,
              fineScaleFactor: .14,
              fineSeed: 0x73a9,
              poreAspectRatios: PawDabRange(.55, 1.25),
              poreAngleJitterRadians: math.pi,
            ),
            paperContact: const PawPaperContactParameters(
              minimumContact: .62,
              maximumContact: .9,
              pressureExponent: .82,
              depositionWeight: .18,
              toothContrast: .9,
              transitionSoftness: .085,
              maximumSampleSpacing: .85,
              toothCoarseWeight: .12,
              toothMediumWeight: .72,
              toothFineWeight: .9,
              coarseDepositionStrength: .1,
            ),
            wetMedia: const PawDabWetMediaParameters(
              enabled: true,
              dilution: .42,
              charge: .86,
              attack: .66,
              bleed: .75,
              granulation: .24,
              wetnessJitter: .82,
              diffusionRadius: .65,
              edgeFeather: .74,
              depositionOpticalGain: 1.68,
              settlingDuration: Duration(milliseconds: 240),
              localOverlapNormalization: 1,
            ),
            coverageTransfer: const PawDabCoverageTransferParameters(
              paperContactFloor: .36,
              textureFloor: .02,
              expectedDabOverlaps: 2.5,
            ),
            emission: PawDabEmissionParameters(
              // Dense, linearly normalized contacts remove the visible row of stamp
              // centers while preserving one canvas-fixed paper field. This is still
              // the shared streaming DAB path; no per-DAB image is created.
              spacingFactor: .05,
              variantCount: 1,
              pressureSizeMinFactor: .42,
              pressureSizeMaxFactor: 1,
              pressureOpacityMinFactor: .52,
              pressureOpacityMaxFactor: 1,
              // Paper grain breaks the wet shoulder in canvas space. Repeating a
              // sinusoidal DAB outline here creates visible scallop/fish-scale rows.
              footprintEdgeRoughness: 0,
              footprintEdgeRoughnessFrequency: 9,
              arcDensityPeriodFactor: .82,
              arcDensityAmplitude: 0,
              canvasDensityScaleFactor: .46,
              canvasDensityAmplitude: 0,
              dynamics: PawDabDynamicsParameters(
                speedReferencePixelsPerSecond: 760,
                slowDepositionScale: 1,
                fastDepositionScale: 1,
                opacityJitterFactor: 0,
              ),
            ),
            maximumDabsPerChunk: 48,
            realtimePresentationTailDabBudget: 112,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x26001a9,
          ));
  static PawDabBrushDefinition get fur => _definitions.putIfAbsent(
      'fur',
      () => PawDabBrushDefinition(
            id: 'fur-dab',
            revision: 70,
            // Fur is made only from free, continuous-root hair geometry. There
            // is no opaque carrier or repeated local tuft.
            preparedFullTip: false,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: 1,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: 0,
                edgeCoverage: 0,
                outerSoftnessFactor: 0,
              ),
              streamingFilamentLayers: const <PawDabStreamingFilamentLayer>[
                PawDabStreamingFilamentLayer(
                  countPerRoot: 10,
                  rootSpacingFactor: .06,
                  lengthFactors: PawDabRange(2.2, 4.0),
                  widthFactors: PawDabRange(.036, .060),
                  spreadFactor: 2.8,
                  coverage: .432,
                  centerDensityExponent: 1.6,
                  directionJitterRadians: .44,
                  shearAngleRadians: -.65,
                  bendFactor: .16,
                  bendBias: .55,
                  familyCoherence: .65,
                  softnessFactor: .022,
                  wanderAmplitudeFactor: .018,
                  turnCompliance: .6,
                  clumpScaleFactor: .16,
                  grooming: PawPersistentLaneGroomingParameters(
                    lookBehindArcFactor: .2,
                    inertia: .8,
                  ),
                  widthTaper: .85,
                  opacityTaper: .80,
                  taperExponent: 2.0,
                  rootFadeFraction: 0,
                  segmentLengthFactor: .24,
                  minimumPressureDensity: .78,
                ),
                PawDabStreamingFilamentLayer(
                  countPerRoot: 8,
                  rootSpacingFactor: .12,
                  lengthFactors: PawDabRange(1.8, 5.6),
                  widthFactors: PawDabRange(.012, .025),
                  spreadFactor: 1.45,
                  coverage: .30,
                  centerDensityExponent: 1.06,
                  directionJitterRadians: .27,
                  shearAngleRadians: -.60,
                  bendFactor: .32,
                  bendBias: .65,
                  familyCoherence: .65,
                  softnessFactor: .016,
                  wanderAmplitudeFactor: .012,
                  turnCompliance: .8,
                  clumpScaleFactor: .24,
                  grooming: PawPersistentLaneGroomingParameters(
                    lookBehindArcFactor: .24,
                    inertia: .9,
                  ),
                  widthTaper: .95,
                  opacityTaper: .90,
                  taperExponent: 1.08,
                  rootFadeFraction: 0,
                  segmentLengthFactor: .22,
                  minimumPressureDensity: .7,
                ),
              ],
            ),
            grain: const PawDabGrainParameters(
              coordinate: PawDabGrainCoordinate.rolling,
              coarseStrength: .22,
              coarseScaleFactor: .65,
              coarseSeed: 3721,
              fineStrength: .12,
              fineScaleFactor: .05,
              fineSeed: 1947,
            ),
            emission: PawDabEmissionParameters(
              spacingFactor: .06,
              variantCount: 1,
              pressureSizeMinFactor: .62,
              pressureSizeMaxFactor: 1.12,
              pressureOpacityMinFactor: .74,
              pressureOpacityMaxFactor: 1,
              dynamics: PawDabDynamicsParameters(
                speedReferencePixelsPerSecond: 640,
                slowDepositionScale: 1.08,
                fastDepositionScale: 1,
                spacingJitterFactor: .025,
                opacityJitterFactor: .1,
                filamentCoverageDepositionScale: 1.24,
              ),
              footprintEdgeRoughness: .035,
              footprintEdgeRoughnessFrequency: 17,
            ),
            maximumDabsPerChunk: 48,
            // Exact live Fur owns endpoint taper plus filament safety look-behind.
            // This is an ownership/work bound only; spacing and visual density stay
            // unchanged. The measured worst-case tail is 184 DABs.
            realtimePresentationTailDabBudget: 192,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x26ad08,
          ));
  static PawDabBrushDefinition get eraser => _definitions.putIfAbsent(
      'eraser',
      () => PawDabBrushDefinition(
            id: 'eraser-dab',
            revision: 3,
            preparedFullTip: true,
            fixedStep: fixedStep,
            template: PawDabTemplateParameters(
              footprint: PawDabFootprintParameters(
                lengthFactor: 1,
                widthFactor: 1,
                shapeExponent: 2,
                centerCoverage: 1,
                edgeCoverage: 1,
                outerSoftnessFactor: 0,
              ),
            ),
            emission:
                PawDabEmissionParameters(spacingFactor: .14, variantCount: 1),
            maximumDabsPerChunk: 48,
            realtimePresentationTailDabBudget: 96,
            maximumBatchPictures: 16,
            compactionBatchSize: 8,
            identitySalt: 0x12ad08,
          ));
}
