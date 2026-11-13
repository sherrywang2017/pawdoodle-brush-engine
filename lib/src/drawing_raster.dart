import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class DrawingRasterImageLoaders {
  @visibleForTesting
  static Future<ui.Image> Function(DrawingRaster raster)? debugOverride;
}

typedef DrawingRasterCompositePainterBuilder = CustomPainter Function(
  ui.Image image,
);

abstract final class DrawingRasterDisplayConfig {
  // Match the bilinear sampling used by live material tiles. Mipmapped
  // downscaling only after commit changes grain coverage on PointerUp.
  static const FilterQuality mainCanvasFilterQuality = FilterQuality.low;
}

enum DrawingTool {
  roundBrush,
  crayon,
  marker,
  softBrush,
  inkBrush,
  furBrush,
  eraser,
}

extension DrawingToolLabel on DrawingTool {
  String get label {
    switch (this) {
      case DrawingTool.roundBrush:
        return 'Round Brush';
      case DrawingTool.crayon:
        return 'Crayon';
      case DrawingTool.marker:
        return 'Marker';
      case DrawingTool.softBrush:
        return 'Soft Brush';
      case DrawingTool.inkBrush:
        return 'Ink Brush';
      case DrawingTool.furBrush:
        return 'Fur Brush';
      case DrawingTool.eraser:
        return 'Eraser';
    }
  }
}

@immutable
class DrawingRaster {
  const DrawingRaster({
    required this.width,
    required this.height,
    required this.pixels,
    required this.hasInk,
  });

  static const schemaVersion = 3;
  static const legacySchemaVersion = 2;

  final int width;
  final int height;

  /// Straight (unpremultiplied) RGBA8888 bytes.
  final Uint8List pixels;
  final bool hasInk;

  String get rasterVersion =>
      width == 1024 && height == 1024 ? 'raster_v2' : 'raster_v1';

  double get pixelScale => rasterVersion == 'raster_v2' ? 2 : 1;

  Size get logicalSize => rasterVersion == 'raster_v2'
      ? const Size(512, 512)
      : Size(width.toDouble(), height.toDouble());

  int get byteLength => pixels.lengthInBytes;

  /// Export the canvas as displayed, rather than leaking the internal square
  /// backing store into galleries. This is a one-time submission transform;
  /// the editor/history remain untouched and stored PNG dimensions carry the
  /// aspect ratio through the existing repository protocol.
  Future<DrawingRaster> forDisplaySize(Size displaySize) async {
    if (!displaySize.width.isFinite ||
        !displaySize.height.isFinite ||
        displaySize.width <= 0 ||
        displaySize.height <= 0) {
      return this;
    }
    final ratio = displaySize.width / displaySize.height;
    final longest = math.max(width, height);
    final outputWidth =
        ratio >= 1 ? longest : math.max(1, (longest * ratio).round());
    final outputHeight =
        ratio >= 1 ? math.max(1, (longest / ratio).round()) : longest;
    if (outputWidth == width && outputHeight == height) return this;
    final source = await toUiImage();
    try {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
          source,
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Rect.fromLTWH(
              0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
          ui.Paint()..filterQuality = FilterQuality.low);
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(outputWidth, outputHeight);
        try {
          final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba);
          if (bytes == null) throw StateError('Could not export canvas');
          return DrawingRaster(
              width: outputWidth,
              height: outputHeight,
              pixels: Uint8List.fromList(bytes.buffer
                  .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)),
              hasInk: hasInk);
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  bool get hasTransparentRgbPollution {
    for (var index = 0; index < pixels.length; index += 4) {
      if (pixels[index + 3] == 0 &&
          (pixels[index] != 0 ||
              pixels[index + 1] != 0 ||
              pixels[index + 2] != 0)) {
        return true;
      }
    }
    return false;
  }

  static DrawingRaster placeholder({bool hasInk = true}) => DrawingRaster(
        width: 1,
        height: 1,
        pixels: Uint8List.fromList(
            hasInk ? const [32, 33, 36, 255] : const [0, 0, 0, 0]),
        hasInk: hasInk,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': schemaVersion,
        'width': width,
        'height': height,
        'format': 'rgba8888',
        'rasterVersion': rasterVersion,
        'logicalWidth': logicalSize.width.toInt(),
        'logicalHeight': logicalSize.height.toInt(),
        'hasInk': hasInk,
        'pixelsBase64': base64Encode(pixels),
      };

  factory DrawingRaster.fromJson(Map<String, dynamic> json) {
    final schema = (json['version'] as num?)?.toInt();
    if (schema != schemaVersion && schema != legacySchemaVersion ||
        json['format'] != 'rgba8888') {
      throw const FormatException('Unsupported raster drawing format');
    }
    final width = (json['width'] as num?)?.toInt();
    final height = (json['height'] as num?)?.toInt();
    final encodedPixels = json['pixelsBase64'] as String?;
    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        encodedPixels == null) {
      throw const FormatException('Invalid raster drawing dimensions');
    }
    final pixels = Uint8List.fromList(base64Decode(encodedPixels));
    if (pixels.length != width * height * 4) {
      throw const FormatException('Invalid raster drawing pixel data');
    }
    final declaredRasterVersion = json['rasterVersion'] as String?;
    if (schema == schemaVersion &&
        declaredRasterVersion != null &&
        declaredRasterVersion != 'raster_v1' &&
        declaredRasterVersion != 'raster_v2') {
      throw const FormatException('Invalid raster drawing version');
    }
    if (declaredRasterVersion == 'raster_v2' &&
        (width != 1024 || height != 1024)) {
      throw const FormatException('Invalid raster_v2 dimensions');
    }
    return DrawingRaster(
      width: width,
      height: height,
      pixels: pixels,
      // The pixels are the source of truth. This prevents a stale hasInk flag
      // from making a visible restored canvas impossible to submit.
      hasInk: _hasInk(pixels),
    );
  }

  static Future<DrawingRaster> fromPngBytes({
    required Uint8List pngBytes,
    required int width,
    required int height,
  }) async {
    final codec = await ui.instantiateImageCodec(
      pngBytes,
      targetWidth: width,
      targetHeight: height,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) throw StateError('Could not decode raster PNG');
    final straightPixels = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return DrawingRaster(
      width: width,
      height: height,
      pixels: Uint8List.fromList(straightPixels),
      hasInk: _hasInk(straightPixels),
    );
  }

  Future<Uint8List> toPngBytes() async {
    final image = await toUiImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode raster PNG');
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image> toUiImage() async {
    // PixelFormat.rgba8888 expects premultiplied bytes. DrawingRaster remains
    // straight RGBA everywhere else, so conversion happens only at this UI
    // image boundary.
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _premultiply(pixels),
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  DrawingRaster copyWithPixels(Uint8List nextPixels) => DrawingRaster(
        width: width,
        height: height,
        pixels: nextPixels,
        hasInk: _hasInk(nextPixels),
      );

  bool hasSamePixelsAs(DrawingRaster other) {
    if (width != other.width ||
        height != other.height ||
        pixels.length != other.pixels.length) {
      return false;
    }
    for (var index = 0; index < pixels.length; index++) {
      if (pixels[index] != other.pixels[index]) return false;
    }
    return true;
  }

  static bool _hasInk(Uint8List bytes) {
    for (var index = 3; index < bytes.length; index += 4) {
      if (bytes[index] != 0) return true;
    }
    return false;
  }

  static Uint8List _premultiply(Uint8List straight) {
    final result = Uint8List(straight.length);
    for (var index = 0; index < straight.length; index += 4) {
      final alpha = straight[index + 3];
      if (alpha == 0) continue;
      result[index] = (straight[index] * alpha / 255).round();
      result[index + 1] = (straight[index + 1] * alpha / 255).round();
      result[index + 2] = (straight[index + 2] * alpha / 255).round();
      result[index + 3] = alpha;
    }
    return result;
  }
}

@immutable
class DrawingEraserEditResult {
  const DrawingEraserEditResult({
    required this.raster,
    required this.changedBounds,
  });

  final DrawingRaster raster;
  final Rect? changedBounds;
}

@immutable
class DrawingFillEditResult {
  const DrawingFillEditResult({
    required this.raster,
    required this.changedBounds,
  });

  final DrawingRaster raster;
  final Rect? changedBounds;
}

class DrawingRasterEditor {
  const DrawingRasterEditor._();

  static const logicalSize = 512;
  static const legacySize = 512;
  static const defaultSize = 1024;

  static DrawingRaster blank({int? size, bool highResolution = true}) {
    final pixelSize = size ?? (highResolution ? defaultSize : legacySize);
    return DrawingRaster(
      width: pixelSize,
      height: pixelSize,
      pixels: Uint8List(pixelSize * pixelSize * 4),
      hasInk: false,
    );
  }

  static DrawingFillEditResult floodFill({
    required DrawingRaster source,
    required Offset normalizedPoint,
    required Color color,
  }) {
    if (source.width == 0 || source.height == 0) {
      return DrawingFillEditResult(raster: source, changedBounds: null);
    }
    final startX =
        (normalizedPoint.dx.clamp(0.0, 1.0) * (source.width - 1)).round();
    final startY =
        (normalizedPoint.dy.clamp(0.0, 1.0) * (source.height - 1)).round();
    final startPixel = startY * source.width + startX;
    final startIndex = startPixel * 4;
    final targetRed = source.pixels[startIndex];
    final targetGreen = source.pixels[startIndex + 1];
    final targetBlue = source.pixels[startIndex + 2];
    final targetAlpha = source.pixels[startIndex + 3];
    final replacementAlpha = (color.a * 255).round().clamp(0, 255);
    final replacementRed =
        replacementAlpha == 0 ? 0 : (color.r * 255).round().clamp(0, 255);
    final replacementGreen =
        replacementAlpha == 0 ? 0 : (color.g * 255).round().clamp(0, 255);
    final replacementBlue =
        replacementAlpha == 0 ? 0 : (color.b * 255).round().clamp(0, 255);
    final replacementMatchesTarget = targetAlpha == replacementAlpha &&
        (targetAlpha == 0 ||
            (targetRed == replacementRed &&
                targetGreen == replacementGreen &&
                targetBlue == replacementBlue));
    if (replacementMatchesTarget) {
      return DrawingFillEditResult(raster: source, changedBounds: null);
    }

    final pixels = Uint8List.fromList(source.pixels);
    final pixelCount = source.width * source.height;
    final words = Uint32List.view(
      pixels.buffer,
      pixels.offsetInBytes,
      pixelCount,
    );
    final targetWord = words[startPixel];
    final replacementWord = Endian.host == Endian.little
        ? replacementRed |
            replacementGreen << 8 |
            replacementBlue << 16 |
            replacementAlpha << 24
        : replacementRed << 24 |
            replacementGreen << 16 |
            replacementBlue << 8 |
            replacementAlpha;

    bool matchesTarget(int pixel) => targetAlpha == 0
        ? pixels[pixel * 4 + 3] == 0
        : words[pixel] == targetWord;

    // A scanline fill keeps one seed per neighboring horizontal span instead
    // of a queue and visited byte for every pixel. The output bytes themselves
    // mark visited pixels because replacementMatchesTarget was handled above.
    var pending = Int32List(math.min(pixelCount, 256));
    var pendingLength = 0;

    void push(int pixel) {
      if (pendingLength == pending.length) {
        final grown = Int32List(pending.length * 2);
        grown.setRange(0, pendingLength, pending);
        pending = grown;
      }
      pending[pendingLength++] = pixel;
    }

    var minX = source.width;
    var minY = source.height;
    var maxX = -1;
    var maxY = -1;
    final fringePixels = <int>{};

    void addAntialiasFringe(int pixel) {
      if (targetAlpha != 0 || pixel < 0 || pixel >= pixelCount) return;
      final alpha = pixels[pixel * 4 + 3];
      if (alpha > 0 && alpha < 255) fringePixels.add(pixel);
    }

    void pushNeighborSpans(int row, int left, int right) {
      if (row < 0 || row >= source.height) return;
      final rowStart = row * source.width;
      var x = left;
      while (x <= right) {
        while (x <= right && !matchesTarget(rowStart + x)) {
          x++;
        }
        if (x > right) return;
        push(rowStart + x);
        while (x <= right && matchesTarget(rowStart + x)) {
          x++;
        }
      }
    }

    push(startPixel);
    while (pendingLength > 0) {
      final seed = pending[--pendingLength];
      if (!matchesTarget(seed)) continue;
      final y = seed ~/ source.width;
      final seedX = seed - y * source.width;
      final rowStart = y * source.width;
      var left = seedX;
      var right = seedX;
      while (left > 0 && matchesTarget(rowStart + left - 1)) {
        left--;
      }
      while (right + 1 < source.width && matchesTarget(rowStart + right + 1)) {
        right++;
      }
      if (left > 0) addAntialiasFringe(rowStart + left - 1);
      if (right + 1 < source.width) {
        addAntialiasFringe(rowStart + right + 1);
      }
      if (y > 0) {
        final above = rowStart - source.width;
        for (var x = left; x <= right; x++) {
          addAntialiasFringe(above + x);
        }
      }
      if (y + 1 < source.height) {
        final below = rowStart + source.width;
        for (var x = left; x <= right; x++) {
          addAntialiasFringe(below + x);
        }
      }
      for (var x = left; x <= right; x++) {
        words[rowStart + x] = replacementWord;
      }
      if (left < minX) minX = left;
      if (right > maxX) maxX = right;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      pushNeighborSpans(y - 1, left, right);
      pushNeighborSpans(y + 1, left, right);
    }

    // Brush antialias pixels contain foreground color plus partial alpha. Put
    // the fill behind only those pixels touching the filled region so their
    // transparent remainder no longer reveals the white canvas. They remain
    // barriers during the flood, so this cannot carry color across the line.
    for (final pixel in fringePixels) {
      final index = pixel * 4;
      final foregroundAlpha = pixels[index + 3];
      final backgroundContribution = replacementAlpha * (255 - foregroundAlpha);
      final outputAlpha = foregroundAlpha +
          ((backgroundContribution + 127) ~/ 255).clamp(0, 255);
      if (outputAlpha == 0) continue;
      for (var channel = 0; channel < 3; channel++) {
        final foreground = pixels[index + channel];
        final background = switch (channel) {
          0 => replacementRed,
          1 => replacementGreen,
          _ => replacementBlue,
        };
        pixels[index + channel] = ((foreground * foregroundAlpha * 255 +
                    background * backgroundContribution) /
                (outputAlpha * 255))
            .round()
            .clamp(0, 255);
      }
      pixels[index + 3] = outputAlpha;
      final y = pixel ~/ source.width;
      final x = pixel - y * source.width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    if (maxX < minX) {
      return DrawingFillEditResult(raster: source, changedBounds: null);
    }
    return DrawingFillEditResult(
      raster: source.copyWithPixels(pixels),
      changedBounds: Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      ),
    );
  }

  static Color sampleColor({
    required DrawingRaster source,
    required Offset normalizedPoint,
  }) {
    final x = (normalizedPoint.dx.clamp(0.0, 1.0) * (source.width - 1)).round();
    final y =
        (normalizedPoint.dy.clamp(0.0, 1.0) * (source.height - 1)).round();
    final index = (y * source.width + x) * 4;
    if (source.pixels[index + 3] == 0) return Colors.white;
    return Color.fromARGB(
      255,
      source.pixels[index],
      source.pixels[index + 1],
      source.pixels[index + 2],
    );
  }

  /// Applies one whole-stroke coverage mask with straight-alpha source-over.
  /// Brush opacity and mask coverage are each multiplied exactly once.
  static DrawingRaster compositeStrokeMask({
    required DrawingRaster source,
    required int maskLeft,
    required int maskTop,
    required int maskWidth,
    required int maskHeight,
    required Uint8List maskAlpha,
    required Color color,
    required double opacity,
  }) {
    if (maskWidth <= 0 ||
        maskHeight <= 0 ||
        maskAlpha.length != maskWidth * maskHeight ||
        opacity <= 0) {
      return source;
    }
    final pixels = Uint8List.fromList(source.pixels);
    for (var localY = 0; localY < maskHeight; localY++) {
      final y = maskTop + localY;
      if (y < 0 || y >= source.height) continue;
      for (var localX = 0; localX < maskWidth; localX++) {
        final coverage = maskAlpha[localY * maskWidth + localX];
        if (coverage == 0) continue;
        final x = maskLeft + localX;
        if (x < 0 || x >= source.width) continue;
        _blend(
          pixels,
          source.width,
          x,
          y,
          color,
          opacity: opacity * coverage / 255,
        );
      }
    }
    return source.copyWithPixels(pixels);
  }

  /// Applies the exact straight-RGBA material payload produced by the live
  /// renderer. This preserves texture RGB and AA edge representation instead
  /// of reconstructing every pixel from a single stroke color plus alpha.
  static DrawingRaster compositeStrokeRgba({
    required DrawingRaster source,
    required int sourceLeft,
    required int sourceTop,
    required int sourceWidth,
    required int sourceHeight,
    required Uint8List sourceRgba,
  }) {
    if (sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        sourceRgba.length != sourceWidth * sourceHeight * 4) {
      return source;
    }
    final pixels = Uint8List.fromList(source.pixels);
    for (var localY = 0; localY < sourceHeight; localY++) {
      final y = sourceTop + localY;
      if (y < 0 || y >= source.height) continue;
      for (var localX = 0; localX < sourceWidth; localX++) {
        final x = sourceLeft + localX;
        if (x < 0 || x >= source.width) continue;
        final sourceIndex = (localY * sourceWidth + localX) * 4;
        final alpha = sourceRgba[sourceIndex + 3];
        if (alpha == 0) continue;
        _blend(
          pixels,
          source.width,
          x,
          y,
          Color.fromARGB(
            alpha,
            sourceRgba[sourceIndex],
            sourceRgba[sourceIndex + 1],
            sourceRgba[sourceIndex + 2],
          ),
          opacity: 1,
        );
      }
    }
    return source.copyWithPixels(pixels);
  }

  /// Applies one whole-stroke antialiased coverage mask to straight RGBA.
  static DrawingEraserEditResult applyEraserMask({
    required DrawingRaster source,
    required int maskLeft,
    required int maskTop,
    required int maskWidth,
    required int maskHeight,
    required Uint8List maskAlpha,
  }) {
    if (maskWidth <= 0 ||
        maskHeight <= 0 ||
        maskAlpha.length != maskWidth * maskHeight) {
      return DrawingEraserEditResult(raster: source, changedBounds: null);
    }
    final pixels = Uint8List.fromList(source.pixels);
    var changedLeft = source.width;
    var changedTop = source.height;
    var changedRight = -1;
    var changedBottom = -1;
    for (var localY = 0; localY < maskHeight; localY++) {
      final y = maskTop + localY;
      if (y < 0 || y >= source.height) continue;
      for (var localX = 0; localX < maskWidth; localX++) {
        final coverage = maskAlpha[localY * maskWidth + localX];
        if (coverage == 0) continue;
        final x = maskLeft + localX;
        if (x < 0 || x >= source.width) continue;
        final index = (y * source.width + x) * 4;
        final oldAlpha = pixels[index + 3];
        if (oldAlpha == 0) continue;
        final newAlpha = (oldAlpha * (255 - coverage) / 255).round();
        if (newAlpha == oldAlpha) continue;
        if (newAlpha == 0) {
          pixels.fillRange(index, index + 4, 0);
        } else {
          // DrawingRaster is straight RGBA. RGB stays unscaled while alpha
          // is reduced exactly once by the coverage mask.
          pixels[index + 3] = newAlpha;
        }
        changedLeft = math.min(changedLeft, x);
        changedTop = math.min(changedTop, y);
        changedRight = math.max(changedRight, x);
        changedBottom = math.max(changedBottom, y);
      }
    }
    if (changedRight < changedLeft) {
      return DrawingEraserEditResult(raster: source, changedBounds: null);
    }
    return DrawingEraserEditResult(
      raster: source.copyWithPixels(pixels),
      changedBounds: Rect.fromLTRB(
        changedLeft.toDouble(),
        changedTop.toDouble(),
        (changedRight + 1).toDouble(),
        (changedBottom + 1).toDouble(),
      ),
    );
  }

  static DrawingRaster erase({
    required DrawingRaster source,
    required List<Offset> normalizedPoints,
    required double width,
  }) {
    if (normalizedPoints.isEmpty || width <= 0) return source;
    final pixelWidth = width * source.pixelScale;
    return _paintPath(
      source,
      normalizedPoints,
      pixelWidth,
      reach: pixelWidth / 2,
      onPixel: (pixels, x, y, _) {
        final index = (y * source.width + x) * 4;
        pixels.fillRange(index, index + 4, 0);
      },
      coverage: (distance, radius) => distance <= radius ? 1 : 0,
    );
  }

  static DrawingRaster _paintPath(
    DrawingRaster source,
    List<Offset> normalizedPoints,
    double width, {
    required double reach,
    required double Function(double distance, double radius) coverage,
    required void Function(Uint8List pixels, int x, int y, double coverage)
        onPixel,
  }) {
    final pixels = Uint8List.fromList(source.pixels);
    final coverageByPixel = <int, double>{};
    final points = normalizedPoints
        .map((point) => Offset(
              point.dx * (source.width - 1),
              point.dy * (source.height - 1),
            ))
        .toList(growable: false);
    final radius = width / 2;
    for (var index = 0; index < points.length; index++) {
      final start = points[index];
      final end = index == 0 ? start : points[index - 1];
      final minX = (math.min(start.dx, end.dx) - reach)
          .floor()
          .clamp(0, source.width - 1);
      final maxX = (math.max(start.dx, end.dx) + reach)
          .ceil()
          .clamp(0, source.width - 1);
      final minY = (math.min(start.dy, end.dy) - reach)
          .floor()
          .clamp(0, source.height - 1);
      final maxY = (math.max(start.dy, end.dy) + reach)
          .ceil()
          .clamp(0, source.height - 1);
      for (var y = minY; y <= maxY; y++) {
        for (var x = minX; x <= maxX; x++) {
          final distance =
              _distanceToSegment(Offset(x + 0.5, y + 0.5), start, end);
          final pixelCoverage = coverage(distance, radius);
          if (pixelCoverage <= 0) continue;
          final pixelIndex = y * source.width + x;
          final previousCoverage = coverageByPixel[pixelIndex] ?? 0;
          if (pixelCoverage > previousCoverage) {
            coverageByPixel[pixelIndex] = pixelCoverage;
          }
        }
      }
    }
    for (final entry in coverageByPixel.entries) {
      final y = entry.key ~/ source.width;
      final x = entry.key % source.width;
      onPixel(pixels, x, y, entry.value);
    }
    return source.copyWithPixels(pixels);
  }

  static double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.dx * delta.dx + delta.dy * delta.dy;
    if (lengthSquared == 0) return (point - start).distance;
    final pointDelta = point - start;
    final projection =
        ((pointDelta.dx * delta.dx + pointDelta.dy * delta.dy) / lengthSquared)
            .clamp(0.0, 1.0);
    final closest = Offset(
      start.dx + delta.dx * projection,
      start.dy + delta.dy * projection,
    );
    return (point - closest).distance;
  }

  static void _blend(Uint8List pixels, int width, int x, int y, Color color,
      {required double opacity}) {
    final index = (y * width + x) * 4;
    final sourceAlpha = (color.a * opacity).clamp(0.0, 1.0);
    final destinationAlpha = pixels[index + 3] / 255;
    final outputAlpha = sourceAlpha + destinationAlpha * (1 - sourceAlpha);
    if (outputAlpha <= 0) {
      pixels.fillRange(index, index + 4, 0);
      return;
    }
    final red = (color.r * 255).round();
    final green = (color.g * 255).round();
    final blue = (color.b * 255).round();
    pixels[index] = ((red * sourceAlpha +
                pixels[index] * destinationAlpha * (1 - sourceAlpha)) /
            outputAlpha)
        .round()
        .clamp(0, 255);
    pixels[index + 1] = ((green * sourceAlpha +
                pixels[index + 1] * destinationAlpha * (1 - sourceAlpha)) /
            outputAlpha)
        .round()
        .clamp(0, 255);
    pixels[index + 2] = ((blue * sourceAlpha +
                pixels[index + 2] * destinationAlpha * (1 - sourceAlpha)) /
            outputAlpha)
        .round()
        .clamp(0, 255);
    pixels[index + 3] = (outputAlpha * 255).round().clamp(0, 255);
  }
}

class DrawingRasterPainter extends CustomPainter {
  const DrawingRasterPainter(this.raster);

  final DrawingRaster? raster;

  @override
  void paint(Canvas canvas, Size size) {
    final value = raster;
    if (value == null) return;
    final scaleX = size.width / value.width;
    final scaleY = size.height / value.height;
    final pixels = value.pixels;
    for (var y = 0; y < value.height; y++) {
      var x = 0;
      while (x < value.width) {
        final index = (y * value.width + x) * 4;
        final alpha = pixels[index + 3];
        if (alpha == 0) {
          x++;
          continue;
        }
        var end = x + 1;
        while (end < value.width) {
          final next = (y * value.width + end) * 4;
          if (pixels[next] != pixels[index] ||
              pixels[next + 1] != pixels[index + 1] ||
              pixels[next + 2] != pixels[index + 2] ||
              pixels[next + 3] != alpha) {
            break;
          }
          end++;
        }
        canvas.drawRect(
          Rect.fromLTWH(x * scaleX, y * scaleY, (end - x) * scaleX, scaleY),
          Paint()
            // The raster already contains coverage alpha. Anti-aliasing each
            // adjacent pixel-run rectangle creates seams and striping.
            ..isAntiAlias = false
            ..color = Color.fromARGB(
                alpha, pixels[index], pixels[index + 1], pixels[index + 2]),
        );
        x = end;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DrawingRasterPainter oldDelegate) =>
      oldDelegate.raster != raster;
}

class DrawingRasterView extends StatefulWidget {
  const DrawingRasterView({
    required this.raster,
    this.filterQuality = FilterQuality.medium,
    this.imageLoader,
    this.compositePainterBuilder,
    this.fallbackRaster,
    this.fallbackPainter,
    this.retainDisplayedImageWhileLoading = false,
    this.discardDisplayedImageOnTargetChange = false,
    this.pendingImagePainter,
    this.onImageReady,
    this.onImageError,
    super.key,
  });

  final DrawingRaster? raster;
  final FilterQuality filterQuality;
  final Future<ui.Image> Function(DrawingRaster raster)? imageLoader;
  final DrawingRasterCompositePainterBuilder? compositePainterBuilder;

  /// Optional pre-commit raster shown until the first decoded image is ready.
  final DrawingRaster? fallbackRaster;

  /// Optional composite painter used while no decoded image is available.
  final CustomPainter? fallbackPainter;

  /// Keeps the last decoded carrier visible until the replacement is ready.
  final bool retainDisplayedImageWhileLoading;

  /// Drops the last decoded carrier as soon as [raster] changes.
  ///
  /// History replacements use this because their transparent pixels remove
  /// content and therefore cannot be composited over the previous carrier.
  /// Ordinary replacements keep the carrier so a failed image load can roll
  /// back without a visible blank frame.
  final bool discardDisplayedImageOnTargetChange;

  /// Optional overlay painted over the retained decoded carrier.
  final CustomPainter? pendingImagePainter;
  final void Function(DrawingRaster raster, int generation)? onImageReady;
  final void Function(
    DrawingRaster raster,
    Object error,
    StackTrace stackTrace,
  )? onImageError;

  @override
  State<DrawingRasterView> createState() => _DrawingRasterViewState();
}

class _DrawingRasterViewState extends State<DrawingRasterView> {
  ui.Image? _displayedImage;
  DrawingRaster? _displayedRaster;
  DrawingRaster? _pendingRaster;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant DrawingRasterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.raster, widget.raster)) {
      if (widget.discardDisplayedImageOnTargetChange) {
        final previous = _displayedImage;
        _displayedImage = null;
        _displayedRaster = null;
        previous?.dispose();
      }
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final raster = widget.raster;
    final generation = ++_generation;
    if (raster == null) {
      final previous = _displayedImage;
      _displayedImage = null;
      _displayedRaster = null;
      _pendingRaster = null;
      if (mounted) setState(() {});
      previous?.dispose();
      return;
    }
    if (_displayedImage != null && identical(_displayedRaster, raster)) {
      _pendingRaster = null;
      return;
    }
    _pendingRaster = raster;
    ui.Image nextImage;
    try {
      final loader =
          widget.imageLoader ?? DrawingRasterImageLoaders.debugOverride;
      nextImage = await (loader?.call(raster) ?? raster.toUiImage());
    } catch (error, stackTrace) {
      if (mounted &&
          generation == _generation &&
          identical(_pendingRaster, raster) &&
          identical(widget.raster, raster)) {
        setState(() => _pendingRaster = null);
        widget.onImageError?.call(raster, error, stackTrace);
      }
      return;
    }
    if (!mounted ||
        generation != _generation ||
        !identical(_pendingRaster, raster) ||
        !identical(widget.raster, raster)) {
      nextImage.dispose();
      return;
    }
    final previous = _displayedImage;
    setState(() {
      _displayedImage = nextImage;
      _displayedRaster = raster;
      _pendingRaster = null;
    });
    widget.onImageReady?.call(raster, generation);
    previous?.dispose();
  }

  @override
  void dispose() {
    _generation++;
    _displayedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _displayedImage;
    final hasDisplayedImage = image != null && _displayedRaster != null;
    // Keep the previous carrier available while a replacement is loading so
    // callers can retain it as the presentation base until an atomic handoff.
    final imageMatchesTarget = hasDisplayedImage &&
        _pendingRaster == null &&
        identical(_displayedRaster, widget.raster);
    if (imageMatchesTarget) {
      final compositeBuilder = widget.compositePainterBuilder;
      if (compositeBuilder != null) {
        return CustomPaint(
          key: const ValueKey('drawing-raster-composite'),
          painter: compositeBuilder(image),
          child: const SizedBox.expand(),
        );
      }
      return RawImage(
        image: image,
        fit: BoxFit.fill,
        filterQuality: widget.filterQuality,
      );
    }
    if (hasDisplayedImage) {
      if (widget.retainDisplayedImageWhileLoading) {
        final pendingPainter = widget.pendingImagePainter;
        if (pendingPainter == null) {
          return RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: widget.filterQuality,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            RawImage(
              image: image,
              fit: BoxFit.fill,
              filterQuality: widget.filterQuality,
            ),
            CustomPaint(
              painter: pendingPainter,
              child: const SizedBox.expand(),
            ),
          ],
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          RawImage(
            image: image,
            fit: BoxFit.fill,
            filterQuality: widget.filterQuality,
          ),
          CustomPaint(
            painter: widget.fallbackPainter ??
                DrawingRasterPainter(widget.fallbackRaster ?? widget.raster),
            child: const SizedBox.expand(),
          ),
        ],
      );
    }
    // Keep the visible canvas correct while the first asynchronous ui.Image is
    // being created or a newer raster is replacing the displayed image. The
    // fallback must represent the current target, never the stale image.
    return CustomPaint(
      painter: widget.fallbackPainter ??
          DrawingRasterPainter(widget.fallbackRaster ?? widget.raster),
      child: const SizedBox.expand(),
    );
  }
}
