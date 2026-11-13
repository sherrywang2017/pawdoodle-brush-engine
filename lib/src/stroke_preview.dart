import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'brush_emission_segment.dart';
import 'smooth_stroke.dart';
import 'streaming_brush_engine.dart';
import 'streaming_dab_brush.dart';
import 'streaming_stroke_modeler.dart';

/// Shared immutable preview segment representation.
typedef PawStrokePreviewSegment = PawBrushEmissionSegment;

/// Immutable data passed from the input/model layer to the preview layer.
/// It intentionally contains no renderer, cache, material state, or
/// interaction handle.
@immutable
class PawStrokePreviewSnapshot {
  PawStrokePreviewSnapshot({
    required this.pointCount,
    required this.color,
    required this.brushSize,
    required this.opacity,
    required this.compositeOperation,
    required this.startPosition,
    required List<PawBrushEmissionSegment> segments,
    required this.bounds,
    this.dabDefinition,
    this.dabEnvironment,
    this.tapMotionSample,
    this.seed = const PawStrokeTextureSeed(0),
    this.dabEmissionIdentity,
    this.dabSealedEndArc = 0,
    this.dabRenderEndArc = 0,
  }) : segments = List<PawBrushEmissionSegment>.unmodifiable(segments);

  factory PawStrokePreviewSnapshot.fromStroke({
    required PawStreamingBrushStroke stroke,
    required PawStreamingCompositeOperation compositeOperation,
  }) {
    final PawStreamingBrushPreviewSource? source =
        stroke is PawStreamingBrushPreviewSource
            ? stroke as PawStreamingBrushPreviewSource
            : null;
    final segments =
        source?.previewEmissionSegments ?? const <PawBrushEmissionSegment>[];
    final dabStroke = stroke is PawStreamingDabStroke ? stroke : null;
    return PawStrokePreviewSnapshot(
      pointCount: stroke.revision,
      color: stroke.color,
      brushSize: stroke.brushSize,
      opacity: stroke.opacity,
      compositeOperation: compositeOperation,
      startPosition: source?.previewStartPosition ??
          (segments.isEmpty ? stroke.bounds.center : segments.first.p0),
      segments: segments,
      bounds: stroke.bounds,
      dabDefinition: dabStroke?.definition,
      dabEnvironment: dabStroke?.environment,
      tapMotionSample: dabStroke?.tapMotionSample,
      seed: stroke.seed,
      dabEmissionIdentity: dabStroke?.emissionIdentity,
      // The modeler proves this display prefix immutable frame-by-frame. Feed
      // that stronger causal frontier to the existing picture cache so only
      // the genuinely provisional tip is re-recorded during PointerMove.
      dabSealedEndArc: dabStroke?.causalStableEndArc ?? 0,
      dabRenderEndArc: dabStroke?.renderEndArc ?? 0,
    );
  }

  final int pointCount;
  final Color color;
  final double brushSize;
  final double opacity;
  final PawStreamingCompositeOperation compositeOperation;
  final Offset? startPosition;
  final List<PawBrushEmissionSegment> segments;
  final Rect bounds;
  final PawDabBrushDefinition? dabDefinition;
  final PawBrushEnvironmentSnapshot? dabEnvironment;
  final PawStreamingMotionSample? tapMotionSample;
  final PawStrokeTextureSeed seed;
  final Object? dabEmissionIdentity;
  final double dabSealedEndArc;
  final double dabRenderEndArc;

  bool get isEmpty =>
      pointCount <= 0 || (segments.isEmpty && startPosition == null);
  bool get isEraser =>
      compositeOperation == PawStreamingCompositeOperation.erase;
}
