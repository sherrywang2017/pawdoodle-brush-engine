import 'dart:math' as math;

import 'brush_raster_resource.dart';

/// Shape programs evaluated in brush-local contact coordinates.
enum PawBrushShapeKind { circle, ellipse, proceduralBristle, bitmapMask }

/// Immutable, allocation-free brush-tip shape field.
///
/// [localX] and [localY] use the normalized contact domain: the prepared
/// footprint boundary is +/-1. Bitmap data is already decoded and owned by a
/// [PawBrushRasterResource]; sampling this class never creates an image or a
/// temporary collection.
class PawBrushShapeField {
  const PawBrushShapeField.circle({
    this.hardness = 1,
  })  : kind = PawBrushShapeKind.circle,
        aspect = 1,
        density = 1,
        direction = 0,
        length = 1,
        variation = 0,
        rootTipAttenuation = 0,
        bitmap = null;

  const PawBrushShapeField.ellipse({
    this.aspect = .72,
    this.hardness = 1,
  })  : kind = PawBrushShapeKind.ellipse,
        density = 1,
        direction = 0,
        length = 1,
        variation = 0,
        rootTipAttenuation = 0,
        bitmap = null;

  const PawBrushShapeField.proceduralBristle({
    this.density = .82,
    this.direction = 0,
    this.length = 1,
    this.variation = .48,
    this.rootTipAttenuation = .82,
    this.aspect = .58,
    this.hardness = .88,
  })  : kind = PawBrushShapeKind.proceduralBristle,
        bitmap = null;

  const PawBrushShapeField.bitmapMask({
    required PawBrushRasterResource resource,
    this.hardness = 1,
  })  : kind = PawBrushShapeKind.bitmapMask,
        bitmap = resource,
        aspect = 1,
        density = 1,
        direction = 0,
        length = 1,
        variation = 0,
        rootTipAttenuation = 0;

  final PawBrushShapeKind kind;
  final double aspect;
  final double hardness;

  /// Aggregate bristle parameters. They describe a field, never a fiber list.
  final double density;
  final double direction;
  final double length;
  final double variation;
  final double rootTipAttenuation;
  final PawBrushRasterResource? bitmap;

  /// Returns contact coverage without allocating on the sampling path.
  double coverage(
    double localX,
    double localY,
    double rotation,
    double pressure,
  ) {
    final angle = rotation + direction;
    var x = localX;
    var y = localY;
    if (angle.abs() > .000001) {
      final cosine = math.cos(angle);
      final sine = math.sin(angle);
      x = localX * cosine + localY * sine;
      y = -localX * sine + localY * cosine;
    }
    final pressureUnit = pressure.clamp(0.0, 1.0).toDouble();
    return switch (kind) {
      PawBrushShapeKind.circle => _compactShape(
          math.sqrt(x * x + y * y),
          hardness,
        ),
      PawBrushShapeKind.ellipse => _compactShape(
          math.sqrt(x * x + y * y / math.max(.04, aspect * aspect)),
          hardness,
        ),
      PawBrushShapeKind.proceduralBristle =>
        _bristleCoverage(x, y, pressureUnit),
      PawBrushShapeKind.bitmapMask => _bitmapCoverage(x, y),
    };
  }

  double _bristleCoverage(double x, double y, double pressure) {
    final axialScale = math.max(.25, length * (.9 + pressure * .16));
    final normalScale = math.max(.12, aspect * (.86 + pressure * .2));
    final axial = x / axialScale;
    final normal = y / normalScale;
    final radial = math.sqrt(axial * axial + normal * normal);
    final body = _compactShape(radial, hardness.clamp(.35, 1).toDouble());
    if (body <= 0) return 0;

    // Stable high-frequency density is evaluated as one scalar field. The
    // harmonics form hair texture up close and average into a bundle at scale.
    final phase = normal * math.pi * (13 + 7 * (1 - pressure));
    final primary = .5 + .5 * math.sin(phase + .31 * math.sin(axial * 5.1));
    final secondary = .5 + .5 * math.sin(phase * 2.37 - axial * 7.3 + .8);
    final strand = (.16 + .59 * primary + .25 * secondary).clamp(0.0, 1.0);
    final edgeExposure = _smoothStep(.18, .82, normal.abs());
    final variationUnit =
        (variation.clamp(0.0, 1.0) * (.2 + .8 * edgeExposure)).toDouble();
    final micro = 1 - variationUnit + variationUnit * strand;

    final alongUnit = ((axial.clamp(-1.0, 1.0) + 1) * .5).toDouble();
    final root = 1 +
        density.clamp(0.0, 1.5) * .24 * (1 - _smoothStep(0, .28, alongUnit));
    // Each fixed bristle contact has tapered axial caps. Dense overlap fills
    // these caps inside a stroke, while the first and last contacts retain a
    // pointed bundle silhouette without stroke-lifecycle state in the cache.
    final rootCap = _smoothStep(.02, .36, alongUnit);
    final tipCap = 1 - _smoothStep(.56 + pressure * .04, .99, alongUnit);
    final tip = 1 -
        rootTipAttenuation.clamp(0.0, 1.0) *
            _smoothStep(.5 + pressure * .06, 1, alongUnit);
    final core = .56 + density.clamp(0.0, 1.5) * .54;
    return (body * core * micro * root * rootCap * tip * tipCap)
        .clamp(0.0, 1.35)
        .toDouble();
  }

  double _bitmapCoverage(double x, double y) {
    final resource = bitmap!;
    if (x.abs() > 1 || y.abs() > 1) return 0;
    final sample = resource.sample(
      (x + 1) * .5,
      (y + 1) * .5,
      addressMode: PawBrushRasterAddressMode.clamp,
    );
    if (hardness >= .999) return sample;
    final exponent = .45 + hardness.clamp(0.0, 1.0) * 1.55;
    return math.pow(sample, exponent).toDouble();
  }

  static double _compactShape(double radius, double hardness) {
    if (radius >= 1) return radius <= 1.000001 && hardness >= .999 ? 1 : 0;
    final boundedHardness = hardness.clamp(0.0, 1.0).toDouble();
    if (boundedHardness >= .999) return 1;
    final edgeStart = .18 + boundedHardness * .78;
    return 1 - _smoothStep(edgeStart, 1, radius);
  }
}

double _smoothStep(num lower, num upper, num value) {
  final span = upper - lower;
  if (span.abs() <= .000001) return value < lower ? 0 : 1;
  final unit = ((value - lower) / span).clamp(0.0, 1.0).toDouble();
  return unit * unit * (3 - 2 * unit);
}
