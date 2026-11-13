part of '../../streaming_dab_brush.dart';

/// Immutable brush parameters required by the shared Dab emission helpers.
/// A live streaming stroke and a detached preview snapshot can both provide
/// this view without introducing another centerline model.
abstract interface class PawDabEmissionSource {
  PawDabBrushDefinition get definition;
  Object get emissionIdentity;
  PawStrokeTextureSeed get seed;
  Color get color;
  double get brushSize;
  double get opacity;
  PawBrushEnvironmentSnapshot get environment;
  Iterable<PawBrushEmissionSegment> get emissionSegments;
  int get revision;
  int get centerlineReplacementEpoch;
  double get acceptedEndArc;
  double get sealedEndArc;
  double get causalStableEndArc;
  double get renderEndArc;
  Offset? get strokeStartPosition;
  PawBrushEmissionSegment? emissionSegmentAtArc(double arc);
  PawStreamingMotionSample? emissionMotionSampleAtArc(double arc);
  PawStreamingMotionSample get tapMotionSample;
}

/// Only explicit assisted replacements can be topologically closed. Merely
/// bringing two freehand endpoints close must not silently join a stroke.
extension PawDabSourceTopology on PawDabEmissionSource {
  bool get isClosed {
    if (centerlineReplacementEpoch == 0 || renderEndArc <= .001) return false;
    final first = emissionSegmentAtArc(0);
    final last = emissionSegmentAtArc(renderEndArc);
    return first != null &&
        last != null &&
        (first.p0 - last.p1).distance < .001;
  }

  double wrapArc(double arc) => isClosed ? arc % renderEndArc : arc;
}

/// One globally identified DAB planned from immutable centerline emission.
/// Preview and commit consume this exact value contract.
@immutable
class PawPlannedDab implements PawBrushBehaviorDab {
  const PawPlannedDab({
    required this.globalDabIndex,
    required this.absoluteArc,
    required this.segmentIndex,
    required this.segmentAmount,
    required this.point,
    required this.tangent,
    required this.motion,
    required this.hash,
  });

  final int globalDabIndex;
  final double absoluteArc;
  final int segmentIndex;
  final double segmentAmount;
  @override
  final Offset point;
  @override
  final Offset tangent;
  final PawStreamingMotionSample motion;
  @override
  final int hash;

  @override
  double get pressure => motion.pressure;

  @override
  double get speedPixelsPerSecond => motion.speedPixelsPerSecond;

  @override
  double get signedCurvature => motion.signedCurvature;
}

/// Pure absolute-arc emission planner shared by live preview and commit.
class PawDabEmissionPlanner {
  const PawDabEmissionPlanner();

  double spacingFor(PawDabEmissionSource source) => math.max(
        .25,
        source.brushSize * source.definition.emission.spacingFactor,
      );

  double positiveOffsetMarginFor(PawDabEmissionSource source) =>
      spacingFor(source) *
      source.definition.emission.dynamics.maximumPositiveSpacingOffsetFactor;

  int endExclusiveForVisibleArc(PawDabEmissionSource source) => math.min(
        ((source.renderEndArc + positiveOffsetMarginFor(source)) /
                    spacingFor(source))
                .ceil() +
            1,
        1 << 30,
      );

  List<PawPlannedDab> planRange({
    required PawDabEmissionSource source,
    required int startIndex,
    required int endExclusive,
  }) {
    if (startIndex < 0 || endExclusive < startIndex) {
      throw RangeError.range(endExclusive, startIndex, 1 << 30);
    }
    final spacing = spacingFor(source);
    final result = <PawPlannedDab>[];
    for (var index = startIndex; index < endExclusive; index++) {
      final hash = PawDabResource._hash(
        source.seed.value ^ source.definition.identitySalt,
        index,
      );
      final nominalArc = index * spacing;
      final nominalSpeed =
          source.definition.emission.dynamics.speedSpacingFactor == 0
              ? 0.0
              : source
                      .emissionMotionSampleAtArc(nominalArc)
                      ?.speedPixelsPerSecond ??
                  0;
      final absoluteArc = source.definition.emission.dynamics.arcForDab(
        index: index,
        spacing: spacing,
        hash: hash,
        speedPixelsPerSecond: nominalSpeed,
      );
      final segment = source.emissionSegmentAtArc(absoluteArc);
      if (segment == null) continue;
      final amount = ((absoluteArc - segment.arcStart) /
              math.max(.000001, segment.arcEnd - segment.arcStart))
          .clamp(0.0, 1.0)
          .toDouble();
      final sample =
          segment.sampleAtArcFraction(amount, absoluteArc: absoluteArc);
      result.add(
        PawPlannedDab(
          globalDabIndex: index,
          absoluteArc: absoluteArc,
          segmentIndex: segment.index,
          segmentAmount: amount,
          point: sample.point,
          tangent: sample.tangent,
          motion: sample.motion,
          hash: hash,
        ),
      );
    }
    return List<PawPlannedDab>.unmodifiable(result);
  }
}

@immutable
class PawDabEmissionSnapshotSource implements PawDabEmissionSource {
  PawDabEmissionSnapshotSource({
    required this.definition,
    required this.emissionIdentity,
    required this.seed,
    required this.color,
    required this.brushSize,
    required this.opacity,
    required this.environment,
    required Iterable<PawBrushEmissionSegment> emissionSegments,
    required this.revision,
    this.centerlineReplacementEpoch = 0,
    required this.sealedEndArc,
    double? acceptedEndArc,
    double? causalStableEndArc,
    required this.renderEndArc,
    required this.strokeStartPosition,
    required this.tapMotionSample,
  })  : acceptedEndArc = acceptedEndArc ?? sealedEndArc,
        causalStableEndArc =
            causalStableEndArc ?? acceptedEndArc ?? sealedEndArc,
        emissionSegments =
            List<PawBrushEmissionSegment>.unmodifiable(emissionSegments);

  @override
  final PawDabBrushDefinition definition;
  @override
  final Object emissionIdentity;
  @override
  final PawStrokeTextureSeed seed;
  @override
  final Color color;
  @override
  final double brushSize;
  @override
  final double opacity;
  @override
  final PawBrushEnvironmentSnapshot environment;
  @override
  final List<PawBrushEmissionSegment> emissionSegments;
  @override
  final int revision;
  @override
  final int centerlineReplacementEpoch;
  @override
  final double acceptedEndArc;
  @override
  final double sealedEndArc;
  @override
  final double causalStableEndArc;
  @override
  final double renderEndArc;
  @override
  final Offset? strokeStartPosition;
  @override
  final PawStreamingMotionSample tapMotionSample;

  @override
  PawBrushEmissionSegment? emissionSegmentAtArc(double arc) {
    if (!arc.isFinite || emissionSegments.isEmpty) return null;
    var low = 0;
    var high = emissionSegments.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final segment = emissionSegments[middle];
      if (arc < segment.arcStart) {
        high = middle - 1;
      } else if (arc > segment.arcEnd) {
        low = middle + 1;
      } else {
        return segment;
      }
    }
    return arc <= emissionSegments.first.arcStart
        ? emissionSegments.first
        : emissionSegments.last;
  }

  @override
  PawStreamingMotionSample? emissionMotionSampleAtArc(double arc) {
    final segment = emissionSegmentAtArc(arc);
    if (segment == null) return null;
    final amount = ((arc - segment.arcStart) /
            math.max(.000001, segment.arcEnd - segment.arcStart))
        .clamp(0.0, 1.0)
        .toDouble();
    return segment.motionAt(amount, absoluteArc: arc);
  }
}
