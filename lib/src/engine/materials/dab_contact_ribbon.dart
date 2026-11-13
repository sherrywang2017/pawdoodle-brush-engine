part of '../../streaming_dab_brush.dart';

extension _DabContactRibbon on PawStreamingDabRenderCache {
  void _appendContactRibbon({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required double startArc,
    required double endArc,
    required PawBrushBehavior? behavior,
    required PawBrushKernel kernel,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    final visibleStart = startArc.clamp(0.0, stroke.renderEndArc).toDouble();
    final visibleEnd = math.min(endArc, stroke.renderEndArc);
    final isTap =
        stroke.renderEndArc <= 0 && stroke.strokeStartPosition != null;
    if (!isTap && visibleEnd <= visibleStart + .000001) return;

    const crossSection = <double>[
      -.5,
      -.485,
      -.45,
      -.39,
      -.32,
      -.24,
      -.15,
      -.07,
      0,
      .07,
      .15,
      .24,
      .32,
      .39,
      .45,
      .485,
      .5,
    ];
    final footprint = stroke.definition.template.footprint;
    final endpoint = stroke.environment.unifiedProgram?.endpoint;
    final paperContact = stroke.definition.paperContact;
    final coverageTransfer = stroke.definition.coverageTransfer;
    final rasterProgram = stroke.environment.rasterProgram;
    final hasRasterShape =
        rasterProgram?.hasRole(PawBrushRasterRoleKind.shape) == true;
    final hasRasterGrain =
        rasterProgram?.hasRole(PawBrushRasterRoleKind.grain) == true;
    final pixelTransfer = PawDabResource._usesContactPixelTransfer(
        stroke.definition,
        rasterProgram: rasterProgram);
    final shapeField = stroke.environment.unifiedProgram?.shape ??
        switch (stroke.environment.unifiedProgram?.kernelKind ??
            stroke.environment.kernelKind) {
          PawBrushKernelKind.inkCoverage => _inkShapeField,
          PawBrushKernelKind.softDensity => _softShapeField,
          PawBrushKernelKind.bristleFilament => _furShapeField,
          _ => _circleShapeField,
        };
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x3a77c1;
    final step =
        PawStreamingDabRenderCache._contactSectionStep(stroke.brushSize);
    final frameRadius =
        PawStreamingDabRenderCache._contactFrameRadius(stroke.brushSize);
    final turns =
        _contactTurnsInRange(_sourceSegments, visibleStart, visibleEnd);
    final waxBends = stroke.definition.dryWax.enabled
        ? _waxBendsInRange(
            _sourceSegments, visibleStart, visibleEnd, stroke.brushSize)
        : const <_PawWaxBend>[];
    final contactNeighborhoods =
        <double, List<(double, _PawFilamentArcSample)>>{};
    final dosePairs = <(double, double, double, bool),
        List<
            (
              (double, _PawFilamentArcSample),
              (double, _PawFilamentArcSample)
            )>>{};
    _PawFilamentArcSample? contactFrame(double arc) =>
        _contactFrames.putIfAbsent(
            arc,
            () => isTap
                ? _PawFilamentArcSample(
                    segmentIndex: 0,
                    point: stroke.strokeStartPosition!,
                    direction: const Offset(1, 0),
                    normal: const Offset(0, 1),
                    motion: stroke.tapMotionSample,
                  )
                : _contactFrameAtArc(stroke, arc, radius: frameRadius));

    _PawFilamentArcSample? turnFrame(double arc, double amount) {
      final sample = contactFrame(arc);
      final turn = turns[arc];
      if (sample == null || turn == null) return sample;
      final direction = turn.directionAt(amount);
      return _PawFilamentArcSample(
        segmentIndex: sample.segmentIndex,
        point: turn.point,
        direction: direction,
        normal: Offset(-direction.dy, direction.dx),
        motion: sample.motion,
        arcRate: sample.arcRate,
      );
    }

    double localDose(Offset vertex, double arc, double halfWidth,
        double ownRadial, double supportScale, bool cap) {
      final strength = stroke.definition.wetMedia.localOverlapNormalization;
      if (strength == 0) return 1;
      final window = stroke.brushSize * 4;
      final sampleStep = stroke.brushSize * .24;
      final first = math.max(0, ((arc - window) / sampleStep).floor());
      final last = math.min((stroke.renderEndArc / sampleStep).ceil(),
          ((arc + window) / sampleStep).ceil());
      double profile(double radial) =>
          1 - _smoothStep(((radial - .38) / .62).clamp(0.0, 1.0));
      final own = profile(ownRadial).clamp(.001, 1.0);
      var total = own, maximum = own;
      final neighborhood = contactNeighborhoods.putIfAbsent(arc, () {
        final result = <(double, _PawFilamentArcSample)>[];
        for (var i = first; i <= last; i++) {
          final at = math.min(stroke.renderEndArc, i * sampleStep);
          // Dose queries only geometric nearest feet. Filtering pressure/load
          // for every neighbor evaluated a complete material pose that none
          // of these calculations read.
          final frame = _contactGeometryAtArc(stroke, at);
          if (frame != null) result.add((at, frame));
        }
        return result;
      });
      // Broad phase once per cross-section. A foot outside the complete tip
      // support cannot contribute to any of its vertices. Keep pairs rather
      // than filtered points so pruning never creates a fictitious long leg.
      final pairs =
          dosePairs.putIfAbsent((arc, halfWidth, supportScale, cap), () {
        final pose = contactFrame(arc)!;
        final center = pose.point;
        final reach = halfWidth * (supportScale + 1) + .0001;
        bool possibleFoot(int i) {
          final previous = neighborhood[i - 1], next = neighborhood[i];
          // The interpolated foot cannot leave the leg's arc interval. Its
          // own near neighborhood is excluded by the dose definition below.
          if (previous.$1 >= arc - sampleStep * 1.5 &&
              next.$1 <= arc + sampleStep * 1.5) {
            return false;
          }
          if (cap) return true;
          // Every body vertex is on this crossbar, including authored edge
          // roughness. Bound both tangent projections over the entire bar.
          // If they cannot cross + -> -, no vertex can have a nearest foot.
          final radius = halfWidth *
              supportScale *
              (1 + stroke.definition.emission.footprintEdgeRoughness.abs());
          double projection(_PawFilamentArcSample p) =>
              (center.dx - p.point.dx) * p.direction.dx +
              (center.dy - p.point.dy) * p.direction.dy;
          double span(_PawFilamentArcSample p) =>
              radius *
              (pose.normal.dx * p.direction.dx +
                      pose.normal.dy * p.direction.dy)
                  .abs();
          return projection(previous.$2) + span(previous.$2) >= 0 &&
              projection(next.$2) - span(next.$2) < 0;
        }

        return [
          for (var i = 1; i < neighborhood.length; i++)
            if (possibleFoot(i) &&
                _DabInstanceEvaluator._distanceToContactLeg(
                        center,
                        neighborhood[i - 1].$2.point,
                        neighborhood[i].$2.point) <=
                    reach)
              (neighborhood[i - 1], neighborhood[i]),
        ];
      });
      for (final pair in pairs) {
        final previousArc = pair.$1.$1;
        final previous = pair.$1.$2;
        final previousDelta = vertex - previous.point;
        final previousProjection = previousDelta.dx * previous.direction.dx +
            previousDelta.dy * previous.direction.dy;
        final entry = pair.$2;
        final at = entry.$1;
        final frame = entry.$2;
        final dx = vertex.dx - frame.point.dx;
        final dy = vertex.dy - frame.point.dy;
        final projection = dx * frame.direction.dx + dy * frame.direction.dy;
        // Positive-to-negative projection is a local nearest foot. A far
        // crossing outside this finite sweep neighborhood keeps its own dose.
        if (previousProjection >= 0 && projection < 0) {
          final fraction =
              previousProjection / (previousProjection - projection);
          final footArc = previousArc + (at - previousArc) * fraction;
          final gap = (footArc - arc).abs();
          if (gap > sampleStep * 1.5) {
            final foot = Offset.lerp(previous.point, frame.point, fraction)!;
            final radial = (vertex - foot).distance / math.max(.001, halfWidth);
            final nearby = 1 -
                _smoothStep(
                    ((gap - window * .65) / (window * .35)).clamp(0.0, 1.0));
            final coverage = profile(radial) * nearby;
            total += coverage;
            maximum = math.max(maximum, coverage);
          }
        }
      }
      return 1 - strength * (1 - maximum / total);
    }

    void appendSection(
      double arc, {
      required bool head,
      required bool tail,
      double capProgress = 0,
      _PawFilamentArcSample? frame,
      double? turnProgress,
    }) {
      final sample = frame ?? contactFrame(arc);
      if (sample == null) return;
      final sectionIndex = (arc / step).round();
      final hash = PawDabResource._hash(seed, sectionIndex);
      _tapKernelDabScratch.set(
        point: sample.point,
        tangent: sample.direction,
        hash: hash,
        motion: sample.motion,
      );
      _evaluateKernelInto(
        stroke: stroke,
        dab: _tapKernelDabScratch,
        previousTangent: sample.direction,
        followingTangent: sample.direction,
        behavior: behavior,
        kernel: kernel,
      );
      final output = _kernelOutputScratch;
      final sectionPoint = sample.point;
      final direction = _DabInstanceEvaluator._normalized(sample.direction);
      var turn = turnProgress == null ? null : turns[arc];
      if (turn == null) {
        for (final bend in waxBends) {
          if (arc >= bend.start && arc <= bend.end) {
            turn = bend.turn;
            turnProgress = bend.progressAt(direction);
            break;
          }
        }
      }
      final wax = stroke.definition.dryWax;
      final dragDirection = wax.enabled && turn != null
          ? turn.dragDirectionAt(turnProgress!)
          : direction;
      final normal = Offset(-direction.dy, direction.dx);
      final wet = stroke.definition.wetMedia;
      final settlement =
          stroke is PawStreamingDabStroke ? stroke.settlementAtArc(arc) : 1.0;
      final dynamics = _evaluateDynamics(
        dynamics: stroke.definition.emission.dynamics,
        motion: sample.motion,
        brushSize: stroke.brushSize,
        hash: hash,
      );
      final pressureSize = _DabInstanceEvaluator._pressureSizeForMotion(
          stroke.definition.emission, sample.motion);
      final endpointSize = endpoint?.sizeScaleAt(
            closed: stroke.isClosed,
            absoluteArc: arc,
            renderEndArc: stroke.renderEndArc,
            brushSize: stroke.brushSize,
          ) ??
          1;
      final endpointOpacity = endpoint?.opacityScaleAt(
            closed: stroke.isClosed,
            absoluteArc: arc,
            renderEndArc: stroke.renderEndArc,
            brushSize: stroke.brushSize,
          ) ??
          1;
      final halfWidth = stroke.brushSize *
          footprint.widthFactor *
          pressureSize *
          dynamics.size *
          output.widthScale.clamp(.35, 1.8) *
          (wet.enabled ? 1 - wet.diffusionRadius * .16 * (1 - settlement) : 1) *
          endpointSize /
          2;
      final supportScale = wet.enabled
          ? 1 + wet.diffusionRadius * .34 * (.25 + .75 * settlement)
          : 1 + footprint.outerSoftnessFactor * .8;
      final pressureOpacity =
          stroke.definition.emission.pressureOpacityMinFactor +
              (stroke.definition.emission.pressureOpacityMaxFactor -
                      stroke.definition.emission.pressureOpacityMinFactor) *
                  sample.motion.pressure;
      final modulation = _DabInstanceEvaluator._densityModulation(
        emission: stroke.definition.emission,
        seed: seed,
        arc: arc,
        brushSize: stroke.brushSize,
        point: sectionPoint,
      );
      final sourceAlpha = (stroke.color.a *
              stroke.opacity *
              pressureOpacity *
              dynamics.deposition *
              dynamics.opacity *
              modulation *
              output.opacityScale *
              endpointOpacity)
          .clamp(0.0, 1.0)
          .toDouble();

      final stateRgb = pixelTransfer
          ? _DabInstanceEvaluator._contactStateColor(
                      dragDirection, settlement, 1,
                      axial: wax.enabled)
                  .toARGB32() &
              0xffffff
          : 0;

      for (final normalFactor in crossSection) {
        // Caps are sampled half-ellipses with the same two-dimensional
        // coverage as the body. Moving only the first opaque cross-section
        // forward made a round endpoint into a hard, sliced extrusion.
        final capNormalScale = math.sqrt(1 - capProgress * capProgress);
        final transverse = normalFactor * 2 * capNormalScale;
        final supportRadial = math
            .sqrt(
              transverse * transverse + capProgress * capProgress,
            )
            .clamp(0.0, 1.0)
            .toDouble();
        final nominalRadial = supportRadial * supportScale;
        final radial = nominalRadial.clamp(0.0, 1.0).toDouble();
        final edgeWeight = footprint.edgeResponse.isIdentity
            ? _smoothStep(((radial - .7) / .3).clamp(0.0, 1.0))
            : footprint.edgeResponse.edgeWeightAt(radial);
        var signedNormal = halfWidth * transverse * supportScale;
        if (!footprint.edgeResponse.isIdentity && radial > 0) {
          final provisional = sectionPoint + normal * signedNormal;
          final inset = footprint.edgeResponse.inwardInsetFactorAt(
            absoluteArc: arc,
            brushSize: stroke.brushSize,
            canvasPoint: provisional,
            strokeSeed: stroke.seed.value ^ stroke.definition.identitySalt,
            paperSeed: stroke.environment.paper.definition.seed,
          );
          signedNormal *= math.max(0.0, 1 - inset * edgeWeight);
        }
        if (stroke.definition.emission.footprintEdgeRoughness > 0) {
          final phase = arc / math.max(.001, stroke.brushSize) * 11.7 +
              sample.point.dx * .071 +
              sample.point.dy * .053 +
              normalFactor.sign * 1.9 +
              seed * .000017;
          signedNormal *= 1 +
              math.sin(phase) *
                  stroke.definition.emission.footprintEdgeRoughness *
                  edgeWeight;
        }
        final materialSignedNormal = signedNormal;
        final geometrySignedNormal = materialSignedNormal *
            (wax.enabled && turn != null
                ? turn.waxReachAt(turnProgress!, materialSignedNormal,
                    roughness:
                        endpoint?.capRoughness ?? footprint.capRoughnessFactor,
                    seed: seed ^ footprint.edgeResponse.seed)
                : 1);
        var capReach = halfWidth *
            supportScale *
            capProgress *
            (endpoint?.capRoundness ?? footprint.capRoundness) *
            (shapeField.kind == PawBrushShapeKind.ellipse
                ? shapeField.aspect
                : 1);
        final capRoughness =
            endpoint?.capRoughness ?? footprint.capRoughnessFactor;
        if (capProgress > 0 && capRoughness > 0) {
          final capNoise = PawDabResource._valueNoise2D(
            normalFactor * 7.3 + (head ? 2.1 : 11.7),
            seed * .000019 + (head ? 0 : 5.3),
            seed ^ footprint.edgeResponse.seed ^ 0x5271,
          );
          capReach = (capReach +
                  (capNoise * 2 - 1) * halfWidth * capRoughness * capProgress)
              .clamp(0.0, halfWidth * supportScale)
              .toDouble();
        }
        final capOffset = head
            ? -capReach
            : tail
                ? capReach
                : 0.0;
        final vertex = sectionPoint +
            direction * capOffset +
            normal * geometrySignedNormal;
        final edgeStart = footprint.edgeResponse.isIdentity
            ? .55
            : footprint.edgeResponse.edgeBandStart;
        final edgeMix = _smoothStep(
          ((radial - edgeStart) / (1 - edgeStart)).clamp(0.0, 1.0),
        );
        final footprintCoverage = footprint.centerCoverage +
            (footprint.edgeCoverage - footprint.centerCoverage) * edgeMix;
        final fringeCore = radial <= .72
            ? 1.0
            : _smoothStep(((1 - radial) / .28).clamp(0.0, 1.0));
        final wetEdgeFloor = wet.enabled ? wet.edgeFeather * .18 : 0.0;
        final fringe = wetEdgeFloor + (1 - wetEdgeFloor) * fringeCore;
        final signedProfile = transverse * supportScale;
        final shapeCoverage = shapeField.coverage(
          capProgress * supportScale,
          signedProfile *
              (shapeField.kind == PawBrushShapeKind.ellipse
                  ? shapeField.aspect
                  : 1),
          0,
          sample.motion.pressure,
        );
        final bitmapShape = hasRasterShape
            ? rasterProgram!.sample(
                role: PawBrushRasterRoleKind.shape,
                canvasX: vertex.dx,
                canvasY: vertex.dy,
                absoluteArc: arc,
                signedNormal: signedNormal,
                brushWidth: stroke.brushSize,
              )
            : 1.0;
        final plainContact = !wet.enabled &&
            !stroke.definition.dryWax.enabled &&
            stroke.environment.unifiedProgram?.kernelKind ==
                PawBrushKernelKind.dabDry;
        final contactHardness = shapeField.hardness;
        final continuousProfile = contactHardness >= .999
            ? (nominalRadial <= 1 ? 1.0 : 0.0)
            : ((1 - nominalRadial) / (1 - contactHardness)).clamp(0.0, 1.0);
        final innerContactCoverage = plainContact
            ? continuousProfile * bitmapShape
            : (footprintCoverage *
                    output.coverageAt(radial: radial, normalizedAlong: 0) *
                    shapeCoverage *
                    bitmapShape *
                    fringe)
                .clamp(0.0, 1.0)
                .toDouble();
        final wetTile = wetAccumulator?.sampleAt(vertex);
        final contactCoverage = plainContact
            ? innerContactCoverage
            : nominalRadial <= 1
                ? innerContactCoverage
                : wet.enabled
                    ? (footprint.edgeCoverage *
                            (.28 + wet.edgeFeather * .42) *
                            // The fringe is transported water, not a fixed blur
                            // around the geometric ribbon. A small dry remainder
                            // avoids a hard clip while tile wetness owns the halo.
                            (.12 + (wetTile?.wetness ?? 0) * .88) *
                            _smoothStep(
                              ((supportScale - nominalRadial) /
                                      math.max(.0001, supportScale - 1))
                                  .clamp(0.0, 1.0),
                            ) *
                            bitmapShape)
                        .clamp(0.0, 1.0)
                        .toDouble()
                    : (footprint.edgeCoverage *
                            (.14 + footprint.outerSoftnessFactor * 1.2) *
                            _smoothStep(
                              ((supportScale - nominalRadial) /
                                      math.max(.0001, supportScale - 1))
                                  .clamp(0.0, 1.0),
                            ) *
                            bitmapShape)
                        .clamp(0.0, 1.0)
                        .toDouble();
        // Contact load retains its authored paper response. Immutable noise
        // lattice caching avoids repeated hash work without replacing spatial
        // material with an average; the shader resolves the pixel-scale wash.
        final wetPaper = wet.enabled && !stroke.definition.dryWax.enabled
            ? stroke.environment.paper.sample(vertex)
            : null;
        final rawPaperCoverage = !paperContact.isEnabled
            ? 1.0
            : wetPaper != null
                ? (1 - paperContact.coarseDepositionStrength * wetPaper.coarse)
                    .clamp(0.0, 1.0)
                : paperContact.coarseDepositionAt(
                    paper: stroke.environment.paper,
                    canvasPoint: vertex,
                  );
        final remappedPaper =
            coverageTransfer.remapPaperContact(rawPaperCoverage);
        double alpha;
        if (stroke.definition.dryWax.enabled) {
          final grainSample = hasRasterGrain
              ? rasterProgram!.sample(
                  role: PawBrushRasterRoleKind.grain,
                  canvasX: vertex.dx,
                  canvasY: vertex.dy,
                  absoluteArc: arc,
                  signedNormal: signedNormal,
                  brushWidth: stroke.brushSize,
                )
              : 1.0;
          final waxCoverage = stroke.definition.dryWax.waxCoverageResponse(
            paperContact: remappedPaper,
            pressure: sample.motion.pressure,
            waxGrainAndScrape: grainSample,
          );
          final thicknessResponse = pixelTransfer
              ? stroke.definition.dryWax.linearWaxMass
              : stroke.definition.dryWax.waxThicknessResponse;
          final waxThickness = thicknessResponse(
            sourceAlpha: sourceAlpha,
            pressure: sample.motion.pressure,
          );
          final draggedGrain = stroke.definition.grain.strokeAlignedCoverageAt(
            absoluteArc: arc,
            signedNormal: materialSignedNormal,
            brushSize: stroke.brushSize,
            strokeSeed: seed,
          );
          final depositedCoverage =
              contactCoverage * waxCoverage * draggedGrain;
          alpha = (pixelTransfer
                  ? depositedCoverage
                  : stroke.definition.dryWax
                      .opticalCoverageResponse(depositedCoverage)) *
              waxThickness;
          if (turn != null) {
            alpha = 1 -
                math
                    .pow(1 - alpha.clamp(0.0, 1.0),
                        turn.waxContactPassesAt(turnProgress!))
                    .toDouble();
          }
        } else {
          final wetCoverage = !wet.enabled
              ? 1.0
              : wet.contactCoverage(
                  paper: wetPaper!,
                  definition: stroke.environment.paper.definition,
                  radial: radial,
                  pressure: sample.motion.pressure,
                  tilePigment: wetTile?.pigment ?? 0,
                  tileWetness: wetTile?.wetness ?? 0,
                );
          alpha = wet.opticalCoverageResponse(
            sourceAlpha * contactCoverage * remappedPaper * wetCoverage,
          );
        }
        if (wet.localOverlapNormalization > 0 && alpha > 0) {
          alpha = 1 -
              math
                  .pow(
                      1 - alpha.clamp(0.0, 1.0),
                      localDose(vertex, arc, halfWidth, radial, supportScale,
                          head || tail))
                  .toDouble();
        }
        positions.add(vertex);
        textureCoordinates.add(pixelTransfer
            ? Offset.zero
            : _DabInstanceEvaluator._grainCoordinate(
                grain: stroke.definition.grain,
                rasterProgram: rasterProgram,
                canvasPoint: vertex,
                arc: arc + capOffset,
                normalDistance: materialSignedNormal,
                brushSize: stroke.brushSize,
              ));
        colors.add(pixelTransfer
            ? Color(((alpha.clamp(0.0, 1.0) * 255).round() << 24) | stateRgb)
            : stroke.color.withValues(alpha: alpha.clamp(0.0, 1.0)));
      }
    }

    final sectionArcs = <double>[visibleStart, visibleEnd, ...turns.keys];
    final firstGrid = (visibleStart / step).floor() + 1;
    final lastGrid = (visibleEnd / step).ceil();
    for (var division = firstGrid; division < lastGrid; division++) {
      final gridArc = division * step;
      if (gridArc > visibleStart + .000001 && gridArc < visibleEnd - .000001) {
        sectionArcs.add(gridArc);
      }
    }
    // Keep the absolute-arc grid at smooth command boundaries. Only a real
    // tangent discontinuity inserts a join: arc subdivision alone cannot fill
    // the finite angular sweep at a zero-length cusp.
    sectionArcs.sort();
    final uniqueSectionArcs = <double>[];
    for (final sectionArc in sectionArcs) {
      if (uniqueSectionArcs.isEmpty ||
          sectionArc - uniqueSectionArcs.last > .000001) {
        uniqueSectionArcs.add(sectionArc);
      }
    }
    // Build each cross-section once inside this batch. Neighboring batches use
    // the same absolute-arc frame and meet at the same coordinates; their
    // internal boundary is not antialiased a second time by the batch paint.
    final sectionBases = <int>[];
    void addSection(double arc,
        {bool head = false,
        bool tail = false,
        double capProgress = 0,
        _PawFilamentArcSample? frame,
        double? turnProgress}) {
      final base = positions.length;
      appendSection(arc,
          head: head,
          tail: tail,
          capProgress: capProgress,
          frame: frame,
          turnProgress: turnProgress);
      sectionBases.add(
        positions.length - base == crossSection.length ? base : -1,
      );
    }

    if (!stroke.isClosed && visibleStart <= .000001) {
      for (final fraction in const [1.0, .98, .92, .82, .68, .5, .3, .1]) {
        addSection(0, head: true, capProgress: fraction);
      }
    }
    // Resolve the rotation of a tight turn before connecting its offsets.
    // Fixed arc steps can skip almost an entire semicircle when the material
    // center slows at a reversal, leaving one large pointed triangle.
    void addInterval(double a, double b, int depth) {
      final first = turnFrame(a, 1);
      final last = turnFrame(b, 0);
      final middle = (a + b) * .5;
      final mid = contactFrame(middle);
      if (first != null &&
          last != null &&
          mid != null &&
          depth < 6 &&
          (_DabInstanceEvaluator._directionTurnRadians(
                      first.direction, mid.direction) >
                  .12 ||
              _DabInstanceEvaluator._directionTurnRadians(
                      mid.direction, last.direction) >
                  .12)) {
        addInterval(a, middle, depth + 1);
        addInterval(middle, b, depth + 1);
      } else {
        addSection(b, frame: last);
      }
    }

    for (var section = 0; section < uniqueSectionArcs.length; section++) {
      final arc = uniqueSectionArcs[section];
      if (section == 0) {
        addSection(arc, frame: turnFrame(arc, 0));
      } else {
        addInterval(uniqueSectionArcs[section - 1], arc, 0);
      }
      final turn = turns[arc];
      // A boundary join belongs to the following command exactly once. The
      // preceding command ends at its incoming crossbar; the next starts there
      // and rotates through the original profile before following the path.
      if (turn != null && arc < visibleEnd - .000001) {
        final divisions = (turn.radians.abs() / .12).ceil();
        for (var i = 1; i <= divisions; i++) {
          addSection(arc,
              frame: turnFrame(arc, i / divisions),
              turnProgress: i / divisions);
        }
      }
    }
    if (!stroke.isClosed && visibleEnd >= stroke.renderEndArc - .000001) {
      for (final fraction in const [.1, .3, .5, .68, .82, .92, .98, 1.0]) {
        addSection(stroke.renderEndArc, tail: true, capProgress: fraction);
      }
    }
    for (var section = 0; section < sectionBases.length - 1; section++) {
      final firstBase = sectionBases[section];
      final secondBase = sectionBases[section + 1];
      if (firstBase >= 0 && secondBase >= 0) {
        for (var band = 0; band < crossSection.length - 1; band++) {
          indices.addAll(<int>[
            firstBase + band,
            secondBase + band,
            secondBase + band + 1,
            firstBase + band,
            secondBase + band + 1,
            firstBase + band + 1,
          ]);
        }
      }
    }
  }
}
