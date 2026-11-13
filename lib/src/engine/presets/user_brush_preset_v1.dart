part of '../../brush_preset.dart';

/// Stable, user-facing Brush Preset Schema v1.
///
/// This is deliberately smaller than [PawDabBrushDefinition]. Internal cache,
/// modeler, batching, curvature, and filament controls are not serialized.
/// [presetId] and [revision] identify compiled resources: changing any field
/// requires incrementing revision, and one id/revision pair must never name two
/// different payloads in the same catalog or import store.
@immutable
class PawUserBrushPresetV1 {
  const PawUserBrushPresetV1({
    required this.presetId,
    required this.revision,
    required this.textureSeed,
    this.sizeScale = 1,
    this.opacity = 1,
    this.spacing = .14,
    this.flow = 1,
    this.tipAspect = .42,
    this.tipHardness = 1,
    this.edgeRoughness = 0,
    this.grainCoordinate = PawDabGrainCoordinate.canvasFixed,
    this.grainStrength = 0,
    this.grainScale = 1,
    this.pressureSizeMinimum = 1,
    this.pressureFlowMinimum = 1,
    this.speedFlow = 0,
    this.sizeJitter = 0,
    this.opacityJitter = 0,
    this.scatter = 0,
  });

  static const int currentSchemaVersion = 1;
  static const String engineName = 'dab_v1';

  final String presetId;
  final int revision;
  final int textureSeed;
  final double sizeScale;
  final double opacity;
  final double spacing;
  final double flow;
  final double tipAspect;
  final double tipHardness;
  final double edgeRoughness;
  final PawDabGrainCoordinate grainCoordinate;
  final double grainStrength;
  final double grainScale;
  final double pressureSizeMinimum;
  final double pressureFlowMinimum;

  /// -1 gives less flow at speed; 0 is neutral; 1 gives more flow at speed.
  final double speedFlow;
  final double sizeJitter;
  final double opacityJitter;
  final double scatter;

  Map<String, Object> toJson() => <String, Object>{
        'schemaVersion': currentSchemaVersion,
        'engine': engineName,
        'presetId': presetId,
        'revision': revision,
        'textureSeed': textureSeed,
        'stroke': <String, Object>{
          'sizeScale': sizeScale,
          'opacity': opacity,
          'spacing': spacing,
          'flow': flow,
        },
        'tip': <String, Object>{
          'aspect': tipAspect,
          'hardness': tipHardness,
          'edgeRoughness': edgeRoughness,
        },
        'grain': <String, Object>{
          'coordinate': grainCoordinate.name,
          'strength': grainStrength,
          'scale': grainScale,
        },
        'dynamics': <String, Object>{
          'pressureSizeMinimum': pressureSizeMinimum,
          'pressureFlowMinimum': pressureFlowMinimum,
          'speedFlow': speedFlow,
          'sizeJitter': sizeJitter,
          'opacityJitter': opacityJitter,
          'scatter': scatter,
        },
      };

  factory PawUserBrushPresetV1.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const <String>{
      'schemaVersion',
      'engine',
      'presetId',
      'revision',
      'textureSeed',
      'stroke',
      'tip',
      'grain',
      'dynamics',
    });
    if (json['schemaVersion'] != currentSchemaVersion) {
      throw const FormatException('Unsupported brush preset schema.');
    }
    if (json['engine'] != engineName) {
      throw const FormatException('Unsupported brush preset engine.');
    }
    final stroke = _object(json, 'stroke');
    final tip = _object(json, 'tip');
    final grain = _object(json, 'grain');
    final dynamics = _object(json, 'dynamics');
    _expectKeys(
        stroke, const <String>{'sizeScale', 'opacity', 'spacing', 'flow'});
    _expectKeys(tip, const <String>{'aspect', 'hardness', 'edgeRoughness'});
    _expectKeys(grain, const <String>{'coordinate', 'strength', 'scale'});
    _expectKeys(dynamics, const <String>{
      'pressureSizeMinimum',
      'pressureFlowMinimum',
      'speedFlow',
      'sizeJitter',
      'opacityJitter',
      'scatter',
    });
    final coordinateName = _string(grain, 'coordinate');
    PawDabGrainCoordinate? coordinate;
    for (final value in PawDabGrainCoordinate.values) {
      if (value.name == coordinateName) coordinate = value;
    }
    if (coordinate == null) {
      throw const FormatException('Invalid grain coordinate.');
    }
    final result = PawUserBrushPresetV1(
      presetId: _string(json, 'presetId'),
      revision: _integer(json, 'revision'),
      textureSeed: _integer(json, 'textureSeed'),
      sizeScale: _number(stroke, 'sizeScale'),
      opacity: _number(stroke, 'opacity'),
      spacing: _number(stroke, 'spacing'),
      flow: _number(stroke, 'flow'),
      tipAspect: _number(tip, 'aspect'),
      tipHardness: _number(tip, 'hardness'),
      edgeRoughness: _number(tip, 'edgeRoughness'),
      grainCoordinate: coordinate,
      grainStrength: _number(grain, 'strength'),
      grainScale: _number(grain, 'scale'),
      pressureSizeMinimum: _number(dynamics, 'pressureSizeMinimum'),
      pressureFlowMinimum: _number(dynamics, 'pressureFlowMinimum'),
      speedFlow: _number(dynamics, 'speedFlow'),
      sizeJitter: _number(dynamics, 'sizeJitter'),
      opacityJitter: _number(dynamics, 'opacityJitter'),
      scatter: _number(dynamics, 'scatter'),
    );
    PawBrushPresetCompiler.validate(result);
    return result;
  }
}
