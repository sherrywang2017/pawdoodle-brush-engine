// Presets are final rather than const because PawDabTemplateParameters makes
// defensive unmodifiable copies of its layer lists.
// ignore_for_file: prefer_const_constructors,
//   prefer_const_literals_to_create_immutables

part of '../../streaming_dab_brush.dart';

abstract final class _DabTipPainter {
  static void _paintPositiveTemplateDetails(
    Canvas canvas,
    PawDabBrushDefinition d,
    int variant,
  ) {
    _DabTipPainter._paintTemplate(canvas, d, variant);
  }

  static void _paintPreparedFullTipBase(
    Canvas canvas,
    PawDabBrushDefinition definition,
    int variant,
  ) {
    final footprint = definition.template.footprint;
    final wet = definition.wetMedia;
    if (!wet.enabled &&
        !definition.dryWax.enabled &&
        footprint.shapeExponent == 2 &&
        !footprint.rectangular &&
        footprint.outerSoftnessFactor > 0 &&
        footprint.centerCoverage > footprint.edgeCoverage) {
      // Integrate a Gaussian optical-density stamp along the stroke. The
      // authored center/edge coverage describes the accumulated stroke, so
      // dense spacing cannot turn its shoulder into a saturated hard rim.
      final centerMass =
          -math.log(1 - footprint.centerCoverage.clamp(.001, .999));
      final edgeMass = -math.log(1 - footprint.edgeCoverage.clamp(.0001, .998));
      final falloff = math.max(.2, math.log(centerMass / edgeMass));
      final extent = 1 + footprint.outerSoftnessFactor;
      final cutoff = math.exp(-falloff * extent * extent);
      final dose =
          definition.emission.spacingFactor * 2 * math.sqrt(falloff / math.pi);
      final colors = <Color>[];
      final stops = <double>[];
      for (var i = 0; i <= 64; i++) {
        final r = extent * i / 64;
        final mass =
            centerMass * (math.exp(-falloff * r * r) - cutoff) / (1 - cutoff);
        colors.add(Colors.white.withValues(alpha: 1 - math.exp(-mass * dose)));
        stops.add(i / 64);
      }
      canvas.save();
      canvas.scale(footprint.lengthFactor / 2, footprint.widthFactor / 2);
      canvas.drawCircle(
          Offset.zero,
          extent,
          Paint()
            ..shader = ui.Gradient.radial(Offset.zero, extent, colors, stops));
      canvas.restore();
      return;
    }
    final bands = wet.enabled ? 26 : 18;
    final outerScale =
        1 + footprint.outerSoftnessFactor + (wet.enabled ? wet.bleed * .14 : 0);
    final seed =
        definition.identitySalt ^ definition.revision ^ variant * 0x45d9f3b;
    for (var band = 0; band < bands; band++) {
      final unit = band / (bands - 1);
      final scale = outerScale + (.06 - outerScale) * unit;
      final materialUnit =
          ((1 - scale) / math.max(.0001, 1 - .06)).clamp(0.0, 1.0).toDouble();
      var coverage = footprint.edgeCoverage +
          (footprint.centerCoverage - footprint.edgeCoverage) *
              _smoothStep(materialUnit);
      var center = Offset.zero;
      var lengthScale = 1.0;
      var widthScale = 1.0;
      if (wet.enabled) {
        final hash = PawDabResource._hash(seed, band + 0x280);
        final retention = (.66 + wet.attack * .24 + wet.charge * .1) *
            (1 - wet.dilution * .28);
        final shoulder = 1 -
            wet.wetnessJitter *
                .16 *
                (1 - materialUnit) *
                (.35 + PawDabResource._unitWindow(hash, 5) * .65);
        coverage *= retention * shoulder;
        final edgeWeight = 1 - _smoothStep(materialUnit);
        final drift = wet.wetnessJitter * .018 * edgeWeight;
        center = Offset(
          (PawDabResource._unit(hash) - .5) * drift,
          (PawDabResource._unitWindow(hash, 11) - .5) * drift,
        );
        lengthScale += (PawDabResource._unitWindow(hash, 17) - .5) *
            wet.wetnessJitter *
            .025 *
            edgeWeight;
        widthScale += (PawDabResource._unitWindow(hash, 23) - .5) *
            wet.wetnessJitter *
            .035 *
            edgeWeight;
      } else if (definition.dryWax.enabled) {
        final hash = PawDabResource._hash(seed ^ 0x6d2b79f5, band + 0x390);
        final edgeWeight = 1 - _smoothStep(materialUnit);
        final bodyVariation = .94 + PawDabResource._unitWindow(hash, 5) * .1;
        coverage *= bodyVariation;
        center = Offset(
          (PawDabResource._unit(hash) - .5) * .012 * edgeWeight,
          (PawDabResource._unitWindow(hash, 11) - .5) * .02 * edgeWeight,
        );
        lengthScale +=
            (PawDabResource._unitWindow(hash, 17) - .5) * .028 * edgeWeight;
        widthScale +=
            (PawDabResource._unitWindow(hash, 23) - .5) * .04 * edgeWeight;
      }
      canvas.drawPath(
        footprint.rectangular
            ? (Path()
              ..addRect(Rect.fromCenter(
                  center: center,
                  width: footprint.lengthFactor * scale * lengthScale,
                  height: footprint.widthFactor * scale * widthScale)))
            : _DabTipPainter._superellipsePath(
                center: center,
                length: footprint.lengthFactor * scale * lengthScale,
                width: footprint.widthFactor * scale * widthScale,
                exponent: footprint.shapeExponent,
              ),
        _DabTipPainter._coveragePaint(
          scale > 1
              ? footprint.edgeCoverage *
                  ((outerScale - scale) / math.max(.0001, outerScale - 1))
                      .clamp(0.0, 1.0)
              : coverage,
          0,
          blendMode: BlendMode.src,
        ),
      );
    }
  }

  /// Bakes material detail that is intrinsic to a local tip into the same
  /// immutable atlas as its coverage. Runtime still submits one quad per dab;
  /// no contact rings, canvas readback, or per-dab image is created.
  ///
  /// Dry wax uses several deterministic variants so fine paper holes do not
  /// repeat as one obvious stamp pattern. Overlapping passes naturally fill
  /// different holes, matching the way crayon becomes more solid with load.
  static void _paintPreparedFullTipMaterial(
    Canvas canvas,
    PawDabBrushDefinition definition,
    int variant,
  ) {
    if (definition.wetMedia.enabled) {
      _DabTipPainter._paintPreparedWetTipMaterial(canvas, definition, variant);
    }
    if (!definition.dryWax.enabled || !definition.grain.isEnabled) return;
    final footprint = definition.template.footprint;
    final grain = definition.grain;
    final seed = definition.identitySalt ^ definition.revision ^ grain.fineSeed;
    final paint = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.clear;

    // Fine, irregular paper-tooth voids across the wax body.
    for (var index = 0; index < 82; index++) {
      final hash = PawDabResource._hash(seed ^ 0x6d2b79f5, index + 0x410);
      final baseX = (PawDabResource._unit(hash) - .5) * footprint.lengthFactor;
      final phase = variant * definition.emission.spacingFactor;
      final x = ((baseX - phase + footprint.lengthFactor * .5) %
              footprint.lengthFactor) -
          footprint.lengthFactor * .5;
      final y = (PawDabResource._unitWindow(hash, 9) - .5) *
          footprint.widthFactor *
          .94;
      final normalizedX = x / math.max(.0001, footprint.lengthFactor * .5);
      final normalizedY = y / math.max(.0001, footprint.widthFactor * .5);
      final radial = math.pow(normalizedX.abs(), footprint.shapeExponent) +
          math.pow(normalizedY.abs(), footprint.shapeExponent);
      if (radial > .88) continue;
      final radius = .012 +
          math.pow(PawDabResource._unitWindow(hash, 17), 1.7).toDouble() * .046;
      final aspect =
          grain.poreAspectRatios.sample(PawDabResource._unitWindow(hash, 25));
      final angle = (PawDabResource._unitWindow(hash, 29) - .5) *
          2 *
          grain.poreAngleJitterRadians;
      paint.color = Colors.white.withValues(
        alpha: (.62 + PawDabResource._unitWindow(hash, 5) * .36) *
            (.82 + grain.fineStrength * .18),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * (1.15 + aspect),
          height: radius * (1.15 + 1 / aspect),
        ),
        paint,
      );
      canvas.restore();
    }

    // Short directional paper-tooth scratches keep some local coherence
    // without producing mechanical full-width bands.
    final toothSeed = definition.identitySalt ^
        definition.revision ^
        grain.fineSeed ^
        0x51ed270b;
    paint.strokeCap = StrokeCap.round;
    for (var index = 0; index < 30; index++) {
      final hash = PawDabResource._hash(toothSeed, index + 0x5d0);
      final y = (PawDabResource._unit(hash) - .5) * footprint.widthFactor * .84;
      final baseX =
          (PawDabResource._unitWindow(hash, 9) - .5) * footprint.lengthFactor;
      final phase = variant * definition.emission.spacingFactor;
      final x = ((baseX - phase + footprint.lengthFactor * .5) %
              footprint.lengthFactor) -
          footprint.lengthFactor * .5;
      final halfLength = .02 + PawDabResource._unitWindow(hash, 15) * .072;
      final tilt = (PawDabResource._unitWindow(hash, 19) - .5) * .045;
      paint
        ..strokeWidth = .006 + PawDabResource._unitWindow(hash, 23) * .014
        ..color = Colors.white.withValues(
          alpha: .42 + PawDabResource._unitWindow(hash, 27) * .34,
        );
      canvas.drawLine(
        Offset(x - halfLength, y - tilt),
        Offset(x + halfLength, y + tilt),
        paint,
      );
    }

    // Sparse edge chips keep the silhouette continuous but visibly waxy.
    for (var index = 0; index < 16; index++) {
      final hash = PawDabResource._hash(seed ^ 0x27d4eb2d, index + 0x790);
      final angle = PawDabResource._unit(hash) * math.pi * 2;
      final radius = .87 + PawDabResource._unitWindow(hash, 7) * .12;
      final x = math.cos(angle) * footprint.lengthFactor * .5 * radius;
      final y = math.sin(angle) * footprint.widthFactor * .5 * radius;
      final chipLength = .01 + PawDabResource._unitWindow(hash, 15) * .026;
      final chipWidth = .004 + PawDabResource._unitWindow(hash, 21) * .011;
      paint.color = Colors.white.withValues(
        alpha: .12 + PawDabResource._unitWindow(hash, 27) * .3,
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle + math.pi / 2);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: chipLength,
          height: chipWidth,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  static void _paintPreparedWetTipMaterial(
    Canvas canvas,
    PawDabBrushDefinition definition,
    int variant,
  ) {
    final wet = definition.wetMedia;
    final footprint = definition.template.footprint;
    final seed = definition.identitySalt ^
        definition.revision ^
        variant * 0x6d2b79f5 ^
        0x3418c;
    final pigment = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.srcOver;

    // Pigment settles in broad translucent pockets. Atlas variants move the
    // pockets, avoiding a repeated dark spot at every DAB center.
    final poolCount = 5 + (wet.charge * 5).round();
    for (var index = 0; index < poolCount; index++) {
      final hash = PawDabResource._hash(seed ^ 0x51ed270b, index + 0x410);
      final x =
          (PawDabResource._unit(hash) - .5) * footprint.lengthFactor * .48;
      final y = (PawDabResource._unitWindow(hash, 9) - .5) *
          footprint.widthFactor *
          .5;
      final radius = .08 + PawDabResource._unitWindow(hash, 15) * .16;
      pigment
        ..color = Colors.white.withValues(
          alpha: (.018 + PawDabResource._unitWindow(hash, 21) * .045) *
              wet.charge *
              (1 - wet.dilution * .45),
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          .018 + wet.bleed * .028,
        );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: radius * (1.2 + PawDabResource._unitWindow(hash, 25) * .8),
          height: radius,
        ),
        pigment,
      );
    }

    // A sparse halo extends beyond the contact. This is local deposition,
    // rather than a blur of the completed canvas, so overlaps can still pool.
    for (var index = 0; index < 18; index++) {
      final hash = PawDabResource._hash(seed ^ 0x27d4eb2d, index + 0x570);
      final angle = index / 18 * math.pi * 2 +
          (PawDabResource._unit(hash) - .5) * wet.wetnessJitter * .38;
      final radial =
          .48 + wet.bleed * (.08 + PawDabResource._unitWindow(hash, 7) * .12);
      final center = Offset(
        math.cos(angle) * footprint.lengthFactor * radial,
        math.sin(angle) * footprint.widthFactor * radial,
      );
      final size = .025 + PawDabResource._unitWindow(hash, 13) * .055;
      pigment
        ..color = Colors.white.withValues(
          alpha:
              (.012 + PawDabResource._unitWindow(hash, 19) * .025) * wet.bleed,
        )
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          .018 + wet.bleed * .034,
        );
      canvas.drawCircle(center, size, pigment);
    }

    if (wet.granulation <= 0) return;
    final waterGap = Paint()
      ..isAntiAlias = true
      ..blendMode = BlendMode.clear;
    for (var index = 0; index < 34; index++) {
      final hash = PawDabResource._hash(seed ^ 0x7f4a7c15, index + 0x690);
      final x =
          (PawDabResource._unit(hash) - .5) * footprint.lengthFactor * .76;
      final y = (PawDabResource._unitWindow(hash, 9) - .5) *
          footprint.widthFactor *
          .78;
      final size = .006 + PawDabResource._unitWindow(hash, 15) * .022;
      waterGap
        ..color = Colors.white.withValues(
          alpha: wet.granulation *
              (.08 + PawDabResource._unitWindow(hash, 21) * .2),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, .006);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: size * (1.2 + PawDabResource._unitWindow(hash, 25) * 1.8),
          height: size,
        ),
        waterGap,
      );
    }
  }

  static void _paintTemplate(
    Canvas canvas,
    PawDabBrushDefinition d,
    int variant,
  ) {
    final template = d.template;
    final seed = d.identitySalt ^ variant;

    // World-space vertices own the footprint coverage. This atlas is a
    // positive-only detail channel and can never erase the destination.
    // 1. Add low-frequency positive density lobes.
    for (var layerIndex = 0;
        layerIndex < template.densityLayers.length;
        layerIndex++) {
      final layer = template.densityLayers[layerIndex];
      for (var item = 0; item < layer.count; item++) {
        final hash = PawDabResource._hash(
            seed ^ (layerIndex + 1) * 0x51ed, item + 0x120);
        final center = Offset(
          layer.alongCenterFactor +
              (PawDabResource._unit(hash) - .5) * layer.alongSpreadFactor,
          layer.normalCenterFactor +
              (PawDabResource._unitWindow(hash, 7) - .5) *
                  layer.normalSpreadFactor,
        );
        final length =
            layer.lengthFactors.sample(PawDabResource._unitWindow(hash, 13));
        final width =
            layer.widthFactors.sample(PawDabResource._unitWindow(hash, 19));
        final angle = (PawDabResource._unitWindow(hash, 25) - .5) *
            2 *
            layer.angleJitterRadians;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        canvas.drawPath(
          _DabTipPainter._superellipsePath(
            center: Offset.zero,
            length: length,
            width: width,
            exponent: 2,
          ),
          _DabTipPainter._coveragePaint(
            layer.coverage.sample(PawDabResource._unitWindow(hash, 3)),
            layer.softnessFactor,
          ),
        );
        canvas.restore();
      }
    }

    // 2. Add directional filaments with the same ribbon construction.
    for (var layerIndex = 0;
        layerIndex < template.filamentLayers.length;
        layerIndex++) {
      final layer = template.filamentLayers[layerIndex];
      for (var item = 0; item < layer.count; item++) {
        final hash = PawDabResource._hash(
            seed ^ (layerIndex + 1) * 0x7f4a, item + 0x240);
        final uniform =
            layer.count == 1 ? 0.0 : item / (layer.count - 1) * 2 - 1;
        final distributed = uniform.sign *
            math.pow(uniform.abs(), layer.normalDistributionExponent);
        final edge = distributed.abs().toDouble();
        final proposedNormal = layer.normalCenterFactor +
            distributed * layer.normalSpreadFactor / 2 +
            (PawDabResource._unit(hash) - .5) * layer.normalJitterFactor;
        final along = layer.alongCenterFactor +
            (PawDabResource._unitWindow(hash, 6) - .5) *
                layer.alongSpreadFactor;
        final nominalLength = layer.lengthCenterFactor +
            (layer.lengthEdgeFactor - layer.lengthCenterFactor) * edge;
        final length = math.max(
          .0001,
          nominalLength +
              (PawDabResource._unitWindow(hash, 12) - .5) *
                  layer.lengthJitterFactor,
        );
        final bend = (layer.bendCenterFactor +
                (layer.bendEdgeFactor - layer.bendCenterFactor) * edge) *
            (PawDabResource._unitWindow(hash, 18) - .5) *
            2;
        final sweep = (layer.sweepCenterFactor +
                (layer.sweepEdgeFactor - layer.sweepCenterFactor) * edge) *
            (PawDabResource._unitWindow(hash, 21) - .5) *
            2;
        final width =
            layer.widthFactors.sample(PawDabResource._unitWindow(hash, 23));
        final coverage = (layer.coverageCenter +
                (layer.coverageEdge - layer.coverageCenter) * edge +
                (PawDabResource._unitWindow(hash, 29) - .5) *
                    layer.coverageJitter)
            .clamp(0.0, 1.0);
        // Each cached bristle crosses the local centerline at a stable bias.
        // Small jitter softens the bundle without falling back to parallel
        // tangent lanes or unrelated random fibers.
        final angle = layer.crossingAngleRadians +
            (PawDabResource._unitWindow(hash, 3) - .5) *
                2 *
                layer.angleJitterRadians;
        final crossingReach = math.max(
          0.0,
          length * .5 * math.sin(angle).abs() - width,
        );
        final normal =
            proposedNormal.clamp(-crossingReach, crossingReach).toDouble();
        canvas.save();
        canvas.translate(along, normal);
        canvas.rotate(angle);
        canvas.drawPath(
          _DabTipPainter._filamentPath(
            length: length,
            width: width,
            bend: bend,
            sweep: sweep,
            rootTaper: layer.rootTaper,
            tipTaper: layer.tipTaper,
          ),
          _DabTipPainter._coveragePaint(coverage, layer.softnessFactor),
        );
        canvas.restore();
      }
    }

    // 3. Negative void parameters feed the shared canvas texture tile. They are
    // intentionally not applied to this positive-detail atlas, because a
    // separate dstOut stamp could erase already-painted canvas content.
  }

  static Paint _coveragePaint(
    double coverage,
    double softness, {
    BlendMode blendMode = BlendMode.srcOver,
  }) {
    final paint = Paint()
      ..isAntiAlias = true
      ..blendMode = blendMode
      ..color = Colors.white.withValues(alpha: coverage.clamp(0.0, 1.0));
    if (softness > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, softness);
    }
    return paint;
  }

  static Path _superellipsePath({
    required Offset center,
    required double length,
    required double width,
    required double exponent,
  }) {
    const segments = 48;
    final path = Path();
    for (var index = 0; index <= segments; index++) {
      final angle = index / segments * math.pi * 2;
      final cosValue = math.cos(angle);
      final sinValue = math.sin(angle);
      final x =
          cosValue.sign * math.pow(cosValue.abs(), 2 / exponent) * length / 2;
      final y =
          sinValue.sign * math.pow(sinValue.abs(), 2 / exponent) * width / 2;
      final point = center + Offset(x.toDouble(), y.toDouble());
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static Path _filamentPath({
    required double length,
    required double width,
    required double bend,
    double sweep = 0,
    double rootTaper = 0,
    required double tipTaper,
  }) {
    final halfLength = length / 2;
    final fullHalfWidth = width / 2;
    final startHalfWidth = fullHalfWidth * (1 - rootTaper);
    final endHalfWidth = fullHalfWidth * (1 - tipTaper);
    return Path()
      ..moveTo(-halfLength, -startHalfWidth)
      ..cubicTo(
        -halfLength / 3,
        bend - fullHalfWidth,
        halfLength / 3,
        bend + sweep - fullHalfWidth,
        halfLength,
        -endHalfWidth,
      )
      ..lineTo(halfLength, endHalfWidth)
      ..cubicTo(
        halfLength / 3,
        bend + sweep + fullHalfWidth,
        -halfLength / 3,
        bend + fullHalfWidth,
        -halfLength,
        startHalfWidth,
      )
      ..close();
  }
}
