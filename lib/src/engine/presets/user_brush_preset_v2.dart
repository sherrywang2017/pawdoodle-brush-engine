part of '../../brush_preset.dart';

/// Brush Studio-ready schema. V1 remains readable and is losslessly promoted
/// for the fields it already knows; V2 adds material and bristle topology.
enum PawUserBristleLayout { mixed, crossing, boardFur }

@immutable
class PawUserBrushPresetV2 {
  const PawUserBrushPresetV2({
    required this.presetId,
    required this.revision,
    required this.textureSeed,
    this.sizeScale = 1,
    this.opacity = 1,
    this.flow = 1,
    this.spacing = .14,
    this.shapeKind = PawBrushShapeKind.circle,
    this.tipAspect = 1,
    this.tipHardness = 1,
    this.tipAngleRadians = 0,
    this.rotationJitterRadians = 0,
    this.scatter = 0,
    this.edgeRoughness = 0,
    this.startTaperBrushLengths = 0,
    this.endTaperBrushLengths = 0,
    this.minimumEndpointSize = 1,
    this.minimumEndpointOpacity = 1,
    this.endpointTaperExponent = 1,
    this.capRoundness = 1,
    this.capRoughness = 0,
    this.grainMode = PawUnifiedBrushGrainMode.none,
    this.grainStructure = PawDabGrainStructure.generic,
    this.grainStrength = 0,
    this.grainScale = 1,
    this.grainRotation = 0,
    this.grainMovement = 0,
    this.pressureToSize = 1,
    this.pressureToOpacity = 1,
    this.pressureToFlow = 1,
    this.speedToFlow = 0,
    this.speedToSpacing = 0,
    this.directionToRotation = 0,
    this.curvatureToShape = 0,
    this.grainToMotion = 0,
    this.deposition = PawUnifiedBrushDepositionModel.opaqueUniform,
    this.bristleDensity = 0,
    this.bristleSpread = 1,
    this.bristleLength = 1,
    this.bristleWidth = .04,
    this.bristleShearRadians = 0,
    this.bristleJitter = .1,
    this.bristleClump = .2,
    this.bristleWander = .04,
    this.bristleGrooming = .35,
    this.bristleTipTaper = 1,
    this.pressureBristleDensity = .5,
    this.bristleLayout = PawUserBristleLayout.mixed,
    this.bristleBend = .36,
    this.bristleGuardLength = 1,
    this.bristleGuardBend = 1,
    this.bristleGuardDensity = 1,
    this.bristleGuardSpread = 1,
    this.bristleSoftness = 0,
    this.bristleClumpScale = 1.6,
    this.bristleBendBias = 0,
    this.bristleTurnCompliance = 0,
    this.wetMedia = const PawDabWetMediaParameters(),
    this.dryWax = const PawDabDryWaxParameters(),
  });

  static const int currentSchemaVersion = 2;
  static const String engineName = 'unified_brush_v2';

  final String presetId;
  final int revision;
  final int textureSeed;
  final double sizeScale;
  final double opacity;
  final double flow;
  final double spacing;
  final PawBrushShapeKind shapeKind;
  final double tipAspect;
  final double tipHardness;
  final double tipAngleRadians;
  final double rotationJitterRadians;
  final double scatter;
  final double edgeRoughness;
  final double startTaperBrushLengths;
  final double endTaperBrushLengths;
  final double minimumEndpointSize;
  final double minimumEndpointOpacity;
  final double endpointTaperExponent;
  final double capRoundness;
  final double capRoughness;
  final PawUnifiedBrushGrainMode grainMode;
  final PawDabGrainStructure grainStructure;
  final double grainStrength;
  final double grainScale;
  final double grainRotation;
  final double grainMovement;
  final double pressureToSize;
  final double pressureToOpacity;
  final double pressureToFlow;
  final double speedToFlow;
  final double speedToSpacing;
  final double directionToRotation;
  final double curvatureToShape;
  final double grainToMotion;
  final PawUnifiedBrushDepositionModel deposition;
  final double bristleDensity;
  final double bristleSpread;
  final double bristleLength;
  final double bristleWidth;
  final double bristleShearRadians;
  final double bristleJitter;
  final double bristleClump;
  final double bristleWander;
  final double bristleGrooming;
  final double bristleTipTaper;
  final double pressureBristleDensity;
  final PawUserBristleLayout bristleLayout;
  final double bristleBend;
  final double bristleGuardLength;
  final double bristleGuardBend;
  final double bristleGuardDensity;
  final double bristleGuardSpread;
  final double bristleSoftness;
  final double bristleClumpScale;
  final double bristleBendBias;
  final double bristleTurnCompliance;
  final PawDabWetMediaParameters wetMedia;
  final PawDabDryWaxParameters dryWax;

  factory PawUserBrushPresetV2.fromV1(PawUserBrushPresetV1 preset) =>
      PawUserBrushPresetV2(
        presetId: preset.presetId,
        revision: preset.revision,
        textureSeed: preset.textureSeed,
        sizeScale: preset.sizeScale,
        opacity: preset.opacity,
        flow: preset.flow,
        spacing: preset.spacing,
        shapeKind: preset.tipAspect == 1
            ? PawBrushShapeKind.circle
            : PawBrushShapeKind.ellipse,
        tipAspect: preset.tipAspect,
        tipHardness: preset.tipHardness,
        scatter: preset.scatter,
        edgeRoughness: preset.edgeRoughness,
        grainMode: preset.grainStrength == 0
            ? PawUnifiedBrushGrainMode.none
            : preset.grainCoordinate == PawDabGrainCoordinate.canvasFixed
                ? PawUnifiedBrushGrainMode.canvasFixed
                : PawUnifiedBrushGrainMode.strokeFollowing,
        grainStrength: preset.grainStrength,
        grainScale: preset.grainScale,
        pressureToSize: 1 - preset.pressureSizeMinimum,
        pressureToOpacity: 1 - preset.pressureFlowMinimum,
        pressureToFlow: 1 - preset.pressureFlowMinimum,
        speedToFlow: preset.speedFlow,
        deposition: preset.grainStrength == 0
            ? PawUnifiedBrushDepositionModel.opaqueUniform
            : PawUnifiedBrushDepositionModel.dryMedia,
      );

  Map<String, Object> toJson() => <String, Object>{
        'schemaVersion': currentSchemaVersion,
        'engine': engineName,
        'presetId': presetId,
        'revision': revision,
        'textureSeed': textureSeed,
        'stroke': <String, Object>{
          'sizeScale': sizeScale,
          'opacity': opacity,
          'flow': flow,
          'spacing': spacing,
        },
        'tip': <String, Object>{
          'shape': shapeKind.name,
          'aspect': tipAspect,
          'hardness': tipHardness,
          'angle': tipAngleRadians,
          'rotationJitter': rotationJitterRadians,
          'scatter': scatter,
          'edgeRoughness': edgeRoughness,
        },
        'endpoint': <String, Object>{
          'startLength': startTaperBrushLengths,
          'endLength': endTaperBrushLengths,
          'minimumSize': minimumEndpointSize,
          'minimumOpacity': minimumEndpointOpacity,
          'exponent': endpointTaperExponent,
          'capRoundness': capRoundness,
          'capRoughness': capRoughness,
        },
        'grain': <String, Object>{
          'mode': grainMode.name,
          'structure': grainStructure.name,
          'strength': grainStrength,
          'scale': grainScale,
          'rotation': grainRotation,
          'movement': grainMovement,
        },
        'dynamics': <String, Object>{
          'pressureSize': pressureToSize,
          'pressureOpacity': pressureToOpacity,
          'pressureFlow': pressureToFlow,
          'speedFlow': speedToFlow,
          'speedSpacing': speedToSpacing,
          'directionRotation': directionToRotation,
          'curvatureShape': curvatureToShape,
          'grainMotion': grainToMotion,
        },
        'material': <String, Object>{
          'deposition': deposition.name,
          'wet': _wetToJson(wetMedia),
          'wax': _waxToJson(dryWax)
        },
        'bristle': <String, Object>{
          'density': bristleDensity,
          'spread': bristleSpread,
          'length': bristleLength,
          'width': bristleWidth,
          'shear': bristleShearRadians,
          'jitter': bristleJitter,
          'clump': bristleClump,
          'wander': bristleWander,
          'grooming': bristleGrooming,
          'tipTaper': bristleTipTaper,
          'pressureDensity': pressureBristleDensity,
          'layout': bristleLayout.name,
          'bend': bristleBend,
          'guardLength': bristleGuardLength,
          'guardBend': bristleGuardBend,
          'guardDensity': bristleGuardDensity,
          'guardSpread': bristleGuardSpread,
          'softness': bristleSoftness,
          'clumpScale': bristleClumpScale,
          'bendBias': bristleBendBias,
          'turnCompliance': bristleTurnCompliance,
        },
      };

  factory PawUserBrushPresetV2.fromJson(Map<String, Object?> json) {
    _expectKeysAllowingOptional(json, const <String>{
      'schemaVersion',
      'engine',
      'presetId',
      'revision',
      'textureSeed',
      'stroke',
      'tip',
      'grain',
      'dynamics',
      'material',
      'bristle',
    }, const <String>{
      'endpoint'
    });
    if (json['schemaVersion'] != currentSchemaVersion ||
        json['engine'] != engineName) {
      throw const FormatException('Unsupported brush preset schema.');
    }
    final stroke = _object(json, 'stroke');
    final tip = _object(json, 'tip');
    final endpoint = _optionalObject(json, 'endpoint');
    if (endpoint.isNotEmpty) {
      _expectKeys(endpoint, const <String>{
        'startLength',
        'endLength',
        'minimumSize',
        'minimumOpacity',
        'exponent',
        'capRoundness',
        'capRoughness',
      });
    }
    final grain = _object(json, 'grain');
    final dynamics = _object(json, 'dynamics');
    final material = _object(json, 'material');
    final bristle = _object(json, 'bristle');
    T named<T extends Enum>(
        List<T> values, Map<String, Object?> source, String key) {
      final name = _string(source, key);
      return values.firstWhere((value) => value.name == name,
          orElse: () => throw FormatException('Invalid $key.'));
    }

    final result = PawUserBrushPresetV2(
      presetId: _string(json, 'presetId'),
      revision: _integer(json, 'revision'),
      textureSeed: _integer(json, 'textureSeed'),
      sizeScale: _number(stroke, 'sizeScale'),
      opacity: _number(stroke, 'opacity'),
      flow: _number(stroke, 'flow'),
      spacing: _number(stroke, 'spacing'),
      shapeKind: named(PawBrushShapeKind.values, tip, 'shape'),
      tipAspect: _number(tip, 'aspect'),
      tipHardness: _number(tip, 'hardness'),
      tipAngleRadians: _number(tip, 'angle'),
      rotationJitterRadians: _number(tip, 'rotationJitter'),
      scatter: _number(tip, 'scatter'),
      edgeRoughness: _number(tip, 'edgeRoughness'),
      startTaperBrushLengths: _numberOr(endpoint, 'startLength', fallback: 0),
      endTaperBrushLengths: _numberOr(endpoint, 'endLength', fallback: 0),
      minimumEndpointSize: _numberOr(endpoint, 'minimumSize', fallback: 1),
      minimumEndpointOpacity:
          _numberOr(endpoint, 'minimumOpacity', fallback: 1),
      endpointTaperExponent: _numberOr(endpoint, 'exponent', fallback: 1),
      capRoundness: _numberOr(endpoint, 'capRoundness', fallback: 1),
      capRoughness: _numberOr(endpoint, 'capRoughness', fallback: 0),
      grainMode: named(PawUnifiedBrushGrainMode.values, grain, 'mode'),
      grainStructure: grain.containsKey('structure')
          ? named(PawDabGrainStructure.values, grain, 'structure')
          : PawDabGrainStructure.generic,
      grainStrength: _number(grain, 'strength'),
      grainScale: _number(grain, 'scale'),
      grainRotation: _number(grain, 'rotation'),
      grainMovement: _number(grain, 'movement'),
      pressureToSize: _number(dynamics, 'pressureSize'),
      pressureToOpacity: _number(dynamics, 'pressureOpacity'),
      pressureToFlow: _number(dynamics, 'pressureFlow'),
      speedToFlow: _number(dynamics, 'speedFlow'),
      speedToSpacing: _number(dynamics, 'speedSpacing'),
      directionToRotation: _number(dynamics, 'directionRotation'),
      curvatureToShape: _number(dynamics, 'curvatureShape'),
      grainToMotion: _number(dynamics, 'grainMotion'),
      deposition: named(
        PawUnifiedBrushDepositionModel.values,
        material,
        'deposition',
      ),
      bristleDensity: _number(bristle, 'density'),
      bristleSpread: _number(bristle, 'spread'),
      bristleLength: _number(bristle, 'length'),
      bristleWidth: _number(bristle, 'width'),
      bristleShearRadians: _number(bristle, 'shear'),
      bristleJitter: _number(bristle, 'jitter'),
      bristleClump: _number(bristle, 'clump'),
      bristleWander: _number(bristle, 'wander'),
      bristleGrooming: _number(bristle, 'grooming'),
      bristleTipTaper: _number(bristle, 'tipTaper'),
      pressureBristleDensity: _number(bristle, 'pressureDensity'),
      bristleLayout: bristle.containsKey('layout')
          ? named(PawUserBristleLayout.values, bristle, 'layout')
          : PawUserBristleLayout.mixed,
      bristleBend: _numberOr(bristle, 'bend', fallback: .36),
      bristleGuardLength: _numberOr(bristle, 'guardLength', fallback: 1),
      bristleGuardBend: _numberOr(bristle, 'guardBend', fallback: 1),
      bristleGuardDensity: _numberOr(bristle, 'guardDensity', fallback: 1),
      bristleGuardSpread: _numberOr(bristle, 'guardSpread', fallback: 1),
      bristleSoftness: _numberOr(bristle, 'softness', fallback: 0),
      bristleClumpScale: _numberOr(bristle, 'clumpScale', fallback: 1.6),
      bristleBendBias: _numberOr(bristle, 'bendBias', fallback: 0),
      bristleTurnCompliance: _numberOr(bristle, 'turnCompliance', fallback: 0),
      wetMedia: _wetFromJson(_optionalObject(material, 'wet')),
      dryWax: _waxFromJson(_optionalObject(material, 'wax')),
    );
    PawBrushPresetCompiler.validateV2(result);
    return result;
  }
}
