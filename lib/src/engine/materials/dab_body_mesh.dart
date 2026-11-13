part of '../../streaming_dab_brush.dart';

extension _DabBodyMesh on PawStreamingDabRenderCache {
  void _appendBodyMesh({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required Offset point,
    required Offset direction,
    required double arc,
    required double pressureSize,
    required PawBrushKernelOutput kernelOutput,
    required Color color,
    required PawStreamingMotionSample motion,
    required double dryMediaCoverage,
    required bool linearizeOverlap,
    PawWetMediaTileAccumulator? wetAccumulator,
  }) {
    final footprint = stroke.definition.template.footprint;
    if (footprint.centerCoverage <= 0 && footprint.edgeCoverage <= 0) return;
    const baseSegments = 24;
    const maximumContactSegments = 48;
    const maximumContactRings = 6;
    final halfLength = stroke.brushSize *
        pressureSize *
        footprint.lengthFactor *
        kernelOutput.lengthScale /
        2;
    final halfWidth = stroke.brushSize *
        pressureSize *
        footprint.widthFactor *
        kernelOutput.widthScale /
        2;
    final normal = Offset(-direction.dy, direction.dx);
    final base = positions.length;
    final paperContact = stroke.definition.paperContact;
    final coverageTransfer = stroke.definition.coverageTransfer;
    final paperDetailCarrier =
        stroke.environment.rasterProgram?.highFrequencyCoordinateSpace ==
                PawBrushRasterCoordinateSpace.canvasFixed &&
            stroke.environment.rasterProgram
                    ?.hasRole(PawBrushRasterRoleKind.paper) ==
                true;
    final contactDynamics = paperContact.isEnabled
        ? _evaluateDynamics(
            dynamics: stroke.definition.emission.dynamics,
            motion: motion,
            brushSize: stroke.brushSize,
            hash: stroke.seed.value,
          )
        : null;
    final requiresSpatialPaperVertices =
        contactDynamics != null && !paperDetailCarrier;
    final usesContactSimulation =
        kernelOutput.tipFieldKind != PawBrushTipFieldKind.none;
    final unifiedProgram = stroke.environment.unifiedProgram;
    final shapeField = usesContactSimulation
        ? unifiedProgram?.shape ??
            switch (kernelOutput.tipFieldKind) {
              PawBrushTipFieldKind.fur => _furShapeField,
              PawBrushTipFieldKind.ink => _inkShapeField,
              PawBrushTipFieldKind.soft => _softShapeField,
              PawBrushTipFieldKind.none => _circleShapeField,
            }
        : null;
    final rasterProgram = stroke.environment.rasterProgram;
    final hasRasterShape =
        rasterProgram?.hasRole(PawBrushRasterRoleKind.shape) == true;
    final hasRasterGrain =
        rasterProgram?.hasRole(PawBrushRasterRoleKind.grain) == true;
    final pixelTransfer = PawDabResource._usesContactPixelTransfer(
        stroke.definition,
        rasterProgram: rasterProgram);
    if (usesContactSimulation) {
      _brushStampScratch.beginDab(
        rotation: math.atan2(direction.dy, direction.dx),
        pressure: motion.pressure,
        grainStrength: kernelOutput.grainResponse,
        deposition: kernelOutput.deposition,
        edgeSoftness: kernelOutput.edgeSoftness,
        materialDensity: kernelOutput.materialDensity,
      );
    }
    Offset textureCoordinate(Offset position) {
      if (pixelTransfer) return Offset.zero;
      final displacement = position - point;
      return _DabInstanceEvaluator._grainCoordinate(
        grain: stroke.definition.grain,
        rasterProgram: stroke.environment.rasterProgram,
        canvasPoint: position,
        arc: arc +
            displacement.dx * direction.dx +
            displacement.dy * direction.dy,
        normalDistance:
            displacement.dx * normal.dx + displacement.dy * normal.dy,
        brushSize: stroke.brushSize,
      );
    }

    Color coverageColor(double radial, Offset canvasPoint) {
      final wetMedia = stroke.definition.wetMedia;
      final wetPaperSample = wetMedia.enabled
          ? stroke.environment.paper.sample(canvasPoint)
          : null;
      final rawPaperCoverage = contactDynamics == null
          ? 1.0
          : pixelTransfer || paperDetailCarrier
              ? paperContact.coarseDepositionAt(
                  paper: stroke.environment.paper,
                  canvasPoint: canvasPoint,
                )
              : paperContact.coverageAt(
                  paper: stroke.environment.paper,
                  canvasPoint: canvasPoint,
                  pressure: motion.pressure,
                  deposition: contactDynamics.deposition,
                );
      final footprintCoverage = footprint.centerCoverage +
          (footprint.edgeCoverage - footprint.centerCoverage) *
              radial.clamp(0.0, 1.0);
      final displacementX = canvasPoint.dx - point.dx;
      final displacementY = canvasPoint.dy - point.dy;
      final along = displacementX * direction.dx + displacementY * direction.dy;
      final signedNormal =
          displacementX * normal.dx + displacementY * normal.dy;
      final normalizedAlong = along / math.max(.0001, halfLength);
      final normalizedNormal = signedNormal / math.max(.0001, halfWidth);
      final kernelCoverage = kernelOutput.coverageAt(
        radial: radial,
        normalizedAlong: normalizedAlong,
      );
      final proceduralShape = usesContactSimulation
          ? shapeField!.coverage(
              normalizedAlong,
              normalizedNormal,
              0,
              motion.pressure,
            )
          : 1.0;
      final bitmapShape = hasRasterShape
          ? rasterProgram!.sample(
              role: PawBrushRasterRoleKind.shape,
              canvasX: canvasPoint.dx,
              canvasY: canvasPoint.dy,
              absoluteArc: arc + along,
              signedNormal: signedNormal,
              brushWidth: stroke.brushSize,
            )
          : 1.0;
      final needsGrainSample =
          usesContactSimulation || kernelOutput.directionalGrainStrength > 0;
      final grainSample = needsGrainSample && hasRasterGrain
          ? rasterProgram!.sample(
              role: PawBrushRasterRoleKind.grain,
              canvasX: canvasPoint.dx,
              canvasY: canvasPoint.dy,
              absoluteArc:
                  arc + along * kernelOutput.directionalGrainAlongScale,
              signedNormal:
                  signedNormal * kernelOutput.directionalGrainNormalScale,
              brushWidth: stroke.brushSize,
            )
          : .5;
      final directionalGrain =
          usesContactSimulation || kernelOutput.directionalGrainStrength <= 0
              ? 1.0
              : kernelOutput.directionalGrainCoverage(grainSample);
      if (usesContactSimulation) {
        // Contact simulation is renderer-local to material tips. Ordinary
        // Round/Crayon/Marker/Eraser DABs retain the proven lightweight path.
        _brushStampScratch.evaluateContact(
          shapeCoverage: footprintCoverage *
              kernelCoverage *
              (1 +
                  (proceduralShape - 1) *
                      kernelOutput.tipMaskStrength.clamp(0.0, 1.0)) *
              bitmapShape,
          grainSample: grainSample,
          radial: radial,
        );
      }
      final contactCoverage = usesContactSimulation
          ? _brushStampScratch.coverage * _brushStampScratch.pigmentAmount
          : footprintCoverage * kernelCoverage * directionalGrain;
      final remappedPaperContact =
          coverageTransfer.remapPaperContact(rawPaperCoverage);
      final dryWax = stroke.definition.dryWax;
      double targetCoverage;
      if (dryWax.enabled) {
        final waxGrainAndScrape = stroke.environment.rasterProgram?.sample(
              role: PawBrushRasterRoleKind.grain,
              canvasX: canvasPoint.dx,
              canvasY: canvasPoint.dy,
              absoluteArc: arc + along,
              signedNormal: signedNormal,
              brushWidth: stroke.brushSize,
            ) ??
            1;
        final waxCoverageResponse = dryWax.waxCoverageResponse(
          paperContact: remappedPaperContact,
          pressure: motion.pressure,
          waxGrainAndScrape: waxGrainAndScrape,
        );
        final thicknessResponse = PawDabResource._usesContactPixelTransfer(
                stroke.definition,
                rasterProgram: rasterProgram)
            ? dryWax.linearWaxMass
            : dryWax.waxThicknessResponse;
        final waxThicknessResponse = thicknessResponse(
          sourceAlpha: color.a,
          pressure: motion.pressure,
        );
        targetCoverage =
            (contactCoverage * waxCoverageResponse * waxThicknessResponse)
                .clamp(0.0, 1.0)
                .toDouble();
      } else {
        final wetTile = wetAccumulator?.sampleAt(canvasPoint);
        final wetCoverage = wetPaperSample == null
            ? 1.0
            : wetMedia.contactCoverage(
                paper: wetPaperSample,
                definition: stroke.environment.paper.definition,
                radial: radial,
                pressure: motion.pressure,
                tilePigment: wetTile?.pigment ?? 0,
                tileWetness: wetTile?.wetness ?? 0,
              );
        targetCoverage = (color.a *
                contactCoverage *
                remappedPaperContact *
                wetCoverage *
                dryMediaCoverage)
            .clamp(0.0, 1.0)
            .toDouble();
      }
      if (kernelOutput.tipFieldKind == PawBrushTipFieldKind.fur &&
          stroke.renderEndArc > stroke.brushSize * .9) {
        // A prepared bristle stamp has pointed local caps, but overlapping
        // stamps can still round the silhouette at the two stroke endpoints.
        // Apply a renderer-local contact envelope over the retained tail. It
        // is derived only from absolute arc, so preview and commit are equal
        // and PawPlannedDab/cache ownership remain unchanged.
        final contactArc = arc + along;
        targetCoverage *=
            stroke.environment.unifiedProgram?.endpoint?.progressAt(
                  closed: stroke.isClosed,
                  absoluteArc: contactArc,
                  renderEndArc: stroke.renderEndArc,
                  brushSize: stroke.brushSize,
                ) ??
                1;
      }
      final alpha = linearizeOverlap
          ? coverageTransfer.linearizeDabCoverage(targetCoverage)
          : targetCoverage;
      return pixelTransfer
          ? _DabInstanceEvaluator._contactStateColor(
              direction,
              stroke is PawStreamingDabStroke ? stroke.settlementAtArc(arc) : 1,
              alpha,
              axial: stroke.definition.dryWax.enabled)
          : color.withValues(alpha: alpha);
    }

    positions.add(point);
    textureCoordinates.add(textureCoordinate(point));
    colors.add(coverageColor(0, point));

    // drawVertices does not provide a screen-space coverage fringe around a
    // hard mesh boundary. The compiler can request a logical-pixel analytic
    // fringe for any eligible local tip; this is not owned by a brush id.
    final preparedEdgeAa = stroke.environment.unifiedProgram?.compiledRenderPlan
            .preparedEdgeAntialiasLogicalPixels ??
        0;
    final analyticEdgeAntialias = preparedEdgeAa > 0
        ? (preparedEdgeAa / math.max(.0001, math.min(halfLength, halfWidth)))
            .clamp(.025, .24)
            .toDouble()
        : 0.0;
    final softness = math
        .max(
          math.max(footprint.outerSoftnessFactor, kernelOutput.edgeSoftness),
          analyticEdgeAntialias,
        )
        .clamp(0.0, .48);
    final materialScale = softness == 0 ? 1.0 : 1 - softness;
    final roughnessReach =
        1 + stroke.definition.emission.footprintEdgeRoughness;
    final requiresDirectionalFieldVertices =
        kernelOutput.directionalGrainStrength > 0;
    final requiresDensityFieldVertices = kernelOutput.radialProfileStrength > 0;
    final materialSegments = switch (kernelOutput.tipFieldKind) {
      // Shape/grain/deposition are continuous scalar fields. Sampling them at
      // the former dense sampling multiplied CPU mesh work without adding stable
      // screen-space detail: the prepared raster grain already carries the
      // high-frequency material signal between these control vertices.
      PawBrushTipFieldKind.fur => 24,
      PawBrushTipFieldKind.ink => 24,
      PawBrushTipFieldKind.soft => 24,
      PawBrushTipFieldKind.none => baseSegments,
    };
    final materialRings = switch (kernelOutput.tipFieldKind) {
      PawBrushTipFieldKind.fur => 3,
      PawBrushTipFieldKind.ink => 2,
      PawBrushTipFieldKind.soft => 2,
      PawBrushTipFieldKind.none => 1,
    };
    final segments = requiresSpatialPaperVertices
        ? math.max(
            materialSegments,
            ((4 *
                        (halfLength + halfWidth) *
                        materialScale *
                        roughnessReach /
                        paperContact.maximumSampleSpacing)
                    .ceil())
                .clamp(baseSegments, maximumContactSegments)
                .toInt(),
          )
        : math.max(
            materialSegments,
            requiresDirectionalFieldVertices ? materialSegments : baseSegments,
          );
    final radialRings = requiresSpatialPaperVertices
        ? math.max(
            materialRings,
            ((math.max(halfLength, halfWidth) *
                        materialScale *
                        roughnessReach /
                        paperContact.maximumSampleSpacing)
                    .ceil())
                .clamp(1, maximumContactRings)
                .toInt(),
          )
        : math.max(
            materialRings,
            requiresDirectionalFieldVertices
                ? materialRings
                : requiresDensityFieldVertices
                    ? materialRings
                    : 1,
          );

    Offset localBoundaryVector(int index, double scale) {
      final angle = index / segments * math.pi * 2;
      final cosValue = math.cos(angle);
      final sinValue = math.sin(angle);
      final edgeNoise = stroke.definition.emission.footprintEdgeRoughness == 0
          ? 1.0
          : 1 +
              math.sin(
                    angle *
                            stroke.definition.emission
                                .footprintEdgeRoughnessFrequency +
                        stroke.seed.value * .000031 +
                        point.dx * .11 +
                        point.dy * .07,
                  ) *
                  stroke.definition.emission.footprintEdgeRoughness;
      final x = cosValue.sign *
          math.pow(cosValue.abs(), 2 / footprint.shapeExponent) *
          halfLength *
          scale *
          edgeNoise;
      final y = sinValue.sign *
          math.pow(sinValue.abs(), 2 / footprint.shapeExponent) *
          halfWidth *
          scale *
          edgeNoise;
      return direction * x.toDouble() + normal * y.toDouble();
    }

    final edgeResponse = footprint.edgeResponse;
    final edgeInsets = edgeResponse.isIdentity
        ? null
        : <double>[
            for (var index = 0; index < segments; index++)
              (() {
                final local = localBoundaryVector(index, materialScale);
                return edgeResponse.inwardInsetFactorAt(
                  absoluteArc:
                      arc + local.dx * direction.dx + local.dy * direction.dy,
                  brushSize: stroke.brushSize,
                  canvasPoint: point + local,
                  strokeSeed:
                      stroke.seed.value ^ stroke.definition.identitySalt,
                  paperSeed: stroke.environment.paper.definition.seed,
                );
              })(),
          ];

    Offset boundaryPoint(
      int index,
      double scale, {
      required double radial,
      bool applyEdgeResponse = true,
    }) {
      final inset = edgeInsets == null || !applyEdgeResponse
          ? 0.0
          : edgeInsets[index] * edgeResponse.edgeWeightAt(radial);
      return point + localBoundaryVector(index, math.max(0.0, scale - inset));
    }

    for (var ring = 1; ring <= radialRings; ring++) {
      final radial = ring / radialRings;
      final ringStart = positions.length;
      for (var index = 0; index < segments; index++) {
        final boundary = boundaryPoint(
          index,
          materialScale * radial,
          radial: radial,
        );
        positions.add(boundary);
        textureCoordinates.add(textureCoordinate(boundary));
        colors.add(coverageColor(radial, boundary));
      }
      if (ring == 1) {
        for (var index = 0; index < segments; index++) {
          indices
            ..add(base)
            ..add(ringStart + index)
            ..add(ringStart + (index + 1) % segments);
        }
        continue;
      }
      final previousStart = ringStart - segments;
      for (var index = 0; index < segments; index++) {
        final next = (index + 1) % segments;
        indices
          ..add(previousStart + index)
          ..add(ringStart + index)
          ..add(ringStart + next)
          ..add(previousStart + index)
          ..add(ringStart + next)
          ..add(previousStart + next);
      }
    }
    if (softness == 0) return;

    final innerStart = positions.length - segments;
    final outerStart = positions.length;
    for (var index = 0; index < segments; index++) {
      final boundary = boundaryPoint(
        index,
        1,
        radial: 1,
        applyEdgeResponse: false,
      );
      positions.add(boundary);
      textureCoordinates.add(textureCoordinate(boundary));
      colors.add(coverageColor(1, boundary).withValues(alpha: 0));
    }
    for (var index = 0; index < segments; index++) {
      final next = (index + 1) % segments;
      indices
        ..add(innerStart + index)
        ..add(outerStart + index)
        ..add(outerStart + next)
        ..add(innerStart + index)
        ..add(outerStart + next)
        ..add(innerStart + next);
    }
  }

  void _appendHybridCarrier({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required double startArc,
    required double endArc,
    required PawBrushBehavior? behavior,
    required PawBrushKernel kernel,
    required PawUnifiedBrushCarrierProfile profile,
  }) {
    if (endArc <= startArc || stroke.renderEndArc <= startArc) return;
    final step = math.max(
      .5,
      stroke.brushSize * profile.maximumSegmentLengthFactor,
    );
    final visibleEnd = math.min(endArc, stroke.renderEndArc);
    final firstOwnedDivision = (startArc / step).ceil();
    final lastOwnedDivision = (visibleEnd / step).ceil();
    if (lastOwnedDivision <= firstOwnedDivision) return;
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x62ca11;
    var sectionCount = 0;
    final sectionVertexCount = profile.crossSection.length;
    for (var division = firstOwnedDivision;
        division <= lastOwnedDivision;
        division++) {
      final arc = math.min(division * step, stroke.renderEndArc);
      final sample = _centerlineSampleAtArc(stroke, arc);
      if (sample == null) continue;
      final previous =
          _centerlineSampleAtArc(stroke, math.max(0.0, arc - step));
      final following = _centerlineSampleAtArc(
        stroke,
        math.min(stroke.renderEndArc, arc + step),
      );
      final hash = PawDabResource._hash(seed, division);
      _tapKernelDabScratch.set(
        point: sample.point,
        tangent: sample.direction,
        hash: hash,
        motion: sample.motion,
      );
      _evaluateKernelInto(
        stroke: stroke,
        dab: _tapKernelDabScratch,
        previousTangent: previous?.direction ?? sample.direction,
        followingTangent: following?.direction ?? sample.direction,
        behavior: behavior,
        kernel: kernel,
      );
      final output = _kernelOutputScratch;
      final pressureSize = _DabInstanceEvaluator._pressureSizeForMotion(
          stroke.definition.emission, sample.motion);
      final endpoint = stroke.environment.unifiedProgram?.endpoint;
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
      final width = stroke.brushSize *
          profile.widthFactor *
          pressureSize *
          output.widthScale.clamp(.5, 1.7) *
          endpointSize;
      // Keep the carrier-local envelope for older authored programs. New
      // presets use the shared endpoint profile for independent size and
      // opacity response across every rendering primitive.
      final taperLength = stroke.brushSize * profile.endpointTaperBrushLengths;
      final legacyCarrierTaper = stroke.isClosed || taperLength <= .0001
          ? 1.0
          : math.min(
              _smoothStep((arc / taperLength).clamp(0.0, 1.0)),
              _smoothStep(
                ((stroke.renderEndArc - arc) / taperLength).clamp(0.0, 1.0),
              ),
            );
      for (var crossIndex = 0;
          crossIndex < profile.crossSection.length;
          crossIndex++) {
        final crossSample = profile.crossSection[crossIndex];
        final edgeWeight =
            ((crossSample.normalFactor.abs() - .24) / .26).clamp(0.0, 1.0);
        final sideRoughness = (PawDabResource._unitWindow(
                      hash,
                      crossSample.normalFactor < 0 ? 11 : 27,
                    ) *
                    2 -
                1) *
            profile.edgeRoughness *
            edgeWeight;
        final signedNormal =
            width * crossSample.normalFactor * (1 + sideRoughness);
        final vertex = sample.point + sample.normal * signedNormal;
        final rawGrain = stroke.environment.rasterProgram?.sample(
              role: PawBrushRasterRoleKind.grain,
              canvasX: vertex.dx,
              canvasY: vertex.dy,
              absoluteArc: arc,
              signedNormal: signedNormal,
              brushWidth: stroke.brushSize,
            ) ??
            1;
        final kernelGrain = output.directionalGrainCoverage(rawGrain);
        final grain =
            1 - profile.grainBreakup + profile.grainBreakup * kernelGrain;
        positions.add(vertex);
        textureCoordinates.add(Offset.zero);
        colors.add(_DabInstanceEvaluator._colorForMotion(
          stroke: stroke,
          motion: sample.motion,
          hash: hash,
          coverage: profile.opacity *
              crossSample.coverage *
              output.coverage.clamp(0.0, 2.0) *
              output.opacityScale.clamp(0.0, 2.0) *
              grain *
              endpointOpacity *
              legacyCarrierTaper,
          canvasPoint: vertex,
          persistentMaterial: PawDabPersistentLaneMaterial.coarseCarrier,
        ));
      }
      if (sectionCount > 0) {
        final previousBase = positions.length - sectionVertexCount * 2;
        final currentBase = positions.length - sectionVertexCount;
        for (var band = 0; band < sectionVertexCount - 1; band++) {
          indices.addAll(<int>[
            previousBase + band,
            currentBase + band,
            currentBase + band + 1,
            previousBase + band,
            currentBase + band + 1,
            previousBase + band + 1,
          ]);
        }
      }
      sectionCount++;
    }
  }
}
