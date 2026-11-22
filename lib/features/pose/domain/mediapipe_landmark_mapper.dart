import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:balance_detect/features/pose/services/pose_landmarker_platform.dart';

/// Converts a MediaPipe Pose Landmarker result into a [PoseFrame].
///
/// MediaPipe already returns coordinates normalized to the upright image (the
/// native bridge rotates the frame before inference), so the only remaining
/// step is to match the camera preview: the front camera preview is mirrored,
/// so x is flipped for the front camera.
final class MediaPipeLandmarkMapper {
  const MediaPipeLandmarkMapper();

  /// MediaPipe Pose Landmarker indices (33-point BlazePose topology).
  static const landmarkIndices = <BodyLandmark, int>{
    BodyLandmark.leftShoulder: 11,
    BodyLandmark.rightShoulder: 12,
    BodyLandmark.leftElbow: 13,
    BodyLandmark.rightElbow: 14,
    BodyLandmark.leftWrist: 15,
    BodyLandmark.rightWrist: 16,
    BodyLandmark.leftIndex: 19,
    BodyLandmark.rightIndex: 20,
    BodyLandmark.leftHip: 23,
    BodyLandmark.rightHip: 24,
    BodyLandmark.leftKnee: 25,
    BodyLandmark.rightKnee: 26,
    BodyLandmark.leftAnkle: 27,
    BodyLandmark.rightAnkle: 28,
    BodyLandmark.leftHeel: 29,
    BodyLandmark.rightHeel: 30,
    BodyLandmark.leftFootIndex: 31,
    BodyLandmark.rightFootIndex: 32,
  };

  PoseFrame map({
    required PoseLandmarkerResult result,
    required Duration timestamp,
    required bool mirrorX,
  }) {
    const stride = PoseLandmarkerResult.valuesPerLandmark;
    final values = result.landmarks;
    final mapped = <BodyLandmark, NormalizedPoint>{};
    for (final entry in landmarkIndices.entries) {
      final offset = entry.value * stride;
      if (offset + stride > values.length) continue;
      final x = _clampNormalized(values[offset]);
      final y = _clampNormalized(values[offset + 1]);
      // MediaPipe "visibility" is the likelihood that the point is visible in
      // the frame, the closest match to ML Kit's landmark likelihood.
      final visibility = _clampNormalized(values[offset + 3]);
      mapped[entry.key] = NormalizedPoint(
        x: mirrorX ? 1 - x : x,
        y: y,
        confidence: visibility,
      );
    }
    return PoseFrame(
      timestamp: timestamp,
      landmarks: mapped,
      imageAspectRatio: result.imageHeight > 0
          ? result.imageWidth / result.imageHeight
          : 1.0,
    );
  }

  double _clampNormalized(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0);
  }
}
