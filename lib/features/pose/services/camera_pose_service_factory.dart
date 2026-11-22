import 'dart:io';

import 'package:balance_detect/core/providers/app_providers.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service.dart';
import 'package:balance_detect/features/pose/services/mediapipe_camera_pose_service.dart';

/// Creates the camera pose service for [engine].
///
/// MediaPipe runs through a native Android bridge, so other platforms always
/// fall back to ML Kit.
CameraPoseService createCameraPoseService(PoseEngine engine) {
  if (engine == PoseEngine.mediaPipe && Platform.isAndroid) {
    return MediaPipeCameraPoseService();
  }
  return MlKitCameraPoseService();
}
