part of '../../brush_preset.dart';

@immutable
class PawCompiledBrushPreset {
  const PawCompiledBrushPreset({
    required this.definition,
    required this.sizeScale,
    required this.opacity,
    this.kernelKind = PawBrushKernelKind.dabDry,
    this.rasterProgram,
    this.unifiedProgram,
  });

  final PawDabBrushDefinition definition;
  final double sizeScale;
  final double opacity;
  final PawBrushKernelKind kernelKind;
  final PawPreparedBrushRasterProgram? rasterProgram;
  final PawUnifiedBrushProgram? unifiedProgram;

  PawStreamingDabStroke createStroke({
    required PawStrokeTextureSeed seed,
    required Color color,
    required double baseSize,
  }) =>
      PawStreamingDabStroke(
        definition: definition,
        seed: seed,
        color: color,
        brushSize: baseSize * sizeScale,
        opacity: opacity,
        environment: unifiedProgram == null
            ? PawBrushEnvironmentSnapshot.forKernel(
                kernelKind: kernelKind,
                rasterProgram: rasterProgram,
              )
            : PawBrushEnvironmentSnapshot.forProgram(unifiedProgram!),
      );
}

typedef PawCompiledBrushProgram = PawCompiledBrushPreset;
