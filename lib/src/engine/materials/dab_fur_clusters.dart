part of '../../streaming_dab_brush.dart';

extension _DabFurClusters on PawStreamingDabRenderCache {
  PawHairVertexBuffer _prepareHairVertices(PawDabEmissionSource stroke) {
    final mesh = _hairVertices..reset();
    final grain = stroke.definition.grain;
    if (!grain.isEnabled) return mesh;
    final raster = stroke.environment.rasterProgram;
    if (raster?.hasHighFrequencyCoverage == true &&
        raster!.highFrequencyCoordinateSpace ==
            PawBrushRasterCoordinateSpace.canvasFixed) {
      mesh.xx = (raster.highFrequencyRasterWidth ?? 64) /
          (raster.highFrequencyCanvasPeriod ?? 64);
      mesh.yy = (raster.highFrequencyRasterHeight ?? 64) /
          (raster.highFrequencyCanvasPeriod ?? 64);
      return mesh;
    }
    final fixed = grain.coordinate == PawDabGrainCoordinate.canvasFixed;
    final factor = PawDabResource._textureTilePixels /
        math.max(
            .0001, (fixed ? 64 : stroke.brushSize) * grain.coarseScaleFactor);
    final movement = PawDabResource._textureTilePixels *
        grain.movement /
        math.max(.0001, stroke.brushSize);
    final c = math.cos(grain.rotationRadians),
        s = math.sin(grain.rotationRadians);
    if (fixed) {
      mesh.xx = factor * c;
      mesh.xy = -factor * s;
      mesh.yx = factor * s;
      mesh.yy = factor * c;
      mesh.xa = movement * c;
      mesh.ya = movement * s;
    } else {
      mesh.xa = (factor + movement) * c;
      mesh.xn = -factor * s;
      mesh.ya = (factor + movement) * s;
      mesh.yn = factor * c;
    }
    return mesh;
  }

  // Continuous crossing-hair emitter. Roots are owned by planned absolute-arc
  // contacts, while each complete hair crosses from one side of the stroke to
  // the other. Authored intrinsic curves and two-ended taper shape each strand;
  // local angular-area compensation limits turn crowding.
  void _appendFurClusters({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required List<PawPlannedDab> plannedDabs,
    required PawFurBehavior behavior,
    required double spacing,
    PawHairVertexBuffer? mesh,
  }) {
    final layers = stroke.definition.template.streamingFilamentLayers;
    if (layers.isEmpty || plannedDabs.isEmpty) return;
    final frameRadius =
        PawStreamingDabRenderCache._hairFrameRadius(stroke.brushSize, spacing);
    final taperSamples = _hairTaperSamples;
    for (var dabIndex = 0; dabIndex < plannedDabs.length; dabIndex++) {
      final dab = plannedDabs[dabIndex];
      final frame = _materialFrameAtArc(
        stroke,
        dab.absoluteArc,
        radius: frameRadius,
        stabilizeExtrapolation: true,
      );
      if (frame == null) continue;
      // Direction may be filtered over a wide neighborhood, but the seated
      // root must follow the modeled input itself. Filtering position again
      // pulls a tight curve inward increasingly as brush size grows.
      final rootPoint =
          _centerlineSampleAtArc(stroke, dab.absoluteArc)?.point ?? frame.point;
      final endpoint = stroke.environment.unifiedProgram?.endpoint;
      final rootSize = endpoint?.sizeScaleAt(
              closed: stroke.isClosed,
              absoluteArc: dab.absoluteArc,
              renderEndArc: stroke.renderEndArc,
              brushSize: stroke.brushSize) ??
          1;
      final rootOpacity = endpoint?.opacityScaleAt(
              closed: stroke.isClosed,
              absoluteArc: dab.absoluteArc,
              renderEndArc: stroke.renderEndArc,
              brushSize: stroke.brushSize) ??
          1;
      _tapKernelDabScratch.set(
        point: frame.point,
        tangent: frame.direction,
        hash: dab.hash,
        motion: frame.motion,
      );
      final pressureSize = _DabInstanceEvaluator._pressureSizeForMotion(
          stroke.definition.emission, frame.motion);
      final hardness = stroke.environment.unifiedProgram?.shape.hardness ?? 1;
      final hardnessFalloff = 4 * (1 - hardness.clamp(0.0, 1.0));
      final emissionDynamics = stroke.definition.emission.dynamics;
      final rootDynamics = _evaluateDynamics(
          dynamics: emissionDynamics,
          motion: frame.motion,
          brushSize: stroke.brushSize,
          hash: 0);
      for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
        final layer = layers[layerIndex];
        if (layer.countPerRoot == 0) continue;
        final rootStride = math.max(
          1,
          (layer.rootSpacingFactor / stroke.definition.emission.spacingFactor)
              .round(),
        );
        if (dab.globalDabIndex % rootStride != 0) continue;
        final directionRadius = frameRadius +
            stroke.brushSize *
                layer.grooming.lookBehindArcFactor *
                (.5 + layer.grooming.inertia);
        final (hairDirection, rotationPerDistance) =
            _hairDirectorAtArc(stroke, dab.absoluteArc, frame, directionRadius);
        final hairNormal = Offset(-hairDirection.dy, hairDirection.dx);
        assert(identical(_fiberClusterGenerator.behavior, behavior));
        _fiberClusterGenerator.generateInto(
          dab: _tapKernelDabScratch,
          previousTangent: frame.direction,
          followingTangent: frame.direction,
          brushSize: stroke.brushSize,
          fiberCount: layer.countPerRoot,
          output: _fiberClusterScratch,
          includeDirections: false,
        );
        lastFilamentRootCount++;
        lastFilamentLaneCount += layer.countPerRoot;
        final clusterTangent = frame.direction;
        final clumpArc = dab.absoluteArc /
            math.max(1, stroke.brushSize * layer.clumpScaleFactor);
        final clumpSeed = stroke.seed.value ^ (layerIndex + 1) * 0x5271;
        // Authored spatial noise is invariant for an absolute-arc root.
        // Keep it while that root is mutable instead of resampling three
        // four-lattice noise fields per hair on every input revision.
        final noiseKey = (dab.globalDabIndex, layerIndex);
        var noiseEntry = _hairRootNoise[noiseKey];
        // Speed-dependent spacing can move a mutable root at the same index.
        if (noiseEntry == null || noiseEntry.$1 != dab.absoluteArc) {
          noiseEntry = (
            dab.absoluteArc,
            [
              for (var f = 0; f < layer.countPerRoot; f++)
                (
                  PawDabResource._valueNoise2D(
                      clumpArc * .7 + 17,
                      f / math.max(1, layer.countPerRoot) * 3.6,
                      clumpSeed ^ 0x3a71),
                  PawDabResource._valueNoise2D(
                      clumpArc,
                      (layer.countPerRoot == 1
                              ? 0
                              : f / (layer.countPerRoot - 1) * 2 - 1) *
                          .3,
                      stroke.seed.value ^ layerIndex * 0x5271),
                  PawDabResource._valueNoise2D(
                      clumpArc + 53,
                      (layer.countPerRoot == 1
                              ? 0
                              : f / (layer.countPerRoot - 1) * 2 - 1) *
                          1.8,
                      clumpSeed ^ 0x1429),
                )
            ]
          );
          _hairRootNoise[noiseKey] = noiseEntry;
        }
        final rootNoise = noiseEntry.$2;
        final lengthPermutation =
            PawDabResource._hash(dab.hash, layerIndex + 73) %
                layer.countPerRoot;
        final transverseRadius = math.max(
            .01,
            stroke.brushSize *
                pressureSize *
                (layer.lengthFactors.maximum *
                        .5 *
                        math.sin(layer.shearAngleRadians).abs() *
                        rootSize +
                    layer.spreadFactor * .29 * math.sqrt(rootSize)));
        for (var filament = 0; filament < layer.countPerRoot; filament++) {
          final fiber = _fiberClusterScratch[filament];
          final filamentHash = PawDabResource._hash(
            dab.hash ^ (layerIndex + 1) * 0x45d9f3b,
            filament,
          );
          // Pressure, speed, charge and curvature are shared by this root.
          // Only size/opacity jitter depend on a hair's individual hash.
          final unit = PawDabResource._unitWindow(filamentHash, 37) * 2 - 1;
          final dynamics = emissionDynamics.sizeJitterFactor == 0 &&
                  emissionDynamics.opacityJitterFactor == 0
              ? rootDynamics
              : _PawDabDynamicsResponse(
                  deposition: rootDynamics.deposition,
                  size: (1 + unit * emissionDynamics.sizeJitterFactor / 2)
                      .clamp(.01, 2.0),
                  opacity: (1 + unit * emissionDynamics.opacityJitterFactor / 2)
                      .clamp(.01, 2.0),
                  filamentLength: rootDynamics.filamentLength,
                  filamentSpread: rootDynamics.filamentSpread,
                  filamentCoverage: rootDynamics.filamentCoverage);
          // A continuous grooming field shares direction and bend across
          // adjacent roots. Per-root randomness alone produces a uniform comb;
          // discrete tuft families make a repeated stamp. Arc coordinates keep
          // this field identical in live, rebuilt and frozen geometry.
          final flowField = rootNoise[filament].$1;
          // Stratify the complete root's length distribution. Coherent field
          // noise must not make an entire root both longer and darker.
          final stratifiedRank = filament.isEven
              ? filament ~/ 2
              : layer.countPerRoot - 1 - filament ~/ 2;
          final lengthRank =
              (stratifiedRank + lengthPermutation) % layer.countPerRoot;
          final individualLength =
              (lengthRank + PawDabResource._unitWindow(filamentHash, 11)) /
                  layer.countPerRoot;
          final length = stroke.brushSize *
              layer.lengthFactors.sample(
                individualLength,
              ) *
              pressureSize *
              dynamics.filamentLength.clamp(.05, 2.0) *
              _fiberClusterScratch.length *
              rootSize;
          if (length <= .000001) continue;
          final lateral = layer.countPerRoot == 1
              ? 0.0
              : filament / (layer.countPerRoot - 1) * 2 - 1;
          final distributed = lateral.sign *
              math.pow(lateral.abs(), layer.centerDensityExponent).toDouble();
          final rootOffset = distributed *
              stroke.brushSize *
              layer.spreadFactor *
              pressureSize *
              dynamics.filamentSpread.clamp(.05, 2.0) *
              fiber.spread /
              2;
          // The generator already owns this relative angle. Converting it to
          // sin/cos, normalizing two vectors and recovering it with atan2 for
          // every strand discarded the original information at high cost.
          final fiberDeviation = fiber.angularDeviation;
          // Coherence reallocates authored angular variation to a continuous
          // family field. It must not add a second independent jitter source.
          final fiberAngle = layer.shearAngleRadians +
              layer.directionJitterRadians *
                  ((flowField - .5) * 2 * layer.familyCoherence +
                      ((PawDabResource._unitWindow(filamentHash, 7) - .5) * 2 +
                              fiberDeviation) *
                          (1 - layer.familyCoherence));
          final shearCosine = math.cos(fiberAngle);
          final shearSine = math.sin(fiberAngle);
          final hairAxis = hairDirection * shearCosine + hairNormal * shearSine;
          final curveNormal = Offset(-hairAxis.dy, hairAxis.dx);
          // Local osculating displacement projected into the strand frame.
          // Bound it smoothly so a cusp cannot curl or explode a long guard.
          // A single root curvature drives the complete hair; no future-frame
          // transport and no change to the authored length distribution.
          final rawTurnOffset = rotationPerDistance *
              length *
              length *
              shearCosine *
              shearCosine *
              shearCosine /
              8;
          final turnLimit = stroke.brushSize * .65 * rootSize;
          final turnOffset =
              layer.turnCompliance == 0 || rawTurnOffset.abs() < 1e-9
                  ? 0.0
                  : layer.turnCompliance *
                      turnLimit *
                      rawTurnOffset /
                      (turnLimit + rawTurnOffset.abs());
          final randomBend =
              (PawDabResource._unitWindow(filamentHash, 23) - .5) * 2;
          // Core hairs remain seated. Sparse outer hairs inherit a coherent
          // lateral sweep, giving the silhouette a loose, flowing guard layer
          // instead of equally rigid needles on every root.
          final sharedBend = (rootNoise[filament].$2 - .5) * 2;
          // Each curved hair passes through its seated midpoint. Independent
          // curvature breaks up rigid combs while families retain a shared lay.
          final bendFlow = .85 +
              sharedBend * .45 * layer.familyCoherence +
              randomBend * .35 * (1 - layer.familyCoherence);
          // Mirror the authored curve with its shear, independently of the
          // stroke's turn. Zero shear must still execute a nonzero bend.
          final bendHandedness = layer.shearAngleRadians < 0 ? -1.0 : 1.0;
          final bend = stroke.brushSize *
              layer.bendFactor *
              bendFlow *
              rootSize *
              bendHandedness;
          final wander =
              stroke.brushSize * layer.wanderAmplitudeFactor * rootSize;
          final signedWander =
              wander * (PawDabResource._unitWindow(filamentHash, 37) * 2 - 1);
          final alongJitter =
              (PawDabResource._unitWindow(filamentHash, 29) - .5) *
                      spacing *
                      1.4 +
                  (rootNoise[filament].$3 - .5) *
                      stroke.brushSize *
                      layer.clumpScaleFactor *
                      layer.familyCoherence *
                      1.5;
          // Root seating contracts more slowly than hair length, so distinct
          // short hairs remain visible instead of collapsing into one needle.
          final seatedOffset = rootOffset * .58 * math.sqrt(rootSize);
          final center = rootPoint +
              hairNormal * seatedOffset +
              clusterTangent * alongJitter;
          final width = stroke.brushSize *
              layer.widthFactors.sample(
                PawDabResource._unitWindow(filamentHash, 19),
              ) *
              pressureSize *
              dynamics.size *
              (1 - lateral.abs() * .35);
          final coverage = layer.coverage *
              layer.pressureDensityCoverage(
                pressure: dab.motion.pressure,
                filamentHash: filamentHash,
              ) *
              fiber.density;
          final bodyColor = _DabInstanceEvaluator._colorForMotion(
            stroke: stroke,
            motion: frame.motion,
            hash: filamentHash,
            coverage: coverage,
            canvasPoint: center,
            resolvedDynamics: dynamics,
          );
          // Intrinsic curved hairs keep their root director along the whole
          // strand. Rotating individual samples through the path twisted the
          // middle of a long hair when it straddled a corner.
          // Share subdivision at a conservative half-pixel bend bucket. Split
          // where the cubic actually departs from a chord, not uniformly at
          // the worst curvature: its nearly straight middle needs fewer nodes.
          final bendBucket = (bend.abs() * 2).ceil();
          final wanderBucket = (wander * 2).ceil();
          final turnBucket = (turnOffset.abs() * 2).ceil();
          final tapers = taperSamples.putIfAbsent(
              (layerIndex, bendBucket, wanderBucket, turnBucket),
              () => [
                    for (final t in _DabFurClusters._hairCurveParameters(
                        bendBucket * .5,
                        layer.bendBias,
                        wanderBucket * .5,
                        turnBucket * .5))
                      (
                        t,
                        math
                            .pow(t == 0 || t == 1 ? 0 : math.sin(math.pi * t),
                                layer.taperExponent * .72)
                            .toDouble(),
                        math
                            .pow(t == 0 || t == 1 ? 0 : math.sin(math.pi * t),
                                layer.taperExponent * .58)
                            .toDouble(),
                        16 * t * (1 - t) * (2 * t - 1) * (2 * t - 1),
                        16 *
                            ((1 - 2 * t) * (2 * t - 1) * (2 * t - 1) +
                                4 * t * (1 - t) * (2 * t - 1)),
                        2 *
                            (4 *
                                    t *
                                    (1 - t) *
                                    (2 * t - 1) *
                                    (1 - layer.bendBias.abs()) +
                                (4 * t * (1 - t) - 1) * layer.bendBias),
                        2 *
                            ((4 * (1 - 2 * t) * (2 * t - 1) + 8 * t * (1 - t)) *
                                    (1 - layer.bendBias.abs()) +
                                4 * (1 - 2 * t) * layer.bendBias),
                        (2 * t - 1) * (2 * t - 1),
                        4 * (2 * t - 1),
                      )
                  ]);
          final segmentCount = tapers.length - 1;
          final rootAlpha =
              1 - math.pow(1 - bodyColor.a, frame.arcRate).toDouble();
          final rgb = bodyColor.toARGB32() & 0xffffff;
          // S/C bias and the small quartic deviation use one whole-hair frame.
          // They do not switch bend families across the middle root rows.
          _PawFilamentLanePoint? previousPoint;
          final sectionSoftness = stroke.brushSize * layer.softnessFactor;
          mesh?.beginHair(segmentCount + 1);
          for (var sampleIndex = 0;
              sampleIndex <= segmentCount;
              sampleIndex++) {
            final (
              t,
              widthTaper,
              opacityTaper,
              wave,
              waveDerivative,
              bendBasis,
              bendDerivativeBasis,
              turnBasis,
              turnDerivativeBasis
            ) = tapers[sampleIndex];
            final normalOffset =
                bend * bendBasis + signedWander * wave + turnOffset * turnBasis;
            // Axis, bend and seating share one director frame. Mixing a
            // narrow path normal with a wider hair director twists the clump.
            final along = length * (t - .5);
            final offsetX = hairAxis.dx * along + curveNormal.dx * normalOffset;
            final offsetY = hairAxis.dy * along + curveNormal.dy * normalOffset;
            final freeX = center.dx + offsetX, freeY = center.dy + offsetY;
            final projectedArc = dab.absoluteArc +
                alongJitter +
                offsetX * frame.direction.dx +
                offsetY * frame.direction.dy;
            // Analytic tangent avoids extra per-hair point/coverage buffers and
            // keeps the tiny tips smooth even with few curve subdivisions.
            final bendDerivative = bend * bendDerivativeBasis +
                signedWander * waveDerivative +
                turnOffset * turnDerivativeBasis;
            final derivativeX =
                hairAxis.dx * length + curveNormal.dx * bendDerivative;
            final derivativeY =
                hairAxis.dy * length + curveNormal.dy * bendDerivative;
            final derivativeLength = math
                .sqrt(derivativeX * derivativeX + derivativeY * derivativeY);
            final normalX = derivativeLength > .000001
                ? -derivativeY / derivativeLength
                : 0.0;
            final normalY = derivativeLength > .000001
                ? derivativeX / derivativeLength
                : 1.0;
            final signedAcross = (freeX - rootPoint.dx) * hairNormal.dx +
                (freeY - rootPoint.dy) * hairNormal.dy;
            final areaCoverage =
                (1 - rotationPerDistance * signedAcross).clamp(.08, 1.0);
            // Stroke-wide optical falloff is separate from each hair's tip
            // taper. The authored hardness now controls this executed path.
            final across = signedAcross / transverseRadius;
            final transverseCoverage = hardnessFalloff == 0
                ? 1.0
                : math.exp(-hardnessFalloff * across * across);
            final sectionWidth =
                width * (1 - layer.widthTaper * (1 - widthTaper));
            final sectionAlpha = rootAlpha *
                (1 - layer.opacityTaper * (1 - opacityTaper)) *
                areaCoverage *
                transverseCoverage *
                rootOpacity;
            if (mesh != null) {
              mesh.addSection(
                  x: freeX,
                  y: freeY,
                  nx: normalX,
                  ny: normalY,
                  width: sectionWidth,
                  softness: sectionSoftness,
                  arc: projectedArc,
                  across: signedAcross,
                  rgb: rgb,
                  alpha: sectionAlpha);
              if (sampleIndex > 0) lastFilamentSegmentCount++;
              continue;
            }
            final point = _PawFilamentLanePoint(
              arc: projectedArc,
              center: Offset(freeX, freeY),
              normal: Offset(normalX, normalY),
              normalDistance: signedAcross,
              width: sectionWidth,
              color: bodyColor.withValues(
                alpha: sectionAlpha,
              ),
            );
            if (previousPoint != null) {
              _DabPersistentLanes._appendFilamentLaneSegment(
                positions: positions,
                textureCoordinates: textureCoordinates,
                colors: colors,
                indices: indices,
                stroke: stroke,
                first: previousPoint,
                second: point,
                connectToPrevious: sampleIndex > 1,
                softness: stroke.brushSize * layer.softnessFactor,
              );
              lastFilamentSegmentCount++;
            }
            previousPoint = point;
          }
          mesh?.endHair();
        }
      }
    }
  }

  static List<double> _hairCurveParameters(
      double bend, double bias, double wander, double turn) {
    final samples = <double>[0, .25, .5, .75, 1];
    final odd = 1 - bias.abs();
    double offset(double t) =>
        8 * t * (1 - t) * (2 * t - 1) * odd + 2 * bias * (4 * t * (1 - t) - 1);
    double wave(double t) => 16 * t * (1 - t) * (2 * t - 1) * (2 * t - 1);
    while (samples.length < 17) {
      var worstError = .45, splitAt = 0.0, splitIndex = -1;
      for (var i = 1; i < samples.length; i++) {
        final a = samples[i - 1], b = samples[i];
        final fa = offset(a), fb = offset(b);
        final slope = (fb - fa) / (b - a);
        // Extrema of cubic-minus-chord, including the pure quadratic C bend.
        final qa = -48 * odd, qb = 48 * odd - 16 * bias;
        final qc = -8 * odd + 8 * bias - slope;
        final discriminant = qb * qb - 4 * qa * qc;
        final extrema = qa.abs() < .000001
            ? <double>[if (qb.abs() > .000001) -qc / qb]
            : <double>[
                if (discriminant > 0) ...[
                  (-qb - math.sqrt(discriminant)) / (2 * qa),
                  (-qb + math.sqrt(discriminant)) / (2 * qa)
                ]
              ];
        // Probe the quartic irregularity inside the existing cubic intervals.
        // Its amplitude is shared conservatively across all signs and hairs.
        final wa = wander == 0 ? 0.0 : wave(a);
        final wb = wander == 0 ? 0.0 : wave(b);
        for (final t in [
          ...extrema,
          if (wander > 0 || turn > 0) ...[
            a + (b - a) * .25,
            (a + b) * .5,
            a + (b - a) * .75
          ]
        ]) {
          if (t <= a || t >= b) continue;
          final error = (offset(t) - fa - slope * (t - a)).abs() * bend +
              (wander == 0
                  ? 0
                  : (wave(t) - wa - (wb - wa) * ((t - a) / (b - a))).abs() *
                      wander *
                      1.1) +
              // Quadratic-minus-chord has known error 4*(t-a)*(b-t).
              4 * turn * (t - a) * (b - t);
          if (error > worstError) {
            worstError = error;
            splitAt = t;
            splitIndex = i;
          }
        }
      }
      if (splitIndex < 0) break;
      samples.insert(splitIndex, splitAt);
    }
    return samples;
  }
}
