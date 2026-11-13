import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'drawing_history.dart';
import 'drawing_raster.dart';
import 'streaming_brush_engine.dart';

@immutable
class PawRasterizedMask {
  const PawRasterizedMask(
      {required this.left,
      required this.top,
      required this.width,
      required this.height,
      required this.alpha,
      this.rgba});
  final int left;
  final int top;
  final int width;
  final int height;
  final Uint8List alpha;
  final Uint8List? rgba;
  bool get isEmpty => width == 0 || height == 0;
}

@immutable
class PawStrokeRasterization {
  const PawStrokeRasterization(
      {required this.mask,
      required this.offscreenDuration,
      required this.readbackDuration});
  final PawRasterizedMask mask;
  final Duration offscreenDuration;
  final Duration readbackDuration;
}

@immutable
class PawStrokeCommitResult {
  const PawStrokeCommitResult(
      {required this.raster,
      required this.rasterization,
      required this.compositeDuration,
      this.changedBounds});
  final DrawingRaster raster;
  final PawStrokeRasterization rasterization;
  final Duration compositeDuration;
  final PawPixelRect? changedBounds;
  Duration get totalDuration =>
      rasterization.offscreenDuration +
      rasterization.readbackDuration +
      compositeDuration;
}

class PawStrokeCommitter {
  const PawStrokeCommitter();

  Future<PawStrokeCommitResult> commitStreamingInteraction(
      {required DrawingRaster source,
      required PawStreamingBrushInteraction interaction}) async {
    interaction.stroke.freeze();
    final rasterWatch = Stopwatch()..start();
    final mask = await interaction.rasterize(
        canvasWidth: source.width,
        canvasHeight: source.height,
        rasterScale: source.pixelScale);
    rasterWatch.stop();
    final rasterization = PawStrokeRasterization(
        mask: PawRasterizedMask(
            left: mask.left,
            top: mask.top,
            width: mask.width,
            height: mask.height,
            alpha: mask.alpha,
            rgba: mask.rgba),
        offscreenDuration: rasterWatch.elapsed,
        readbackDuration: Duration.zero);
    final compositeWatch = Stopwatch()..start();
    if (interaction.compositeOperation ==
        PawStreamingCompositeOperation.erase) {
      final edit = DrawingRasterEditor.applyEraserMask(
          source: source,
          maskLeft: mask.left,
          maskTop: mask.top,
          maskWidth: mask.width,
          maskHeight: mask.height,
          maskAlpha: mask.alpha);
      compositeWatch.stop();
      final bounds = edit.changedBounds;
      return PawStrokeCommitResult(
          raster: edit.raster,
          rasterization: rasterization,
          compositeDuration: compositeWatch.elapsed,
          changedBounds: bounds == null
              ? null
              : PawPixelRect.fromLTRB(bounds.left.toInt(), bounds.top.toInt(),
                  bounds.right.toInt(), bounds.bottom.toInt()));
    }
    final rgba = mask.rgba;
    final raster = rgba == null
        ? DrawingRasterEditor.compositeStrokeMask(
            source: source,
            maskLeft: mask.left,
            maskTop: mask.top,
            maskWidth: mask.width,
            maskHeight: mask.height,
            maskAlpha: mask.alpha,
            color: interaction.stroke.color.withValues(alpha: 1),
            opacity: 1,
          )
        : DrawingRasterEditor.compositeStrokeRgba(
            source: source,
            sourceLeft: mask.left,
            sourceTop: mask.top,
            sourceWidth: mask.width,
            sourceHeight: mask.height,
            sourceRgba: rgba,
          );
    compositeWatch.stop();
    return PawStrokeCommitResult(
        raster: raster,
        rasterization: rasterization,
        compositeDuration: compositeWatch.elapsed);
  }
}
