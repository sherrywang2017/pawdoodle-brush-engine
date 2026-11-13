part of '../../streaming_dab_brush.dart';

extension _DabPersistentLanes on PawStreamingDabRenderCache {
  static double _persistentClumpedOffset({
    required PawDabPersistentLaneLayer layer,
    required int laneId,
    required double brushSize,
  }) {
    final uniform =
        layer.laneCount == 1 ? 0.0 : laneId / (layer.laneCount - 1) * 2 - 1;
    final distributed = uniform.sign *
        math.pow(uniform.abs(), layer.centerDensityExponent).toDouble();
    final baseOffset = distributed * brushSize * layer.spreadFactor / 2;
    final clumpIndex = laneId % layer.clumpCount;
    final clumpCenter = layer.clumpCount == 1
        ? 0.0
        : clumpIndex / (layer.clumpCount - 1) * 2 - 1;
    return baseOffset * (1 - layer.clumpStrength) +
        clumpCenter * brushSize * layer.spreadFactor * .5 * layer.clumpStrength;
  }

  void _appendPersistentLanes({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required List<Offset> carrierPositions,
    required List<Offset> carrierTextureCoordinates,
    required List<Color> carrierColors,
    required List<int> carrierIndices,
    required PawDabEmissionSource stroke,
    required double startArc,
    required double endArc,
  }) {
    final layers = stroke.definition.template.persistentLaneLayers;
    if (layers.isEmpty ||
        endArc <= startArc ||
        stroke.renderEndArc <= startArc) {
      return;
    }
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x62c91;
    // Core and guard layers may use different segment grids and look-behind
    // horizons, but every raw absolute-arc query is shared before lane work.
    final samples = <double, _PawFilamentArcSample?>{};
    _PawFilamentArcSample? sampleAt(double arc) => samples.putIfAbsent(
          arc,
          () {
            final result = _centerlineSampleAtArc(stroke, arc);
            if (result != null) lastPersistentArcSampleCount++;
            return result;
          },
        );
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      if (layer.laneCount == 0) continue;
      final layerHashSeed = seed ^ (layerIndex + 1) * 0x45d9f3b;
      final layerPositions =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierPositions
              : positions;
      final layerTextureCoordinates =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierTextureCoordinates
              : textureCoordinates;
      final layerColors =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierColors
              : colors;
      final layerIndices =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierIndices
              : indices;
      final segmentLength =
          math.max(.5, stroke.brushSize * layer.segmentLengthFactor);
      final visibleEnd = math.min(endArc, stroke.renderEndArc);
      // A mesh batch owns a persistent-lane segment by the segment's global
      // absolute-arc start, not by the Dab batch edge. Dab/chunk boundaries
      // may therefore group commands differently, but they can never split a
      // lane quad and introduce a new antialiased seam.
      final firstOwnedDivision = (startArc / segmentLength).ceil();
      final lastOwnedDivision = (visibleEnd / segmentLength).ceil();
      if (lastOwnedDivision <= firstOwnedDivision) continue;

      final ownedSegments = <(double, double)>[
        for (var division = firstOwnedDivision;
            division < lastOwnedDivision;
            division++)
          (
            division * segmentLength,
            math.min((division + 1) * segmentLength, stroke.renderEndArc),
          ),
      ];
      if (ownedSegments.isEmpty) continue;
      final groomedFrames = <double, PawPersistentLaneGroomingFrame>{};

      PawPersistentLaneGroomingFrame groomedFrameAt(
        double arc,
        _PawFilamentArcSample current,
      ) =>
          groomedFrames.putIfAbsent(arc, () {
            final historyLength =
                stroke.brushSize * layer.grooming.lookBehindArcFactor;
            final pastArc = math.max(0.0, arc - historyLength);
            final past = sampleAt(pastArc) ?? current;
            return layer.grooming.evaluate(
              currentDirection: current.direction,
              pastDirection: past.direction,
              absoluteArc: arc,
              brushSize: stroke.brushSize,
              signedCurvature: current.motion.signedCurvature,
            );
          });

      lastPersistentLaneCount += layer.laneCount;
      for (var laneId = 0; laneId < layer.laneCount; laneId++) {
        final hash = PawDabResource._hash(layerHashSeed, laneId);
        final clumpedOffset = _DabPersistentLanes._persistentClumpedOffset(
          layer: layer,
          laneId: laneId,
          brushSize: stroke.brushSize,
        );
        final halfSpread = stroke.brushSize * layer.spreadFactor / 2;
        final effectiveOffsetUnit = halfSpread <= .000001
            ? 0.0
            : (clumpedOffset / halfSpread).clamp(-1.0, 1.0);
        final width = stroke.brushSize *
            layer.widthFactors.sample(PawDabResource._unitWindow(hash, 11));
        final phase = PawDabResource._unitWindow(hash, 23) * math.pi * 2;
        final period = math.max(
          .0001,
          stroke.brushSize *
              layer.wanderPeriodFactor *
              (.8 + PawDabResource._unitWindow(hash, 29) * .4),
        );

        _PawFilamentLanePoint? pointAt(double arc) {
          final sample = sampleAt(arc);
          if (sample == null) return null;
          // Preserve the old normal exactly when grooming is neutral; ordinary
          // persistent layers do not pay for past queries or angle math.
          final frame =
              layer.grooming.isIdentity ? null : groomedFrameAt(arc, sample);
          final normal = frame?.normal ?? sample.normal;
          final wander = math.sin(arc / period * math.pi * 2 + phase) *
              stroke.brushSize *
              layer.wanderAmplitudeFactor;
          final splayScale = frame?.splayScaleFor(effectiveOffsetUnit) ?? 1.0;
          // Wander is deliberately independent: curvature only splays the
          // stable clumped lane offset, never its oscillating micro-motion.
          final normalDistance = clumpedOffset * splayScale + wander;
          final rootFadeLength = stroke.brushSize * layer.rootFadeArcFactor;
          final tipFadeLength = stroke.brushSize * layer.tipFadeArcFactor;
          final rootFade = stroke.isClosed || rootFadeLength == 0
              ? 1.0
              : (arc / rootFadeLength).clamp(0.0, 1.0);
          final tipDistance = stroke.renderEndArc - arc;
          final tipFade = stroke.isClosed || tipFadeLength == 0
              ? 1.0
              : (tipDistance / tipFadeLength).clamp(0.0, 1.0);
          final center = sample.point + normal * normalDistance;
          final color = _DabInstanceEvaluator._colorForMotion(
            stroke: stroke,
            motion: sample.motion,
            hash: hash,
            coverage: layer.coverage *
                layer.pressureDensityCoverage(
                  pressure: sample.motion.pressure,
                  laneHash: hash,
                ) *
                layer.coverageEnvelopeAt(
                  absoluteArc: arc,
                  brushSize: stroke.brushSize,
                  layerHashSeed: layerHashSeed,
                  laneId: laneId,
                ) *
                rootFade *
                tipFade,
            canvasPoint: center,
            persistentMaterial: layer.material,
          );
          return _PawFilamentLanePoint(
            arc: arc,
            center: center,
            normal: normal,
            normalDistance: normalDistance,
            width: width *
                _DabInstanceEvaluator._pressureSizeForMotion(
                  stroke.definition.emission,
                  sample.motion,
                ),
            color: color,
          );
        }

        for (final segment in ownedSegments) {
          final first = pointAt(segment.$1);
          final second = pointAt(segment.$2);
          if (first != null && second != null) {
            _DabPersistentLanes._appendFilamentLaneSegment(
              positions: layerPositions,
              textureCoordinates: layerTextureCoordinates,
              colors: layerColors,
              indices: layerIndices,
              stroke: stroke,
              first: first,
              second: second,
            );
            lastPersistentLaneSegmentCount++;
          }
        }
      }
    }
  }

  static void _appendPersistentLaneTap({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required List<Offset> carrierPositions,
    required List<Offset> carrierTextureCoordinates,
    required List<Color> carrierColors,
    required List<int> carrierIndices,
    required PawDabEmissionSource stroke,
    required Offset point,
    required Offset direction,
  }) {
    final layers = stroke.definition.template.persistentLaneLayers;
    if (layers.isEmpty) return;
    final normal = Offset(-direction.dy, direction.dx);
    final motion = stroke.tapMotionSample;
    final seed = stroke.seed.value ^ stroke.definition.identitySalt ^ 0x62c91;
    for (var layerIndex = 0; layerIndex < layers.length; layerIndex++) {
      final layer = layers[layerIndex];
      final layerHashSeed = seed ^ (layerIndex + 1) * 0x45d9f3b;
      final layerPositions =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierPositions
              : positions;
      final layerTextureCoordinates =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierTextureCoordinates
              : textureCoordinates;
      final layerColors =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierColors
              : colors;
      final layerIndices =
          layer.material == PawDabPersistentLaneMaterial.coarseCarrier
              ? carrierIndices
              : indices;
      for (var laneId = 0; laneId < layer.laneCount; laneId++) {
        final hash = PawDabResource._hash(layerHashSeed, laneId);
        // A tap has no arc history, so grooming and wander stay neutral. Its
        // static distribution still follows the layer's clump semantics.
        final offset = _DabPersistentLanes._persistentClumpedOffset(
          layer: layer,
          laneId: laneId,
          brushSize: stroke.brushSize,
        );
        final halfLength = math.max(1.0, stroke.brushSize * .15);
        final width = stroke.brushSize *
            layer.widthFactors.sample(PawDabResource._unitWindow(hash, 11)) *
            _DabInstanceEvaluator._pressureSizeForMotion(
                stroke.definition.emission, motion);
        final center = point + normal * offset;
        final color = _DabInstanceEvaluator._colorForMotion(
          stroke: stroke,
          motion: motion,
          hash: hash,
          coverage: layer.coverage *
              layer.pressureDensityCoverage(
                pressure: motion.pressure,
                laneHash: hash,
              ) *
              layer.coverageEnvelopeAt(
                absoluteArc: 0,
                brushSize: stroke.brushSize,
                layerHashSeed: layerHashSeed,
                laneId: laneId,
              ),
          canvasPoint: center,
          persistentMaterial: layer.material,
        );
        final start = center - direction * halfLength;
        final middle = center;
        final end = center + direction * halfLength;
        _DabPersistentLanes._appendFilamentLaneSegment(
          positions: layerPositions,
          textureCoordinates: layerTextureCoordinates,
          colors: layerColors,
          indices: layerIndices,
          stroke: stroke,
          first: _PawFilamentLanePoint(
            arc: 0,
            center: start,
            normal: normal,
            normalDistance: offset,
            width: width,
            color: color.withValues(alpha: 0),
          ),
          second: _PawFilamentLanePoint(
            arc: halfLength,
            center: middle,
            normal: normal,
            normalDistance: offset,
            width: width,
            color: color,
          ),
        );
        _DabPersistentLanes._appendFilamentLaneSegment(
          positions: layerPositions,
          textureCoordinates: layerTextureCoordinates,
          colors: layerColors,
          indices: layerIndices,
          stroke: stroke,
          first: _PawFilamentLanePoint(
            arc: halfLength,
            center: middle,
            normal: normal,
            normalDistance: offset,
            width: width,
            color: color,
          ),
          second: _PawFilamentLanePoint(
            arc: halfLength * 2,
            center: end,
            normal: normal,
            normalDistance: offset,
            width: 0,
            color: color.withValues(alpha: 0),
          ),
        );
      }
    }
  }

  static void _appendFilamentLaneSegment({
    required List<Offset> positions,
    required List<Offset> textureCoordinates,
    required List<Color> colors,
    required List<int> indices,
    required PawDabEmissionSource stroke,
    required _PawFilamentLanePoint first,
    required _PawFilamentLanePoint second,
    bool connectToPrevious = false,
    double softness = 0,
  }) {
    // Consecutive pieces of one curve share their three cross-section
    // vertices. Sharing preserves the coverage and removes duplicate work.
    final base = positions.length - (connectToPrevious ? 3 : 0);
    // A subpixel strand needs transverse coverage, not a binary triangle.
    // A tent integrates to half its support width; compensate the peak so
    // narrowing a hair reduces pigment continuously instead of losing pixels.
    // The feather is document-local, so zoom and export preserve the material.
    // Authored softness broadens this kernel at constant integrated coverage;
    // it does not blur the composite stroke or hide the inter-hair gaps.
    for (final point in connectToPrevious ? [second] : [first, second]) {
      final unfilteredSupport = point.width / 2 + .45;
      final halfSupport = unfilteredSupport + softness;
      final peak = (point.width / unfilteredSupport).clamp(0.0, 1.0) *
          unfilteredSupport /
          halfSupport;
      for (final side in const [-1.0, 0.0, 1.0]) {
        final offset = side * halfSupport;
        final vertex = point.center + point.normal * offset;
        positions.add(vertex);
        textureCoordinates.add(stroke.definition.grain.isEnabled
            ? _DabInstanceEvaluator._grainCoordinate(
                grain: stroke.definition.grain,
                rasterProgram: stroke.environment.rasterProgram,
                canvasPoint: vertex,
                arc: point.arc,
                normalDistance: point.normalDistance + offset,
                brushSize: stroke.brushSize,
              )
            : Offset.zero);
        colors.add(point.color.withValues(
          alpha: side == 0 ? point.color.a * peak : 0,
        ));
      }
    }
    for (var band = 0; band < 2; band++) {
      indices.addAll(<int>[
        base + band,
        base + 3 + band,
        base + 4 + band,
        base + band,
        base + 4 + band,
        base + 1 + band,
      ]);
    }
  }
}
