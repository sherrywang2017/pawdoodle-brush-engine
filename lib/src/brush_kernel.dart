import 'dart:math' as math;

import 'brush_behavior.dart';
import 'brush_tip_field.dart';

/// Runtime representation selected by a compiled brush preset.
///
/// Stateless coverage kernels consumed by the shared renderer.
enum PawBrushKernelKind {
  dabDry,
  bristleFilament,
  inkCoverage,
  softDensity,
}

/// Reusable bridge from a brush-specific behavior response to a kernel.
///
/// The render cache owns one instance and resets it for every DAB. Kernels
/// only read primitive fields, so this bridge adds no hot-path allocations.
class PawBrushKernelInput {
  double brushSize = 1;
  double widthScale = 1;
  double opacityScale = 1;
  double overlapDarkening = 0;
  double velocityThinning = 1;
  double spread = 1;
  double lengthScale = 1;
  double density = 1;
  double tipFade = 0;
  double accumulatedDensity = 0;
  double directionX = 1;
  double directionY = 0;

  void reset() {
    brushSize = 1;
    widthScale = 1;
    opacityScale = 1;
    overlapDarkening = 0;
    velocityThinning = 1;
    spread = 1;
    lengthScale = 1;
    density = 1;
    tipFade = 0;
    accumulatedDensity = 0;
    directionX = 1;
    directionY = 0;
  }
}

/// Mutable, reusable renderer response produced by a brush kernel.
class PawBrushKernelOutput {
  PawBrushTipFieldKind tipFieldKind = PawBrushTipFieldKind.none;
  double widthScale = 1;
  double lengthScale = 1;
  double opacityScale = 1;
  double coverage = 1;
  double tipMaskStrength = 0;
  double grainResponse = 0;
  double deposition = 1;
  double materialDensity = 0;
  double edgeSoftness = 0;
  double directionX = 1;
  double directionY = 0;

  /// Coverage-field coefficients consumed by the existing footprint mesh.
  double edgeCoverageScale = 1;
  double coverageExponent = 1;
  double tipFade = 0;
  double radialProfileStrength = 0;
  double centerDensity = 1;
  double middleDensity = 1;
  double directionalProfileStrength = 0;
  double rootDensity = 1;
  double tipDensity = 1;
  double tipStart = 1;

  /// Directional material-grain response. Zero keeps non-Fur
  /// kernels out of the raster sampling branch entirely.
  double directionalGrainStrength = 0;
  double directionalGrainFloor = 1;
  double directionalGrainContrast = 1;
  double directionalGrainAlongScale = 1;
  double directionalGrainNormalScale = 1;

  void reset() {
    tipFieldKind = PawBrushTipFieldKind.none;
    widthScale = 1;
    lengthScale = 1;
    opacityScale = 1;
    coverage = 1;
    tipMaskStrength = 0;
    grainResponse = 0;
    deposition = 1;
    materialDensity = 0;
    edgeSoftness = 0;
    directionX = 1;
    directionY = 0;
    edgeCoverageScale = 1;
    coverageExponent = 1;
    tipFade = 0;
    radialProfileStrength = 0;
    centerDensity = 1;
    middleDensity = 1;
    directionalProfileStrength = 0;
    rootDensity = 1;
    tipDensity = 1;
    tipStart = 1;
    directionalGrainStrength = 0;
    directionalGrainFloor = 1;
    directionalGrainContrast = 1;
    directionalGrainAlongScale = 1;
    directionalGrainNormalScale = 1;
  }

  /// Evaluates the continuous, allocation-free local coverage field.
  ///
  /// [radial] is zero at the footprint center and one at its material edge.
  /// [normalizedAlong] follows the kernel direction from -1 (root) to 1
  /// (tip). Values above one are deliberately allowed: coverage is a material
  /// multiplier and the renderer performs the final alpha clamp.
  double coverageAt({
    required double radial,
    required double normalizedAlong,
  }) {
    final boundedRadial = radial.clamp(0.0, 1.0).toDouble();
    final shapedRadial =
        math.pow(boundedRadial, coverageExponent.clamp(.05, 8.0)).toDouble();
    final legacyEdgeResponse =
        1 + (edgeCoverageScale.clamp(0.0, 2.0) - 1) * shapedRadial;
    var radialResponse = legacyEdgeResponse;
    if (radialProfileStrength > 0) {
      // Keep a stable middle shoulder between the dense core and halo. Apart
      // from producing a believable tuft/airbrush mass, this avoids visible
      // contour bands when neighboring mesh rings interpolate the field.
      final centerToMiddle = _smoothStep(0, .38, boundedRadial);
      final middleToEdge = _smoothStep(.58, 1, boundedRadial);
      final core =
          centerDensity + (middleDensity - centerDensity) * centerToMiddle;
      final profile =
          core + (edgeCoverageScale.clamp(0.0, 2.0) - core) * middleToEdge;
      radialResponse = legacyEdgeResponse +
          (profile - legacyEdgeResponse) *
              radialProfileStrength.clamp(0.0, 1.0);
    }
    var alongResponse = 1.0;
    if (directionalProfileStrength > 0) {
      final alongUnit = (normalizedAlong.clamp(-1.0, 1.0).toDouble() + 1) * .5;
      final rootWeight = 1 - _smoothStep(0, .34, alongUnit);
      final rootToMiddle = 1 + (rootDensity - 1) * rootWeight;
      final tipWeight = _smoothStep(tipStart.clamp(.2, .95), 1, alongUnit);
      final shapedTip =
          math.pow(tipWeight, math.max(.1, tipFade.clamp(.1, 4.0))).toDouble();
      final profile = rootToMiddle + (tipDensity - rootToMiddle) * shapedTip;
      alongResponse =
          1 + (profile - 1) * directionalProfileStrength.clamp(0.0, 1.0);
    } else if (tipFade > 0) {
      final tipUnit = ((normalizedAlong.clamp(-1.0, 1.0) + 1) * .5);
      alongResponse = math
          .pow(math.max(.08, 1 - tipUnit * .55), tipFade.clamp(.05, 4.0))
          .toDouble();
    }
    return math.max(0.0, coverage * radialResponse * alongResponse);
  }

  /// Converts a prepared stroke-following grain sample into a coverage
  /// multiplier without allocating renderer-local response objects.
  double directionalGrainCoverage(double sample) {
    if (directionalGrainStrength <= 0) return 1;
    final adjusted =
        (.5 + (sample.clamp(0.0, 1.0) - .5) * directionalGrainContrast)
            .clamp(0.0, 1.0)
            .toDouble();
    final material =
        directionalGrainFloor + (1 - directionalGrainFloor) * adjusted;
    return 1 - directionalGrainStrength + directionalGrainStrength * material;
  }
}

abstract class PawBrushKernel {
  const PawBrushKernel();

  void evaluateInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
  });
}

class PawDabBrushKernel extends PawBrushKernel {
  const PawDabBrushKernel();

  @override
  void evaluateInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
  }) {
    output.reset();
    _writeUnitDirection(dab.tangent.dx, dab.tangent.dy, output);
  }
}

class PawInkKernel extends PawBrushKernel {
  const PawInkKernel();

  @override
  void evaluateInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
  }) {
    final pressure = dab.pressure.clamp(0.0, 1.0);
    final speed = (dab.speedPixelsPerSecond / 1500).clamp(0.0, 1.0).toDouble();
    final thinning = input.velocityThinning.clamp(.2, 1.2);
    output
      ..reset()
      ..tipFieldKind = PawBrushTipFieldKind.ink
      ..widthScale = input.widthScale.clamp(.2, 2.1)
      // Fast movement narrows the normal axis while extending the footprint
      // slightly along motion, avoiding a row of circular stamps.
      ..lengthScale = (1 + (1 - thinning) * .58).clamp(.8, 1.5)
      // Curvature changes topology, not pigment mass. The shared ribbon owns
      // the finite-radius turn, so widening/darkening it again here created
      // the irregular corner islands seen in slow strokes.
      ..opacityScale = input.opacityScale.clamp(0.0, 2.0)
      ..coverage = 1
      ..tipMaskStrength = 1
      ..grainResponse = (.28 + speed * .025 + pressure * .035).clamp(.28, .34)
      // Absolute-arc spacing already normalizes contact count. Pressure may
      // change width and grain response, but one unit of traveled arc carries
      // one unit of pigment regardless of PointerMove cadence.
      ..deposition = 1
      // The opaque core remains pen-like while pressure opens a translucent,
      // paper-modulated wet shoulder. This is contact deposition, not blur.
      ..edgeSoftness = (.065 + pressure * .025).clamp(.065, .09)
      ..edgeCoverageScale = (.22 + pressure * .08).clamp(.22, .31)
      ..coverageExponent = 1.08 - pressure * .08
      ..radialProfileStrength = 1
      ..centerDensity = 1.04 + pressure * .06
      ..middleDensity = .97 + pressure * .04;
    _writeUnitDirection(dab.tangent.dx, dab.tangent.dy, output);
  }
}

class PawFurKernel extends PawBrushKernel {
  const PawFurKernel();

  @override
  void evaluateInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
  }) {
    final density = input.density.clamp(0.0, 1.5);
    final pressure = dab.pressure.clamp(0.0, 1.0);
    final speed = (dab.speedPixelsPerSecond / 1400).clamp(0.0, 1.0).toDouble();
    final tip = input.tipFade.clamp(0.0, 3.0).toDouble();
    output
      ..reset()
      ..tipFieldKind = PawBrushTipFieldKind.fur
      ..widthScale = (input.spread * 1.08).clamp(.5, 1.82)
      ..lengthScale = (input.lengthScale * .96).clamp(.45, 1.65)
      ..opacityScale = (input.opacityScale * 1.38).clamp(0.0, 2.0)
      // The earlier footprint was intentionally faint because line geometry
      // carried the visible mass. The current path moves that mass into one
      // field, so this material multiplier may exceed one before final clamp.
      ..coverage = 1.25 + density * .45
      ..tipMaskStrength = 1
      ..grainResponse =
          (.28 + (1 - pressure) * .08 + speed * .05).clamp(.28, .42)
      ..deposition = (1 + pressure * .26 - speed * .1).clamp(.88, 1.24)
      ..edgeSoftness =
          (.24 + (1 - density.clamp(0.0, 1.0)) * .05).clamp(.24, .3)
      ..edgeCoverageScale = (.34 + density * .12).clamp(.34, .49)
      ..coverageExponent = 1.05
      ..tipFade = input.tipFade.clamp(.05, 3.0)
      ..radialProfileStrength = 1
      ..centerDensity = .98 + pressure * .3
      ..middleDensity = .62 + density * .16
      ..directionalProfileStrength = 1
      ..rootDensity = 1.14 + pressure * .18
      ..tipDensity = (.12 + pressure * .12).clamp(.12, .25)
      ..tipStart = (.48 + speed * .08).clamp(.48, .57)
      // Lower pressure exposes more separated directional strands; speed and
      // tip fade add a restrained combed response without emitting lines.
      ..directionalGrainStrength =
          (.12 + (1 - pressure) * .06 + speed * .035 + tip * .008)
              .clamp(.12, .27)
      ..directionalGrainFloor = (.46 + pressure * .14).clamp(.46, .62)
      ..directionalGrainContrast =
          (1.28 + speed * .24 + tip * .08).clamp(1.25, 1.72)
      ..directionalGrainAlongScale = (1 - speed * .42).clamp(.56, 1.0)
      ..directionalGrainNormalScale = (.78 + pressure * .5).clamp(.78, 1.28);
    _writeUnitDirection(input.directionX, input.directionY, output);
  }
}

class PawSoftKernel extends PawBrushKernel {
  const PawSoftKernel();

  @override
  void evaluateInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
  }) {
    final density = math.max(0.0, input.accumulatedDensity);
    final saturation = 1 - math.exp(-density * .48);
    final pressure = dab.pressure.clamp(0.0, 1.0);
    output
      ..reset()
      ..tipFieldKind = PawBrushTipFieldKind.soft
      ..widthScale =
          (input.widthScale * (.72 + .48 * math.sqrt(pressure))).clamp(.62, 1.2)
      ..lengthScale = 1
      ..opacityScale = input.opacityScale.clamp(0.0, 1.5)
      ..coverage = 4.2 + saturation * .8
      ..tipMaskStrength = 1
      // Procreate-style Soft Airbrush uses a smooth shape falloff. Flow
      // accumulation supplies variation; a repeating grain tile makes loops
      // look faceted and adds work without useful detail.
      ..grainResponse = 0
      ..deposition = (.82 + saturation * .12).clamp(.82, .94)
      ..materialDensity = density
      ..edgeSoftness = .48
      ..edgeCoverageScale = .66
      ..coverageExponent = 1.3
      ..radialProfileStrength = 1
      ..centerDensity = 1.26 + saturation * .08
      ..middleDensity = .76 + saturation * .06;
    _writeUnitDirection(dab.tangent.dx, dab.tangent.dy, output);
  }
}

double _smoothStep(num lower, num upper, num value) {
  final range = upper - lower;
  if (range.abs() <= .000001) return value < lower ? 0 : 1;
  final unit = ((value - lower) / range).clamp(0.0, 1.0).toDouble();
  return unit * unit * (3 - 2 * unit);
}

abstract final class PawBrushKernelRegistry {
  static const PawDabBrushKernel dab = PawDabBrushKernel();
  static const PawInkKernel ink = PawInkKernel();
  static const PawFurKernel fur = PawFurKernel();
  static const PawSoftKernel soft = PawSoftKernel();

  static PawBrushKernel forKind(PawBrushKernelKind kind) => switch (kind) {
        PawBrushKernelKind.inkCoverage => ink,
        PawBrushKernelKind.bristleFilament => fur,
        PawBrushKernelKind.softDensity => soft,
        PawBrushKernelKind.dabDry => dab,
      };

  static PawBrushKernelKind fallbackKindForBrushId(String brushId) =>
      switch (brushId) {
        'ink-dab' => PawBrushKernelKind.inkCoverage,
        'fur-dab' => PawBrushKernelKind.bristleFilament,
        'soft-dab' => PawBrushKernelKind.softDensity,
        _ => PawBrushKernelKind.dabDry,
      };
}

void _writeUnitDirection(
  double x,
  double y,
  PawBrushKernelOutput output,
) {
  final length = math.sqrt(x * x + y * y);
  if (length <= .000001) {
    output
      ..directionX = 1
      ..directionY = 0;
    return;
  }
  output
    ..directionX = x / length
    ..directionY = y / length;
}
