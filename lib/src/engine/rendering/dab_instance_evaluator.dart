part of '../../streaming_dab_brush.dart';

extension _DabInstanceEvaluator on PawStreamingDabRenderCache {
  static _PawDabInstance _dabInstance({
    required PawDabEmissionSource stroke,
    required PawDabResource resource,
    required int index,
    required double arc,
    required Offset point,
    required PawStreamingMotionSample motion,
    required PawBrushKernelOutput kernelOutput,
  }) {
    final definition = stroke.definition;
    final emission = definition.emission;
    final seed = stroke.seed.value ^ definition.identitySalt;
    final hash = PawDabResource._hash(seed, index);
    final variant = definition.dryWax.enabled
        ? index % resource.variantCount
        : hash % resource.variantCount;
    final sourceRect = resource.variantRects[variant];
    final alongScatter = (PawDabResource._unitWindow(hash, 7) - .5) *
        stroke.brushSize *
        emission.alongScatterFactor;
    final normalScatter = (PawDabResource._unitWindow(hash, 15) - .5) *
        stroke.brushSize *
        emission.normalScatterFactor;
    final direction = _DabInstanceEvaluator._normalized(
      Offset(kernelOutput.directionX, kernelOutput.directionY),
    );
    final normal = Offset(-direction.dy, direction.dx);
    final center = point + direction * alongScatter + normal * normalScatter;
    final normalizedPressure = motion.pressure;
    final pressureSize = emission.pressureSizeMinFactor +
        (emission.pressureSizeMaxFactor - emission.pressureSizeMinFactor) *
            normalizedPressure;
    final pressureOpacity = emission.pressureOpacityMinFactor +
        (emission.pressureOpacityMaxFactor -
                emission.pressureOpacityMinFactor) *
            normalizedPressure;
    final dynamics = _evaluateDynamics(
      dynamics: emission.dynamics,
      motion: motion,
      brushSize: stroke.brushSize,
      hash: hash,
    );
    final rotationJitter = (PawDabResource._unitWindow(hash, 23) - .5) *
        2 *
        emission.rotationJitterRadians;
    final footprintAngle = emission.baseRotationRadians +
        math.atan2(direction.dy, direction.dx) *
            emission.directionRotationFactor +
        rotationJitter;
    final footprintDirection =
        Offset(math.cos(footprintAngle), math.sin(footprintAngle));
    final modulation = _DabInstanceEvaluator._densityModulation(
      emission: emission,
      seed: seed,
      arc: arc,
      brushSize: stroke.brushSize,
      point: center,
    );
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
    return _PawDabInstance(
      transform: ui.RSTransform.fromComponents(
        rotation: footprintAngle,
        scale: stroke.brushSize *
            pressureSize *
            dynamics.size /
            resource.pixelsPerLogicalUnit *
            kernelOutput.widthScale *
            endpointSize,
        anchorX: sourceRect.width / 2,
        anchorY: sourceRect.height / 2,
        translateX: center.dx,
        translateY: center.dy,
      ),
      sourceRect: sourceRect,
      color: stroke.color.withValues(
        alpha: (stroke.color.a *
                stroke.opacity *
                pressureOpacity *
                dynamics.deposition *
                dynamics.opacity *
                modulation *
                kernelOutput.opacityScale *
                endpointOpacity)
            .clamp(0.0, 1.0),
      ),
      center: center,
      direction: footprintDirection,
      pressureSize: pressureSize * dynamics.size,
    );
  }

  static void _fillStampInstance({
    required PawDabEmissionSource stroke,
    required PawDabResource resource,
    required int index,
    required double arc,
    required Offset point,
    required PawStreamingMotionSample motion,
    required PawBrushKernelOutput kernelOutput,
    required PawStampInstance output,
  }) {
    final definition = stroke.definition;
    final emission = definition.emission;
    final seed = stroke.seed.value ^ definition.identitySalt;
    final hash = PawDabResource._hash(seed, index);
    final variant = definition.dryWax.enabled
        ? index % resource.variantCount
        : hash % resource.variantCount;
    final sourceRect = resource.variantRects[variant];
    final alongScatter = (PawDabResource._unitWindow(hash, 7) - .5) *
        stroke.brushSize *
        emission.alongScatterFactor;
    final normalScatter = (PawDabResource._unitWindow(hash, 15) - .5) *
        stroke.brushSize *
        emission.normalScatterFactor;
    final direction = _DabInstanceEvaluator._normalized(
      Offset(kernelOutput.directionX, kernelOutput.directionY),
    );
    final normal = Offset(-direction.dy, direction.dx);
    final center = point + direction * alongScatter + normal * normalScatter;
    final normalizedPressure = motion.pressure;
    final pressureSize = emission.pressureSizeMinFactor +
        (emission.pressureSizeMaxFactor - emission.pressureSizeMinFactor) *
            normalizedPressure;
    final pressureOpacity = emission.pressureOpacityMinFactor +
        (emission.pressureOpacityMaxFactor -
                emission.pressureOpacityMinFactor) *
            normalizedPressure;
    final dynamics = _evaluateDynamics(
      dynamics: emission.dynamics,
      motion: motion,
      brushSize: stroke.brushSize,
      hash: hash,
    );
    final rotationJitter = (PawDabResource._unitWindow(hash, 23) - .5) *
        2 *
        emission.rotationJitterRadians;
    final footprintAngle = emission.baseRotationRadians +
        math.atan2(direction.dy, direction.dx) *
            emission.directionRotationFactor +
        rotationJitter;
    final footprintDirection =
        Offset(math.cos(footprintAngle), math.sin(footprintAngle));
    final modulation = _DabInstanceEvaluator._densityModulation(
      emission: emission,
      seed: seed,
      arc: arc,
      brushSize: stroke.brushSize,
      point: center,
    );
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
    final rawAlpha = (stroke.color.a *
            stroke.opacity *
            pressureOpacity *
            dynamics.deposition *
            dynamics.opacity *
            modulation *
            kernelOutput.opacityScale *
            endpointOpacity)
        .clamp(0.0, 1.0)
        .toDouble();
    final resolvedColor = stroke.color.withValues(
      alpha: definition.wetMedia.enabled
          ? definition.coverageTransfer.linearizeDabCoverage(rawAlpha)
          : rawAlpha,
    );
    output
      ..globalDabIndex = index
      ..centerX = center.dx
      ..centerY = center.dy
      ..rotation = footprintAngle
      ..scale = stroke.brushSize
      ..widthScale = kernelOutput.widthScale * endpointSize
      ..lengthScale = kernelOutput.lengthScale * endpointSize
      ..opacity = resolvedColor.a
      ..color = resolvedColor.toARGB32()
      ..variant = variant
      ..sourceLeft = sourceRect.left
      ..sourceTop = sourceRect.top
      ..sourceWidth = sourceRect.width
      ..sourceHeight = sourceRect.height
      ..absoluteArc = arc
      ..pressure = normalizedPressure
      ..grainPhase =
          definition.grain.coordinate == PawDabGrainCoordinate.rolling
              ? arc / math.max(.0001, stroke.brushSize)
              : null
      ..directionX = footprintDirection.dx
      ..directionY = footprintDirection.dy
      ..pressureSize = pressureSize * dynamics.size;
  }

  static double _sampleDryMediaCoverage({
    required PawDabEmissionSource stroke,
    required Offset point,
    required double arc,
  }) =>
      stroke.environment.rasterProgram?.sampleDryMediaCoverage(
        canvasX: point.dx,
        canvasY: point.dy,
        absoluteArc: arc,
        signedNormal: 0,
        brushWidth: stroke.brushSize,
      ) ??
      1;

  static double _pressureSizeForMotion(
    PawDabEmissionParameters emission,
    PawStreamingMotionSample motion,
  ) =>
      emission.pressureSizeMinFactor +
      (emission.pressureSizeMaxFactor - emission.pressureSizeMinFactor) *
          motion.pressure;

  static Color _colorForMotion({
    required PawDabEmissionSource stroke,
    required PawStreamingMotionSample motion,
    required int hash,
    required double coverage,
    Offset? canvasPoint,
    PawDabPersistentLaneMaterial? persistentMaterial,
    _PawDabDynamicsResponse? resolvedDynamics,
  }) {
    final emission = stroke.definition.emission;
    final pressureOpacity = emission.pressureOpacityMinFactor +
        (emission.pressureOpacityMaxFactor -
                emission.pressureOpacityMinFactor) *
            motion.pressure;
    final dynamics = resolvedDynamics ??
        _evaluateDynamics(
          dynamics: emission.dynamics,
          motion: motion,
          brushSize: stroke.brushSize,
          hash: hash,
        );
    final contact = stroke.definition.paperContact;
    final paperDetailCarrier =
        stroke.environment.rasterProgram?.highFrequencyCoordinateSpace ==
                PawBrushRasterCoordinateSpace.canvasFixed &&
            stroke.environment.rasterProgram
                    ?.hasRole(PawBrushRasterRoleKind.paper) ==
                true;
    final paperCoverage = canvasPoint == null || !contact.isEnabled
        ? 1.0
        : switch (persistentMaterial) {
            PawDabPersistentLaneMaterial.coarseCarrier =>
              contact.coarseDepositionAt(
                paper: stroke.environment.paper,
                canvasPoint: canvasPoint,
              ),
            _ when paperDetailCarrier =>
              stroke.definition.coverageTransfer.remapPaperContact(
                contact.coarseDepositionAt(
                  paper: stroke.environment.paper,
                  canvasPoint: canvasPoint,
                ),
              ),
            _ => stroke.definition.coverageTransfer.remapPaperContact(
                contact.coverageAt(
                  paper: stroke.environment.paper,
                  canvasPoint: canvasPoint,
                  pressure: motion.pressure,
                  deposition: dynamics.deposition,
                ),
              ),
          };
    return stroke.color.withValues(
      alpha: (stroke.color.a *
              stroke.opacity *
              pressureOpacity *
              dynamics.deposition *
              dynamics.opacity *
              dynamics.filamentCoverage *
              coverage *
              paperCoverage)
          .clamp(0.0, 1.0),
    );
  }

  // Premultiplied state: RG carries direction, B carries absorption age,
  // alpha carries deposited contact. Dry wax encodes (cos 2a, sin 2a): opposite
  // drags share an axis instead of cancelling when their contact overlaps.
  // Pigment color is a material uniform.
  static Color _contactStateColor(Offset direction, double age, double load,
      {bool axial = false}) {
    final encoded = axial
        ? Offset(direction.dx * direction.dx - direction.dy * direction.dy,
            2 * direction.dx * direction.dy)
        : direction;
    return Color.from(
        alpha: load.clamp(0.0, 1.0),
        red: ((encoded.dx + 1) / 2).clamp(0.0, 1.0),
        green: ((encoded.dy + 1) / 2).clamp(0.0, 1.0),
        blue: age.clamp(0.0, 1.0));
  }

  static double _densityModulation({
    required PawDabEmissionParameters emission,
    required int seed,
    required double arc,
    required double brushSize,
    required Offset point,
  }) {
    var result = 1.0;
    if (emission.arcDensityAmplitude > 0) {
      final coordinate =
          arc / math.max(.0001, brushSize * emission.arcDensityPeriodFactor);
      final firstIndex = coordinate.floor();
      final fraction = coordinate - firstIndex;
      final smooth = fraction * fraction * (3 - 2 * fraction);
      final first = PawDabResource._unit(
        PawDabResource._hash(seed ^ 0x520a, firstIndex),
      );
      final second = PawDabResource._unit(
        PawDabResource._hash(seed ^ 0x520a, firstIndex + 1),
      );
      final unit = first + (second - first) * smooth;
      result *= 1 + (unit * 2 - 1) * emission.arcDensityAmplitude;
    }
    if (emission.canvasDensityAmplitude > 0) {
      final scale = math.max(
        .0001,
        brushSize * emission.canvasDensityScaleFactor,
      );
      final x = point.dx / scale;
      final y = point.dy / scale;
      final left = x.floor();
      final top = y.floor();
      final fx = x - left;
      final fy = y - top;
      final sx = fx * fx * (3 - 2 * fx);
      final sy = fy * fy * (3 - 2 * fy);
      double sample(int cellX, int cellY) => PawDabResource._unit(
            PawDabResource._hash(
              seed ^ cellX * 0x45d9f3b,
              cellY ^ 0x6d2b79f5,
            ),
          );
      final topValue =
          sample(left, top) + (sample(left + 1, top) - sample(left, top)) * sx;
      final bottomValue = sample(left, top + 1) +
          (sample(left + 1, top + 1) - sample(left, top + 1)) * sx;
      final unit = topValue + (bottomValue - topValue) * sy;
      result *= 1 + (unit * 2 - 1) * emission.canvasDensityAmplitude;
    }
    return result;
  }

  static Offset _normalized(Offset value) {
    final distance = value.distance;
    return distance > .000001 ? value / distance : const Offset(1, 0);
  }

  static double _directionTurnRadians(Offset from, Offset to) {
    final first = _DabInstanceEvaluator._normalized(from);
    final second = _DabInstanceEvaluator._normalized(to);
    return math
        .atan2(
          first.dx * second.dy - first.dy * second.dx,
          first.dx * second.dx + first.dy * second.dy,
        )
        .abs();
  }

  /// Maps a transverse material coordinate onto a fold-free swept surface.
  ///
  static Offset _grainCoordinate({
    required PawDabGrainParameters grain,
    required PawPreparedBrushRasterProgram? rasterProgram,
    required Offset canvasPoint,
    required double arc,
    required double normalDistance,
    required double brushSize,
  }) {
    if (rasterProgram?.hasHighFrequencyCoverage == true) {
      final coordinateSpace = rasterProgram!.highFrequencyCoordinateSpace;
      if (coordinateSpace == PawBrushRasterCoordinateSpace.canvasFixed) {
        final period = rasterProgram.highFrequencyCanvasPeriod ?? 64;
        final rasterWidth = rasterProgram.highFrequencyRasterWidth ?? 64;
        final rasterHeight = rasterProgram.highFrequencyRasterHeight ?? 64;
        return Offset(
          canvasPoint.dx / period * rasterWidth,
          canvasPoint.dy / period * rasterHeight,
        );
      }
    }
    var coordinate = switch (grain.coordinate) {
      // Canvas-fixed grain is physical paper: changing brush size must not
      // zoom or shift it. Scale factors are relative to a 64 logical-pixel
      // reference period rather than to the active brush diameter.
      PawDabGrainCoordinate.canvasFixed => canvasPoint *
          (PawDabResource._textureTilePixels /
              math.max(.0001, 64 * grain.coarseScaleFactor)),
      // Arc is always absolute, so a rolling tile keeps its phase across
      // overlapping Dabs, sealed chunks, and the provisional tail.
      PawDabGrainCoordinate.rolling => Offset(arc, normalDistance) *
          (PawDabResource._textureTilePixels /
              math.max(.0001, brushSize * grain.coarseScaleFactor)),
    };
    if (grain.movement != 0) {
      coordinate += Offset(
        arc /
            math.max(.0001, brushSize * grain.coarseScaleFactor) *
            PawDabResource._textureTilePixels *
            grain.movement,
        0,
      );
    }
    if (grain.rotationRadians != 0) {
      final cosine = math.cos(grain.rotationRadians);
      final sine = math.sin(grain.rotationRadians);
      coordinate = Offset(
        coordinate.dx * cosine - coordinate.dy * sine,
        coordinate.dx * sine + coordinate.dy * cosine,
      );
    }
    return coordinate;
  }

  /// Builds one continuous, canvas-contact carrier for a stroke interval.
  ///
  /// High-frequency paper/grain stays in the texture sampled by drawVertices;
  /// the CPU mesh only carries centerline shape, pressure, low-frequency paper
  /// response, and a bounded transverse coverage profile. Geometry therefore
  /// scales with stroke length instead of `dab count * radial sampling density`.
  static double _distanceToContactLeg(Offset p, Offset a, Offset b) {
    final leg = b - a;
    final lengthSquared = leg.distanceSquared;
    if (lengthSquared < 1e-12) return (p - a).distance;
    final delta = p - a;
    final t = ((delta.dx * leg.dx + delta.dy * leg.dy) / lengthSquared)
        .clamp(0.0, 1.0);
    return (p - (a + leg * t)).distance;
  }
}
