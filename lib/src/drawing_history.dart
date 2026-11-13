import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'drawing_raster.dart';

abstract final class DrawingHistoryConfig {
  static const int patchTileSize = 16;
  static const int fillPatchTileSize = 32;
  static const int checkpointInterval = 20;
  static const int checkpointPatchByteThreshold = 8 * 1024 * 1024;

  /// Includes the operation-zero base checkpoint.
  static const int maximumRetainedCheckpoints = 5;
}

@immutable
class PawPixelRect {
  const PawPixelRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  })  : assert(width >= 0),
        assert(height >= 0);

  factory PawPixelRect.fromLTRB(int left, int top, int right, int bottom) {
    if (right < left || bottom < top) {
      throw ArgumentError('Pixel bounds must have non-negative dimensions');
    }
    return PawPixelRect(
      left: left,
      top: top,
      width: right - left,
      height: bottom - top,
    );
  }

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  bool get isEmpty => width == 0 || height == 0;
  int get pixelCount => width * height;

  PawPixelRect clipTo(int canvasWidth, int canvasHeight) {
    final clippedLeft = left.clamp(0, canvasWidth);
    final clippedTop = top.clamp(0, canvasHeight);
    final clippedRight = right.clamp(0, canvasWidth);
    final clippedBottom = bottom.clamp(0, canvasHeight);
    return PawPixelRect.fromLTRB(
      math.min(clippedLeft, clippedRight),
      math.min(clippedTop, clippedBottom),
      math.max(clippedLeft, clippedRight),
      math.max(clippedTop, clippedBottom),
    );
  }

  bool overlaps(PawPixelRect other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;

  @override
  bool operator ==(Object other) =>
      other is PawPixelRect &&
      left == other.left &&
      top == other.top &&
      width == other.width &&
      height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PawPixelRect($left, $top, $width, $height)';
}

sealed class DrawingPatchPayload {
  const DrawingPatchPayload();

  int get byteLength;
  bool get isTransparent;
}

@immutable
class DrawingPatchRgba extends DrawingPatchPayload {
  DrawingPatchRgba(Uint8List pixels)
      : _pixels = Uint8List.fromList(pixels),
        super();

  final Uint8List _pixels;

  Uint8List get pixels => Uint8List.fromList(_pixels);

  @override
  int get byteLength => _pixels.lengthInBytes;

  @override
  bool get isTransparent => false;
}

@immutable
class DrawingPatchTransparent extends DrawingPatchPayload {
  const DrawingPatchTransparent();

  @override
  int get byteLength => 0;

  @override
  bool get isTransparent => true;
}

@immutable
class DrawingRasterPatchRegion {
  factory DrawingRasterPatchRegion({
    required PawPixelRect bounds,
    required DrawingPatchPayload before,
    required DrawingPatchPayload after,
  }) {
    if (bounds.isEmpty || bounds.left < 0 || bounds.top < 0) {
      throw ArgumentError.value(bounds, 'bounds', 'Invalid patch bounds');
    }
    final expectedLength = bounds.pixelCount * 4;
    _validatePayloadLength(before, expectedLength, 'before');
    _validatePayloadLength(after, expectedLength, 'after');
    return DrawingRasterPatchRegion._(
      bounds: bounds,
      before: before,
      after: after,
    );
  }

  const DrawingRasterPatchRegion._({
    required this.bounds,
    required this.before,
    required this.after,
  });

  final PawPixelRect bounds;
  final DrawingPatchPayload before;
  final DrawingPatchPayload after;

  int get byteLength => before.byteLength + after.byteLength;

  static void _validatePayloadLength(
    DrawingPatchPayload payload,
    int expectedLength,
    String name,
  ) {
    if (payload is DrawingPatchRgba &&
        payload._pixels.length != expectedLength) {
      throw ArgumentError.value(
        payload._pixels.length,
        name,
        'Expected $expectedLength RGBA bytes',
      );
    }
  }
}

enum DrawingHistoryOperationKind { brush, eraser, fill, clear, restore }

@immutable
class DrawingRasterPatch {
  factory DrawingRasterPatch({
    required int canvasWidth,
    required int canvasHeight,
    required double pixelScale,
    required Iterable<DrawingRasterPatchRegion> regions,
    required DrawingHistoryOperationKind operationKind,
  }) {
    if (canvasWidth <= 0 || canvasHeight <= 0) {
      throw ArgumentError('Patch canvas dimensions must be positive');
    }
    if (!pixelScale.isFinite || pixelScale <= 0) {
      throw ArgumentError.value(pixelScale, 'pixelScale');
    }
    final copiedRegions = List<DrawingRasterPatchRegion>.unmodifiable(regions);
    for (var index = 0; index < copiedRegions.length; index++) {
      final region = copiedRegions[index];
      if (region.bounds.right > canvasWidth ||
          region.bounds.bottom > canvasHeight) {
        throw ArgumentError.value(
          region.bounds,
          'regions',
          'Patch region exceeds the canvas',
        );
      }
      for (var otherIndex = 0; otherIndex < index; otherIndex++) {
        if (region.bounds.overlaps(copiedRegions[otherIndex].bounds)) {
          throw ArgumentError('Patch regions must not overlap');
        }
      }
    }
    return DrawingRasterPatch._(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      pixelScale: pixelScale,
      regions: copiedRegions,
      operationKind: operationKind,
    );
  }

  const DrawingRasterPatch._({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.pixelScale,
    required this.regions,
    required this.operationKind,
  });

  final int canvasWidth;
  final int canvasHeight;
  final double pixelScale;
  final List<DrawingRasterPatchRegion> regions;
  final DrawingHistoryOperationKind operationKind;

  bool get isEmpty => regions.isEmpty;
  int get byteLength =>
      regions.fold(0, (total, region) => total + region.byteLength);
}

abstract final class DrawingRasterPatchCodec {
  static DrawingRasterPatch extract({
    required DrawingRaster before,
    required DrawingRaster after,
    required PawPixelRect candidateBounds,
    required DrawingHistoryOperationKind operationKind,
    int tileSize = DrawingHistoryConfig.patchTileSize,
  }) {
    _validateCompatible(before, after);
    if (tileSize <= 0) {
      throw ArgumentError.value(tileSize, 'tileSize');
    }
    final clipped = candidateBounds.clipTo(before.width, before.height);
    if (clipped.isEmpty) {
      return DrawingRasterPatch(
        canvasWidth: before.width,
        canvasHeight: before.height,
        pixelScale: before.pixelScale,
        regions: const <DrawingRasterPatchRegion>[],
        operationKind: operationKind,
      );
    }

    final regions = <DrawingRasterPatchRegion>[];
    final firstTileX = clipped.left ~/ tileSize;
    final firstTileY = clipped.top ~/ tileSize;
    final lastTileX = (clipped.right - 1) ~/ tileSize;
    final lastTileY = (clipped.bottom - 1) ~/ tileSize;
    for (var tileY = firstTileY; tileY <= lastTileY; tileY++) {
      for (var tileX = firstTileX; tileX <= lastTileX; tileX++) {
        final tileLeft = math.max(clipped.left, tileX * tileSize);
        final tileTop = math.max(clipped.top, tileY * tileSize);
        final tileRight = math.min(clipped.right, (tileX + 1) * tileSize);
        final tileBottom = math.min(clipped.bottom, (tileY + 1) * tileSize);
        final changed = _changedBounds(
          before,
          after,
          tileLeft,
          tileTop,
          tileRight,
          tileBottom,
        );
        if (changed == null) continue;
        final beforeBytes = _extractBytes(before, changed);
        final afterBytes = _extractBytes(after, changed);
        regions.add(DrawingRasterPatchRegion(
          bounds: changed,
          before: _payloadFor(beforeBytes),
          after: _payloadFor(afterBytes),
        ));
      }
    }
    return DrawingRasterPatch(
      canvasWidth: before.width,
      canvasHeight: before.height,
      pixelScale: before.pixelScale,
      regions: regions,
      operationKind: operationKind,
    );
  }

  static DrawingRaster apply(
    DrawingRaster source,
    DrawingRasterPatch patch, {
    required bool useAfter,
  }) {
    if (source.width != patch.canvasWidth ||
        source.height != patch.canvasHeight ||
        source.pixelScale != patch.pixelScale) {
      throw StateError('Patch and raster dimensions or pixel scale differ');
    }
    final pixels = Uint8List.fromList(source.pixels);
    for (final region in patch.regions) {
      _writePayload(
        pixels,
        source.width,
        region.bounds,
        useAfter ? region.after : region.before,
      );
    }
    return source.copyWithPixels(pixels);
  }

  static void _validateCompatible(DrawingRaster before, DrawingRaster after) {
    if (before.width != after.width ||
        before.height != after.height ||
        before.pixelScale != after.pixelScale) {
      throw StateError('Cannot diff incompatible drawing rasters');
    }
  }

  static PawPixelRect? _changedBounds(
    DrawingRaster before,
    DrawingRaster after,
    int left,
    int top,
    int right,
    int bottom,
  ) {
    var changedLeft = right;
    var changedTop = bottom;
    var changedRight = left - 1;
    var changedBottom = top - 1;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final index = (y * before.width + x) * 4;
        var differs = false;
        for (var channel = 0; channel < 4; channel++) {
          if (before.pixels[index + channel] != after.pixels[index + channel]) {
            differs = true;
            break;
          }
        }
        if (!differs) continue;
        changedLeft = math.min(changedLeft, x);
        changedTop = math.min(changedTop, y);
        changedRight = math.max(changedRight, x);
        changedBottom = math.max(changedBottom, y);
      }
    }
    if (changedRight < changedLeft) return null;
    return PawPixelRect.fromLTRB(
      changedLeft,
      changedTop,
      changedRight + 1,
      changedBottom + 1,
    );
  }

  static Uint8List _extractBytes(DrawingRaster raster, PawPixelRect bounds) {
    final result = Uint8List(bounds.pixelCount * 4);
    for (var row = 0; row < bounds.height; row++) {
      final sourceStart = ((bounds.top + row) * raster.width + bounds.left) * 4;
      final targetStart = row * bounds.width * 4;
      result.setRange(
        targetStart,
        targetStart + bounds.width * 4,
        raster.pixels,
        sourceStart,
      );
    }
    return result;
  }

  static DrawingPatchPayload _payloadFor(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte != 0) return DrawingPatchRgba(bytes);
    }
    return const DrawingPatchTransparent();
  }

  static void _writePayload(
    Uint8List target,
    int canvasWidth,
    PawPixelRect bounds,
    DrawingPatchPayload payload,
  ) {
    final rgba = payload is DrawingPatchRgba ? payload._pixels : null;
    for (var row = 0; row < bounds.height; row++) {
      final targetStart = ((bounds.top + row) * canvasWidth + bounds.left) * 4;
      final length = bounds.width * 4;
      if (rgba == null) {
        target.fillRange(targetStart, targetStart + length, 0);
      } else {
        final sourceStart = row * length;
        target.setRange(
          targetStart,
          targetStart + length,
          rgba,
          sourceStart,
        );
      }
    }
  }
}

@immutable
class DrawingHistoryEntry {
  const DrawingHistoryEntry({
    required this.operationIndex,
    required this.patch,
    this.committedAt,
  });

  final int operationIndex;
  final DrawingRasterPatch patch;
  final DateTime? committedAt;
}

@immutable
class DrawingRasterCheckpoint {
  DrawingRasterCheckpoint({
    required this.operationIndex,
    required DrawingRaster raster,
  }) : raster = _copyRaster(raster);

  final int operationIndex;
  final DrawingRaster raster;

  int get byteLength => raster.byteLength;
}

@immutable
class DrawingHistoryDiagnostics {
  const DrawingHistoryDiagnostics({
    required this.operationCount,
    required this.cursor,
    required this.redoCount,
    required this.patchRegionCount,
    required this.latestPatchBytes,
    required this.totalPatchBytes,
    required this.redoBytes,
    required this.checkpointCount,
    required this.checkpointBytes,
    required this.totalHistoryBytes,
    required this.equivalentFullSnapshotBytes,
    required this.memoryReductionRatio,
  });

  final int operationCount;
  final int cursor;
  final int redoCount;
  final int patchRegionCount;
  final int latestPatchBytes;
  final int totalPatchBytes;
  final int redoBytes;
  final int checkpointCount;
  final int checkpointBytes;
  final int totalHistoryBytes;
  final int equivalentFullSnapshotBytes;
  final double memoryReductionRatio;
}

@immutable
class DrawingReplayDiagnostics {
  const DrawingReplayDiagnostics({
    required this.requestedFrame,
    required this.checkpointIndex,
    required this.patchesApplied,
    required this.rebuildDuration,
    required this.staleRebuildCount,
  });

  const DrawingReplayDiagnostics.empty()
      : requestedFrame = -1,
        checkpointIndex = 0,
        patchesApplied = 0,
        rebuildDuration = Duration.zero,
        staleRebuildCount = 0;

  final int requestedFrame;
  final int checkpointIndex;
  final int patchesApplied;
  final Duration rebuildDuration;
  final int staleRebuildCount;
}

abstract interface class DrawingReplaySource {
  int get frameCount;
  DrawingReplayDiagnostics get diagnostics;

  Future<DrawingRaster> frameAt(int index);

  Stream<DrawingRaster> play({
    Duration frameDuration = const Duration(milliseconds: 450),
    int startFrame = 0,
  });
}

class DrawingHistoryReplaySource implements DrawingReplaySource {
  DrawingHistoryReplaySource({
    required List<DrawingHistoryEntry> history,
    required List<DrawingRasterCheckpoint> checkpoints,
    required List<int> frameOperations,
  })  : _history = List<DrawingHistoryEntry>.unmodifiable(history),
        _checkpoints = List<DrawingRasterCheckpoint>.unmodifiable(checkpoints),
        _frameOperations = List<int>.unmodifiable(frameOperations);

  final List<DrawingHistoryEntry> _history;
  final List<DrawingRasterCheckpoint> _checkpoints;
  final List<int> _frameOperations;
  DrawingReplayDiagnostics _diagnostics =
      const DrawingReplayDiagnostics.empty();

  @override
  int get frameCount => _frameOperations.length;

  @override
  DrawingReplayDiagnostics get diagnostics => _diagnostics;

  @override
  Future<DrawingRaster> frameAt(int index) async {
    if (index < 0 || index >= frameCount) {
      throw RangeError.index(index, _frameOperations, 'index');
    }
    return _rebuild(_frameOperations[index], requestedFrame: index);
  }

  @override
  Stream<DrawingRaster> play({
    Duration frameDuration = const Duration(milliseconds: 450),
    int startFrame = 0,
  }) async* {
    if (startFrame < 0 || startFrame > frameCount) {
      throw RangeError.range(startFrame, 0, frameCount, 'startFrame');
    }
    if (startFrame == frameCount) return;
    DrawingRaster? working;
    var workingOperation = -1;
    for (var frame = startFrame; frame < _frameOperations.length; frame++) {
      final operation = _frameOperations[frame];
      if (working == null || operation < workingOperation) {
        working = _rebuild(operation, requestedFrame: frame);
      } else {
        final watch = Stopwatch()..start();
        var applied = 0;
        for (var index = workingOperation; index < operation; index++) {
          working = DrawingRasterPatchCodec.apply(
            working!,
            _history[index].patch,
            useAfter: true,
          );
          applied++;
        }
        watch.stop();
        _diagnostics = DrawingReplayDiagnostics(
          requestedFrame: frame,
          checkpointIndex: workingOperation,
          patchesApplied: applied,
          rebuildDuration: watch.elapsed,
          staleRebuildCount: _diagnostics.staleRebuildCount,
        );
      }
      workingOperation = operation;
      yield working!;
      if (frameDuration > Duration.zero && frame + 1 < frameCount) {
        await Future<void>.delayed(frameDuration);
      }
    }
  }

  DrawingRaster _rebuild(int operation, {required int requestedFrame}) {
    final watch = Stopwatch()..start();
    var checkpoint = _checkpoints.first;
    for (final candidate in _checkpoints) {
      if (candidate.operationIndex <= operation &&
          candidate.operationIndex >= checkpoint.operationIndex) {
        checkpoint = candidate;
      }
    }
    var raster = _copyRaster(checkpoint.raster);
    var applied = 0;
    for (var index = checkpoint.operationIndex; index < operation; index++) {
      raster = DrawingRasterPatchCodec.apply(
        raster,
        _history[index].patch,
        useAfter: true,
      );
      applied++;
    }
    watch.stop();
    _diagnostics = DrawingReplayDiagnostics(
      requestedFrame: requestedFrame,
      checkpointIndex: checkpoint.operationIndex,
      patchesApplied: applied,
      rebuildDuration: watch.elapsed,
      staleRebuildCount: _diagnostics.staleRebuildCount,
    );
    return raster;
  }
}

DrawingRaster _copyRaster(DrawingRaster raster) => DrawingRaster(
      width: raster.width,
      height: raster.height,
      pixels: Uint8List.fromList(raster.pixels),
      hasInk: raster.hasInk,
    );
