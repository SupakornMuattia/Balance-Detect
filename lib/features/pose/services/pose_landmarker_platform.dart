import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One MediaPipe Pose Landmarker result for a single person.
///
/// [landmarks] holds 33 points x `[x, y, z, visibility, presence]`, with x and
/// y normalized (0..1) to the upright, unmirrored image of
/// [imageWidth] x [imageHeight]. [worldLandmarks] holds 33 points x
/// `[x, y, z]` in meters, with the origin between the hips.
class PoseLandmarkerResult {
  const PoseLandmarkerResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.landmarks,
    required this.worldLandmarks,
    required this.inferenceMilliseconds,
  });

  factory PoseLandmarkerResult.fromMap(Map<Object?, Object?> map) {
    return PoseLandmarkerResult(
      imageWidth: (map['width']! as num).toDouble(),
      imageHeight: (map['height']! as num).toDouble(),
      landmarks: map['landmarks']! as Float32List,
      worldLandmarks: map['worldLandmarks'] as Float32List? ?? Float32List(0),
      inferenceMilliseconds: (map['inferenceMs'] as num?)?.toInt() ?? 0,
    );
  }

  static const valuesPerLandmark = 5;
  static const valuesPerWorldLandmark = 3;

  final double imageWidth;
  final double imageHeight;
  final Float32List landmarks;
  final Float32List worldLandmarks;
  final int inferenceMilliseconds;

  int get landmarkCount => landmarks.length ~/ valuesPerLandmark;
}

abstract interface class PoseLandmarkerPlatform {
  /// Loads the model. Returns the delegate actually in use ("gpu" or "cpu").
  Future<String> initialize({String? model, bool preferGpu = true});

  /// Runs the model on one NV21 camera frame. [rotation] is the clockwise
  /// rotation in degrees that makes the frame upright. Returns null when no
  /// person is found.
  Future<PoseLandmarkerResult?> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotation,
    required int timestampMilliseconds,
  });

  Future<void> close();
}

/// Native MediaPipe Pose Landmarker (see `PoseLandmarkerBridge.kt`).
class MethodChannelPoseLandmarkerPlatform implements PoseLandmarkerPlatform {
  const MethodChannelPoseLandmarkerPlatform();

  static const _channel = MethodChannel('com.balancedetect/pose');

  @override
  Future<String> initialize({String? model, bool preferGpu = true}) async {
    final reply = await _channel.invokeMapMethod<String, Object?>(
      'initialize',
      <String, Object?>{
        'model': ?model,
        'delegate': preferGpu ? 'gpu' : 'cpu',
      },
    );
    return reply?['delegate'] as String? ?? 'unknown';
  }

  @override
  Future<PoseLandmarkerResult?> detect({
    required Uint8List nv21,
    required int width,
    required int height,
    required int bytesPerRow,
    required int rotation,
    required int timestampMilliseconds,
  }) async {
    final reply = await _channel.invokeMethod<Map<Object?, Object?>>(
      'detect',
      <String, Object>{
        'bytes': nv21,
        'width': width,
        'height': height,
        'bytesPerRow': bytesPerRow,
        'rotation': rotation,
        'timestampMs': timestampMilliseconds,
      },
    );
    return reply == null ? null : PoseLandmarkerResult.fromMap(reply);
  }

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}
