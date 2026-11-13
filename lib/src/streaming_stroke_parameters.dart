import 'package:flutter/foundation.dart';

@immutable
class PawFixedStepModelParameters {
  const PawFixedStepModelParameters({
    required this.stepRateHz,
    required this.responsePerSecond,
    required this.dampingRatio,
    required this.predictionMilliseconds,
    required this.maximumPredictionDistance,
    required this.maximumStepsPerAppend,
    required this.minimumOutputDistance,
  });

  final double stepRateHz;
  final double responsePerSecond;
  final double dampingRatio;
  final double predictionMilliseconds;
  final double maximumPredictionDistance;
  final int maximumStepsPerAppend;
  final double minimumOutputDistance;

  List<Object> get _identity => <Object>[
        stepRateHz,
        responsePerSecond,
        dampingRatio,
        predictionMilliseconds,
        maximumPredictionDistance,
        maximumStepsPerAppend,
        minimumOutputDistance,
      ];

  String get stableCacheKey => _identity.join(',');

  void validate() {
    for (final entry in <(String, double)>[
      ('stepRateHz', stepRateHz),
      ('responsePerSecond', responsePerSecond),
      ('dampingRatio', dampingRatio),
      ('predictionMilliseconds', predictionMilliseconds),
      ('maximumPredictionDistance', maximumPredictionDistance),
      ('minimumOutputDistance', minimumOutputDistance),
    ]) {
      if (!entry.$2.isFinite || entry.$2 < 0) {
        throw ArgumentError.value(entry.$2, entry.$1, 'must be finite');
      }
    }
    if (stepRateHz < 60 ||
        stepRateHz > 480 ||
        responsePerSecond < 1 ||
        responsePerSecond > 120 ||
        dampingRatio < .5 ||
        dampingRatio > 2 ||
        predictionMilliseconds > 16 ||
        maximumPredictionDistance <= 0 ||
        maximumPredictionDistance > 64 ||
        maximumStepsPerAppend < 1 ||
        maximumStepsPerAppend > 128 ||
        minimumOutputDistance <= 0 ||
        minimumOutputDistance > 4) {
      throw ArgumentError('Fixed-step model exceeds range/work limits.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PawFixedStepModelParameters &&
      stableCacheKey == other.stableCacheKey;

  @override
  int get hashCode => Object.hashAll(_identity);
}
