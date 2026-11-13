part of '../../streaming_dab_brush.dart';

abstract final class _DabGrainTexture {
  static ui.Image _createTextureTile(PawDabBrushDefinition definition) {
    final picture = _DabGrainTexture._recordTextureTile(definition);
    try {
      return picture.toImageSync(
          PawDabResource._textureTilePixels, PawDabResource._textureTilePixels);
    } finally {
      picture.dispose();
    }
  }

  static Future<ui.Image> _createTextureTileAsync(
    PawDabBrushDefinition definition,
  ) async {
    final picture = _DabGrainTexture._recordTextureTile(definition);
    try {
      return await picture.toImage(
          PawDabResource._textureTilePixels, PawDabResource._textureTilePixels);
    } finally {
      picture.dispose();
    }
  }

  static ui.Picture _recordTextureTile(PawDabBrushDefinition definition) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    final grain = definition.grain;
    final strength = grain.coarseStrength;
    final fineStrength = grain.fineStrength;
    double tileNoise(
      double x,
      double y, {
      required int cells,
      int? verticalCells,
      required int noiseSeed,
    }) {
      final rows = verticalCells ?? cells;
      final gridX = x / PawDabResource._textureTilePixels * cells;
      final gridY = y / PawDabResource._textureTilePixels * rows;
      final x0 = gridX.floor();
      final y0 = gridY.floor();
      final x1 = (x0 + 1) % cells;
      final y1 = (y0 + 1) % rows;
      final tx = _smoothStep(gridX - x0);
      final ty = _smoothStep(gridY - y0);
      double lattice(int latticeX, int latticeY) => PawDabResource._unit(
            PawDabResource._hash(
              noiseSeed ^ latticeX * 0x45d9f3b,
              latticeY * 0x27d4eb2d,
            ),
          );
      final top = lattice(x0 % cells, y0 % rows) * (1 - tx) +
          lattice(x1, y0 % rows) * tx;
      final bottom = lattice(x0 % cells, y1) * (1 - tx) + lattice(x1, y1) * tx;
      return top * (1 - ty) + bottom * ty;
    }

    if (grain.structure == PawDabGrainStructure.waxAggregate &&
        grain.isEnabled) {
      // A crayon does not deposit a round mark with opacity noise inside it.
      // It contacts connected paper peaks. Domain-warped, differently oriented
      // height bands are thresholded into irregular wax plates. Their feature
      // size is calibrated at native 3x density so paper gaps stay pinhole-
      // sized instead of opening into marker-like white islands.

      canvas.drawColor(const Color(0x00000000), BlendMode.src);
      final coveragePoints = List<List<Offset>>.generate(
        256,
        (_) => <Offset>[],
      );
      final waxSeed =
          definition.identitySalt ^ definition.revision ^ grain.coarseSeed;
      for (var y = 0; y < PawDabResource._textureTilePixels; y++) {
        for (var x = 0; x < PawDabResource._textureTilePixels; x++) {
          final sampleX = x + .5;
          final sampleY = y + .5;
          final warpX = (tileNoise(
                    sampleX,
                    sampleY,
                    cells: 11,
                    verticalCells: 15,
                    noiseSeed: waxSeed ^ 0x17a31,
                  ) -
                  .5) *
              5;
          final warpY = (tileNoise(
                    sampleX,
                    sampleY,
                    cells: 15,
                    verticalCells: 11,
                    noiseSeed: waxSeed ^ 0x4e91,
                  ) -
                  .5) *
              5;
          final longFlake = tileNoise(
            sampleX + warpX,
            sampleY + warpY,
            cells: 31,
            verticalCells: 37,
            noiseSeed: waxSeed,
          );
          final splitFlake = tileNoise(
            sampleX +
                math.sin(sampleY /
                        PawDabResource._textureTilePixels *
                        math.pi *
                        2) *
                    6 +
                warpX,
            sampleY + warpY,
            cells: 57,
            verticalCells: 61,
            noiseSeed: waxSeed ^ 0x6d2b79f5,
          );
          final waxBody = tileNoise(
            sampleX -
                math.sin(sampleY /
                        PawDabResource._textureTilePixels *
                        math.pi *
                        2) *
                    5 -
                warpY,
            sampleY + warpX,
            cells: 53,
            verticalCells: 43,
            noiseSeed: waxSeed ^ 0x2c1b3c6d,
          );
          final fine = tileNoise(
            sampleX,
            sampleY,
            cells: 79,
            verticalCells: 89,
            noiseSeed: waxSeed ^ grain.fineSeed ^ 0x51ed270b,
          );
          final pixelHash = PawDabResource._unit(
            PawDabResource._hash(waxSeed ^ x * 0x45d9f3b, y * 0x27d4eb2d),
          );
          // Apple Notes wax is dominated by connected medium flakes. Keeping
          // the interpolated tooth subordinate avoids the uniform white
          // "worms" produced when a two-pixel field controls every pore.
          final aggregateLoad = tileNoise(
            sampleX + warpY * 3,
            sampleY + warpX * 3,
            cells: 5,
            verticalCells: 7,
            noiseSeed: waxSeed ^ 0x72413,
          );
          final scrape = tileNoise(
            sampleX,
            sampleY,
            cells: 2,
            verticalCells: 61,
            noiseSeed: grain.strokeAlignedSeed,
          );
          final height = aggregateLoad * .18 +
              longFlake * .22 +
              splitFlake * .22 +
              waxBody * .21 +
              fine * .16 +
              pixelHash * .01;
          final strengthMix =
              (grain.coarseStrength * .55 + grain.fineStrength * .45)
                  .clamp(0.0, 1.0);
          // Flakes share a slowly varying load, while narrow dragged grooves
          // cross many flakes. Both are evaluated in the texture pass: a
          // 17-vertex ribbon cannot sample subpixel scrape channels faithfully.
          final scrapeCoverage = 1 -
              grain.strokeAlignedStrength *
                  .9 *
                  _smoothStep(((scrape - .6) / .22).clamp(0.0, 1.0));
          final loadedWax = _smoothStep(((height - .33) / .18).clamp(0.0, 1.0));
          final toothContact = _smoothStep(
              ((fine * .5 + splitFlake * .35 + pixelHash * .15 - .26) / .24)
                  .clamp(0.0, 1.0));
          final physicalDeposit = loadedWax * toothContact;
          final loadedCoverage = (1 -
                  math.pow(
                      1 -
                          (math.pow(physicalDeposit, strengthMix * 2.4) *
                                  scrapeCoverage)
                              .clamp(0.0, 1.0),
                      definition.dryWax.opticalDensity))
              .clamp(0.0, 1.0);
          final aggregateCharge = 1 -
              .12 * _smoothStep(((.55 - aggregateLoad) / .28).clamp(0.0, 1.0));
          final rawCoverage = loadedCoverage * aggregateCharge;
          final textureFloor = definition.coverageTransfer.textureFloor;
          final coverage = textureFloor + (1 - textureFloor) * rawCoverage;
          final alpha = (coverage * 255).round().clamp(0, 255);
          coveragePoints[alpha].add(Offset(sampleX, sampleY));
        }
      }
      final coveragePaint = Paint()
        ..isAntiAlias = false
        ..blendMode = BlendMode.src;
      for (var alpha = 0; alpha < coveragePoints.length; alpha++) {
        final points = coveragePoints[alpha];
        if (points.isEmpty) continue;
        coveragePaint.color = Colors.white.withAlpha(alpha);
        canvas.drawPoints(ui.PointMode.points, points, coveragePaint);
      }
      return recorder.endRecording();
    }
    if (grain.structure == PawDabGrainStructure.absorbentWash &&
        grain.isEnabled) {
      // Watercolor pigment settles against a stationary sheet. Broad pools,
      // cotton-fiber breakup and granulation therefore share canvas space;
      // none of these fields rolls with the tip or restarts at a corner.
      canvas.drawColor(const Color(0x00000000), BlendMode.src);
      final coveragePoints = List<List<Offset>>.generate(
        256,
        (_) => <Offset>[],
      );
      final washSeed =
          definition.identitySalt ^ definition.revision ^ grain.coarseSeed;
      for (var y = 0; y < PawDabResource._textureTilePixels; y++) {
        for (var x = 0; x < PawDabResource._textureTilePixels; x++) {
          final sampleX = x + .5;
          final sampleY = y + .5;
          final warpX = (tileNoise(
                    sampleX,
                    sampleY,
                    cells: 3,
                    verticalCells: 5,
                    noiseSeed: washSeed ^ 0x17a31,
                  ) -
                  .5) *
              15;
          final warpY = (tileNoise(
                    sampleX,
                    sampleY,
                    cells: 5,
                    verticalCells: 3,
                    noiseSeed: washSeed ^ 0x4e91,
                  ) -
                  .5) *
              15;
          final pool = tileNoise(
            sampleX + warpX,
            sampleY + warpY,
            cells: 5,
            verticalCells: 7,
            noiseSeed: washSeed,
          );
          final bloom = tileNoise(
            sampleX -
                math.sin(sampleY /
                        PawDabResource._textureTilePixels *
                        math.pi *
                        2) *
                    6 -
                warpY,
            sampleY +
                math.sin(sampleX /
                        PawDabResource._textureTilePixels *
                        math.pi *
                        2) *
                    4 +
                warpX,
            cells: 17,
            verticalCells: 13,
            noiseSeed: washSeed ^ 0x6d2b79f5,
          );
          final cotton = tileNoise(
            sampleX + warpX * .35,
            sampleY + warpY * .35,
            cells: 59,
            verticalCells: 71,
            noiseSeed: washSeed ^ 0x2c1b3c6d,
          );
          final granulation = tileNoise(
            sampleX,
            sampleY,
            cells: 113,
            verticalCells: 107,
            noiseSeed: washSeed ^ grain.fineSeed ^ 0x51ed270b,
          );
          // The supplied Apple Notes stroke preserves its broad wet pool but
          // carries substantially more one-to-eight-pixel paper energy than a
          // smooth airbrush. Transfer part of the pool weight to cotton and
          // granulation instead of increasing total contrast.
          final fluidHeight =
              pool * .48 + bloom * .32 + cotton * .14 + granulation * .06;
          final poolCoverage =
              _smoothStep(((fluidHeight - .2) / .6).clamp(0.0, 1.0));
          final valleyDeposit = _smoothStep(
            (((1 - cotton) * .58 + granulation * .42 - .16) / .7)
                .clamp(0.0, 1.0),
          );
          final variation =
              (grain.coarseStrength * .72 + grain.fineStrength * .28)
                  .clamp(0.0, 1.0);
          final material =
              (.4 + (poolCoverage - .5) * .38 + (valleyDeposit - .5) * .22)
                  .clamp(0.0, 1.0);
          final rawCoverage =
              (1 - variation + variation * material).clamp(0.0, 1.0);
          final textureFloor = definition.coverageTransfer.textureFloor;
          final coverage = textureFloor + (1 - textureFloor) * rawCoverage;
          final alpha = (coverage * 255).round().clamp(0, 255);
          coveragePoints[alpha].add(Offset(sampleX, sampleY));
        }
      }
      final coveragePaint = Paint()
        ..isAntiAlias = false
        ..blendMode = BlendMode.src;
      for (var alpha = 0; alpha < coveragePoints.length; alpha++) {
        final points = coveragePoints[alpha];
        if (points.isEmpty) continue;
        coveragePaint.color = Colors.white.withAlpha(alpha);
        canvas.drawPoints(ui.PointMode.points, points, coveragePaint);
      }
      return recorder.endRecording();
    }
    if (grain.structure == PawDabGrainStructure.fibrousWash &&
        grain.isEnabled) {
      // The x axis is absolute arc and y is the material normal for a rolling
      // grain. Strongly anisotropic fields therefore follow every bend as
      // dragged brush fibers. This removes the canvas-fixed round clouds that
      // made Ink read as a Soft/Round brush with a noise overlay.
      canvas.drawColor(const Color(0x00000000), BlendMode.src);
      final coveragePoints = List<List<Offset>>.generate(
        256,
        (_) => <Offset>[],
      );
      final wetSeed =
          definition.identitySalt ^ definition.revision ^ grain.coarseSeed;
      for (var y = 0; y < PawDabResource._textureTilePixels; y++) {
        for (var x = 0; x < PawDabResource._textureTilePixels; x++) {
          final sampleX = x + .5;
          final sampleY = y + .5;
          final warp = tileNoise(
            sampleX,
            sampleY,
            cells: 3,
            verticalCells: 5,
            noiseSeed: wetSeed ^ 0x1f123bb5,
          );
          final warpedX = sampleX + (warp - .5) * 18;
          final warpedY = sampleY + (warp - .5) * 8;
          final loadedFiber = tileNoise(
            warpedX,
            warpedY,
            cells: 4,
            verticalCells: 3,
            noiseSeed: wetSeed,
          );
          final splitFiber = tileNoise(
            warpedX + sampleY * .09,
            warpedY,
            cells: 9,
            verticalCells: 4,
            noiseSeed: wetSeed ^ 0x6d2b79f5,
          );
          final crossFiber = tileNoise(
            warpedX,
            warpedY,
            cells: 4,
            verticalCells: 17,
            noiseSeed: wetSeed ^ 0x2c1b3c6d,
          );
          final granulation = tileNoise(
            sampleX,
            sampleY,
            cells: 37,
            verticalCells: 29,
            noiseSeed: wetSeed ^ grain.fineSeed ^ 0x51ed270b,
          );
          final charge = loadedFiber * .56 +
              splitFiber * .2 +
              crossFiber * .19 +
              granulation * .05;
          final wash = _smoothStep(((charge - .12) / .76).clamp(0.0, 1.0));
          final fiberCore =
              _smoothStep(((splitFiber - .16) / .7).clamp(0.0, 1.0));
          final variation =
              (grain.coarseStrength * .72 + grain.fineStrength * .28)
                  .clamp(0.0, 1.0);
          final material = (.46 + wash * .45 + fiberCore * .09).clamp(0.0, 1.0);
          final rawCoverage =
              (1 - variation + variation * material).clamp(0.0, 1.0);
          final textureFloor = definition.coverageTransfer.textureFloor;
          final coverage = textureFloor + (1 - textureFloor) * rawCoverage;
          final alpha = (coverage * 255).round().clamp(0, 255);
          coveragePoints[alpha].add(Offset(sampleX, sampleY));
        }
      }
      final coveragePaint = Paint()
        ..isAntiAlias = false
        ..blendMode = BlendMode.src;
      for (var alpha = 0; alpha < coveragePoints.length; alpha++) {
        final points = coveragePoints[alpha];
        if (points.isEmpty) continue;
        coveragePaint.color = Colors.white.withAlpha(alpha);
        canvas.drawPoints(ui.PointMode.points, points, coveragePaint);
      }
      return recorder.endRecording();
    }
    if (strength > 0 ||
        fineStrength > 0 ||
        definition.template.coverageVoidLayers.isNotEmpty) {
      final paint = Paint()
        ..isAntiAlias = true
        ..blendMode = BlendMode.dstOut;
      final seed =
          definition.identitySalt ^ grain.coarseSeed ^ definition.revision;
      void paintGrain({
        required int grainSeed,
        required int count,
        required double minimumRadius,
        required double maximumRadius,
        required double layerStrength,
        required bool fineLayer,
      }) {
        if (layerStrength <= 0) return;
        for (var index = 0; index < count; index++) {
          final hash = PawDabResource._hash(grainSeed, index + 0x710);
          final center = Offset(
            PawDabResource._unit(hash) * PawDabResource._textureTilePixels,
            PawDabResource._unitWindow(hash, 11) *
                PawDabResource._textureTilePixels,
          );
          final radius = minimumRadius +
              PawDabResource._unitWindow(hash, 21) *
                  (maximumRadius - minimumRadius);
          final aspect = grain.poreAspectRatios
              .sample(PawDabResource._unitWindow(hash, 25));
          final angle = (PawDabResource._unitWindow(hash, 29) - .5) *
              2 *
              grain.poreAngleJitterRadians;
          final dryMediaPore = definition.dryWax.enabled;
          paint
            ..color = Colors.white.withValues(
              alpha: layerStrength *
                  (dryMediaPore
                      ? fineLayer
                          ? .05 + PawDabResource._unitWindow(hash, 5) * .18
                          : .16 + PawDabResource._unitWindow(hash, 5) * .34
                      : definition.wetMedia.enabled
                          ? .18 + PawDabResource._unitWindow(hash, 5) * .46
                          : .12 + PawDabResource._unitWindow(hash, 5) * .44),
            )
            ..maskFilter = dryMediaPore
                ? MaskFilter.blur(
                    BlurStyle.normal,
                    radius * (fineLayer ? .38 : .28),
                  )
                : definition.wetMedia.enabled
                    ? MaskFilter.blur(BlurStyle.normal, radius * .2)
                    : null;
          for (final dx in const <int>[
            -PawDabResource._textureTilePixels,
            0,
            PawDabResource._textureTilePixels
          ]) {
            for (final dy in const <int>[
              -PawDabResource._textureTilePixels,
              0,
              PawDabResource._textureTilePixels
            ]) {
              canvas.save();
              canvas.translate(
                center.dx + dx.toDouble(),
                center.dy + dy.toDouble(),
              );
              canvas.rotate(angle);
              canvas.scale(aspect, 1 / aspect);
              canvas.drawCircle(Offset.zero, radius, paint);
              canvas.restore();
            }
          }
        }
      }

      paintGrain(
        grainSeed: seed,
        count: definition.dryWax.enabled ? 84 : 34,
        minimumRadius: definition.dryWax.enabled ? 3.5 : 2.5,
        maximumRadius: definition.dryWax.enabled ? 14 : 10,
        layerStrength: strength,
        fineLayer: false,
      );
      paintGrain(
        grainSeed:
            definition.identitySalt ^ grain.fineSeed ^ definition.revision,
        count: ((definition.dryWax.enabled ? 72 : 36) *
                math.pow(
                  grain.coarseScaleFactor / grain.fineScaleFactor,
                  1.35,
                ))
            .round()
            .clamp(36, definition.dryWax.enabled ? 5200 : 3600),
        minimumRadius: math.max(
          definition.dryWax.enabled ? .45 : .3,
          2.5 * grain.fineScaleFactor / grain.coarseScaleFactor,
        ),
        maximumRadius: math.max(
          definition.dryWax.enabled ? 2.6 : .8,
          10 * grain.fineScaleFactor / grain.coarseScaleFactor,
        ),
        layerStrength: fineStrength,
        fineLayer: true,
      );
      paint.maskFilter = null;
      for (var layerIndex = 0;
          layerIndex < definition.template.coverageVoidLayers.length;
          layerIndex++) {
        final layer = definition.template.coverageVoidLayers[layerIndex];
        for (var item = 0; item < layer.count; item++) {
          final hash = PawDabResource._hash(
              seed ^ (layerIndex + 1) * 0x6c8e, item + 0x930);
          final center = Offset(
            PawDabResource._unit(hash) * PawDabResource._textureTilePixels,
            PawDabResource._unitWindow(hash, 9) *
                PawDabResource._textureTilePixels,
          );
          final length = (layer.lengthFactors
                      .sample(PawDabResource._unitWindow(hash, 15)) *
                  PawDabResource._textureTilePixels)
              .clamp(1.0, PawDabResource._textureTilePixels * .8);
          final width =
              (layer.widthFactors.sample(PawDabResource._unitWindow(hash, 21)) *
                      PawDabResource._textureTilePixels)
                  .clamp(1.0, PawDabResource._textureTilePixels * .8);
          final angle = (PawDabResource._unitWindow(hash, 27) - .5) *
              2 *
              layer.angleJitterRadians;
          paint
            ..color = Colors.white.withValues(
              alpha: layer.strength
                  .sample(PawDabResource._unitWindow(hash, 3))
                  .clamp(0.0, 1.0),
            )
            ..maskFilter = layer.softnessFactor == 0
                ? null
                : MaskFilter.blur(
                    BlurStyle.normal,
                    layer.softnessFactor *
                        PawDabResource._textureTilePixels *
                        .15,
                  );
          for (final dx in const <int>[
            -PawDabResource._textureTilePixels,
            0,
            PawDabResource._textureTilePixels
          ]) {
            for (final dy in const <int>[
              -PawDabResource._textureTilePixels,
              0,
              PawDabResource._textureTilePixels
            ]) {
              canvas.save();
              canvas.translate(
                center.dx + dx.toDouble(),
                center.dy + dy.toDouble(),
              );
              canvas.rotate(angle);
              canvas.drawOval(
                Rect.fromCenter(
                  center: Offset.zero,
                  width: length,
                  height: width,
                ),
                paint,
              );
              canvas.restore();
            }
          }
        }
      }
    }
    final textureFloor = definition.coverageTransfer.textureFloor;
    if (textureFloor > 0) {
      // White dstOver maps the completed mask alpha exactly to
      // floor + (1 - floor) * raw while preserving a white alpha mask.
      canvas.drawColor(
        Colors.white.withValues(alpha: textureFloor),
        BlendMode.dstOver,
      );
    }
    return recorder.endRecording();
  }
}
