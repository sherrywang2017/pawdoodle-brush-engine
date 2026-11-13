part of '../../streaming_dab_brush.dart';

/// Stateless material response controls evaluated from an absolute motion
/// sample. The default is deliberately identity for every response.
@immutable
class PawDabDynamicsParameters {
  const PawDabDynamicsParameters({
    this.speedReferencePixelsPerSecond = 600,
    this.slowDepositionScale = 1,
    this.fastDepositionScale = 1,
    this.pressureDepositionMinFactor = 1,
    this.speedSpacingFactor = 0,
    this.turnDepositionScale = 1,
    this.spacingJitterFactor = 0,
    this.sizeJitterFactor = 0,
    this.opacityJitterFactor = 0,
    this.chargeDecayArcFactor = 0,
    this.chargeMinimum = 1,
    this.filamentLengthDepositionScale = 0,
    this.filamentSpreadDepositionScale = 0,
    this.filamentCoverageDepositionScale = 0,
    this.filamentTurnLengthScale = 1,
    this.filamentTurnSpreadScale = 1,
  });

  final double speedReferencePixelsPerSecond;
  final double slowDepositionScale;
  final double fastDepositionScale;
  final double pressureDepositionMinFactor;
  final double speedSpacingFactor;
  final double turnDepositionScale;
  final double spacingJitterFactor;
  final double sizeJitterFactor;
  final double opacityJitterFactor;

  /// Zero disables charge. Otherwise this is brush-size multiples to minimum.
  final double chargeDecayArcFactor;
  final double chargeMinimum;
  final double filamentLengthDepositionScale;
  final double filamentSpreadDepositionScale;
  final double filamentCoverageDepositionScale;
  final double filamentTurnLengthScale;
  final double filamentTurnSpreadScale;

  double get maximumPositiveSpacingOffsetFactor =>
      spacingJitterFactor / 2 + speedSpacingFactor.abs() * .2;
  double get maximumFilamentLengthResponse => _maximumFilamentResponse(
        depositionScale: filamentLengthDepositionScale,
        turnScale: filamentTurnLengthScale,
      );
  double get maximumFilamentSpreadResponse => _maximumFilamentResponse(
        depositionScale: filamentSpreadDepositionScale,
        turnScale: filamentTurnSpreadScale,
      );

  void validate() {
    if (!_finitePositive(speedReferencePixelsPerSecond) ||
        !_finiteInRange(slowDepositionScale, 0, 4) ||
        !_finiteInRange(fastDepositionScale, 0, 4) ||
        !_finiteInRange(pressureDepositionMinFactor, 0, 1) ||
        !_finiteInRange(speedSpacingFactor, -1, 1) ||
        !_finiteInRange(turnDepositionScale, 0, 4) ||
        !_finiteInRange(spacingJitterFactor, 0, .45) ||
        !_finiteInRange(sizeJitterFactor, 0, .8) ||
        !_finiteInRange(opacityJitterFactor, 0, .95) ||
        !_finiteInRange(chargeDecayArcFactor, 0, 10000) ||
        !_finiteInRange(chargeMinimum, 0, 1) ||
        !_finiteInRange(filamentLengthDepositionScale, -2, 2) ||
        !_finiteInRange(filamentSpreadDepositionScale, -2, 2) ||
        !_finiteInRange(filamentCoverageDepositionScale, -2, 2) ||
        !_finiteInRange(filamentTurnLengthScale, 0, 2) ||
        !_finiteInRange(filamentTurnSpreadScale, 0, 2)) {
      throw ArgumentError('Invalid dab dynamics parameters.');
    }
  }

  /// A bounded absolute-index perturbation. Adjacent emitted arcs remain
  /// monotonic because the factor is limited below one spacing interval.
  double arcForDab({
    required int index,
    required double spacing,
    required int hash,
    double speedPixelsPerSecond = 0,
  }) =>
      math.max(
        0.0,
        (index +
                (PawDabResource._unitWindow(hash, 31) - .5) *
                    spacingJitterFactor +
                speedSpacingFactor *
                    (speedPixelsPerSecond / speedReferencePixelsPerSecond)
                        .clamp(0.0, 1.0) *
                    .2) *
            spacing,
      );
}

@immutable
class _PawDabDynamicsResponse {
  const _PawDabDynamicsResponse({
    required this.deposition,
    required this.size,
    required this.opacity,
    required this.filamentLength,
    required this.filamentSpread,
    required this.filamentCoverage,
  });

  final double deposition;
  final double size;
  final double opacity;
  final double filamentLength;
  final double filamentSpread;
  final double filamentCoverage;
}

_PawDabDynamicsResponse _evaluateDynamics({
  required PawDabDynamicsParameters dynamics,
  required PawStreamingMotionSample motion,
  required double brushSize,
  required int hash,
}) {
  final speedFraction =
      (motion.speedPixelsPerSecond / dynamics.speedReferencePixelsPerSecond)
          .clamp(0.0, 1.0);
  final speedDeposition = dynamics.slowDepositionScale +
      (dynamics.fastDepositionScale - dynamics.slowDepositionScale) *
          speedFraction;
  final pressureDeposition = dynamics.pressureDepositionMinFactor +
      (1 - dynamics.pressureDepositionMinFactor) * motion.pressure;
  // Curvature is 1/px; brush-size normalization makes this response stable
  // across preset widths while preserving the signed raw sample for later use.
  final turn = (motion.signedCurvature.abs() * brushSize).clamp(0.0, 1.0);
  final turnDeposition = 1 + (dynamics.turnDepositionScale - 1) * turn;
  final charge = dynamics.chargeDecayArcFactor == 0
      ? 1.0
      : dynamics.chargeMinimum +
          (1 - dynamics.chargeMinimum) *
              math.exp(-motion.absoluteArc /
                  math.max(.0001, brushSize * dynamics.chargeDecayArcFactor));
  final unit = PawDabResource._unitWindow(hash, 37) * 2 - 1;
  final size = 1 + unit * dynamics.sizeJitterFactor / 2;
  final opacity = 1 + unit * dynamics.opacityJitterFactor / 2;
  final deposition =
      (speedDeposition * pressureDeposition * turnDeposition * charge)
          .clamp(0.0, 4.0);
  return _PawDabDynamicsResponse(
    deposition: deposition,
    size: size.clamp(.01, 2.0),
    opacity: opacity.clamp(.01, 2.0),
    filamentLength:
        (1 + dynamics.filamentLengthDepositionScale * (deposition - 1)) *
            (1 + (dynamics.filamentTurnLengthScale - 1) * turn),
    filamentSpread:
        (1 + dynamics.filamentSpreadDepositionScale * (deposition - 1)) *
            (1 + (dynamics.filamentTurnSpreadScale - 1) * turn),
    filamentCoverage:
        1 + dynamics.filamentCoverageDepositionScale * (deposition - 1),
  );
}
