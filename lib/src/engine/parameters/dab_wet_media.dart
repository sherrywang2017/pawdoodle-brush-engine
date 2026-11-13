part of '../../streaming_dab_brush.dart';

/// Canvas-contact wet deposition.
///
/// Dilution and charge control pigment load, attack keeps the center seated,
/// while bleed and granulation respond to the document-owned paper bands.
/// This is an absorbent-paper model, not destination-color transport: it can
/// produce an Apple Notes-like wet edge without pretending to simulate a
/// complete watercolor fluid solver.
@immutable
class PawDabWetMediaParameters {
  const PawDabWetMediaParameters({
    this.enabled = false,
    this.dilution = 0,
    this.charge = 1,
    this.attack = 1,
    this.bleed = 0,
    this.granulation = 0,
    this.wetnessJitter = 0,
    this.diffusionRadius = 0,
    this.edgeFeather = 0,
    this.depositionOpticalGain = 1,
    this.settlingDuration = Duration.zero,
    this.localOverlapNormalization = 0,
  });

  final bool enabled;
  final double dilution;
  final double charge;
  final double attack;
  final double bleed;
  final double granulation;
  final double wetnessJitter;
  final double diffusionRadius;
  final double edgeFeather;
  final double depositionOpticalGain;
  final Duration settlingDuration;
  final double localOverlapNormalization;

  /// Edit the exposed wash controls without dropping other authored physics.
  PawDabWetMediaParameters copyWith({double? dilution, double? bleed}) =>
      PawDabWetMediaParameters(
        enabled: enabled,
        dilution: dilution ?? this.dilution,
        charge: charge,
        attack: attack,
        bleed: bleed ?? this.bleed,
        granulation: granulation,
        wetnessJitter: wetnessJitter,
        diffusionRadius: diffusionRadius,
        edgeFeather: edgeFeather,
        depositionOpticalGain: depositionOpticalGain,
        settlingDuration: settlingDuration,
        localOverlapNormalization: localOverlapNormalization,
      );

  double opticalCoverageResponse(double coverage) {
    final value = coverage.clamp(0.0, 1.0).toDouble();
    if (!enabled || depositionOpticalGain == 1 || value == 0 || value == 1) {
      return value;
    }
    return (1 - math.pow(1 - value, depositionOpticalGain))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double contactCoverage({
    required PawPaperHeightSample paper,
    required PawPaperDefinition definition,
    required double radial,
    required double pressure,
    double tilePigment = 0,
    double tileWetness = 0,
  }) {
    if (!enabled) return 1;
    final edge = _smoothStep(
      ((radial.clamp(0.0, 1.0) - .38) / .62).clamp(0.0, 1.0),
    );
    final fiberHeight = paper.weightedHeight(
      definition: definition,
      coarseResponseWeight: .08,
      mediumResponseWeight: .72,
      fineResponseWeight: 1,
    );
    final valley = 1 - fiberHeight;
    final capillaryHeight = paper.weightedHeight(
      definition: definition,
      coarseResponseWeight: .48,
      mediumResponseWeight: .46,
      fineResponseWeight: .06,
    );
    final pigmentLoad = (.76 + charge * .24) * (1 - dilution * .26);
    final seatedCore = attack + (1 - attack) * (1 - edge * .54);
    final granularRetention =
        1 - granulation * (.18 + fiberHeight * .62) * (.55 + edge * .45);
    // Low/medium paper bands make a slowly varying wet shoulder. Fine tooth
    // remains granulation; it must not turn the outline into a periodic wave.
    final wetness = tileWetness.clamp(0.0, 1.0);
    final capillaryCloud = 1 + bleed * edge * ((.5 - capillaryHeight) * .68);
    final capillaryEdge =
        (1 - bleed * edge * (.2 + fiberHeight * .5)) * capillaryCloud;
    final pressureSeat = .82 + pressure.clamp(0.0, 1.0) * .18;
    // Stateful tiles transport water/pigment support; they are not an alpha
    // feedback multiplier. Previously both stored pigment and water made the
    // center darker, so a slow trace or corner revisit formed periodic pools.
    // Existing water now only dilutes the contact, with a slightly stronger
    // effect at the absorbent shoulder.
    final moistureDilution = 1 - wetness * (.025 + edge * .075);
    return (pigmentLoad *
            seatedCore *
            granularRetention *
            capillaryEdge *
            pressureSeat *
            moistureDilution *
            (.92 + valley * wetnessJitter * .2))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void validate() {
    if (!_finiteInRange(dilution, 0, 1) ||
        !_finiteInRange(charge, 0, 1) ||
        !_finiteInRange(attack, 0, 1) ||
        !_finiteInRange(bleed, 0, 1) ||
        !_finiteInRange(granulation, 0, 1) ||
        !_finiteInRange(wetnessJitter, 0, 1) ||
        !_finiteInRange(diffusionRadius, 0, 1) ||
        !_finiteInRange(edgeFeather, 0, 1) ||
        !_finiteInRange(depositionOpticalGain, .5, 4) ||
        settlingDuration.isNegative ||
        settlingDuration.inMicroseconds > 800000 ||
        !_finiteInRange(localOverlapNormalization, 0, 1)) {
      throw ArgumentError('Invalid wet-media parameters.');
    }
  }
}
