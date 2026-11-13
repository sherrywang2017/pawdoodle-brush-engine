part of '../../brush_preset.dart';

/// The only production mapping from a drawing tool to its runtime preset.
abstract final class PawBrushPresetCatalog {
  static final Map<String, PawUnifiedBrushProgram> _unifiedPrograms =
      <String, PawUnifiedBrushProgram>{};

  static void debugInvalidate() {
    _unifiedPrograms.clear();
    PawDabBrushDefinitions.debugInvalidate();
  }

  // The production catalog is the only place that composes the unified
  // expression. The streaming renderer consumes this object; it does not
  // create a Crayon/Ink/Fur/Soft engine of its own.
  static PawUnifiedBrushProgram get _roundUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'round',
          () => const PawUnifiedBrushProgram(
                id: 'production:round',
                revision: 1,
                shape: PawBrushShapeField.circle(),
                kernelKind: PawBrushKernelKind.dabDry,
                kernel: PawBrushKernelRegistry.dab,
                deposition: PawUnifiedBrushDepositionModel.opaqueUniform,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.sweptCoverage,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsSweptCoverage: true,
                  needsPreparedTip: false,
                  preparedEdgeAntialiasLogicalPixels: 0,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .8,
                  pressureToOpacity: .2,
                ),
              ));

  static PawUnifiedBrushProgram get _crayonUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'crayon',
          () => const PawUnifiedBrushProgram(
                id: 'production:crayon',
                revision: 28,
                shape: PawBrushShapeField.circle(hardness: .64),
                kernelKind: PawBrushKernelKind.dabDry,
                kernel: PawBrushKernelRegistry.dab,
                grainMode: PawUnifiedBrushGrainMode.canvasFixed,
                deposition: PawUnifiedBrushDepositionModel.dryMedia,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.contactMesh,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsCanvasContact: true,
                  needsDryMediaContact: true,
                  needsCanvasFixedGrain: true,
                ),
                endpoint: PawUnifiedBrushEndpointProfile(
                  capRoundness: .46,
                  capRoughness: .25,
                  startTaperBrushLengths: .25,
                  endTaperBrushLengths: .35,
                  minimumOpacityFactor: .65,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .72,
                  pressureToOpacity: .6,
                  speedToFlow: 0,
                  grainToMotion: .5,
                ),
              ));

  static PawUnifiedBrushProgram get _markerUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'marker',
          () => const PawUnifiedBrushProgram(
                id: 'production:marker',
                revision: 1,
                shape: PawBrushShapeField.ellipse(aspect: .22, hardness: .88),
                kernelKind: PawBrushKernelKind.dabDry,
                kernel: PawBrushKernelRegistry.dab,
                deposition: PawUnifiedBrushDepositionModel.glazeLike,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.sweptCoverage,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsSweptCoverage: true,
                  needsPreparedTip: false,
                  preparedEdgeAntialiasLogicalPixels: 0,
                ),
                endpoint: PawUnifiedBrushEndpointProfile(capRoundness: 1),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .35,
                  pressureToOpacity: .4,
                ),
              ));

  static PawUnifiedBrushProgram get _softUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'soft',
          () => const PawUnifiedBrushProgram(
                id: 'production:soft',
                revision: 5,
                shape: PawBrushShapeField.circle(hardness: .58),
                kernelKind: PawBrushKernelKind.softDensity,
                kernel: PawBrushKernelRegistry.soft,
                behavior: PawBrushBehaviorRegistry.soft,
                grainMode: PawUnifiedBrushGrainMode.none,
                deposition: PawUnifiedBrushDepositionModel.airbrushDensity,
                supportsStatefulMaterial: true,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.preparedStamp,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsPreparedTip: true,
                  needsStatefulDensity: true,
                ),
                endpoint: PawUnifiedBrushEndpointProfile(
                  startTaperBrushLengths: .6,
                  endTaperBrushLengths: .5,
                  minimumOpacityFactor: .28,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .48,
                  pressureToOpacity: .7,
                  speedToFlow: -.12,
                ),
              ));

  static PawUnifiedBrushProgram get _inkUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'ink',
          () => const PawUnifiedBrushProgram(
                id: 'production:ink',
                revision: 26,
                shape: PawBrushShapeField.ellipse(aspect: .96, hardness: .96),
                kernelKind: PawBrushKernelKind.inkCoverage,
                kernel: PawBrushKernelRegistry.ink,
                behavior: PawBrushBehaviorRegistry.ink,
                grainMode: PawUnifiedBrushGrainMode.canvasFixed,
                deposition: PawUnifiedBrushDepositionModel.buildUp,
                supportsStatefulMaterial: true,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.sweptCoverage,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsSweptCoverage: true,
                  needsCanvasContact: true,
                  needsCanvasFixedGrain: true,
                  needsTemporalContact: true,
                  needsBuildUp: true,
                ),
                endpoint: PawUnifiedBrushEndpointProfile(
                  capRoundness: .9,
                  capRoughness: .08,
                  startTaperBrushLengths: .08,
                  endTaperBrushLengths: .18,
                  minimumOpacityFactor: .42,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .85,
                  pressureToOpacity: .35,
                  speedToFlow: -.18,
                  curvatureToShape: .2,
                  grainToMotion: .35,
                ),
              ));

  static PawUnifiedBrushProgram get _furUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'fur',
          () => const PawUnifiedBrushProgram(
                id: 'production:fur',
                revision: 25,
                shape: PawBrushShapeField.proceduralBristle(
                  density: .96,
                  direction: 0,
                  length: .96,
                  variation: .38,
                  rootTipAttenuation: .94,
                  aspect: .68,
                  hardness: .48,
                ),
                kernelKind: PawBrushKernelKind.bristleFilament,
                kernel: PawBrushKernelRegistry.fur,
                behavior: PawBrushBehaviorRegistry.fur,
                grainMode: PawUnifiedBrushGrainMode.strokeFollowing,
                deposition: PawUnifiedBrushDepositionModel.buildUp,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.contactMesh,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsStreamingHairs: true,
                  needsBuildUp: true,
                ),
                endpoint: PawUnifiedBrushEndpointProfile(
                  startTaperBrushLengths: 3,
                  endTaperBrushLengths: 3,
                  minimumSizeFactor: .14,
                  minimumOpacityFactor: .8,
                  taperExponent: .8,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .62,
                  pressureToOpacity: .48,
                  speedToFlow: -.14,
                  directionToRotation: 1,
                  curvatureToShape: .18,
                  grainToMotion: .8,
                  bristleSpread: .72,
                ),
              ));

  static PawUnifiedBrushProgram get _eraserUnifiedProgram =>
      _unifiedPrograms.putIfAbsent(
          'eraser',
          () => const PawUnifiedBrushProgram(
                id: 'production:eraser',
                revision: 1,
                shape: PawBrushShapeField.circle(),
                kernelKind: PawBrushKernelKind.dabDry,
                kernel: PawBrushKernelRegistry.dab,
                deposition: PawUnifiedBrushDepositionModel.opaqueUniform,
                renderRepresentation:
                    PawUnifiedBrushRenderRepresentation.preparedStamp,
                renderPlan: PawCompiledBrushRenderPlan(
                  needsPreparedTip: true,
                  preparedEdgeAntialiasLogicalPixels: .6,
                ),
                dynamics: PawUnifiedBrushDynamicsProfile(
                  pressureToSize: .8,
                  pressureToOpacity: 0,
                ),
              ));

  static PawCompiledBrushPreset forTool(DrawingTool tool) =>
      PawBrushProgramCompiler.compileBuiltin(tool);

  static PawCompiledBrushPreset _compiledForTool(DrawingTool tool) =>
      switch (tool) {
        DrawingTool.roundBrush => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.round,
            sizeScale: 1,
            opacity: 1,
            kernelKind: PawBrushKernelKind.dabDry,
            unifiedProgram: _roundUnifiedProgram,
          ),
        DrawingTool.crayon => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.crayon,
            sizeScale: 1.68,
            opacity: .98,
            kernelKind: PawBrushKernelKind.dabDry,
            unifiedProgram: _crayonUnifiedProgram,
          ),
        DrawingTool.marker => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.marker,
            sizeScale: 1 / .94,
            opacity: .94,
            kernelKind: PawBrushKernelKind.dabDry,
            unifiedProgram: _markerUnifiedProgram,
          ),
        DrawingTool.softBrush => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.soft,
            // Full atlas coordinates now preserve the authored footprint.
            // Only compensate for the translucent shoulder, not atlas padding.
            sizeScale: 1.9,
            opacity: .75,
            kernelKind: PawBrushKernelKind.softDensity,
            unifiedProgram: _softUnifiedProgram,
          ),
        DrawingTool.inkBrush => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.ink,
            // Ink carries translucent paper breakup across its shoulder. Its
            // geometric support is wider so the alpha-weighted visible width
            // matches Round at the same user-selected size.
            sizeScale: 2,
            opacity: .94,
            kernelKind: PawBrushKernelKind.inkCoverage,
            unifiedProgram: _inkUnifiedProgram,
          ),
        DrawingTool.furBrush => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.fur,
            sizeScale: .83,
            opacity: .98,
            kernelKind: PawBrushKernelKind.bristleFilament,
            unifiedProgram: _furUnifiedProgram,
          ),
        DrawingTool.eraser => PawCompiledBrushPreset(
            definition: PawDabBrushDefinitions.eraser,
            sizeScale: 2,
            opacity: 1,
            unifiedProgram: _eraserUnifiedProgram,
          ),
      };
}
