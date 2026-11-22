import 'dart:async';
import 'dart:io';

import 'package:balance_detect/core/constants/assessment_config.dart';
import 'package:balance_detect/core/errors/user_facing_exception.dart';
import 'package:balance_detect/core/logging/app_logger.dart';
import 'package:balance_detect/features/pose/domain/mediapipe_landmark_mapper.dart';
import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:balance_detect/features/pose/domain/pose_frame_smoother.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service.dart';
import 'package:balance_detect/features/pose/services/pose_landmarker_platform.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera pose tracking backed by MediaPipe Pose Landmarker (Android only).
///
/// Camera handling, frame throttling, smoothing and debug metrics match
/// [MlKitCameraPoseService], so the assessment screens can use either one
/// through [CameraPoseService].
class MediaPipeCameraPoseService implements CameraPoseService {
  MediaPipeCameraPoseService({
    this._platform = const MethodChannelPoseLandmarkerPlatform(),
    this.preferGpu = true,
  });

  final PoseLandmarkerPlatform _platform;
  final bool preferGpu;

  final StreamController<PoseFrame> _frameController =
      StreamController<PoseFrame>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  final StreamController<PoseDebugMetrics> _metricsController =
      StreamController<PoseDebugMetrics>.broadcast();
  static const _landmarkMapper = MediaPipeLandmarkMapper();
  final _frameSmoother = PoseFrameSmoother();
  final Stopwatch _sessionClock = Stopwatch();
  final Stopwatch _fpsClock = Stopwatch();
  CameraController? _cameraController;
  CameraDescription? _camera;
  bool _landmarkerReady = false;
  bool _processing = false;
  bool _disposed = false;
  Duration _lastProcessedAt = Duration.zero;
  int _processedFrameCount = 0;

  /// The delegate MediaPipe is running on ("gpu" or "cpu"), once initialized.
  String? activeDelegate;

  static const _orientations = <DeviceOrientation, int>{
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  String get engineLabel => 'MediaPipe full (${activeDelegate ?? '…'})';

  @override
  CameraController? get cameraController => _cameraController;

  @override
  Stream<PoseFrame> get frames => _frameController.stream;

  @override
  Stream<Object> get errors => _errorController.stream;

  @override
  Stream<PoseDebugMetrics> get debugMetrics => _metricsController.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) throw StateError('Camera service has been disposed');
    if (!Platform.isAndroid) {
      throw UnsupportedError('MediaPipe pose tracking is Android only');
    }
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      throw UserFacingException(
        permission.isPermanentlyDenied
            ? 'ปิดสิทธิ์กล้องอยู่ กรุณาเปิดสิทธิ์ในการตั้งค่าอุปกรณ์'
            : 'ต้องอนุญาตใช้กล้องเพื่อประเมินท่าทาง',
        canOpenSettings: permission.isPermanentlyDenied,
      );
    }

    activeDelegate = await _platform.initialize(preferGpu: preferGpu);
    _landmarkerReady = true;
    AppLogger.event('mediapipe_pose_initialized', <String, Object?>{
      'delegate': activeDelegate,
    });
    if (_disposed) {
      await _closeLandmarker();
      return;
    }

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw const UserFacingException('ไม่พบกล้องบนอุปกรณ์นี้');
    }
    _camera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      _camera!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    _cameraController = controller;
    await controller.initialize();
    _sessionClock
      ..reset()
      ..start();
    _frameSmoother.reset();
    _fpsClock
      ..reset()
      ..start();
    await controller.startImageStream(_onCameraImage);
  }

  void _onCameraImage(CameraImage image) {
    final now = _sessionClock.elapsed;
    if (_processing ||
        !_landmarkerReady ||
        now - _lastProcessedAt < AssessmentConfig.cameraFrameInterval) {
      return;
    }
    _processing = true;
    _lastProcessedAt = now;
    unawaited(_processImage(image, now));
  }

  Future<void> _processImage(CameraImage image, Duration capturedAt) async {
    final processingClock = Stopwatch()..start();
    try {
      final rotation = _uprightRotation();
      if (rotation == null || image.planes.length != 1) return;
      final plane = image.planes.single;
      final result = await _platform.detect(
        nv21: plane.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: plane.bytesPerRow,
        rotation: rotation,
        timestampMilliseconds: capturedAt.inMilliseconds,
      );
      if (_disposed) return;

      final swapsAxes = rotation == 90 || rotation == 270;
      final orientedWidth = swapsAxes ? image.height : image.width;
      final orientedHeight = swapsAxes ? image.width : image.height;
      final detectedFrame = result == null
          ? PoseFrame(
              timestamp: capturedAt,
              landmarks: const {},
              imageAspectRatio: orientedWidth / orientedHeight,
            )
          : _landmarkMapper.map(
              result: result,
              timestamp: capturedAt,
              mirrorX: _camera?.lensDirection == CameraLensDirection.front,
            );
      final frame = _frameSmoother.smooth(detectedFrame);
      _frameController.add(frame);
      _reportMetrics(frame, processingClock.elapsedMilliseconds);
    } catch (error) {
      AppLogger.error('pose_processing_error', error);
      if (!_disposed) _errorController.add(error);
    } finally {
      _processing = false;
    }
  }

  /// Clockwise rotation (degrees) that turns the sensor image upright, using
  /// the same rule as [MlKitCameraPoseService].
  int? _uprightRotation() {
    final controller = _cameraController;
    final camera = _camera;
    if (controller == null || camera == null) return null;
    final compensation = _orientations[controller.value.deviceOrientation];
    if (compensation == null) return null;
    final sensorOrientation = camera.sensorOrientation;
    return camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
  }

  void _reportMetrics(PoseFrame frame, int processingMilliseconds) {
    _processedFrameCount += 1;
    final fpsSeconds = _fpsClock.elapsedMilliseconds / 1000;
    if (fpsSeconds < 1) return;
    final confidence = frame.landmarks.isEmpty
        ? 0.0
        : frame.landmarks.values
                  .map((point) => point.confidence)
                  .reduce((a, b) => a + b) /
              frame.landmarks.length;
    _metricsController.add(
      PoseDebugMetrics(
        framesPerSecond: _processedFrameCount / fpsSeconds,
        poseConfidence: confidence,
        processingMilliseconds: processingMilliseconds,
      ),
    );
    _processedFrameCount = 0;
    _fpsClock
      ..reset()
      ..start();
  }

  Future<void> _closeLandmarker() async {
    if (!_landmarkerReady) return;
    _landmarkerReady = false;
    try {
      await _platform.close();
    } catch (error) {
      AppLogger.error('mediapipe_pose_close_failed', error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sessionClock.stop();
    _fpsClock.stop();
    _frameSmoother.reset();
    final controller = _cameraController;
    _cameraController = null;
    if (controller?.value.isStreamingImages ?? false) {
      await controller?.stopImageStream();
    }
    await controller?.dispose();
    await _closeLandmarker();
    await _frameController.close();
    await _errorController.close();
    await _metricsController.close();
  }
}
