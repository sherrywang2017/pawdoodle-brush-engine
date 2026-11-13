part of '../../streaming_dab_brush.dart';

extension _DabSweptCoverage on PawStreamingDabRenderCache {
  void _syncSweptCoverage(PawDabEmissionSource stroke) {
    final program = stroke.environment.unifiedProgram!;
    final definition = stroke.definition;
    final emission = definition.emission;
    final wet = definition.wetMedia;
    final endpoint = program.endpoint;
    final sections = <PawSweepSection>[];
    lastSweepRebuiltSectionCount = 0;
    final centerline = Path();
    void section(
        Offset point, Offset tangent, PawStreamingMotionSample motion) {
      lastSweepRebuiltSectionCount++;
      final arc = motion.absoluteArc;
      final hash = PawDabResource._hash(stroke.seed.value, (arc * 16).round());
      _tapKernelDabScratch.set(
          point: point, tangent: tangent, hash: hash, motion: motion);
      _evaluateKernelInto(
          stroke: stroke,
          dab: _tapKernelDabScratch,
          previousTangent: tangent,
          followingTangent: tangent,
          behavior: program.behavior,
          kernel: program.kernel);
      final dynamics = _evaluateDynamics(
          dynamics: emission.dynamics,
          motion: motion,
          brushSize: stroke.brushSize,
          hash: hash);
      final settlement =
          stroke is PawStreamingDabStroke ? stroke.settlementAtArc(arc) : 1.0;
      final endpointOpacity = endpoint?.opacityScaleAt(
              closed: stroke.isClosed,
              absoluteArc: arc,
              renderEndArc: stroke.renderEndArc,
              brushSize: stroke.brushSize) ??
          1;
      final size =
          _DabInstanceEvaluator._pressureSizeForMotion(emission, motion) *
              dynamics.size *
              _kernelOutputScratch.widthScale.clamp(.35, 1.8) *
              (endpoint?.sizeScaleAt(
                      closed: stroke.isClosed,
                      absoluteArc: arc,
                      renderEndArc: stroke.renderEndArc,
                      brushSize: stroke.brushSize) ??
                  1);
      final load = (stroke.opacity *
              stroke.color.a *
              (emission.pressureOpacityMinFactor +
                  (emission.pressureOpacityMaxFactor -
                          emission.pressureOpacityMinFactor) *
                      motion.pressure) *
              dynamics.opacity *
              dynamics.deposition *
              _kernelOutputScratch.opacityScale *
              (endpoint?.tangentSize == true ? 1 : endpointOpacity))
          .clamp(0.0, 1.0);
      sections.add(PawSweepSection(
          point,
          stroke.brushSize *
              .5 *
              size *
              definition.template.footprint.widthFactor *
              (wet.enabled
                  ? 1 - wet.diffusionRadius * .16 * (1 - settlement)
                  : 1),
          load,
          arc: arc,
          opacity: endpoint?.tangentSize == true ? endpointOpacity : 1));
    }

    var first = true;
    final liveIndices = <int>{};
    for (final segment in stroke.emissionSegments) {
      liveIndices.add(segment.index);
      if (first) {
        centerline.moveTo(segment.p0.dx, segment.p0.dy);
        final sample = segment.sampleAt(0, absoluteArc: segment.arcStart);
        section(sample.point, sample.tangent, sample.motion);
        first = false;
      }
      centerline.cubicTo(segment.c1.dx, segment.c1.dy, segment.c2.dx,
          segment.c2.dy, segment.p1.dx, segment.p1.dy);
      final reusable = segment.arcEnd <
              stroke.renderEndArc -
                  stroke.brushSize * (endpoint?.endTaperBrushLengths ?? 0) &&
          (!wet.enabled ||
              stroke is! PawStreamingDabStroke ||
              stroke.settlementAtArc(segment.arcEnd) >= 1);
      final cached = _sweepSections[segment.index];
      if (reusable && cached != null && identical(cached.$1, segment)) {
        sections.addAll(cached.$2);
        continue;
      }
      final start = sections.length;
      // Chord spacing is bounded in document units, not by pointer cadence.
      final steps = math.max(1,
          (segment.arcLength / math.max(.75, stroke.brushSize * .08)).ceil());
      for (var j = 1; j <= steps; j++) {
        final t = j / steps;
        final sample = segment.sampleAt(t,
            absoluteArc: segment.arcStart + segment.arcLength * t);
        section(sample.point, sample.tangent, sample.motion);
      }
      if (reusable) {
        _sweepSections[segment.index] = (segment, sections.sublist(start));
      }
    }
    _sweepSections.removeWhere((index, _) => !liveIndices.contains(index));
    if (first && stroke.strokeStartPosition != null) {
      section(stroke.strokeStartPosition!, const Offset(1, 0),
          stroke.tapMotionSample);
    }
    _sweptGrainCoordinates?.dispose();
    _sweptGrainCoordinates = null;
    final grain = definition.grain;
    if (!wet.enabled &&
        (grain.coarseStrength > 0 || grain.fineStrength > 0) &&
        (grain.coordinate == PawDabGrainCoordinate.rolling ||
            grain.movement != 0)) {
      // This is a coordinate field, not pigment geometry. Overlapping quads
      // replace their UV samples, while the independent sweep owns coverage.
      // A triangle fold can therefore never deposit extra pigment.
      final positions = <Offset>[], coordinates = <Offset>[];
      for (var i = 0; i < math.max(1, sections.length - 1); i++) {
        if (sections.isEmpty) break;
        final a = sections[i],
            b = sections[math.min(i + 1, sections.length - 1)];
        final delta = b.point - a.point;
        final d = delta.distance > .000001
            ? delta / delta.distance
            : const Offset(1, 0);
        final n = Offset(-d.dy, d.dx);
        final reach = math.max(a.radius, b.radius) * 1.5 + 1;
        final corners = [
          a.point - d * reach - n * reach,
          b.point + d * reach - n * reach,
          b.point + d * reach + n * reach,
          a.point - d * reach + n * reach
        ];
        for (final j in const [0, 1, 2, 0, 2, 3]) {
          final point = corners[j], offset = point - a.point;
          positions.add(point);
          coordinates.add(_DabInstanceEvaluator._grainCoordinate(
              grain: grain,
              rasterProgram: stroke.environment.rasterProgram,
              canvasPoint: point,
              arc: a.arc + offset.dx * d.dx + offset.dy * d.dy,
              normalDistance: offset.dx * n.dx + offset.dy * n.dy,
              brushSize: stroke.brushSize));
        }
      }
      if (positions.isNotEmpty) {
        _sweptGrainCoordinates = ui.Vertices(ui.VertexMode.triangles, positions,
            textureCoordinates: coordinates);
      }
    }
    _sweptCoverage?.dispose();
    _sweptCoverage = PawSweptCoverage(
        tangentCaps: endpoint?.tangentSize == true,
        coverageCeiling: (stroke.opacity *
                stroke.color.a *
                math.max(emission.dynamics.slowDepositionScale,
                    emission.dynamics.fastDepositionScale) *
                math.max(1, emission.dynamics.turnDepositionScale))
            .clamp(0.0, 1.0),
        sections: sections,
        aspect: program.shape.kind == PawBrushShapeKind.ellipse &&
                (emission.directionRotationFactor == 0 || sections.length == 1)
            ? program.shape.aspect
            : 1,
        rotation: emission.baseRotationRadians,
        hardness: wet.enabled
            ? definition.template.footprint.edgeCoverage.clamp(.35, .85)
            : program.shape.hardness,
        capRoundness: (endpoint?.capRoundness ??
                definition.template.footprint.capRoundness) *
            (program.shape.kind == PawBrushShapeKind.ellipse &&
                    emission.directionRotationFactor != 0 &&
                    sections.length > 1
                ? program.shape.aspect
                : 1),
        color: wet.enabled ? const Color(0xff8080ff) : stroke.color,
        exactCenterline: centerline);
    lastSweepSectionCount = sections.length;
    performanceCapture?.recordSweptCoverage(
        revision: stroke.revision,
        sections: sections.length,
        rebuiltSections: lastSweepRebuiltSectionCount,
        layers: sweepLayerCount);
    if (sections.isNotEmpty) {
      var bounds = Rect.fromCircle(
          center: sections.first.point, radius: sections.first.radius * 1.5);
      for (final section in sections.skip(1)) {
        bounds = bounds.expandToInclude(Rect.fromCircle(
            center: section.point, radius: section.radius * 1.5));
      }
      _sweptCoverageBounds = bounds;
      _unpaintedContactBounds.add(bounds);
    }
    _lastVisibleDabExclusive = PawStreamingDabRenderCache._emissionPlanner
        .endExclusiveForVisibleArc(stroke);
    _lastSealedEndArc = stroke.sealedEndArc;
    _lastCausalStableEndArc = stroke.causalStableEndArc;
    _lastRenderEndArc = stroke.renderEndArc;
    lastTailDabCount = _lastVisibleDabExclusive;
    _previousTailStartIndex = 0;
    _previousTailEndExclusive = _lastVisibleDabExclusive;
  }
}
