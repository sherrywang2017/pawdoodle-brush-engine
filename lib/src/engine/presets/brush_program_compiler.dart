part of '../../brush_preset.dart';

/// Single public compiler boundary for curated built-ins and persisted user
/// presets. Both products are the same [PawCompiledBrushProgram] consumed by
/// [PawStreamingDabStroke].
abstract final class PawBrushProgramCompiler {
  static PawCompiledBrushProgram compileBuiltin(DrawingTool tool) =>
      PawBrushPresetCatalog._compiledForTool(tool);

  static PawCompiledBrushProgram compileUserV1(PawUserBrushPresetV1 preset) =>
      PawBrushPresetCompiler.compile(preset);

  static PawCompiledBrushProgram compileUserV2(PawUserBrushPresetV2 preset) =>
      PawBrushPresetCompiler.compileV2(preset);
}
