import 'dart:typed_data';

import 'package:balance_detect/features/pose/domain/mediapipe_landmark_mapper.dart';
import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:balance_detect/features/pose/services/pose_landmarker_platform.dart';
import 'package:flutter_test/flutter_test.dart';

PoseLandmarkerResult _result({
  required Map<int, List<double>> points,
  double width = 480,
  double height = 720,
}) {
  final values = Float32List(33 * PoseLandmarkerResult.valuesPerLandmark);
  for (final entry in points.entries) {
    values.setAll(entry.key * PoseLandmarkerResult.valuesPerLandmark, [
      ...entry.value,
    ]);
  }
  return PoseLandmarkerResult(
    imageWidth: width,
    imageHeight: height,
    landmarks: values,
    worldLandmarks: Float32List(0),
    inferenceMilliseconds: 12,
  );
}

void main() {
  const mapper = MediaPipeLandmarkMapper();

  test('maps MediaPipe indices to the 18 body landmarks', () {
    final frame = mapper.map(
      result: _result(
        points: {
          15: [0.2, 0.4, -0.1, 0.9, 0.95], // left wrist
          32: [0.7, 0.95, 0.0, 0.6, 0.8], // right foot index
        },
      ),
      timestamp: const Duration(milliseconds: 500),
      mirrorX: false,
    );

    expect(frame.landmarks, hasLength(18));
    final wrist = frame[BodyLandmark.leftWrist]!;
    expect(wrist.x, closeTo(0.2, 1e-6));
    expect(wrist.y, closeTo(0.4, 1e-6));
    expect(wrist.confidence, closeTo(0.9, 1e-6));
    final toe = frame[BodyLandmark.rightFootIndex]!;
    expect(toe.x, closeTo(0.7, 1e-6));
    expect(toe.confidence, closeTo(0.6, 1e-6));
    expect(frame.timestamp, const Duration(milliseconds: 500));
    expect(frame.imageAspectRatio, closeTo(480 / 720, 1e-9));
  });

  test('mirrors x for the front camera preview', () {
    final frame = mapper.map(
      result: _result(
        points: {
          11: [0.25, 0.3, 0, 1, 1],
        },
      ),
      timestamp: Duration.zero,
      mirrorX: true,
    );

    expect(frame[BodyLandmark.leftShoulder]!.x, closeTo(0.75, 1e-6));
    expect(frame[BodyLandmark.leftShoulder]!.y, closeTo(0.3, 1e-6));
  });

  test('clamps out-of-frame and non-finite values', () {
    final frame = mapper.map(
      result: _result(
        points: {
          27: [-0.2, 1.3, 0, double.nan, 1], // left ankle
        },
      ),
      timestamp: Duration.zero,
      mirrorX: false,
    );

    final ankle = frame[BodyLandmark.leftAnkle]!;
    expect(ankle.x, 0);
    expect(ankle.y, 1);
    expect(ankle.confidence, 0);
  });

  test('skips landmarks missing from a short result', () {
    final frame = mapper.map(
      result: PoseLandmarkerResult(
        imageWidth: 480,
        imageHeight: 720,
        landmarks: Float32List(12 * PoseLandmarkerResult.valuesPerLandmark),
        worldLandmarks: Float32List(0),
        inferenceMilliseconds: 0,
      ),
      timestamp: Duration.zero,
      mirrorX: false,
    );

    expect(frame[BodyLandmark.leftShoulder], isNotNull);
    expect(frame[BodyLandmark.rightShoulder], isNull);
  });
}
