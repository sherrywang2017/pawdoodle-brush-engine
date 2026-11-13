import 'dart:math' as math;

/// Renderer-local tip programs used by the existing footprint mesh.
///
/// The enum is carried by the reusable kernel output, never by a planned DAB.
enum PawBrushTipFieldKind { none, fur, ink, soft }

/// Fixed-size procedural bristle field.
///
/// It models a coherent bundle, not individual fibers: an anisotropic body
/// supplies the mass, several bounded harmonics expose strand-scale density,
/// and the longitudinal response darkens the root while fading the tip.
class PawFurTipField {
  const PawFurTipField();

  double coverageMultiplier({
    required double normalizedAlong,
    required double normalizedNormal,
    required double absoluteArc,
    required double brushSize,
    required double directionX,
    required double directionY,
    required double pressure,
    required double speedPixelsPerSecond,
    required double signedCurvature,
    required int seed,
    double grainStrength = 1,
  }) {
    final along = normalizedAlong.clamp(-1.0, 1.0).toDouble();
    final normal = normalizedNormal.clamp(-1.0, 1.0).toDouble();
    final normalDistance = normal.abs();
    final pressureUnit = pressure.clamp(0.0, 1.0).toDouble();
    final speedUnit = (speedPixelsPerSecond / 1500).clamp(0.0, 1.0).toDouble();

    // The axial shoulder stays long while normal coverage narrows quickly.
    // A non-zero lateral floor lets the outer softness ring carry a sparse,
    // feathery silhouette instead of clipping the bundle at its material edge.
    final axial = .38 + .62 * math.pow(math.max(0.0, 1 - along.abs()), .24);
    final lateral =
        .16 + .84 * math.pow(math.max(0.0, 1 - normalDistance), .58);
    final centerWeight = 1 - _smoothStep(.18, .72, normalDistance);
    final density = (.34 + .76 * centerWeight) * axial * lateral;

    final alongUnit = (along + 1) * .5;
    final root = 1 + .28 * (1 - _smoothStep(0, .3, alongUnit));
    final tipFadeStart = .57 - speedUnit * .05;
    final tip = 1 - .9 * _smoothStep(tipFadeStart, 1, alongUnit);

    // Stroke-following phase keeps neighboring DABs coherent. The direction
    // term avoids identical band phase after sharp turns without randomizing
    // individual strands or allocating a fiber list.
    final safeBrushSize = math.max(1.0, brushSize);
    final directionPhase = (directionX * .71 + directionY * .43) * math.pi;
    final seedPhase = (seed & 0xffff) * .000137;
    final phase = normal * math.pi * (12 + 8 * (1 - pressureUnit)) +
        absoluteArc / safeBrushSize * math.pi * 1.7 +
        directionPhase +
        seedPhase;
    final primary = .5 + .5 * math.sin(phase + .22 * math.sin(phase * .37));
    final secondary = .5 + .5 * math.sin(phase * 2.31 + seedPhase * .7);
    final strandDensity =
        (.18 + .58 * primary + .24 * secondary).clamp(0.0, 1.0);
    final effectiveGrain =
        ((.2 + (1 - pressureUnit) * .12 + speedUnit * .06) * grainStrength)
            .clamp(0.0, .46)
            .toDouble();
    final micro = 1 - effectiveGrain + effectiveGrain * strandDensity;

    final bend =
        (signedCurvature * safeBrushSize * normal).clamp(-.16, .16).toDouble();
    return math.max(0.0, density * root * tip * micro * (1 + bend));
  }
}

/// Procedural ink tip: a stable pigment body with pressure-sensitive edge
/// spread and small stroke-following density variation.
class PawInkTipField {
  const PawInkTipField();

  double coverageMultiplier({
    required double radial,
    required double normalizedAlong,
    required double normalizedNormal,
    required double absoluteArc,
    required double brushSize,
    required double pressure,
    required double speedPixelsPerSecond,
    required double signedCurvature,
    required int seed,
    double grainStrength = 1,
  }) {
    final radius = radial.clamp(0.0, 1.0).toDouble();
    final pressureUnit = pressure.clamp(0.0, 1.0).toDouble();
    final speedUnit = (speedPixelsPerSecond / 1500).clamp(0.0, 1.0).toDouble();
    final edgeStart = .9 - pressureUnit * .11;
    final edge = _smoothStep(edgeStart, 1, radius);
    final edgeBody = 1 - edge * (.08 + pressureUnit * .16);

    final safeBrushSize = math.max(1.0, brushSize);
    // Absolute arc plus signed normal makes the pigment phase agree where
    // neighboring DABs overlap, so deposition does not average it flat.
    final phase = absoluteArc / safeBrushSize * math.pi * 1.45 +
        normalizedNormal * math.pi * 5.3 +
        (seed & 0x7fff) * .00019;
    final pigment =
        .5 + .31 * math.sin(phase) + .19 * math.sin(phase * 2.17 + 1.1);
    final pigmentStrength =
        ((.3 + speedUnit * .08) * grainStrength).clamp(0.0, .46);
    final pigmentResponse =
        1 + pigmentStrength * (pigment.clamp(0.0, 1.0).toDouble() - .5) * 1.15;
    final cornerPool =
        1 + (signedCurvature.abs() * safeBrushSize).clamp(0.0, 1.0) * .12;
    return math.max(0.0, edgeBody * pigmentResponse * cornerPool);
  }
}

/// Polynomial soft-airbrush density. This is sampled directly by the tile
/// raster path; it is neither a blur nor a full-canvas intermediate buffer.
class PawSoftTipField {
  const PawSoftTipField();

  double coverageMultiplier({
    required double radial,
    required double pressure,
    required double accumulatedDensity,
  }) {
    final radius = radial.clamp(0.0, 1.0).toDouble();
    final pressureUnit = pressure.clamp(0.0, 1.0).toDouble();
    final remaining = math.max(0.0, 1 - radius);
    final longTail = .16 + .84 * math.pow(remaining, 1.55);
    final core =
        1 + (1 - _smoothStep(0, .32, radius)) * (.28 + pressureUnit * .16);
    final saturation = (1 - math.exp(-math.max(0.0, accumulatedDensity) * .42));
    return longTail * core * (1 + saturation * .16);
  }
}

double _smoothStep(num lower, num upper, num value) {
  final range = upper - lower;
  if (range.abs() <= .000001) return value < lower ? 0 : 1;
  final unit = ((value - lower) / range).clamp(0.0, 1.0).toDouble();
  return unit * unit * (3 - 2 * unit);
}
