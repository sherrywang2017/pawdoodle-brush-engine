part of '../../streaming_dab_brush.dart';

double _smoothStep(double unit) => unit * unit * (3 - 2 * unit);

bool _finitePositive(double value) => value.isFinite && value > 0;
bool _finiteNonNegative(double value) => value.isFinite && value >= 0;
bool _finiteInRange(double value, double minimum, double maximum) =>
    value.isFinite && value >= minimum && value <= maximum;

double _maximumFilamentResponse({
  required double depositionScale,
  required double turnScale,
}) {
  var maximum = 0.0;
  for (final deposition in const <double>[0, 4]) {
    for (final turn in const <double>[0, 1]) {
      final response = (1 + depositionScale * (deposition - 1)) *
          (1 + (turnScale - 1) * turn);
      maximum = math.max(maximum, response.clamp(.05, 2.0));
    }
  }
  return maximum;
}
