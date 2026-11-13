part of '../../brush_preset.dart';

Map<String, Object?> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('$key must be an object.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object?> _optionalObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <String, Object?>{};
  if (value is! Map) throw FormatException('$key must be an object.');
  return value.map((key, value) => MapEntry(key.toString(), value));
}

Map<String, Object> _wetToJson(PawDabWetMediaParameters p) => {
      'enabled': p.enabled,
      'dilution': p.dilution,
      'charge': p.charge,
      'attack': p.attack,
      'bleed': p.bleed,
      'granulation': p.granulation,
      'wetnessJitter': p.wetnessJitter,
      'diffusionRadius': p.diffusionRadius,
      'edgeFeather': p.edgeFeather,
      'opticalGain': p.depositionOpticalGain,
      'settlingMilliseconds': p.settlingDuration.inMicroseconds / 1000,
      'localOverlapNormalization': p.localOverlapNormalization,
    };

PawDabWetMediaParameters _wetFromJson(Map<String, Object?> p) {
  if (p.isEmpty) return const PawDabWetMediaParameters();
  _expectKeys(p, _wetToJson(const PawDabWetMediaParameters()).keys.toSet());
  if (p['enabled'] is! bool) {
    throw const FormatException('Invalid wet enabled.');
  }
  return PawDabWetMediaParameters(
      enabled: p['enabled'] as bool,
      dilution: _number(p, 'dilution'),
      charge: _number(p, 'charge'),
      attack: _number(p, 'attack'),
      bleed: _number(p, 'bleed'),
      granulation: _number(p, 'granulation'),
      wetnessJitter: _number(p, 'wetnessJitter'),
      diffusionRadius: _number(p, 'diffusionRadius'),
      edgeFeather: _number(p, 'edgeFeather'),
      depositionOpticalGain: _number(p, 'opticalGain'),
      settlingDuration: Duration(
          microseconds: (_number(p, 'settlingMilliseconds') * 1000).round()),
      localOverlapNormalization: _number(p, 'localOverlapNormalization'));
}

Map<String, Object> _waxToJson(PawDabDryWaxParameters p) => {
      'enabled': p.enabled,
      'coveragePressureFloor': p.coveragePressureFloor,
      'coveragePressureExponent': p.coveragePressureExponent,
      'grainSuppression': p.grainSuppressionAtFullPressure,
      'thicknessPressureFloor': p.thicknessPressureFloor,
      'thicknessPressureExponent': p.thicknessPressureExponent,
      'opticalDensity': p.opticalDensity,
      'coverageOpticalGain': p.coverageOpticalGain,
      'dragStrength': p.dragStrength,
      'dragLength': p.dragLength,
      'dragWidth': p.dragWidth,
    };

PawDabDryWaxParameters _waxFromJson(Map<String, Object?> p) {
  if (p.isEmpty) return const PawDabDryWaxParameters();
  const dragKeys = {'dragStrength', 'dragLength', 'dragWidth'};
  _expectKeysAllowingOptional(
      p,
      _waxToJson(const PawDabDryWaxParameters())
          .keys
          .toSet()
          .difference(dragKeys),
      dragKeys);
  if (p['enabled'] is! bool) {
    throw const FormatException('Invalid wax enabled.');
  }
  return PawDabDryWaxParameters(
      enabled: p['enabled'] as bool,
      coveragePressureFloor: _number(p, 'coveragePressureFloor'),
      coveragePressureExponent: _number(p, 'coveragePressureExponent'),
      grainSuppressionAtFullPressure: _number(p, 'grainSuppression'),
      thicknessPressureFloor: _number(p, 'thicknessPressureFloor'),
      thicknessPressureExponent: _number(p, 'thicknessPressureExponent'),
      opticalDensity: _number(p, 'opticalDensity'),
      coverageOpticalGain: _number(p, 'coverageOpticalGain'),
      dragStrength: _numberOr(p, 'dragStrength', fallback: 0),
      dragLength: _numberOr(p, 'dragLength', fallback: .22),
      dragWidth: _numberOr(p, 'dragWidth', fallback: .025));
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

double _number(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num || !value.toDouble().isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return value.toDouble();
}

double _numberOr(
  Map<String, Object?> json,
  String key, {
  required double fallback,
}) =>
    json.containsKey(key) ? _number(json, key) : fallback;

void _expectKeys(Map<String, Object?> json, Set<String> expected) {
  if (json.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(json.keys.toSet()).isNotEmpty) {
    throw const FormatException('Invalid brush preset fields.');
  }
}

void _expectKeysAllowingOptional(
  Map<String, Object?> json,
  Set<String> required,
  Set<String> optional,
) {
  final keys = json.keys.toSet();
  if (keys.difference(required.union(optional)).isNotEmpty ||
      required.difference(keys).isNotEmpty) {
    throw const FormatException('Invalid brush preset fields.');
  }
}
