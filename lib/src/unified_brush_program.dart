import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'brush_behavior.dart';
import 'brush_kernel.dart';
import 'brush_raster_resource.dart';
import 'brush_shape_field.dart';

/// The coordinate space in which a unified brush consumes its grain field.
///
/// The actual field remains owned by [PawBrushRasterProgram]. This enum is
/// descriptive program metadata and is also used by offline diagnostics when
/// a candidate has no prepared production resource.
enum PawUnifiedBrushGrainMode {
  none,
  canvasFixed,
  strokeFollowing,
  brushLocal,
}

/// Pigment deposition vocabulary shared by the production brush programs.
///
/// These are response models, not separate renderers. The existing DAB
/// renderer still owns blending and cache lifetime; the program only declares
/// how a brush is expected to load material.
enum PawUnifiedBrushDepositionModel {
  opaqueUniform,
  buildUp,
  glazeLike,
  airbrushDensity,
  dryMedia,
}

/// One renderer vocabulary shared by every unified brush program.
enum PawUnifiedBrushRenderRepresentation {
  /// A swept coverage field; adjacent contacts are united before deposition.
  sweptCoverage,

  /// Complete stamp-local coverage is prepared once; runtime owns instances.
  preparedStamp,

  /// Coverage genuinely depends on canvas-local contact samples.
  contactMesh,

  /// A prepared stamp is combined with a small canvas-local carrier.
  hybrid,
}

/// Runtime primitives selected by the brush compiler.
///
/// This is the production boundary between brush authoring and rendering. The
/// renderer consumes capabilities and never needs to know whether a program
/// came from a built-in tool or a user preset.
@immutable
class PawCompiledBrushRenderPlan {
  const PawCompiledBrushRenderPlan({
    this.needsSweptCoverage = false,
    this.needsTemporalContact = false,
    this.needsPreparedTip = false,
    this.needsCanvasContact = false,
    this.needsCarrier = false,
    this.needsPersistentBristles = false,
    this.needsStreamingHairs = false,
    this.needsStatefulDensity = false,
    this.needsWetMediaTiles = false,
    this.needsCanvasFixedGrain = false,
    this.needsDryMediaContact = false,
    this.needsBuildUp = false,
    this.preparedEdgeAntialiasLogicalPixels = 0,
  });

  final bool needsPreparedTip;
  final bool needsSweptCoverage;
  final bool needsTemporalContact;
  final bool needsCanvasContact;
  final bool needsCarrier;
  final bool needsPersistentBristles;
  final bool needsStreamingHairs;
  final bool needsStatefulDensity;
  final bool needsWetMediaTiles;
  final bool needsCanvasFixedGrain;
  final bool needsDryMediaContact;
  final bool needsBuildUp;

  /// Width of the analytic coverage fringe baked into a prepared local tip.
  final double preparedEdgeAntialiasLogicalPixels;

  int get passCount => <bool>[
        needsPreparedTip,
        needsCanvasContact,
        needsCarrier,
        needsPersistentBristles,
        needsStreamingHairs,
        needsStatefulDensity,
        needsWetMediaTiles,
        needsCanvasFixedGrain,
        needsDryMediaContact,
        needsBuildUp,
      ].where((value) => value).length;

  void validate() {
    if (!preparedEdgeAntialiasLogicalPixels.isFinite ||
        preparedEdgeAntialiasLogicalPixels < 0 ||
        preparedEdgeAntialiasLogicalPixels > 2 ||
        passCount > 10 ||
        (!needsPreparedTip && preparedEdgeAntialiasLogicalPixels != 0)) {
      throw ArgumentError('Invalid compiled brush render plan.');
    }
  }

  Map<String, Object> toJson() => <String, Object>{
        'swept_coverage': needsSweptCoverage,
        'temporal_contact': needsTemporalContact,
        'prepared_tip': needsPreparedTip,
        'canvas_contact': needsCanvasContact,
        'carrier': needsCarrier,
        'persistent_bristles': needsPersistentBristles,
        'streaming_hairs': needsStreamingHairs,
        'stateful_density': needsStatefulDensity,
        'wet_media_tiles': needsWetMediaTiles,
        'canvas_fixed_grain': needsCanvasFixedGrain,
        'dry_media_contact': needsDryMediaContact,
        'build_up': needsBuildUp,
        'prepared_edge_aa_px': preparedEdgeAntialiasLogicalPixels,
      };
}

/// Small, serializable description of how unified inputs are expected to
/// affect a brush. The concrete kernel remains responsible for evaluating the
/// response into the cache-owned [PawBrushKernelOutput].
@immutable
class PawUnifiedBrushDynamicsProfile {
  const PawUnifiedBrushDynamicsProfile({
    this.pressureToSize = 1,
    this.pressureToOpacity = 1,
    this.speedToFlow = 0,
    this.speedToSpacing = 0,
    this.directionToRotation = 0,
    this.curvatureToShape = 0,
    this.grainToMotion = 0,
    this.bristleSpread = 0,
  });

  final double pressureToSize;
  final double pressureToOpacity;
  final double speedToFlow;
  final double speedToSpacing;
  final double directionToRotation;
  final double curvatureToShape;
  final double grainToMotion;
  final double bristleSpread;

  void validate() {
    for (final value in <double>[
      pressureToSize,
      pressureToOpacity,
      speedToFlow,
      speedToSpacing,
      directionToRotation,
      curvatureToShape,
      grainToMotion,
      bristleSpread,
    ]) {
      if (!value.isFinite || value < -2 || value > 2) {
        throw ArgumentError('Invalid unified brush dynamics profile.');
      }
    }
  }

  Map<String, Object> toJson() => <String, Object>{
        'pressure_to_size': pressureToSize,
        'pressure_to_opacity': pressureToOpacity,
        'speed_to_flow': speedToFlow,
        'speed_to_spacing': speedToSpacing,
        'direction_to_rotation': directionToRotation,
        'curvature_to_shape': curvatureToShape,
        'grain_to_motion': grainToMotion,
        'bristle_spread': bristleSpread,
      };
}

/// Brush-authored contact and lift response at the two stroke endpoints.
///
/// Lengths are expressed in brush widths so the same preset keeps its gesture
/// at every selected size. Size and opacity are separate because a physical
/// tool can keep a blunt silhouette while its material fades, or taper to a
/// fine opaque point. The renderer samples this one profile for prepared
/// stamps, contact ribbons, carriers, and bristles.
@immutable
class PawUnifiedBrushEndpointProfile {
  const PawUnifiedBrushEndpointProfile({
    this.startTaperBrushLengths = 0,
    this.endTaperBrushLengths = 0,
    this.minimumSizeFactor = 1,
    this.minimumOpacityFactor = 1,
    this.taperExponent = 1,
    this.capRoundness = 1,
    this.capRoughness = 0,
    this.tangentSize = false,
  });

  final double startTaperBrushLengths;
  final double endTaperBrushLengths;
  final double minimumSizeFactor;
  final double minimumOpacityFactor;
  final double taperExponent;

  /// 0 is a blunt contact cut; 1 is a semicircular swept cap.
  final double capRoundness;

  /// Bounded longitudinal material breakup across the cap.
  final double capRoughness;

  /// Shape taper with a concave side and an independent longitudinal fade.
  /// Physical bristle and bundled ink profiles retain their contact envelope.
  final bool tangentSize;

  bool get isIdentity =>
      startTaperBrushLengths == 0 &&
      endTaperBrushLengths == 0 &&
      minimumSizeFactor == 1 &&
      minimumOpacityFactor == 1 &&
      capRoundness == 1 &&
      capRoughness == 0;

  void validate() {
    if (!_inRange(startTaperBrushLengths, 0, 4) ||
        !_inRange(endTaperBrushLengths, 0, 4) ||
        !_inRange(minimumSizeFactor, 0, 1) ||
        !_inRange(minimumOpacityFactor, 0, 1) ||
        !_inRange(taperExponent, .2, 6) ||
        !_inRange(capRoundness, 0, 1) ||
        !_inRange(capRoughness, 0, .25)) {
      throw ArgumentError('Invalid unified brush endpoint profile.');
    }
  }

  /// A zero-to-one eased envelope independent of the authored minimums.
  double progressAt({
    bool closed = false,
    required double absoluteArc,
    required double renderEndArc,
    required double brushSize,
  }) {
    if (closed || renderEndArc <= .0001 || brushSize <= .0001) return 1;
    final start = _endProgress(
      absoluteArc,
      brushSize * startTaperBrushLengths,
    );
    final end = _endProgress(
      renderEndArc - absoluteArc,
      brushSize * endTaperBrushLengths,
    );
    return math.min(start, end);
  }

  double sizeScaleAt({
    bool closed = false,
    required double absoluteArc,
    required double renderEndArc,
    required double brushSize,
  }) {
    if (!tangentSize) {
      return minimumSizeFactor +
          (1 - minimumSizeFactor) *
              progressAt(
                  closed: closed,
                  absoluteArc: absoluteArc,
                  renderEndArc: renderEndArc,
                  brushSize: brushSize);
    }
    if (closed || renderEndArc <= .0001 || brushSize <= .0001) return 1;
    double widthProgress(double distance, double length) {
      if (length <= .0001) return 1;
      final t = (distance / length).clamp(0.0, 1.0);
      // A concave width ramp meets the body with zero slope, without the
      // narrow neck created by smoothstep's zero slope at the small tip.
      // Exponent controls the opening angle while preserving concavity.
      return 1 - math.pow(1 - t, 1 + taperExponent).toDouble();
    }

    final progress = math.min(
        widthProgress(absoluteArc, brushSize * startTaperBrushLengths),
        widthProgress(
            renderEndArc - absoluteArc, brushSize * endTaperBrushLengths));
    return minimumSizeFactor + (1 - minimumSizeFactor) * progress;
  }

  double opacityScaleAt({
    bool closed = false,
    required double absoluteArc,
    required double renderEndArc,
    required double brushSize,
  }) =>
      minimumOpacityFactor +
      (1 - minimumOpacityFactor) *
          progressAt(
            closed: closed,
            absoluteArc: absoluteArc,
            renderEndArc: renderEndArc,
            brushSize: brushSize,
          );

  double _endProgress(double distance, double length) {
    if (length <= .0001) return 1;
    final unit = (distance / length).clamp(0.0, 1.0).toDouble();
    final smooth = unit * unit * (3 - 2 * unit);
    return math.pow(smooth, taperExponent).toDouble();
  }

  Map<String, Object> toJson() => <String, Object>{
        'start_taper_brush_lengths': startTaperBrushLengths,
        'end_taper_brush_lengths': endTaperBrushLengths,
        'minimum_size_factor': minimumSizeFactor,
        'minimum_opacity_factor': minimumOpacityFactor,
        'taper_exponent': taperExponent,
        'cap_roundness': capRoundness,
        'cap_roughness': capRoughness,
        'tangent_size': tangentSize,
      };

  static bool _inRange(double value, double minimum, double maximum) =>
      value.isFinite && value >= minimum && value <= maximum;
}

/// Low-cost centerline material used by a hybrid brush representation.
///
/// The carrier is a program component rather than a renderer-side brush-id
/// special case. Its width and opacity are modulated by the same behavior and
/// kernel output as the prepared detail stamps.
@immutable
class PawUnifiedBrushCarrierCrossSectionSample {
  const PawUnifiedBrushCarrierCrossSectionSample({
    required this.normalFactor,
    required this.coverage,
  });

  /// Signed location across the full carrier width. The legal range is
  /// `-.5 .. .5`, so a profile can describe edge, shoulder and core bands.
  final double normalFactor;
  final double coverage;

  Map<String, Object> toJson() => <String, Object>{
        'normal_factor': normalFactor,
        'coverage': coverage,
      };
}

@immutable
class PawUnifiedBrushCarrierProfile {
  const PawUnifiedBrushCarrierProfile({
    required this.widthFactor,
    required this.opacity,
    this.crossSection = const <PawUnifiedBrushCarrierCrossSectionSample>[
      PawUnifiedBrushCarrierCrossSectionSample(
        normalFactor: -.5,
        coverage: 1,
      ),
      PawUnifiedBrushCarrierCrossSectionSample(
        normalFactor: .5,
        coverage: 1,
      ),
    ],
    this.maximumSegmentLengthFactor = .28,
    this.grainBreakup = 0,
    this.edgeRoughness = 0,
    this.endpointTaperBrushLengths = 0,
  });

  final double widthFactor;
  final double opacity;
  final List<PawUnifiedBrushCarrierCrossSectionSample> crossSection;
  final double maximumSegmentLengthFactor;
  final double grainBreakup;
  final double edgeRoughness;
  final double endpointTaperBrushLengths;

  void validate() {
    if (!widthFactor.isFinite ||
        widthFactor <= 0 ||
        widthFactor > 2 ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        !maximumSegmentLengthFactor.isFinite ||
        maximumSegmentLengthFactor < .05 ||
        maximumSegmentLengthFactor > 1 ||
        !grainBreakup.isFinite ||
        grainBreakup < 0 ||
        grainBreakup > .5 ||
        !edgeRoughness.isFinite ||
        edgeRoughness < 0 ||
        edgeRoughness > .3 ||
        !endpointTaperBrushLengths.isFinite ||
        endpointTaperBrushLengths < 0 ||
        endpointTaperBrushLengths > 4 ||
        crossSection.length < 2 ||
        crossSection.length > 8) {
      throw ArgumentError('Invalid unified brush carrier profile.');
    }
    var previous = double.negativeInfinity;
    for (final sample in crossSection) {
      if (!sample.normalFactor.isFinite ||
          sample.normalFactor < -.5 ||
          sample.normalFactor > .5 ||
          sample.normalFactor <= previous ||
          !sample.coverage.isFinite ||
          sample.coverage < 0 ||
          sample.coverage > 1) {
        throw ArgumentError('Invalid unified brush carrier cross-section.');
      }
      previous = sample.normalFactor;
    }
  }

  Map<String, Object> toJson() => <String, Object>{
        'width_factor': widthFactor,
        'opacity': opacity,
        'cross_section': <Object>[
          for (final sample in crossSection) sample.toJson(),
        ],
        'maximum_segment_length_factor': maximumSegmentLengthFactor,
        'grain_breakup': grainBreakup,
        'edge_roughness': edgeRoughness,
        'endpoint_taper_brush_lengths': endpointTaperBrushLengths,
      };
}

/// The single production brush expression.
///
/// A program is a composition of the existing shape field, raster role
/// program, behavior, kernel, deposition model, and dynamics metadata. It is
/// intentionally a small value object: it does not own a renderer, a cache,
/// pointer semantics, or a second resource system.
@immutable
class PawUnifiedBrushProgram {
  const PawUnifiedBrushProgram({
    required this.id,
    required this.revision,
    required this.shape,
    required this.kernelKind,
    required this.kernel,
    this.behavior,
    this.rasterProgram,
    this.grainMode = PawUnifiedBrushGrainMode.none,
    this.deposition = PawUnifiedBrushDepositionModel.opaqueUniform,
    this.dynamics = const PawUnifiedBrushDynamicsProfile(),
    this.supportsStatefulMaterial = false,
    this.renderRepresentation = PawUnifiedBrushRenderRepresentation.contactMesh,
    this.renderPlan =
        const PawCompiledBrushRenderPlan(needsCanvasContact: true),
    this.carrier,
    this.endpoint,
  });

  final String id;
  final int revision;
  final PawBrushShapeField shape;
  final PawBrushKernelKind kernelKind;
  final PawBrushKernel kernel;
  final PawBrushBehavior? behavior;
  final PawPreparedBrushRasterProgram? rasterProgram;
  final PawUnifiedBrushGrainMode grainMode;
  final PawUnifiedBrushDepositionModel deposition;
  final PawUnifiedBrushDynamicsProfile dynamics;
  final bool supportsStatefulMaterial;
  final PawUnifiedBrushRenderRepresentation renderRepresentation;
  final PawCompiledBrushRenderPlan renderPlan;
  final PawUnifiedBrushCarrierProfile? carrier;
  final PawUnifiedBrushEndpointProfile? endpoint;

  /// Compatibility view for programs that only declared the former
  /// representation enum. New compilers always provide [renderPlan].
  PawCompiledBrushRenderPlan get compiledRenderPlan {
    if (carrier != null && !renderPlan.needsCarrier) {
      return const PawCompiledBrushRenderPlan(
        needsPreparedTip: true,
        needsCarrier: true,
      );
    }
    if (renderRepresentation ==
            PawUnifiedBrushRenderRepresentation.preparedStamp &&
        !renderPlan.needsPreparedTip) {
      return const PawCompiledBrushRenderPlan(needsPreparedTip: true);
    }
    return renderPlan;
  }

  PawBrushShapeField get shapeField => shape;
  PawPreparedBrushRasterProgram? get raster => rasterProgram;

  void validate() {
    if (id.isEmpty || revision < 1) {
      throw ArgumentError('Invalid unified brush program identity.');
    }
    dynamics.validate();
    renderPlan.validate();
    carrier?.validate();
    endpoint?.validate();
    if (renderRepresentation == PawUnifiedBrushRenderRepresentation.hybrid &&
        carrier == null) {
      throw ArgumentError('A hybrid program must declare its carrier.');
    }
    if (renderRepresentation != PawUnifiedBrushRenderRepresentation.hybrid &&
        carrier != null) {
      throw ArgumentError('Only a hybrid program may declare a carrier.');
    }
    if ((renderPlan.needsStatefulDensity ||
            renderPlan.needsWetMediaTiles ||
            renderPlan.needsTemporalContact) !=
        supportsStatefulMaterial) {
      throw ArgumentError('Stateful capability and program state must agree.');
    }
    if (kernelKind == PawBrushKernelKind.bristleFilament &&
        shape.kind != PawBrushShapeKind.proceduralBristle) {
      throw ArgumentError(
        'A bristle program must expose a procedural bristle shape field.',
      );
    }
    if (kernelKind == PawBrushKernelKind.softDensity &&
        deposition != PawUnifiedBrushDepositionModel.airbrushDensity) {
      throw ArgumentError(
        'A soft program must use the airbrush density deposition model.',
      );
    }
  }

  /// Evaluates the existing behavior and kernel through one explicit program
  /// boundary. All supplied mutable objects are cache-owned scratch objects;
  /// this method allocates nothing on the pointer-move path.
  void evaluateKernelInto({
    required PawBrushBehaviorDab dab,
    required PawBrushKernelInput input,
    required PawBrushKernelOutput output,
    required double brushSize,
    required double flow,
    required Offset previousTangent,
    required Offset followingTangent,
    required bool preserveFurDirectionDiscontinuity,
    required PawFiberClusterGenerator fiberClusterGenerator,
    required PawFiberCluster fiberCluster,
    required PawInkDabResponse inkResponse,
    required PawSoftTileDensityAccumulator? softAccumulator,
  }) {
    input
      ..reset()
      ..brushSize = brushSize;
    final selectedBehavior = behavior;
    if (selectedBehavior case final PawInkBehavior ink) {
      ink.evaluateInto(dab, inkResponse);
      input
        ..widthScale = inkResponse.widthScale
        ..opacityScale = inkResponse.opacityScale
        ..overlapDarkening = inkResponse.overlapDarkening
        ..velocityThinning = inkResponse.velocityThinning;
    } else if (selectedBehavior case final PawFurBehavior fur) {
      assert(identical(fiberClusterGenerator.behavior, fur));
      fiberClusterGenerator.generateInto(
        dab: dab,
        previousTangent: previousTangent,
        followingTangent: followingTangent,
        preserveDirectionDiscontinuity: preserveFurDirectionDiscontinuity,
        brushSize: brushSize,
        fiberCount: 0,
        output: fiberCluster,
      );
      input
        ..spread = fiberCluster.spread
        ..lengthScale = fiberCluster.length
        ..density = fiberCluster.density
        ..tipFade = fiberCluster.tipFade
        ..directionX = fiberCluster.direction.dx
        ..directionY = fiberCluster.direction.dy;
    } else if (selectedBehavior case final PawSoftBehavior soft) {
      final accumulator = softAccumulator;
      if (accumulator == null) {
        throw StateError('Soft behavior requires the render-cache density.');
      }
      final density = soft.accumulate(
        dab: dab,
        brushSize: brushSize,
        accumulator: accumulator,
        flow: flow,
      );
      input
        ..accumulatedDensity = density
        ..opacityScale = soft.opacityScaleForDensity(density);
    }
    kernel.evaluateInto(dab: dab, input: input, output: output);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'revision': revision,
        'kernel': kernelKind.name,
        'shape': shape.kind.name,
        'grain_mode': grainMode.name,
        'deposition': deposition.name,
        'stateful_material': supportsStatefulMaterial,
        'render_representation': renderRepresentation.name,
        'compiled_render_plan': compiledRenderPlan.toJson(),
        'carrier': carrier?.toJson(),
        'endpoint': endpoint?.toJson(),
        'raster_roles': rasterProgram?.cache.resources
            .map((resource) => resource.resourceId)
            .toList(growable: false),
        'dynamics': dynamics.toJson(),
      };
}

/// A stable dab-like sample used by offline tools and tests. It deliberately
/// implements the same narrow behavior input consumed by the production
/// behavior layer without importing pointer events or a widget.
@immutable
class PawUnifiedBrushOfflineDab implements PawBrushBehaviorDab {
  const PawUnifiedBrushOfflineDab({
    required this.point,
    required this.tangent,
    required this.hash,
    required this.pressure,
    required this.speedPixelsPerSecond,
    this.signedCurvature = 0,
  });

  @override
  final Offset point;
  @override
  final Offset tangent;
  @override
  final int hash;
  @override
  final double pressure;
  @override
  final double speedPixelsPerSecond;
  @override
  final double signedCurvature;
}
