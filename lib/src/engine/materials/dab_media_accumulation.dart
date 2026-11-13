part of '../../streaming_dab_brush.dart';

extension _DabMediaAccumulation on PawStreamingDabRenderCache {
  void _accumulateSoftRange({
    required PawDabEmissionSource stroke,
    required int start,
    required int endExclusive,
    required PawSoftTileDensityAccumulator accumulator,
    required PawSoftBehavior behavior,
  }) {
    for (final dab in PawStreamingDabRenderCache._emissionPlanner.planRange(
      source: stroke,
      startIndex: start,
      endExclusive: endExclusive,
    )) {
      behavior.accumulate(
        dab: dab,
        brushSize: stroke.brushSize,
        accumulator: accumulator,
        flow: stroke.opacity,
      );
    }
  }

  void _accumulateWetRange({
    required PawDabEmissionSource stroke,
    required int start,
    required int endExclusive,
    required PawWetMediaTileAccumulator accumulator,
  }) {
    final wet = stroke.definition.wetMedia;
    for (final dab in PawStreamingDabRenderCache._emissionPlanner.planRange(
      source: stroke,
      startIndex: start,
      endExclusive: endExclusive,
    )) {
      accumulator.deposit(
        dab: dab,
        flow: stroke.opacity,
        dilution: wet.dilution,
        charge: wet.charge,
        diffusion: wet.diffusionRadius,
      );
    }
  }
}
