part of '../../streaming_dab_brush.dart';

@immutable
class PawDabCoverageVoidLayer {
  const PawDabCoverageVoidLayer({
    required this.count,
    required this.lengthFactors,
    required this.widthFactors,
    required this.strength,
    this.softnessFactor = 0,
    this.angleJitterRadians = 0,
  });

  final int count;
  final PawDabRange lengthFactors;
  final PawDabRange widthFactors;
  final PawDabRange strength;
  final double softnessFactor;
  final double angleJitterRadians;

  void validate() {
    lengthFactors.validate('void length', minimumAllowed: .0001);
    widthFactors.validate('void width', minimumAllowed: .0001);
    strength.validate('void strength', maximumAllowed: 1);
    if (count < 0 ||
        count > 48 ||
        !_finiteInRange(softnessFactor, 0, 1) ||
        !_finiteInRange(angleJitterRadians, 0, math.pi)) {
      throw ArgumentError('Invalid dab void layer.');
    }
  }
}

@immutable
class PawDabTemplateParameters {
  PawDabTemplateParameters({
    required this.footprint,
    List<PawDabDensityLayer> densityLayers = const <PawDabDensityLayer>[],
    List<PawDabFilamentLayer> filamentLayers = const <PawDabFilamentLayer>[],
    List<PawDabStreamingFilamentLayer> streamingFilamentLayers =
        const <PawDabStreamingFilamentLayer>[],
    List<PawDabPersistentLaneLayer> persistentLaneLayers =
        const <PawDabPersistentLaneLayer>[],
    List<PawDabCoverageVoidLayer> coverageVoidLayers =
        const <PawDabCoverageVoidLayer>[],
  })  : densityLayers = List<PawDabDensityLayer>.unmodifiable(densityLayers),
        filamentLayers = List<PawDabFilamentLayer>.unmodifiable(filamentLayers),
        streamingFilamentLayers =
            List<PawDabStreamingFilamentLayer>.unmodifiable(
          streamingFilamentLayers,
        ),
        persistentLaneLayers =
            List<PawDabPersistentLaneLayer>.unmodifiable(persistentLaneLayers),
        coverageVoidLayers =
            List<PawDabCoverageVoidLayer>.unmodifiable(coverageVoidLayers);

  final PawDabFootprintParameters footprint;
  final List<PawDabDensityLayer> densityLayers;
  final List<PawDabFilamentLayer> filamentLayers;
  final List<PawDabStreamingFilamentLayer> streamingFilamentLayers;
  final List<PawDabPersistentLaneLayer> persistentLaneLayers;

  /// Negative coverage repeated in the same canvas/rolling coordinate domain
  /// as [PawDabBrushDefinition.grain]. It is never stamp-local; destination-out
  /// is confined to constructing its private coverage tile, so it cannot erase
  /// previously committed paint.
  final List<PawDabCoverageVoidLayer> coverageVoidLayers;

  bool get hasPositiveDetails {
    for (final layer in densityLayers) {
      if (layer.count > 0) return true;
    }
    for (final layer in filamentLayers) {
      if (layer.count > 0) return true;
    }
    return false;
  }

  double get maximumReachX {
    var result = footprint.maximumReachX;
    for (final layer in densityLayers) {
      result = math.max(result, layer.maximumReachX);
    }
    for (final layer in filamentLayers) {
      result = math.max(result, layer.maximumReachX);
    }
    for (final layer in streamingFilamentLayers) {
      result = math.max(result, layer.maximumAlongReach);
    }
    return result;
  }

  double get maximumReachY {
    var result = footprint.maximumReachY;
    for (final layer in densityLayers) {
      result = math.max(result, layer.maximumReachY);
    }
    for (final layer in filamentLayers) {
      result = math.max(result, layer.maximumReachY);
    }
    for (final layer in streamingFilamentLayers) {
      result = math.max(result, layer.maximumNormalReach);
    }
    for (final layer in persistentLaneLayers) {
      result = math.max(result, layer.maximumNormalReach);
    }
    return result;
  }

  double get logicalExtent => 2 * math.max(maximumReachX, maximumReachY) + .16;

  void validate() {
    footprint.validate();
    if (densityLayers.length > 8 ||
        filamentLayers.length > 8 ||
        streamingFilamentLayers.length > 4 ||
        persistentLaneLayers.length > 4 ||
        coverageVoidLayers.length > 8) {
      throw ArgumentError('Too many dab template layers.');
    }
    for (final layer in densityLayers) {
      layer.validate();
    }
    for (final layer in filamentLayers) {
      layer.validate();
    }
    for (final layer in streamingFilamentLayers) {
      layer.validate();
    }
    for (final layer in persistentLaneLayers) {
      layer.validate();
    }
    for (final layer in coverageVoidLayers) {
      layer.validate();
    }
    // Free streaming hairs have no prepared-tip bitmap to undersample. Keep
    // the existing atlas limit for stamp materials; bound their longer guard
    // geometry independently so authored wisps can extend past the core.
    final maximumExtent = streamingFilamentLayers.isNotEmpty &&
            filamentLayers.isEmpty &&
            densityLayers.isEmpty &&
            persistentLaneLayers.isEmpty
        ? 16
        : 8;
    if (!logicalExtent.isFinite ||
        logicalExtent <= 0 ||
        logicalExtent > maximumExtent) {
      throw ArgumentError('Invalid dab template extent.');
    }
  }
}
