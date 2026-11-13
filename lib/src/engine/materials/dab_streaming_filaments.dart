part of '../../streaming_dab_brush.dart';

extension _DabStreamingFilaments on PawStreamingDabRenderCache {
  void _appendStreamingFilaments({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required double startArc,
    required double endArc,
  }) {
    final layers = stroke.definition.template.streamingFilamentLayers;
    if (layers.isEmpty || endArc <= startArc) return;
    final renderEndArc = stroke.renderEndArc;
    if (renderEndArc <= startArc) return;
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x741a;
    // Root motion, current endpoints, and finite past endpoints all share one
    // batch-local absolute-arc table. Lane count only grows bounded mesh work.
    final arcSamples = <double, _PawFilamentArcSample?>{};
    _PawFilamentArcSample? sampleAt(double arc) => arcSamples.putIfAbsent(
          arc,
          () => _filamentSampleAtArc(stroke, arc),
        );
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      if (layer.countPerRoot == 0) continue;
      final layerHashSeed = seed ^ (layerIndex + 1) * 0x45d9f3b;
      final groomedFrames = <double, PawPersistentLaneGroomingFrame>{};

      PawPersistentLaneGroomingFrame groomedFrameAt(
        double arc,
        _PawFilamentArcSample current,
      ) =>
          groomedFrames.putIfAbsent(arc, () {
            final pastArc = layer.grooming.pastArcFor(
              absoluteArc: arc,
              brushSize: stroke.brushSize,
            );
            final past = sampleAt(pastArc) ?? current;
            return layer.grooming.evaluate(
              currentDirection: current.direction,
              pastDirection: past.direction,
              absoluteArc: arc,
              brushSize: stroke.brushSize,
              signedCurvature: current.motion.signedCurvature,
            );
          });

      final rootPeriod =
          math.max(.25, stroke.brushSize * layer.rootSpacingFactor);
      // Roots can be longer under pressure and the bounded response. Search
      // that complete overlap so a root never disappears at a chunk boundary.
      final maximumLength = stroke.brushSize *
          layer.lengthFactors.maximum *
          stroke.definition.emission.pressureSizeMaxFactor *
          stroke.definition.emission.dynamics.maximumFilamentLengthResponse;
      // Root ownership is based only on its absolute root arc. A root is
      // emitted once, including its whole visible range, so chunk boundaries
      // cannot change the mesh segmentation or alpha blending of a fiber.
      final firstRoot = startArc <= 0
          ? (-maximumLength / rootPeriod).floor() - 1
          : (startArc / rootPeriod).floor() - 1;
      final lastRoot = (endArc / rootPeriod).ceil();
      for (var rootIndex = firstRoot; rootIndex <= lastRoot; rootIndex++) {
        final rootHash = layer.familyHashForRoot(
          layerHashSeed: layerHashSeed,
          rootIndex: rootIndex,
        );
        final rootArc = layer.rootArcFor(
          brushSize: stroke.brushSize,
          rootIndex: rootIndex,
          familyHash: rootHash,
        );
        final ownsRoot = rootArc >= startArc && rootArc < endArc;
        if (!ownsRoot && !(startArc <= 0 && rootArc < 0)) continue;
        final rootMotion = sampleAt(math.max(0.0, rootArc))?.motion;
        if (rootMotion == null) continue;
        final rootDynamics = _evaluateDynamics(
          dynamics: stroke.definition.emission.dynamics,
          motion: rootMotion,
          brushSize: stroke.brushSize,
          hash: rootHash,
        );
        final lanes = <_PawFilamentLanePlan>[];
        for (var filament = 0; filament < layer.countPerRoot; filament++) {
          final filamentHash = PawDabResource._hash(
            layerHashSeed,
            rootIndex * 97 + filament,
          );
          final length = stroke.brushSize *
              layer.lengthFactors.sample(layer.coherentUnitSample(
                familyHash: rootHash,
                filamentHash: filamentHash,
                window: 11,
              )) *
              _DabInstanceEvaluator._pressureSizeForMotion(
                  stroke.definition.emission, rootMotion) *
              rootDynamics.filamentLength.clamp(.05, 2.0);
          final tipArc = rootArc + length;
          final ownsLeadingRoot = startArc <= 0 && rootArc < 0 && tipArc > 0;
          if (!ownsRoot && !ownsLeadingRoot) continue;
          final clippedStartArc = math.max(0.0, rootArc);
          final clippedEndArc = math.min(renderEndArc, tipArc);
          if (clippedEndArc <= clippedStartArc + .000001) continue;
          final uniform = layer.countPerRoot == 1
              ? 0.0
              : filament / (layer.countPerRoot - 1) * 2 - 1;
          final signedLane = uniform.sign *
              math.pow(uniform.abs(), layer.centerDensityExponent).toDouble();
          final edge = signedLane.abs();
          final coherentSignedLane = layer.coherentLateralUnit(
            familyHash: rootHash,
            individualUnit: signedLane,
          );
          final stableLaneOffset = coherentSignedLane *
              stroke.brushSize *
              layer.spreadFactor *
              _DabInstanceEvaluator._pressureSizeForMotion(
                stroke.definition.emission,
                rootMotion,
              ) *
              rootDynamics.filamentSpread.clamp(.05, 2.0) /
              2;
          final rootOffsetJitter = (layer.coherentUnitSample(
                    familyHash: rootHash,
                    filamentHash: filamentHash,
                    window: 17,
                  ) -
                  .5) *
              stroke.brushSize *
              layer.spreadFactor *
              _DabInstanceEvaluator._pressureSizeForMotion(
                stroke.definition.emission,
                rootMotion,
              ) *
              rootDynamics.filamentSpread.clamp(.05, 2.0) *
              .08;
          final laneOffset = stableLaneOffset + rootOffsetJitter;
          final rootWidth = stroke.brushSize *
              layer.widthFactors.sample(layer.coherentUnitSample(
                familyHash: rootHash,
                filamentHash: filamentHash,
                window: 19,
              )) *
              (1 - edge * .35);
          final bendPhase = layer.coherentAngleSample(
            familyHash: rootHash,
            filamentHash: filamentHash,
            window: 23,
          );
          final directionOffset =
              layer.grooming.preferredDirectionOffsetRadians +
                  (layer.coherentUnitSample(
                            familyHash: rootHash,
                            filamentHash: filamentHash,
                            window: 29,
                          ) -
                          .5) *
                      2 *
                      layer.directionJitterRadians;
          final maximumSegmentLength = math.max(
            .25,
            stroke.brushSize * layer.segmentLengthFactor,
          );
          // Absolute arc divisions make both geometry and lookup work invariant
          // to sealed/tail chunk boundaries.
          final firstDivision =
              (clippedStartArc / maximumSegmentLength).floor();
          final lastDivision = (clippedEndArc / maximumSegmentLength).ceil();
          final divisionArcs = <double>[clippedStartArc];
          final rootFadeEnd = rootArc + length * layer.rootFadeFraction;
          if (rootFadeEnd > clippedStartArc && rootFadeEnd < clippedEndArc) {
            divisionArcs.add(rootFadeEnd);
          }
          for (var division = firstDivision + 1;
              division < lastDivision;
              division++) {
            final arc = division * maximumSegmentLength;
            if (arc > clippedStartArc && arc < clippedEndArc) {
              divisionArcs.add(arc);
            }
          }
          divisionArcs.sort();
          divisionArcs.add(clippedEndArc);
          lanes.add(_PawFilamentLanePlan(
            hash: filamentHash,
            rootArc: rootArc,
            length: length,
            laneOffset: laneOffset,
            stableLaneOffset: stableLaneOffset,
            rootOffsetJitter: rootOffsetJitter,
            rootWidth: rootWidth,
            bendPhase: bendPhase,
            directionOffset: directionOffset,
            divisionArcs: divisionArcs,
          ));
        }
        if (lanes.isEmpty) continue;
        lastFilamentRootCount++;
        lastFilamentLaneCount += lanes.length;
        for (final lane in lanes) {
          _PawFilamentLanePoint? lanePointAt(double arc) {
            final sample = sampleAt(arc);
            if (sample == null) return null;
            final fraction =
                ((arc - lane.rootArc) / lane.length).clamp(0.0, 1.0);
            final taper = math.pow(fraction, layer.taperExponent).toDouble();
            final dynamics = _evaluateDynamics(
              dynamics: stroke.definition.emission.dynamics,
              motion: sample.motion,
              brushSize: stroke.brushSize,
              hash: lane.hash,
            );
            final frame =
                layer.grooming.isIdentity ? null : groomedFrameAt(arc, sample);
            final normal = frame?.normal ?? sample.normal;
            final bendOffset = math.sin(fraction * math.pi + lane.bendPhase) *
                stroke.brushSize *
                layer.bendFactor;
            final directionOffset =
                math.tan(lane.directionOffset) * (arc - lane.rootArc);
            final offset = frame == null
                ? lane.laneOffset + bendOffset + directionOffset
                : lane.stableLaneOffset *
                        frame.splayScaleFor(
                          (lane.stableLaneOffset /
                                  math.max(
                                    .000001,
                                    stroke.brushSize * layer.spreadFactor / 2,
                                  ))
                              .clamp(-1.0, 1.0),
                        ) +
                    lane.rootOffsetJitter +
                    bendOffset +
                    directionOffset;
            final width = lane.rootWidth *
                _DabInstanceEvaluator._pressureSizeForMotion(
                    stroke.definition.emission, sample.motion) *
                dynamics.size *
                (1 - layer.widthTaper * taper);
            final rootFade = layer.rootFadeFraction == 0
                ? 1.0
                : (fraction / layer.rootFadeFraction).clamp(0.0, 1.0);
            final center = sample.point + normal * offset;
            final color = _DabInstanceEvaluator._colorForMotion(
              stroke: stroke,
              motion: sample.motion,
              hash: lane.hash,
              coverage: layer.coverage *
                  layer.pressureDensityCoverage(
                    pressure: sample.motion.pressure,
                    filamentHash: lane.hash,
                  ) *
                  (1 - layer.opacityTaper * taper) *
                  rootFade,
              canvasPoint: center,
            );
            return _PawFilamentLanePoint(
              arc: arc,
              center: center,
              normal: normal,
              normalDistance: offset,
              width: width,
              color: color,
            );
          }

          var previous = lanePointAt(lane.divisionArcs.first);
          for (var division = 1;
              division < lane.divisionArcs.length;
              division++) {
            final current = lanePointAt(lane.divisionArcs[division]);
            if (previous != null && current != null) {
              _DabPersistentLanes._appendFilamentLaneSegment(
                positions: positions,
                textureCoordinates: textureCoordinates,
                colors: colors,
                indices: indices,
                stroke: stroke,
                first: previous,
                second: current,
              );
              lastFilamentSegmentCount++;
            }
            previous = current;
          }
        }
      }
    }
  }

  // A tap has no centerline interval to query. Streaming fibers therefore use
  // one deterministic local tuft here only; ordinary Dabs continue to use the
  // absolute-arc emitter above and never repeat this geometry.
  static void _appendStreamingFilamentTap({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required Offset point,
    required Offset direction,
  }) {
    final layers = stroke.definition.template.streamingFilamentLayers;
    if (layers.isEmpty) return;
    final normal = Offset(-direction.dy, direction.dx);
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x741a;
    final tapMotion =
        stroke.emissionMotionSampleAtArc(0) ?? stroke.tapMotionSample;
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final layerHashSeed = seed ^ (layerIndex + 1) * 0x45d9f3b;
      final familyHash = PawDabResource._hash(layerHashSeed, 0);
      for (var filament = 0; filament < layer.countPerRoot; filament++) {
        final hash = PawDabResource._hash(
          layerHashSeed,
          filament,
        );
        final uniform = layer.countPerRoot == 1
            ? 0.0
            : filament / (layer.countPerRoot - 1) * 2 - 1;
        final distributed = uniform.sign *
            math.pow(uniform.abs(), layer.centerDensityExponent).toDouble();
        final coherentDistributed = layer.coherentLateralUnit(
          familyHash: familyHash,
          individualUnit: distributed,
        );
        final dynamics = _evaluateDynamics(
          dynamics: stroke.definition.emission.dynamics,
          motion: tapMotion,
          brushSize: stroke.brushSize,
          hash: hash,
        );
        final pressureSize = _DabInstanceEvaluator._pressureSizeForMotion(
            stroke.definition.emission, tapMotion);
        final length = stroke.brushSize *
            layer.lengthFactors.sample(layer.coherentUnitSample(
              familyHash: familyHash,
              filamentHash: hash,
              window: 11,
            )) *
            pressureSize *
            dynamics.filamentLength.clamp(.05, 2.0);
        final rootOffset = coherentDistributed *
                stroke.brushSize *
                layer.spreadFactor *
                pressureSize *
                dynamics.filamentSpread.clamp(.05, 2.0) /
                2 +
            (layer.coherentUnitSample(
                      familyHash: familyHash,
                      filamentHash: hash,
                      window: 17,
                    ) -
                    .5) *
                stroke.brushSize *
                layer.spreadFactor *
                pressureSize *
                dynamics.filamentSpread.clamp(.05, 2.0) *
                .08;
        final directionOffset = (layer.coherentUnitSample(
                  familyHash: familyHash,
                  filamentHash: hash,
                  window: 29,
                ) -
                .5) *
            2 *
            layer.directionJitterRadians;
        final shearedDirection = direction * math.cos(layer.shearAngleRadians) +
            normal * math.sin(layer.shearAngleRadians);
        final fiberDirection = _DabInstanceEvaluator._normalized(
          shearedDirection + normal * math.tan(directionOffset),
        );
        final fiberNormal = Offset(-fiberDirection.dy, fiberDirection.dx);
        final bend = (layer.coherentUnitSample(
                  familyHash: familyHash,
                  filamentHash: hash,
                  window: 23,
                ) -
                .5) *
            2 *
            stroke.brushSize *
            layer.bendFactor;
        final root =
            point + normal * rootOffset - fiberDirection * length * .16;
        final middle =
            root + fiberDirection * length * .56 + fiberNormal * bend;
        final tip = root + fiberDirection * length + fiberNormal * bend * .25;
        final fadeFraction = layer.rootFadeFraction;
        final fade = fadeFraction == 0
            ? root
            : Offset.lerp(root, middle, fadeFraction / .56)!;
        final width = stroke.brushSize *
            layer.widthFactors.sample(layer.coherentUnitSample(
              familyHash: familyHash,
              filamentHash: hash,
              window: 19,
            )) *
            pressureSize *
            dynamics.size *
            (1 - distributed.abs() * .35);
        final rootColor = _DabInstanceEvaluator._colorForMotion(
          stroke: stroke,
          motion: tapMotion,
          hash: hash,
          coverage: layer.coverage *
              layer.pressureDensityCoverage(
                pressure: tapMotion.pressure,
                filamentHash: hash,
              ),
          canvasPoint: root,
        );
        final fadedRootColor = rootColor.withValues(
          alpha: fadeFraction == 0 ? rootColor.a : 0,
        );
        final fadeColor = rootColor.withValues(
          alpha: rootColor.a *
              (1 -
                      layer.opacityTaper *
                          math.pow(fadeFraction, layer.taperExponent))
                  .clamp(0.0, 1.0),
        );
        final middleColor = rootColor.withValues(
          alpha: rootColor.a *
              (1 - layer.opacityTaper * math.pow(.56, layer.taperExponent))
                  .clamp(0.0, 1.0),
        );
        final tipColor = rootColor.withValues(
          alpha: rootColor.a * (1 - layer.opacityTaper),
        );
        void appendSegment(
          Offset first,
          Offset second,
          double firstWidth,
          double secondWidth,
          Color firstColor,
          Color secondColor,
          double firstArc,
          double secondArc,
        ) {
          final base = positions.length;
          final firstNormal = Offset(
              -_DabInstanceEvaluator._normalized(second - first).dy,
              _DabInstanceEvaluator._normalized(second - first).dx);
          final secondNormal = firstNormal;
          final corners = <Offset>[
            first - firstNormal * firstWidth / 2,
            first + firstNormal * firstWidth / 2,
            second - secondNormal * secondWidth / 2,
            second + secondNormal * secondWidth / 2,
          ];
          positions.addAll(corners);
          textureCoordinates.addAll(<Offset>[
            for (final corner in corners)
              _DabInstanceEvaluator._grainCoordinate(
                grain: stroke.definition.grain,
                rasterProgram: stroke.environment.rasterProgram,
                canvasPoint: corner,
                arc: firstArc + (corner - first).distance,
                normalDistance: 0,
                brushSize: stroke.brushSize,
              ),
          ]);
          colors.addAll(
              <Color>[firstColor, firstColor, secondColor, secondColor]);
          indices.addAll(
              <int>[base, base + 2, base + 3, base, base + 3, base + 1]);
        }

        if (fadeFraction > 0) {
          final fadeTaper = math.pow(fadeFraction, layer.taperExponent);
          final fadeWidth = width * (1 - layer.widthTaper * fadeTaper);
          appendSegment(root, fade, width, fadeWidth, fadedRootColor, fadeColor,
              0, length * fadeFraction);
          appendSegment(
              fade,
              middle,
              fadeWidth,
              width *
                  (1 - layer.widthTaper * math.pow(.56, layer.taperExponent)),
              fadeColor,
              middleColor,
              length * fadeFraction,
              length * .56);
        } else {
          appendSegment(
              root,
              middle,
              width,
              width *
                  (1 - layer.widthTaper * math.pow(.56, layer.taperExponent)),
              rootColor,
              middleColor,
              0,
              length * .56);
        }
        appendSegment(
            middle,
            tip,
            width * (1 - layer.widthTaper * math.pow(.56, layer.taperExponent)),
            width * (1 - layer.widthTaper),
            middleColor,
            tipColor,
            length * .56,
            length);
      }
    }
  }
}
