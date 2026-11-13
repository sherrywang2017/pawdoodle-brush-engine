import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
class DrawingInputSample {
  const DrawingInputSample(
      {required this.x,
      required this.y,
      required this.timestamp,
      required this.pressure,
      required this.pressureMin,
      required this.pressureMax,
      required this.deviceKind});
  final double x;
  final double y;
  final Duration timestamp;
  final double pressure;
  final double pressureMin;
  final double pressureMax;
  final PointerDeviceKind deviceKind;
  Offset get position => Offset(x, y);
  bool get hasFinitePosition => x.isFinite && y.isFinite;
  double? get normalizedPressure {
    if (!pressure.isFinite || !pressureMin.isFinite || !pressureMax.isFinite) {
      return null;
    }
    final range = pressureMax - pressureMin;
    if (range <= .000001) {
      return null;
    }
    return ((pressure - pressureMin) / range).clamp(0.0, 1.0);
  }
}

@immutable
class DrawingStrokeStyle {
  const DrawingStrokeStyle({required this.color, required this.baseSize});
  final Color color;
  final double baseSize;
}

@immutable
class PawStrokeTextureSeed {
  const PawStrokeTextureSeed(this.value);
  final int value;
}

@immutable
class PawStrokePresentationToken {
  const PawStrokePresentationToken(
      {required this.strokeGeneration,
      required this.geometryRevision,
      required this.presentationSequence});
  final int strokeGeneration;
  final int geometryRevision;
  final int presentationSequence;
  bool isNewerThan(PawStrokePresentationToken other) =>
      strokeGeneration == other.strokeGeneration &&
      presentationSequence > other.presentationSequence;
  @override
  bool operator ==(Object other) =>
      other is PawStrokePresentationToken &&
      strokeGeneration == other.strokeGeneration &&
      geometryRevision == other.geometryRevision &&
      presentationSequence == other.presentationSequence;
  @override
  int get hashCode =>
      Object.hash(strokeGeneration, geometryRevision, presentationSequence);
}

@immutable
class PawStrokeCommitToken {
  const PawStrokeCommitToken(
      {required this.strokeGeneration,
      required this.geometryRevision,
      required this.presentationSequence,
      required this.commitId});
  factory PawStrokeCommitToken.fromPresentation(
          {required PawStrokePresentationToken presentationToken,
          required int commitId}) =>
      PawStrokeCommitToken(
          strokeGeneration: presentationToken.strokeGeneration,
          geometryRevision: presentationToken.geometryRevision,
          presentationSequence: presentationToken.presentationSequence,
          commitId: commitId);
  final int strokeGeneration;
  final int geometryRevision;
  final int presentationSequence;
  final int commitId;
  PawStrokePresentationToken get presentationToken =>
      PawStrokePresentationToken(
          strokeGeneration: strokeGeneration,
          geometryRevision: geometryRevision,
          presentationSequence: presentationSequence);
  @override
  bool operator ==(Object other) =>
      other is PawStrokeCommitToken &&
      strokeGeneration == other.strokeGeneration &&
      geometryRevision == other.geometryRevision &&
      presentationSequence == other.presentationSequence &&
      commitId == other.commitId;
  @override
  int get hashCode => Object.hash(
      strokeGeneration, geometryRevision, presentationSequence, commitId);
}

enum PawCommitPresentationPhase {
  visibleOld('VISIBLE_OLD'),
  waitingCommit('WAITING_COMMIT'),
  swapReady('SWAP_READY'),
  visibleNew('VISIBLE_NEW');

  const PawCommitPresentationPhase(this.wireName);

  final String wireName;
}

@immutable
class PawCommitPresentationState {
  const PawCommitPresentationState({
    required this.phase,
    required this.oldImageId,
    required this.newImageId,
    required this.overlayToken,
    required this.commitId,
  });

  final PawCommitPresentationPhase phase;
  final int oldImageId;
  final int newImageId;
  final PawStrokePresentationToken? overlayToken;
  final int commitId;

  Map<String, Object?> toJson() => <String, Object?>{
        'transition': phase.wireName,
        'oldImageId': oldImageId,
        'newImageId': newImageId,
        'overlayToken': overlayToken == null
            ? null
            : '${overlayToken!.strokeGeneration}:'
                '${overlayToken!.geometryRevision}:'
                '${overlayToken!.presentationSequence}',
        'commitId': commitId,
      };
}

@immutable
class PawStrokeCommitDiagnostics {
  const PawStrokeCommitDiagnostics(
      {this.commitToken,
      this.commitPresentationState,
      this.commitPresentationTransitions = const <PawCommitPresentationState>[],
      this.previewMaterialCalls = 0,
      this.previewP95Ms = 0,
      this.commitP95Ms = 0,
      required this.paintAcknowledgmentCount,
      required this.acceptedAcknowledgmentCount,
      required this.duplicateAcknowledgmentCount,
      required this.commitStartedCount,
      required this.commitCompletedCount,
      required this.saveRasterCount,
      required this.imageReadyCount,
      required this.acceptedImageReadyCount,
      required this.duplicateImageReadyCount,
      required this.staleImageReadyCount});
  final PawStrokeCommitToken? commitToken;
  final PawCommitPresentationState? commitPresentationState;
  final List<PawCommitPresentationState> commitPresentationTransitions;
  final int previewMaterialCalls;
  final double previewP95Ms;
  final double commitP95Ms;
  final int paintAcknowledgmentCount;
  final int acceptedAcknowledgmentCount;
  final int duplicateAcknowledgmentCount;
  final int commitStartedCount;
  final int commitCompletedCount;
  final int saveRasterCount;
  final int imageReadyCount;
  final int acceptedImageReadyCount;
  final int duplicateImageReadyCount;
  final int staleImageReadyCount;

  Map<String, Object> toJson() => <String, Object>{
        if (commitPresentationState != null)
          'commitPresentationState': commitPresentationState!.toJson(),
        'commitPresentationTransitions': <Object?>[
          for (final transition in commitPresentationTransitions)
            transition.toJson(),
        ],
        'preview_material_calls': previewMaterialCalls,
        'preview_p95_ms': previewP95Ms,
        'commit_p95_ms': commitP95Ms,
        'paint_acknowledgment_count': paintAcknowledgmentCount,
        'accepted_acknowledgment_count': acceptedAcknowledgmentCount,
        'duplicate_acknowledgment_count': duplicateAcknowledgmentCount,
        'commit_started_count': commitStartedCount,
        'commit_completed_count': commitCompletedCount,
        'save_raster_count': saveRasterCount,
        'image_ready_count': imageReadyCount,
        'accepted_image_ready_count': acceptedImageReadyCount,
        'duplicate_image_ready_count': duplicateImageReadyCount,
        'stale_image_ready_count': staleImageReadyCount,
      };
}
