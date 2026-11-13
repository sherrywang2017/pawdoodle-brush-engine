part of '../../streaming_dab_brush.dart';

class _PawDabInstance {
  const _PawDabInstance({
    required this.transform,
    required this.sourceRect,
    required this.color,
    required this.center,
    required this.direction,
    required this.pressureSize,
  });

  final ui.RSTransform transform;
  final Rect sourceRect;
  final Color color;
  final Offset center;
  final Offset direction;
  final double pressureSize;
}

class _PawKernelDabScratch implements PawBrushBehaviorDab {
  @override
  Offset point = Offset.zero;
  @override
  Offset tangent = const Offset(1, 0);
  @override
  int hash = 0;
  @override
  double pressure = .5;
  @override
  double speedPixelsPerSecond = 600;
  @override
  double signedCurvature = 0;

  void set({
    required Offset point,
    required Offset tangent,
    required int hash,
    required PawStreamingMotionSample motion,
  }) {
    this.point = point;
    this.tangent = tangent;
    this.hash = hash;
    pressure = motion.pressure;
    speedPixelsPerSecond = motion.speedPixelsPerSecond;
    signedCurvature = motion.signedCurvature;
  }
}

class _PawGeometryPayloadCounter {
  int vertexCount = 0;
  int indexCount = 0;
  int atlasInstanceCount = 0;

  void add({
    required int vertices,
    required int indices,
    required int atlasInstances,
  }) {
    vertexCount += vertices;
    indexCount += indices;
    atlasInstanceCount += atlasInstances;
  }

  PawBrushGeometryPayloadProxy get snapshot => PawBrushGeometryPayloadProxy(
        vertexCountProxy: vertexCount,
        indexCountProxy: indexCount,
        atlasInstanceCountProxy: atlasInstanceCount,
      );
}

class _PawFilamentArcSample {
  const _PawFilamentArcSample({
    required this.segmentIndex,
    required this.point,
    required this.direction,
    required this.normal,
    required this.motion,
    this.arcRate = 1,
  });

  final double arcRate;
  final int segmentIndex;
  final Offset point;
  final Offset direction;
  final Offset normal;
  final PawStreamingMotionSample motion;
}

class _PawFilamentLanePoint {
  const _PawFilamentLanePoint({
    required this.arc,
    required this.center,
    required this.normal,
    required this.normalDistance,
    required this.width,
    required this.color,
  });

  final double arc;
  final Offset center;
  final Offset normal;
  final double normalDistance;
  final double width;
  final Color color;
}

class _PawFilamentLanePlan {
  const _PawFilamentLanePlan({
    required this.hash,
    required this.rootArc,
    required this.length,
    required this.laneOffset,
    required this.stableLaneOffset,
    required this.rootOffsetJitter,
    required this.rootWidth,
    required this.bendPhase,
    required this.directionOffset,
    required this.divisionArcs,
  });

  final int hash;
  final double rootArc;
  final double length;
  final double laneOffset;
  final double stableLaneOffset;
  final double rootOffsetJitter;
  final double rootWidth;
  final double bendPhase;
  final double directionOffset;
  final List<double> divisionArcs;
}
