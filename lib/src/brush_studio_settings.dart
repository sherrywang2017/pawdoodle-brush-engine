import 'dart:math' as math;

import 'brush_preset.dart';
import 'brush_shape_field.dart';
import 'streaming_dab_brush.dart'
    show PawDabWetMediaParameters, PawDabGrainStructure;

enum PawStudioTip { round, flat, fur }

enum PawStudioGrain { smooth, paper, fibers }

/// A small editor projection of V2. Only V2 is persisted as parameter truth.
class PawStudioSettings {
  const PawStudioSettings({
    this.tip = PawStudioTip.round,
    this.grain = PawStudioGrain.paper,
    this.size = 1,
    this.tipAspect = .32,
    double? tipRoundness,
    double? startTaper,
    double? endTaper,
    this.endpointOpacity = .8,
    this.wetMedia = const PawDabWetMediaParameters(),
    this.flow = .8,
    this.softness = .25,
    this.spacing = .14,
    this.texture = .3,
    this.textureScale = 1,
    this.pressure = .45,
    this.scatter = 0,
    this.density = .65,
    this.turn = .65,
  }) : tipRoundness = tipRoundness ?? (tip == PawStudioTip.fur ? .14 : .35),
       startTaper = startTaper ?? (tip == PawStudioTip.fur ? 3 : .6),
       endTaper = endTaper ?? (tip == PawStudioTip.fur ? 3 : .9);

  final PawStudioTip tip;
  final PawStudioGrain grain;
  final PawDabWetMediaParameters wetMedia;
  bool get isWet => wetMedia.enabled;
  bool get supportsScatter =>
      !isWet &&
      tip != PawStudioTip.fur &&
      (grain == PawStudioGrain.smooth || texture == 0);
  bool get supportsSpacing =>
      tip == PawStudioTip.fur || (supportsScatter && scatter > 0);

  static const parameterHelp = <String, String>{
    'Tip size':
        'Width at the endpoint: 0% is pointed, 100% is full width. Round joins the tip tangentially; Flat keeps a straight cut. Start and End taper set the transition lengths and opening angle.',
    'Start taper':
        'Length of the pointed-to-full-width transition at the start, in brush widths. 0 removes the start taper.',
    'End taper':
        'Length of the full-width-to-pointed transition at the end, in brush widths. 0 removes the end taper.',
    'Dilution':
        'Adds water to the pigment. Higher values make a lighter wash while keeping the paper texture.',
    'Bleed':
        'Controls how far wet pigment spreads into nearby paper fibers. It does not change the selected tip size.',
    'Size': 'Scales the canvas brush size from 0.5x to 2x. Start at 1x.',
    'Tip aspect':
        'Depth relative to width for Flat taps and scattered contacts. It stays straight at every aspect. For continuous strokes, use Tip size and taper lengths to set the endpoint width and opening angle.',
    'Paint flow':
        'More flow deposits more pigment. Start around 70-85%; lower it for lighter layers.',
    'Soft edges':
        '0% gives a firm edge; higher values make a softer, more transparent shoulder. Try 0-20% for Flat and 15-40% for soft round brushes.',
    'Spacing':
        'Distance between scattered contacts or hair roots, relative to brush size. Fur displays core-root spacing (6% by default); guard roots use twice that distance. Lower values make them denser. Continuous unscattered strokes do not use stamp spacing, so this control is disabled for them.',
    'Texture strength':
        'How strongly the texture breaks up the pigment. 0% removes it; try 10-35% before increasing. Disabled for Smooth.',
    'Texture size':
        'Scales the texture features. Below 1x gives finer texture, above 1x gives larger marks. It does not change the brush width.',
    'Pressure response':
        'Higher values make lighter pressure thinner and paler. A pressure-capable pen is needed to vary it while drawing; a finger uses neutral pressure. Try 0% for consistent-width lines.',
    'Scatter':
        'Moves individual smooth Round/Flat contacts sideways. 0% draws a continuous stroke. Textured contact and Fur do not support this control; use Hair density for Fur.',
    'Hair density':
        'More hairs make a fuller bundle and cost more drawing work. Try 50-70%, then adjust Paint flow.',
    'Follow turns':
        'For Fur: higher values let hairs follow changes in direction more readily; lower values retain more of their previous direction.',
  };
  final double size,
      tipRoundness,
      startTaper,
      endTaper,
      endpointOpacity,
      tipAspect,
      flow,
      softness,
      spacing,
      texture,
      textureScale,
      pressure,
      scatter,
      density,
      turn;

  factory PawStudioSettings.fromPreset(PawUserBrushPresetV2 p) =>
      PawStudioSettings(
        tip: p.bristleDensity > 0
            ? PawStudioTip.fur
            : p.shapeKind == PawBrushShapeKind.ellipse
            ? PawStudioTip.flat
            : PawStudioTip.round,
        grain: p.wetMedia.enabled
            ? PawStudioGrain.paper
            : p.grainMode == PawUnifiedBrushGrainMode.none
            ? PawStudioGrain.smooth
            : p.grainMode == PawUnifiedBrushGrainMode.strokeFollowing
            ? PawStudioGrain.fibers
            : PawStudioGrain.paper,
        size: p.sizeScale,
        tipRoundness: p.minimumEndpointSize,
        startTaper: p.startTaperBrushLengths,
        endTaper: p.endTaperBrushLengths,
        endpointOpacity: p.minimumEndpointOpacity,
        wetMedia: p.wetMedia,
        tipAspect: p.shapeKind == PawBrushShapeKind.ellipse ? p.tipAspect : .32,
        flow: p.flow,
        softness: 1 - p.tipHardness,
        spacing: p.spacing,
        texture: p.grainStrength,
        textureScale: p.grainScale,
        pressure: p.pressureToSize,
        scatter: p.scatter,
        density: p.bristleDensity > 0 ? p.bristleDensity : .65,
        turn: p.bristleTurnCompliance,
      );

  PawStudioSettings copyWith({
    PawStudioTip? tip,
    PawStudioGrain? grain,
    double? size,
    double? tipAspect,
    double? tipRoundness,
    double? startTaper,
    double? endTaper,
    PawDabWetMediaParameters? wetMedia,
    double? flow,
    double? softness,
    double? spacing,
    double? texture,
    double? textureScale,
    double? pressure,
    double? scatter,
    double? density,
    double? turn,
  }) => PawStudioSettings(
    tip: tip ?? this.tip,
    grain: (wetMedia ?? this.wetMedia).enabled
        ? PawStudioGrain.paper
        : grain ?? this.grain,
    wetMedia: (tip ?? this.tip) == PawStudioTip.fur
        ? const PawDabWetMediaParameters()
        : wetMedia ?? this.wetMedia,
    size: size ?? this.size,
    tipAspect: tipAspect ?? this.tipAspect,
    tipRoundness:
        tipRoundness ??
        (tip == PawStudioTip.fur && this.tip != tip ? .14 : this.tipRoundness),
    startTaper:
        startTaper ??
        (tip == PawStudioTip.fur && this.tip != tip ? 3 : this.startTaper),
    endTaper:
        endTaper ??
        (tip == PawStudioTip.fur && this.tip != tip ? 3 : this.endTaper),
    endpointOpacity: endpointOpacity,
    flow: flow ?? this.flow,
    softness: softness ?? this.softness,
    spacing: spacing ?? this.spacing,
    texture: texture ?? this.texture,
    textureScale: textureScale ?? this.textureScale,
    pressure: pressure ?? this.pressure,
    scatter: scatter ?? this.scatter,
    density: density ?? this.density,
    turn: turn ?? this.turn,
  );

  PawUserBrushPresetV2 toPreset(String id, int revision, {int seed = 193}) {
    final fur = tip == PawStudioTip.fur;
    return PawUserBrushPresetV2(
      presetId: id,
      revision: revision,
      textureSeed: seed,
      wetMedia: fur ? const PawDabWetMediaParameters() : wetMedia,
      sizeScale: size,
      flow: flow,
      spacing: spacing,
      shapeKind: tip == PawStudioTip.flat
          ? PawBrushShapeKind.ellipse
          : PawBrushShapeKind.circle,
      tipAspect: tip == PawStudioTip.flat ? tipAspect : 1,
      tipHardness: 1 - softness,
      directionToRotation: tip == PawStudioTip.flat ? 1 : 0,
      grainStructure: isWet
          ? PawDabGrainStructure.absorbentWash
          : PawDabGrainStructure.generic,
      grainMode: fur
          ? PawUnifiedBrushGrainMode.strokeFollowing
          : isWet
          ? PawUnifiedBrushGrainMode.canvasFixed
          : switch (grain) {
              PawStudioGrain.smooth => PawUnifiedBrushGrainMode.none,
              PawStudioGrain.paper => PawUnifiedBrushGrainMode.canvasFixed,
              PawStudioGrain.fibers => PawUnifiedBrushGrainMode.strokeFollowing,
            },
      grainStrength: !fur && !isWet && grain == PawStudioGrain.smooth
          ? 0
          : texture,
      grainScale: textureScale,
      pressureToSize: pressure,
      pressureToOpacity: pressure * .3,
      pressureToFlow: pressure * .45,
      scatter: isWet ? 0 : scatter,
      bristleLayout: fur
          ? PawUserBristleLayout.boardFur
          : PawUserBristleLayout.crossing,
      bristleDensity: fur ? density : 0,
      bristleLength: 1.45,
      bristleSpread: 1.4,
      bristleWidth: .035,
      bristleShearRadians: -.6,
      bristleJitter: .24,
      bristleClump: .65,
      bristleClumpScale: .22,
      bristleBend: .2,
      bristleBendBias: .6,
      bristleWander: .015,
      bristleSoftness: softness * .06,
      bristleTurnCompliance: turn,
      bristleGrooming: .25,
      bristleGuardDensity: .7,
      bristleGuardLength: 1.3,
      startTaperBrushLengths: startTaper,
      endTaperBrushLengths: endTaper,
      minimumEndpointSize: tipRoundness,
      minimumEndpointOpacity: endpointOpacity,
    );
  }

  static PawStudioSettings random(math.Random random) => PawStudioSettings(
    tip: PawStudioTip.values[random.nextInt(3)],
    grain: PawStudioGrain.values[random.nextInt(3)],
    size: .7 + random.nextDouble() * .8,
    flow: .45 + random.nextDouble() * .5,
    softness: random.nextDouble() * .75,
    spacing: .09 + random.nextDouble() * .15,
    texture: .1 + random.nextDouble() * .6,
    textureScale: .5 + random.nextDouble() * 1.5,
    pressure: random.nextDouble() * .8,
    scatter: random.nextDouble() * .12,
    density: .3 + random.nextDouble() * .5,
    turn: random.nextDouble(),
  );
}
