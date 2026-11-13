part of '../../held_stroke_assist.dart';

@immutable
class PawCircleFit {
  const PawCircleFit({
    required this.center,
    required this.radius,
    required this.rmsResidual,
    required this.maximumResidual,
    required this.signedSweep,
    required this.signCoherence,
    this.medianResidual = 0,
    this.trimmedRmsResidual = 0,
    this.p90Residual = 0,
    this.angularCoverage = 0,
    this.endpointResidual = 0,
  });

  final Offset center;
  final double radius;
  final double rmsResidual;
  final double maximumResidual;
  final double signedSweep;
  final double signCoherence;
  final double medianResidual;
  final double trimmedRmsResidual;
  final double p90Residual;
  final double angularCoverage;
  final double endpointResidual;

  Map<String, Object> toJson() => <String, Object>{
        'angular_coverage': angularCoverage,
        'sign_coherence': signCoherence,
        'median_residual': medianResidual,
        'trimmed_rms': trimmedRmsResidual,
        'p90_residual': p90Residual,
        'maximum_residual': maximumResidual,
        'endpoint_residual': endpointResidual,
      };
}

@immutable
class PawEllipseFit {
  const PawEllipseFit({
    required this.center,
    required this.majorRadius,
    required this.minorRadius,
    required this.rotationRadians,
    required this.rmsRadialResidual,
    required this.maximumRadialResidual,
    required this.signedSweep,
    required this.signCoherence,
  });

  final Offset center;
  final double majorRadius;
  final double minorRadius;
  final double rotationRadians;
  final double rmsRadialResidual;
  final double maximumRadialResidual;
  final double signedSweep;
  final double signCoherence;
}
