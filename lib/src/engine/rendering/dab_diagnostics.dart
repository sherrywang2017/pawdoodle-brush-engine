part of '../../streaming_dab_brush.dart';

enum PawDabBatchCommandKind { drawAtlas, drawVertices, drawPreparedStamp }

extension PawDabBatchCommandContract on PawDabBatchCommandKind {
  bool get usesOffscreenLayer => switch (this) {
        PawDabBatchCommandKind.drawAtlas ||
        PawDabBatchCommandKind.drawVertices ||
        PawDabBatchCommandKind.drawPreparedStamp =>
          false,
      };

  bool get readsPixels => switch (this) {
        PawDabBatchCommandKind.drawAtlas ||
        PawDabBatchCommandKind.drawVertices ||
        PawDabBatchCommandKind.drawPreparedStamp =>
          false,
      };
}

@immutable
class PawDabResourceCacheDiagnostics {
  const PawDabResourceCacheDiagnostics({
    required this.entryCount,
    required this.capacity,
    required this.atlasCreationCount,
    required this.evictionCount,
    required this.ownerImageDisposalCount,
    required this.liveLeaseCount,
    required this.leaseImageDisposalCount,
    required this.keys,
  });

  final int entryCount;
  final int capacity;
  final int atlasCreationCount;
  final int evictionCount;
  final int ownerImageDisposalCount;
  final int liveLeaseCount;
  final int leaseImageDisposalCount;
  final List<String> keys;
}

@immutable
class PawDabRenderCommandDiagnostics {
  const PawDabRenderCommandDiagnostics({
    required this.batchCount,
    required this.kinds,
    required this.resourceCreationsDuringSync,
  });

  final int batchCount;
  final Set<PawDabBatchCommandKind> kinds;
  final int resourceCreationsDuringSync;
}

@immutable
class PawDabSealedCacheDiagnostics {
  const PawDabSealedCacheDiagnostics({
    required this.sealedSourcePictureCount,
    required this.tailPictureCount,
    required this.flattenedImageCount,
    required this.flattenedPixelCount,
    required this.flattenedRasterScales,
    required this.logicalSize,
    required this.rasterScale,
    required this.retainedGeometryPayloadProxy,
  });

  final int sealedSourcePictureCount;
  final int tailPictureCount;
  final int flattenedImageCount;
  final int flattenedPixelCount;
  final List<double> flattenedRasterScales;
  final Size logicalSize;
  final double rasterScale;
  final PawBrushGeometryPayloadProxy retainedGeometryPayloadProxy;

  int get retainedPictureCount => sealedSourcePictureCount + tailPictureCount;

  int get flattenedRgbaByteBudget => flattenedPixelCount * 4;
}
