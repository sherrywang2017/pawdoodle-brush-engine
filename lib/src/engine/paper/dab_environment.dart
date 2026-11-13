part of '../../streaming_dab_brush.dart';

@immutable
class PawBrushEnvironmentSnapshot {
  const PawBrushEnvironmentSnapshot({
    required this.paper,
    this.rasterProgram,
    this.kernelKind,
    this.unifiedProgram,
  });

  factory PawBrushEnvironmentSnapshot.withRasterProgram(
    PawPreparedBrushRasterProgram rasterProgram, {
    PawBrushKernelKind? kernelKind,
  }) =>
      PawBrushEnvironmentSnapshot(
        paper: PawPaperField(
          PawPaperDefinition.defaultPaper,
          rasterProgram: rasterProgram,
        ),
        rasterProgram: rasterProgram,
        kernelKind: kernelKind,
      );

  factory PawBrushEnvironmentSnapshot.forProgram(
    PawUnifiedBrushProgram program,
  ) {
    program.validate();
    return PawBrushEnvironmentSnapshot(
      paper: PawPaperField(
        PawPaperDefinition.defaultPaper,
        rasterProgram: program.rasterProgram,
      ),
      rasterProgram: program.rasterProgram,
      kernelKind: program.kernelKind,
      unifiedProgram: program,
    );
  }

  factory PawBrushEnvironmentSnapshot.forKernel({
    required PawBrushKernelKind kernelKind,
    PawPreparedBrushRasterProgram? rasterProgram,
  }) =>
      PawBrushEnvironmentSnapshot(
        paper: PawPaperField(
          PawPaperDefinition.defaultPaper,
          rasterProgram: rasterProgram,
        ),
        rasterProgram: rasterProgram,
        kernelKind: kernelKind,
      );

  static final PawBrushEnvironmentSnapshot defaultEnvironment =
      PawBrushEnvironmentSnapshot(
    paper: PawPaperField(PawPaperDefinition.defaultPaper),
  );

  final PawPaperField paper;
  final PawPreparedBrushRasterProgram? rasterProgram;
  final PawBrushKernelKind? kernelKind;
  final PawUnifiedBrushProgram? unifiedProgram;
}
