part of '../../streaming_dab_brush.dart';

@immutable
class PawDabOwnershipDiagnostics {
  const PawDabOwnershipDiagnostics({
    required this.visibleDabExclusive,
    required this.safeDabExclusive,
    required this.nextSealedDabIndex,
    required this.sealedEndArc,
    required this.causalStableEndArc,
    required this.renderEndArc,
    required this.tailStartIndex,
    required this.tailEndExclusive,
    required this.tailDabCount,
    required this.newImmutableDabs,
    required this.newChunkCount,
    required this.recordedChunkCount,
  });

  final int visibleDabExclusive;
  final int safeDabExclusive;
  final int nextSealedDabIndex;
  final double sealedEndArc;
  final double causalStableEndArc;
  final double renderEndArc;
  final int tailStartIndex;
  final int tailEndExclusive;
  final int tailDabCount;
  final int newImmutableDabs;
  final int newChunkCount;
  final int recordedChunkCount;

  int get unownedVisibleDabCount =>
      math.max(0, visibleDabExclusive - tailEndExclusive);

  int get doubleOwnedVisibleDabCount =>
      math.max(0, nextSealedDabIndex - tailStartIndex);

  bool get hasExactVisibleOwnership =>
      tailStartIndex == nextSealedDabIndex &&
      unownedVisibleDabCount == 0 &&
      doubleOwnedVisibleDabCount == 0;
}

@immutable
class _PawPlannedDabIdentity {
  _PawPlannedDabIdentity(
    PawPlannedDab dab, {
    this.materialTailUnit = 1,
    this.endpointProgress = 1,
  })  : globalDabIndex = dab.globalDabIndex,
        absoluteArc = dab.absoluteArc,
        segmentIndex = dab.segmentIndex,
        segmentAmount = dab.segmentAmount,
        point = dab.point,
        tangent = dab.tangent,
        pressure = dab.motion.pressure,
        speedPixelsPerSecond = dab.motion.speedPixelsPerSecond,
        signedCurvature = dab.motion.signedCurvature,
        hash = dab.hash;

  final int globalDabIndex;
  final double absoluteArc;
  final int segmentIndex;
  final double segmentAmount;
  final Offset point;
  final Offset tangent;
  final double pressure;
  final double speedPixelsPerSecond;
  final double signedCurvature;
  final int hash;
  final double materialTailUnit;
  final double endpointProgress;

  @override
  bool operator ==(Object other) =>
      other is _PawPlannedDabIdentity &&
      globalDabIndex == other.globalDabIndex &&
      absoluteArc == other.absoluteArc &&
      segmentIndex == other.segmentIndex &&
      segmentAmount == other.segmentAmount &&
      point == other.point &&
      tangent == other.tangent &&
      pressure == other.pressure &&
      speedPixelsPerSecond == other.speedPixelsPerSecond &&
      signedCurvature == other.signedCurvature &&
      hash == other.hash &&
      materialTailUnit == other.materialTailUnit &&
      endpointProgress == other.endpointProgress;

  @override
  int get hashCode => Object.hash(
        globalDabIndex,
        absoluteArc,
        segmentIndex,
        segmentAmount,
        point,
        tangent,
        pressure,
        speedPixelsPerSecond,
        signedCurvature,
        hash,
        materialTailUnit,
        endpointProgress,
      );
}

@immutable
class _PawEmissionSegmentIdentity {
  _PawEmissionSegmentIdentity(PawBrushEmissionSegment segment)
      : index = segment.index,
        p0 = segment.p0,
        c1 = segment.c1,
        c2 = segment.c2,
        p1 = segment.p1,
        startTangent = segment.startTangent,
        endTangent = segment.endTangent,
        arcStart = segment.arcStart,
        arcEnd = segment.arcEnd,
        startPressure = segment.startPressure,
        endPressure = segment.endPressure,
        startTime = segment.startTime,
        endTime = segment.endTime;

  final int index;
  final Offset p0;
  final Offset c1;
  final Offset c2;
  final Offset p1;
  final Offset startTangent;
  final Offset endTangent;
  final double arcStart;
  final double arcEnd;
  final double startPressure;
  final double endPressure;
  final Duration startTime;
  final Duration endTime;

  @override
  bool operator ==(Object other) =>
      other is _PawEmissionSegmentIdentity &&
      index == other.index &&
      p0 == other.p0 &&
      c1 == other.c1 &&
      c2 == other.c2 &&
      p1 == other.p1 &&
      startTangent == other.startTangent &&
      endTangent == other.endTangent &&
      arcStart == other.arcStart &&
      arcEnd == other.arcEnd &&
      startPressure == other.startPressure &&
      endPressure == other.endPressure &&
      startTime == other.startTime &&
      endTime == other.endTime;

  @override
  int get hashCode => Object.hash(
        index,
        p0,
        c1,
        c2,
        p1,
        startTangent,
        endTangent,
        arcStart,
        arcEnd,
        startPressure,
        endPressure,
        startTime,
        endTime,
      );
}

class _PawRetainedDabChunk {
  const _PawRetainedDabChunk({
    required this.endExclusive,
    required this.command,
    required this.identities,
    required this.segmentIdentities,
    required this.softPrefixSignature,
    required this.geometryPayloadProxy,
  });

  final int endExclusive;

  /// Exact material primitives retained as direct Canvas submissions.
  ///
  /// Mutable and predicted geometry must never be retained as a Picture: a
  /// changed identity replaces this bounded command, while an unchanged
  /// command is replayed without rebuilding Dart geometry. Only promotion to
  /// the immutable prefix records the command into a Picture.
  final _PawDabDirectCommand command;
  final List<_PawPlannedDabIdentity> identities;
  final List<_PawEmissionSegmentIdentity> segmentIdentities;
  final int softPrefixSignature;
  final PawBrushGeometryPayloadProxy geometryPayloadProxy;

  bool matches(
    int nextEndExclusive,
    List<_PawPlannedDabIdentity> nextIdentities,
    List<_PawEmissionSegmentIdentity> nextSegmentIdentities,
    int nextSoftPrefixSignature,
  ) {
    if (endExclusive != nextEndExclusive ||
        softPrefixSignature != nextSoftPrefixSignature ||
        identities.length != nextIdentities.length) {
      return false;
    }
    for (var index = 0; index < identities.length; index++) {
      if (identities[index] != nextIdentities[index]) return false;
    }
    if (segmentIdentities.length != nextSegmentIdentities.length) return false;
    for (var index = 0; index < segmentIdentities.length; index++) {
      if (segmentIdentities[index] != nextSegmentIdentities[index]) {
        return false;
      }
    }
    return true;
  }

  void dispose() => command.dispose();
}

class _PawDabDirectCommand {
  _PawDabDirectCommand({
    required this.body,
    required this.atlas,
    required this.carrier,
    required this.preparedStamp,
    this.carrierVertexCount = 0,
    this.preparedStampVertexCount = 0,
  });

  final _PawDabVerticesBatch? body;
  final _PawDabAtlasBatch? atlas;
  final _PawDabVerticesBatch? carrier;
  final _PawPreparedStampBatch? preparedStamp;
  final int carrierVertexCount;
  final int preparedStampVertexCount;

  // Unknown stamp extents remain uncullable. Contact-only and hair commands
  // already own exact vertex bounds, including their analytic fringe.
  Rect? get bounds {
    if (atlas != null || preparedStamp != null) return null;
    if (body == null) return carrier?.bounds ?? Rect.zero;
    return carrier == null
        ? body!.bounds
        : body!.bounds.expandToInclude(carrier!.bounds);
  }

  int get workUnits =>
      (body == null ? 0 : 1) +
      (atlas == null ? 0 : 1) +
      (carrier == null ? 0 : 1) +
      (preparedStamp == null ? 0 : 1);

  void paint(Canvas canvas, PawDabResource resource) {
    body?.paint(canvas, resource);
    atlas?.paint(canvas, resource);
    carrier?.paint(canvas, resource);
    preparedStamp?.paint(canvas, resource);
  }

  void dispose() {
    body?.dispose();
    carrier?.dispose();
    preparedStamp?.dispose();
  }
}
