import 'dart:async';

import 'package:balance_detect/core/constants/assessment_config.dart';
import 'package:balance_detect/core/domain/assessment_enums.dart';
import 'package:balance_detect/core/errors/user_facing_exception.dart';
import 'package:balance_detect/core/logging/app_logger.dart';
import 'package:balance_detect/core/providers/app_providers.dart';
import 'package:balance_detect/core/services/screen_awake_service.dart';
import 'package:balance_detect/core/services/voice_guidance_service.dart';
import 'package:balance_detect/core/utils/id_generator.dart';
import 'package:balance_detect/core/utils/unit_conversion.dart';
import 'package:balance_detect/core/widgets/app_scaffold_body.dart';
import 'package:balance_detect/core/widgets/error_screens.dart';
import 'package:balance_detect/core/widgets/loading_view.dart';
import 'package:balance_detect/core/widgets/status_banner.dart';
import 'package:balance_detect/features/assessment/domain/assessment_session.dart';
import 'package:balance_detect/features/assessment/domain/calibration_record.dart';
import 'package:balance_detect/features/functional_reach/domain/distance_calibration_service.dart';
import 'package:balance_detect/features/functional_reach/domain/functional_reach_instructions.dart';
import 'package:balance_detect/features/functional_reach/domain/functional_reach_logic.dart';
import 'package:balance_detect/features/functional_reach/domain/functional_reach_posture_service.dart';
import 'package:balance_detect/features/functional_reach/domain/functional_reach_result.dart';
import 'package:balance_detect/features/functional_reach/domain/reach_measurement_service.dart';
import 'package:balance_detect/features/functional_reach/presentation/reach_threshold_bar.dart';
import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:balance_detect/features/pose/domain/pose_validation.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_assessment_layout.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_check_chips.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_debug_panel.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_guide_frame.dart';
import 'package:balance_detect/features/pose/presentation/pose_skeleton_overlay.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service_factory.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FunctionalReachAssessmentScreen extends ConsumerStatefulWidget {
  const FunctionalReachAssessmentScreen({required this.heightCm, super.key});

  final double heightCm;

  @override
  ConsumerState<FunctionalReachAssessmentScreen> createState() =>
      _FunctionalReachAssessmentScreenState();
}

class _FunctionalReachAssessmentScreenState
    extends ConsumerState<FunctionalReachAssessmentScreen>
    with WidgetsBindingObserver {
  final _stateMachine = FunctionalReachStateMachine();
  final _poseValidationService = const PoseValidationService();
  final _postureService = const FunctionalReachPostureService();
  final _anthropometricCalibrationService =
      const AnthropometricHeightCalibrationService();
  final _heightSpanSamples = <double>[];
  final String _sessionId = IdGenerator.generate('session');
  late final CameraPoseService _cameraService;
  StreamSubscription<PoseFrame>? _frameSubscription;
  StreamSubscription<Object>? _errorSubscription;
  StreamSubscription<PoseDebugMetrics>? _metricsSubscription;
  PoseValidation? _validation;
  FunctionalReachPostureValidation? _postureValidation;
  PrimaryBodySide? _trackedArmSide;
  PoseFrame? _lastFrame;
  PoseDebugMetrics? _debugMetrics;
  CalibrationRecord? _calibration;
  ReachMeasurementService? _measurement;
  FunctionalReachResult? _result;
  Duration? _baselineStartedAt;
  Duration? _reachStartedAt;
  Duration? _heightCalibrationStartedAt;
  InvalidReason? _invalidReason;
  Object? _initializationError;
  bool _initialized = false;
  bool _saving = false;
  bool _saved = false;
  int _poseLostFrames = 0;
  int _processingErrors = 0;
  double _baselineProgress = 0;
  double _reachProgress = 0;
  double _heightCalibrationProgress = 0;
  String _heightCalibrationMessage = 'อยู่นิ่ง ให้เห็นหัวไหล่และเท้าครบ';
  bool _poseAcquiredLogged = false;
  final _screenAwake = ScreenAwakeService.instance.createLease();
  final _voiceGuidance = VoiceGuidanceService();
  Timer? _positioningCountdownTimer;
  Timer? _readyCountdownTimer;
  int? _positioningCountdown;
  int? _readyCountdown;
  bool _voiceEnabled = true;
  bool _debugVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_screenAwake.acquire());
    _cameraService = createCameraPoseService(ref.read(poseEngineProvider));
    _stateMachine.transitionTo(FunctionalReachState.positioning);
    unawaited(_voiceGuidance.initialize());
    unawaited(
      _voiceGuidance.announce(
        FunctionalReachInstructions.positioningVoice,
        force: true,
      ),
    );
    _frameSubscription = _cameraService.frames.listen(_onFrame);
    _errorSubscription = _cameraService.errors.listen(_onProcessingError);
    _metricsSubscription = _cameraService.debugMetrics.listen((metrics) {
      if (mounted) setState(() => _debugMetrics = metrics);
    });
    unawaited(_initializeCamera());
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (error) {
      AppLogger.error('camera_initialization_failed', error);
      if (_stateMachine.canTransitionTo(FunctionalReachState.error)) {
        _stateMachine.transitionTo(FunctionalReachState.error);
      }
      unawaited(_screenAwake.release());
      if (mounted) setState(() => _initializationError = error);
    }
  }

  void _onProcessingError(Object error) {
    _processingErrors += 1;
    if (_processingErrors < 5) return;
    if (_stateMachine.canTransitionTo(FunctionalReachState.error)) {
      _stateMachine.transitionTo(FunctionalReachState.error);
      unawaited(_screenAwake.release());
      if (mounted) setState(() => _initializationError = error);
    }
  }

  void _onFrame(PoseFrame frame) {
    if (!mounted) return;
    _lastFrame = frame;
    final validation = _poseValidationService.validate(
      frame,
      requireSideView: true,
      trackedSide: _trackedArmSide,
      requireWristForArm: false,
    );
    _validation = validation;
    final postureSide = _trackedArmSide ?? validation.primarySide;
    final posture = _postureService.validate(frame, postureSide);
    _postureValidation = posture;
    if (validation.canStart && !_poseAcquiredLogged) {
      _poseAcquiredLogged = true;
      AppLogger.event('pose_acquired', <String, Object?>{
        'confidence': validation.confidence,
      });
    }

    final activeState = _stateMachine.state;
    if (activeState == FunctionalReachState.positioning) {
      if (validation.canStart) {
        unawaited(_voiceGuidance.announce(validation.guidance));
        _schedulePositioningStart();
      } else {
        _cancelPositioningCountdown();
        unawaited(_voiceGuidance.announce(validation.guidance));
      }
    } else if (activeState == FunctionalReachState.ready) {
      if (validation.canStart &&
          posture.canMeasure &&
          posture.reachPointVisible) {
        _scheduleReachStart();
      } else {
        _cancelReadyCountdown();
        unawaited(
          _voiceGuidance.announce(
            validation.canStart ? posture.guidance : validation.guidance,
          ),
        );
      }
    } else if (activeState == FunctionalReachState.calibrating) {
      _processHeightCalibration(frame, validation);
    }
    if (activeState == FunctionalReachState.baseline ||
        activeState == FunctionalReachState.reaching) {
      if (!validation.canStart) {
        _poseLostFrames += 1;
        if (_poseLostFrames >= AssessmentConfig.poseLostFrameLimit) {
          _invalidate(InvalidReason.poseLost);
          return;
        }
      } else {
        _poseLostFrames = 0;
      }
    }

    if (activeState == FunctionalReachState.baseline) {
      if (!validation.canStart) {
        _resetBaselineCapture();
        unawaited(_voiceGuidance.announce(validation.guidance));
      } else if (!posture.canMeasure) {
        _resetBaselineCapture();
        unawaited(_voiceGuidance.announce(posture.guidance));
      } else if (!posture.reachPointVisible) {
        _resetBaselineCapture();
        unawaited(_voiceGuidance.announce(posture.guidance));
      } else {
        _baselineStartedAt ??= frame.timestamp;
        _measurement?.addBaselineFrame(frame, _trackedArmSide!);
        final elapsed = frame.timestamp - _baselineStartedAt!;
        _baselineProgress =
            elapsed.inMilliseconds /
            AssessmentConfig.reachBaselineDuration.inMilliseconds;
        if (elapsed >= AssessmentConfig.reachBaselineDuration) {
          final measurement = _measurement;
          if (measurement?.finalizeStableBaseline() ?? false) {
            _stateMachine.transitionTo(FunctionalReachState.ready);
            _scheduleReachStart();
            AppLogger.event('reach_baseline_ready', <String, Object?>{
              'arm_to_torso_angle': posture.armToTorsoAngleDegrees,
              'elbow_angle': posture.elbowAngleDegrees,
              'tracked_foot_side': measurement?.trackedFootSide?.name,
              'foot_jitter_cm': measurement?.baselineFootJitterCm,
            });
          } else {
            final footBaselineUnstable =
                (measurement?.baselineFootJitterNormalized ?? 0) >
                AssessmentConfig.reachFootBaselineMaxJitterNormalized;
            AppLogger.event('reach_baseline_rejected', <String, Object?>{
              'tracked_foot_side': measurement?.trackedFootSide?.name,
              'foot_jitter_normalized':
                  measurement?.baselineFootJitterNormalized,
              'foot_jitter_cm': measurement?.baselineFootJitterCm,
              'foot_unstable': footBaselineUnstable,
            });
            unawaited(
              _voiceGuidance.announce(
                footBaselineUnstable
                    ? 'จุดเท้าฝั่งกล้องยังไม่นิ่ง วางเท้าให้นิ่งและอย่าบังเท้าข้างนี้'
                    : 'จุดร่างกายยังไม่นิ่ง กรุณาค้างท่าเดิมอีกครั้ง',
              ),
            );
            _measurement = ReachMeasurementService(calibration: _calibration!);
            _baselineStartedAt = frame.timestamp;
            _baselineProgress = 0;
          }
        }
      }
    } else if (activeState == FunctionalReachState.reaching &&
        validation.canStart) {
      if (!posture.reachPointVisible) {
        _poseLostFrames += 1;
        if (_poseLostFrames >= AssessmentConfig.poseLostFrameLimit) {
          _invalidate(InvalidReason.poseLost);
          return;
        }
        unawaited(_voiceGuidance.announce(posture.guidance));
        setState(() {});
        return;
      }
      _poseLostFrames = 0;
      final snapshot = _measurement!.addReachFrame(frame, _trackedArmSide!);
      if (snapshot.footMovementDetected) {
        AppLogger.event('foot_movement_detected', <String, Object?>{
          'tracked_side': snapshot.trackedFootSide?.name,
          'tracked_cm': snapshot.trackedFootMovementCm,
          'raw_cm': snapshot.trackedFootRawMovementCm,
          'relative_cm': snapshot.trackedFootRelativeMovementCm,
          'ankle_cm': snapshot.trackedFootAnkleMovementCm,
          'left_cm': snapshot.leftFootMovementCm,
          'right_cm': snapshot.rightFootMovementCm,
          'threshold_cm': snapshot.footMovementThresholdCm,
          'confirmation_frames':
              AssessmentConfig.footMovementConfirmationFrames,
        });
        _invalidate(InvalidReason.footMoved);
        return;
      }
      final elapsed = frame.timestamp - _reachStartedAt!;
      _reachProgress =
          elapsed.inMilliseconds / AssessmentConfig.reachWindow.inMilliseconds;
      if (elapsed >= AssessmentConfig.reachWindow) _completeReach();
    }
    setState(() {});
  }

  void _beginCalibration() {
    if (_stateMachine.state != FunctionalReachState.positioning ||
        !(_validation?.canStart ?? false)) {
      return;
    }
    _trackedArmSide = _validation!.primarySide;
    AppLogger.event('reach_tracking_side_locked', <String, Object?>{
      'side': _trackedArmSide!.name,
      'confidence': _validation!.confidence,
    });
    _heightSpanSamples.clear();
    _heightCalibrationStartedAt = null;
    _heightCalibrationProgress = 0;
    _heightCalibrationMessage = 'อยู่นิ่ง ให้เห็นหัวไหล่และเท้าครบ';
    _stateMachine.transitionTo(FunctionalReachState.calibrating);
    unawaited(
      _voiceGuidance.announce(
        'กำลังคำนวณสเกลจากส่วนสูง กรุณาอยู่นิ่ง',
        force: true,
      ),
    );
    setState(() {});
  }

  void _processHeightCalibration(PoseFrame frame, PoseValidation validation) {
    if (!validation.canStart) {
      _heightSpanSamples.clear();
      _heightCalibrationStartedAt = null;
      _heightCalibrationProgress = 0;
      _heightCalibrationMessage = validation.guidance;
      unawaited(_voiceGuidance.announce(validation.guidance));
      return;
    }
    final bodySpan = _shoulderToAnkleSpan(frame, validation.primarySide);
    if (bodySpan == null) {
      _heightSpanSamples.clear();
      _heightCalibrationStartedAt = null;
      _heightCalibrationProgress = 0;
      _heightCalibrationMessage = 'กรุณาจัดให้เห็นหัวไหล่และเท้าครบ';
      unawaited(_voiceGuidance.announce(_heightCalibrationMessage));
      return;
    }
    _heightCalibrationStartedAt ??= frame.timestamp;
    _heightSpanSamples.add(bodySpan);
    final elapsed = frame.timestamp - _heightCalibrationStartedAt!;
    _heightCalibrationProgress =
        (elapsed.inMilliseconds /
                AssessmentConfig
                    .anthropometricCalibrationDuration
                    .inMilliseconds)
            .clamp(0.0, 1.0);
    if (elapsed < AssessmentConfig.anthropometricCalibrationDuration ||
        _heightSpanSamples.length <
            AssessmentConfig.anthropometricCalibrationMinFrames) {
      return;
    }
    try {
      final calibration = _anthropometricCalibrationService.calibrate(
        sessionId: _sessionId,
        heightCm: widget.heightCm,
        visibleSpanSamples: _heightSpanSamples,
        imageAspectRatio: frame.imageAspectRatio,
      );
      _calibration = calibration;
      _measurement = ReachMeasurementService(calibration: calibration);
      _stateMachine.transitionTo(FunctionalReachState.baseline);
      _baselineStartedAt = null;
      _heightCalibrationMessage = '';
      unawaited(
        _voiceGuidance.announce(
          FunctionalReachInstructions.calibratedVoice,
          force: true,
        ),
      );
      AppLogger.event('anthropometric_calibration_success', <String, Object?>{
        'height_cm': widget.heightCm,
        'confidence': calibration.confidence,
      });
    } on FormatException catch (error) {
      _heightSpanSamples.clear();
      _heightCalibrationStartedAt = frame.timestamp;
      _heightCalibrationProgress = 0;
      _heightCalibrationMessage = error.message;
      unawaited(_voiceGuidance.announce(error.message, force: true));
    }
  }

  double? _shoulderToAnkleSpan(PoseFrame frame, PrimaryBodySide side) {
    final shoulder = frame[side.shoulder];
    final ankle = frame[side.ankle];
    if (shoulder == null || ankle == null) return null;
    final span = (ankle.y - shoulder.y).abs();
    return span > AssessmentConfig.calibrationMinNormalizedSpan ? span : null;
  }

  void _resetBaselineCapture() {
    if (_calibration == null) return;
    if (_baselineStartedAt != null || _baselineProgress > 0) {
      _measurement = ReachMeasurementService(calibration: _calibration!);
    }
    _baselineStartedAt = null;
    _baselineProgress = 0;
  }

  void _schedulePositioningStart() {
    if (_stateMachine.state != FunctionalReachState.positioning ||
        _positioningCountdownTimer != null ||
        !(_validation?.canStart ?? false)) {
      return;
    }
    _positioningCountdown = 3;
    unawaited(_voiceGuidance.announce('ตำแหน่งพร้อม สาม', force: true));
    if (mounted) setState(() {});
    _positioningCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted ||
          _stateMachine.state != FunctionalReachState.positioning ||
          !(_validation?.canStart ?? false)) {
        timer.cancel();
        _positioningCountdownTimer = null;
        _positioningCountdown = null;
        unawaited(_voiceGuidance.stop());
        if (mounted) setState(() {});
        return;
      }
      final next = (_positioningCountdown ?? 0) - 1;
      if (next <= 0) {
        timer.cancel();
        _positioningCountdownTimer = null;
        _positioningCountdown = null;
        _beginCalibration();
      } else {
        _positioningCountdown = next;
        unawaited(_voiceGuidance.announce(_countdownWord(next), force: true));
      }
      if (mounted) setState(() {});
    });
  }

  void _scheduleReachStart() {
    if (_stateMachine.state != FunctionalReachState.ready ||
        _readyCountdownTimer != null ||
        _lastFrame == null ||
        !(_validation?.canStart ?? false) ||
        !(_postureValidation?.canMeasure ?? false)) {
      return;
    }
    _readyCountdown = 3;
    unawaited(_voiceGuidance.announce('พร้อมเอื้อม สาม', force: true));
    if (mounted) setState(() {});
    _readyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted ||
          _stateMachine.state != FunctionalReachState.ready ||
          !(_validation?.canStart ?? false) ||
          !(_postureValidation?.canMeasure ?? false)) {
        timer.cancel();
        _readyCountdownTimer = null;
        _readyCountdown = null;
        unawaited(_voiceGuidance.stop());
        if (mounted) setState(() {});
        return;
      }
      final next = (_readyCountdown ?? 0) - 1;
      if (next <= 0) {
        timer.cancel();
        _readyCountdownTimer = null;
        _readyCountdown = null;
        unawaited(_voiceGuidance.announce('เริ่มเอื้อม', force: true));
        _startReach();
      } else {
        _readyCountdown = next;
        unawaited(_voiceGuidance.announce(_countdownWord(next), force: true));
      }
      if (mounted) setState(() {});
    });
  }

  void _cancelPositioningCountdown() {
    final wasActive =
        _positioningCountdownTimer != null || _positioningCountdown != null;
    _positioningCountdownTimer?.cancel();
    _positioningCountdownTimer = null;
    _positioningCountdown = null;
    if (wasActive) unawaited(_voiceGuidance.stop());
    if (wasActive && mounted) setState(() {});
  }

  void _cancelReadyCountdown() {
    final wasActive = _readyCountdownTimer != null || _readyCountdown != null;
    _readyCountdownTimer?.cancel();
    _readyCountdownTimer = null;
    _readyCountdown = null;
    if (wasActive) unawaited(_voiceGuidance.stop());
    if (wasActive && mounted) setState(() {});
  }

  String _countdownWord(int seconds) => switch (seconds) {
    3 => 'สาม',
    2 => 'สอง',
    1 => 'หนึ่ง',
    _ => '$seconds',
  };

  void _startReach() {
    if (_stateMachine.state != FunctionalReachState.ready ||
        _lastFrame == null ||
        !(_validation?.canStart ?? false) ||
        !(_postureValidation?.canMeasure ?? false)) {
      return;
    }
    _stateMachine.transitionTo(FunctionalReachState.reaching);
    _readyCountdownTimer?.cancel();
    _readyCountdownTimer = null;
    _readyCountdown = null;
    _reachStartedAt = _lastFrame!.timestamp;
    _reachProgress = 0;
    AppLogger.event('reach_started');
    setState(() {});
  }

  void _completeReach() {
    if (_stateMachine.state != FunctionalReachState.reaching) return;
    final snapshot = _measurement!.snapshot;
    final inches = UnitConversion.centimetersToInches(
      snapshot.maximumDistanceCm,
    );
    final status = FunctionalReachClassifier.classifyInches(inches);
    _result = FunctionalReachResult(
      id: IdGenerator.generate('reach'),
      sessionId: _sessionId,
      timestamp: DateTime.now(),
      distanceCm: snapshot.maximumDistanceCm,
      distanceInch: inches,
      thresholdInch: AssessmentConfig.functionalReachThresholdInches,
      status: status,
      footMovementDetected: false,
      calibrationMethod: _calibration!.method,
      confidence: snapshot.confidence,
      valid: true,
    );
    _stateMachine.transitionTo(FunctionalReachState.completed);
    unawaited(_screenAwake.release());
    unawaited(_cameraService.dispose());
    AppLogger.event('reach_peak', <String, Object?>{
      'distanceCm': snapshot.maximumDistanceCm,
      'confidence': snapshot.confidence,
    });
    setState(() {});
  }

  void _invalidate(InvalidReason reason) {
    if (!_stateMachine.canTransitionTo(FunctionalReachState.invalid)) return;
    final previousState = _stateMachine.state;
    _cancelPositioningCountdown();
    _cancelReadyCountdown();
    _invalidReason = reason;
    _stateMachine.transitionTo(FunctionalReachState.invalid);
    unawaited(_screenAwake.release());
    unawaited(_cameraService.dispose());
    AppLogger.event('reach_invalidated', <String, Object?>{
      'reason': reason.name,
      'from_state': previousState.name,
    });
    if (reason == InvalidReason.footMoved) {
      unawaited(
        _voiceGuidance.announce(
          'ตรวจพบว่าเท้าฝั่งกล้องขยับต่อเนื่อง กรุณาวางเท้าให้นิ่งแล้วเริ่มใหม่',
          force: true,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  String get _invalidMessage => switch (_invalidReason) {
    InvalidReason.footMoved =>
      'ตรวจพบการขยับของเท้าฝั่งกล้องต่อเนื่อง ผลระยะเอื้อมจึงไม่ถือว่าเป็นการทดสอบที่ใช้ได้',
    InvalidReason.poseLost =>
      'ระบบมองไม่เห็นร่างกายครบระหว่างทดสอบ กรุณาจัดตำแหน่งกล้องใหม่',
    InvalidReason.interrupted =>
      'แอปถูกพักหรือหน้าจอถูกล็อกระหว่างทดสอบ เพื่อความถูกต้องจึงต้องเริ่มใหม่',
    _ => 'การทดสอบไม่เป็นไปตามขั้นตอน กรุณาลองอีกครั้ง',
  };

  Future<void> _saveResult() async {
    final result = _result;
    final calibration = _calibration;
    if (result == null || calibration == null || _saved) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(assessmentRepositoryProvider);
      final profile = await repository.getProfile();
      final session = AssessmentSession(
        id: _sessionId,
        profileId: profile?.id,
        timestamp: result.timestamp,
        valid: true,
        functionalReach: result,
      );
      await repository.saveFunctionalReach(session, calibration, result);
      ref.read(historyRevisionProvider.notifier).bump();
      _saved = true;
      if (mounted) context.go('/history');
    } catch (error) {
      AppLogger.error('save_functional_reach_failed', error);
      if (mounted) _showMessage('บันทึกผลไม่สำเร็จ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _retry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            FunctionalReachAssessmentScreen(heightCm: widget.heightCm),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleVoice() {
    final enabled = !_voiceEnabled;
    setState(() => _voiceEnabled = enabled);
    unawaited(_voiceGuidance.setEnabled(enabled));
    if (enabled) {
      final state = _stateMachine.state;
      final message =
          state == FunctionalReachState.baseline ||
              state == FunctionalReachState.ready
          ? _postureValidation?.guidance
          : _validation?.guidance;
      unawaited(
        _voiceGuidance.announce(message ?? 'เปิดเสียงคำแนะนำแล้ว', force: true),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final current = _stateMachine.state;
    if (current == FunctionalReachState.positioning ||
        current == FunctionalReachState.calibrating ||
        current == FunctionalReachState.baseline ||
        current == FunctionalReachState.ready ||
        current == FunctionalReachState.reaching) {
      _invalidate(InvalidReason.interrupted);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_frameSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_metricsSubscription?.cancel());
    unawaited(_cameraService.dispose());
    _positioningCountdownTimer?.cancel();
    _readyCountdownTimer?.cancel();
    unawaited(_screenAwake.release());
    unawaited(_voiceGuidance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stateMachine.state == FunctionalReachState.invalid) {
      return InvalidTestScreen(reason: _invalidMessage, onRetry: _retry);
    }
    if (_stateMachine.state == FunctionalReachState.error) {
      final error = _initializationError;
      return PermissionErrorScreen(
        message: error is UserFacingException
            ? error.message
            : 'เปิดกล้องหรือตรวจจับท่าทางไม่สำเร็จ กรุณาลองอีกครั้ง',
        canOpenSettings: error is UserFacingException && error.canOpenSettings,
        onRetry: _retry,
      );
    }
    if (_stateMachine.state == FunctionalReachState.completed) {
      return _buildResult();
    }
    if (!_initialized) {
      return const Scaffold(
        body: LoadingView(label: 'กำลังเปิดกล้องและเตรียมระบบตรวจจับท่าทาง'),
      );
    }
    final developerMode = ref.watch(debugOverlayProvider);
    final showDebug = developerMode && _debugVisible;
    final controller = _cameraService.cameraController!;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final aspectRatio = portrait
        ? 1 / controller.value.aspectRatio
        : controller.value.aspectRatio;
    final state = _stateMachine.state;
    final showGuideFrame =
        state == FunctionalReachState.positioning ||
        state == FunctionalReachState.calibrating;
    final (icon, headline, subline) = _headerGuidance;
    return CameraAssessmentLayout(
      stepLabel: 'ขั้นที่ $_currentStep จาก 5: $_screenTitle',
      guidanceIcon: icon,
      headline: headline,
      subline: subline,
      voiceEnabled: _voiceEnabled,
      onToggleVoice: _toggleVoice,
      developerMode: developerMode,
      debugVisible: _debugVisible,
      onToggleDebug: () => setState(() => _debugVisible = !_debugVisible),
      preview: CameraPreview(controller),
      previewAspectRatio: aspectRatio,
      previewLayers: [
        if (showGuideFrame)
          CameraGuideFrame(
            showSilhouette:
                state == FunctionalReachState.positioning &&
                !(_validation?.bodyVisible ?? false),
          ),
        if (showDebug)
          PoseSkeletonOverlay(frame: _lastFrame, trackedSide: _trackedSide),
      ],
      cameraTopRight: showDebug
          ? FpsBadge(framesPerSecond: _debugMetrics?.framesPerSecond)
          : null,
      cameraBottom: showDebug ? _buildDebugPanel() : null,
      bottom: _buildBottom(showDebug),
    );
  }

  String get _screenTitle => switch (_stateMachine.state) {
    FunctionalReachState.positioning => 'จัดตำแหน่งกล้อง',
    FunctionalReachState.calibrating => 'ปรับเทียบระยะ',
    FunctionalReachState.baseline => 'เก็บตำแหน่งเริ่มต้น',
    FunctionalReachState.ready => 'พร้อมทดสอบ',
    FunctionalReachState.reaching => 'กำลังวัดระยะเอื้อม',
    _ => 'Functional Reach Test',
  };

  int get _currentStep => switch (_stateMachine.state) {
    FunctionalReachState.positioning => 1,
    FunctionalReachState.calibrating => 2,
    FunctionalReachState.baseline => 3,
    FunctionalReachState.ready => 4,
    FunctionalReachState.reaching => 5,
    _ => 1,
  };

  /// Icon, short headline and subline for the yellow guidance header.
  (IconData, String, String?) get _headerGuidance {
    switch (_stateMachine.state) {
      case FunctionalReachState.positioning:
        final validation = _validation;
        if (validation == null) {
          return (
            Icons.search_rounded,
            'กำลังค้นหา',
            'ยืนให้กล้องเห็นตั้งแต่หัวถึงเท้า',
          );
        }
        if (!validation.bodyVisible) {
          return (
            Icons.arrow_downward_rounded,
            'ถอยหลังอีก',
            'จนกล้องเห็นตั้งแต่หัวถึงเท้า',
          );
        }
        if (!validation.armVisible) {
          return (
            Icons.accessibility_new_rounded,
            'หันแขนเข้ากล้อง',
            'ให้เห็นไหล่และข้อศอกฝั่งที่หันเข้ากล้อง',
          );
        }
        if (!validation.feetVisible) {
          return (
            Icons.arrow_downward_rounded,
            'ให้เห็นเท้า 2 ข้าง',
            'ขยับกล้องลงหรือถอยออกอีกนิด',
          );
        }
        if (!validation.sideView) {
          return (
            Icons.rotate_right_rounded,
            'หันข้างเข้ากล้อง',
            'ให้ไหล่ข้างหนึ่งหันเข้าหากล้อง',
          );
        }
        if (!validation.canStart) {
          return (
            Icons.wb_sunny_outlined,
            'ภาพยังไม่ชัด',
            'เพิ่มแสงและอยู่นิ่ง',
          );
        }
        final countdown = _positioningCountdown;
        return (
          Icons.check_rounded,
          countdown == null ? 'อยู่นิ่ง' : 'อยู่นิ่ง $countdown',
          'ตำแหน่งพร้อมแล้ว ระบบจะเริ่มเอง',
        );
      case FunctionalReachState.calibrating:
        return (
          Icons.straighten_rounded,
          'อยู่นิ่ง',
          'กำลังคำนวณสเกลจากส่วนสูง ${widget.heightCm.toStringAsFixed(0)} ซม.',
        );
      case FunctionalReachState.baseline:
        final posture = _postureValidation;
        final ready = posture?.canMeasure ?? false;
        return (
          Icons.front_hand_outlined,
          ready ? 'ค้างท่าไว้' : 'ยกแขนไปข้างหน้า',
          posture?.guidance ?? FunctionalReachInstructions.baselineDetail,
        );
      case FunctionalReachState.ready:
        final countdown = _readyCountdown;
        return (
          Icons.timer_outlined,
          countdown == null ? 'เตรียมเอื้อม' : 'เริ่มใน $countdown',
          'เอื้อมไปข้างหน้าให้ไกลที่สุด ห้ามขยับเท้า',
        );
      case FunctionalReachState.reaching:
        return (
          Icons.arrow_forward_rounded,
          'เอื้อมไปข้างหน้า',
          'ให้ไกลที่สุดโดยไม่ขยับเท้า',
        );
      default:
        return (Icons.info_outline_rounded, _screenTitle, null);
    }
  }

  PrimaryBodySide? get _trackedSide =>
      _trackedArmSide ?? _validation?.primarySide;

  Widget _buildBottom(bool showDebug) => switch (_stateMachine.state) {
    FunctionalReachState.positioning => CameraCheckChips(
      checks: _positioningChecks(showDebug),
    ),
    FunctionalReachState.calibrating => CameraStageStatus(
      title: 'กำลังคำนวณสเกลจากส่วนสูง',
      progress: _heightCalibrationProgress,
      message: _heightCalibrationMessage.isEmpty
          ? 'คำนวณสำเร็จ ระบบกำลังเตรียมขั้นตอนถัดไป'
          : _heightCalibrationMessage,
    ),
    FunctionalReachState.baseline => CameraStageStatus(
      title: 'ท่าถูกและอยู่นิ่งจนแถบเต็ม',
      progress: _baselineProgress,
      checks: [
        CameraCheck(
          label: 'แขน 90°',
          passed: _postureValidation?.armPerpendicularToTorso ?? false,
          pending: _postureValidation == null,
          metric: showDebug
              ? _formatAngle(_postureValidation?.armToTorsoAngleDegrees)
              : null,
        ),
        CameraCheck(
          label: 'ศอกตรง',
          passed: _postureValidation?.elbowExtended ?? false,
          pending: _postureValidation == null,
          metric: showDebug
              ? _formatAngle(_postureValidation?.elbowAngleDegrees)
              : null,
        ),
      ],
    ),
    FunctionalReachState.ready => CameraStageStatus(
      title: _readyPostureOk ? 'พร้อมเริ่ม' : 'จัดท่าแขนอีกครั้ง',
      value: _readyCountdown?.toString(),
      message: _readyPostureOk
          ? 'ระบบจะเริ่มวัดเอง ไม่ต้องกดปุ่ม'
          : _postureValidation?.guidance ??
                FunctionalReachInstructions.readyPrompt,
    ),
    FunctionalReachState.reaching => CameraStageStatus(
      title: 'กำลังวัด',
      value:
          '${_measurement?.maximumDistanceCm.toStringAsFixed(1) ?? '0.0'} ซม.',
      progress: _reachProgress,
      message: 'ระบบจะเก็บระยะสูงสุดตลอดช่วงทดสอบ',
    ),
    _ => const SizedBox.shrink(),
  };

  bool get _readyPostureOk =>
      (_postureValidation?.canMeasure ?? false) &&
      (_postureValidation?.reachPointVisible ?? false);

  List<CameraCheck> _positioningChecks(bool showDebug) {
    final validation = _validation;
    final pending = validation == null;
    final frame = _lastFrame;
    final side = _trackedSide;
    String? metric(String Function() build) => showDebug ? build() : null;
    final sideLetter = side == PrimaryBodySide.left ? 'L' : 'R';
    return [
      CameraCheck(
        label: 'ทั้งตัว',
        passed: validation?.bodyVisible ?? false,
        pending: pending,
        metric: metric(
          () =>
              'ankle ${_formatConfidence(side == null ? null : frame?[side.ankle]?.confidence)}',
        ),
      ),
      CameraCheck(
        label: 'ไหล่–ศอก',
        passed: validation?.armVisible ?? false,
        pending: pending,
        metric: metric(
          () =>
              '$sideLetter arm ${_formatConfidence(frame == null || side == null ? null : _trackedArmConfidence(frame, side))}',
        ),
      ),
      CameraCheck(
        label: 'เท้า 2 ข้าง',
        passed: validation?.feetVisible ?? false,
        pending: pending,
        metric: metric(() => 'heel ${_heelConfidenceLabel(frame)}'),
      ),
      CameraCheck(
        label: 'หันข้าง',
        passed: validation?.sideView ?? false,
        pending: pending,
        metric: metric(() => 'sh.w ${_shoulderWidthLabel(frame)}'),
      ),
    ];
  }

  String _heelConfidenceLabel(PoseFrame? frame) {
    final left = frame?[BodyLandmark.leftHeel];
    final right = frame?[BodyLandmark.rightHeel];
    if (left == null || right == null) return 'n/a';
    final lowest = left.confidence < right.confidence
        ? left.confidence
        : right.confidence;
    return lowest.toStringAsFixed(2);
  }

  /// Shoulder separation relative to torso length; small values mean the
  /// person is standing side-on to the camera.
  String _shoulderWidthLabel(PoseFrame? frame) {
    final ls = frame?[BodyLandmark.leftShoulder];
    final rs = frame?[BodyLandmark.rightShoulder];
    final lh = frame?[BodyLandmark.leftHip];
    final rh = frame?[BodyLandmark.rightHip];
    if (ls == null || rs == null || lh == null || rh == null) return 'n/a';
    final torso = (ls.distanceTo(lh) + rs.distanceTo(rh)) / 2;
    if (torso == 0) return 'n/a';
    return ((ls.x - rs.x).abs() / torso).toStringAsFixed(2);
  }

  String get _systemStateLabel => switch (_stateMachine.state) {
    FunctionalReachState.positioning =>
      (_validation?.canStart ?? false) ? 'POSE_READY' : 'WAIT_POSE',
    FunctionalReachState.calibrating => 'CALIBRATING',
    FunctionalReachState.baseline => 'BASELINE',
    FunctionalReachState.ready => 'READY',
    FunctionalReachState.reaching => 'REACHING',
    final other => other.name.toUpperCase(),
  };

  Widget _buildDebugPanel() {
    final frame = _lastFrame;
    final trackedSide = _trackedSide;
    final fps = _debugMetrics?.framesPerSecond;
    final snapshot = _measurement?.snapshot;
    final sideLabel = trackedSide == null
        ? null
        : trackedSide == PrimaryBodySide.left
        ? 'ซ้าย'
        : 'ขวา';
    final posture = frame == null || trackedSide == null
        ? null
        : _postureService.validate(frame, trackedSide);
    final armConfidence = frame == null || trackedSide == null
        ? null
        : _trackedArmConfidence(frame, trackedSide);
    final (statusColor, status) = posture == null
        ? (Colors.white, 'กำลังค้นหาร่างกาย')
        : _poseDiagnosticStatus(posture);
    final armConfidenceOk =
        armConfidence != null &&
        armConfidence >= AssessmentConfig.poseConfidenceThreshold;
    final footMoving =
        snapshot != null &&
        snapshot.trackedFootMovementCm >= snapshot.footMovementThresholdCm;
    return CameraDebugPanel(
      logEventName: 'camera_debug_snapshot',
      statusColor: statusColor,
      status: status,
      confidence: armConfidence,
      rows: [
        CameraDebugRow('สถานะระบบ', _systemStateLabel),
        CameraDebugRow(
          'แขนที่ติดตาม',
          sideLabel == null ? '—' : '$sideLabel (ฝั่งกล้อง)',
        ),
        CameraDebugRow(
          'ความมั่นใจแขน',
          '${_formatConfidence(armConfidence)} / '
              '${AssessmentConfig.poseConfidenceThreshold.toStringAsFixed(2)}',
          color: armConfidenceOk ? CameraColors.devGood : CameraColors.devBad,
        ),
        CameraDebugRow(
          'มุมแขน–ลำตัว',
          _formatAngle(posture?.armToTorsoAngleDegrees),
        ),
        CameraDebugRow('มุมศอก', _formatAngle(posture?.elbowAngleDegrees)),
        CameraDebugRow(
          'จุดจัดท่า',
          sideLabel == null ? '—' : 'ไหล่–ศอก $sideLabel',
        ),
        CameraDebugRow(
          'จุดวัดจริง',
          sideLabel == null ? '—' : 'ข้อมือ$sideLabel',
        ),
        CameraDebugRow(
          'เท้าขยับ',
          snapshot == null
              ? 'ไม่'
              : '${footMoving ? 'ใช่' : 'ไม่'} '
                    '(${snapshot.trackedFootMovementCm.toStringAsFixed(1)}/'
                    '${snapshot.footMovementThresholdCm.toStringAsFixed(1)} ซม.)',
          color: footMoving ? CameraColors.devBad : CameraColors.devGood,
        ),
        const CameraDebugRow('แขนอีกข้าง', 'ข้างตัว (ไม่วัด)'),
        CameraDebugRow(
          'ระยะเอื้อม',
          '${_measurement?.maximumDistanceCm.toStringAsFixed(1) ?? '—'} ซม.',
        ),
        CameraDebugRow('เอนจิน', _cameraService.engineLabel),
        CameraDebugRow(
          'อัตราเฟรม',
          _formatFps(fps),
          color: CameraColors.devBad,
        ),
      ],
    );
  }

  (Color, String) _poseDiagnosticStatus(
    FunctionalReachPostureValidation posture,
  ) {
    if (!posture.landmarksReliable) {
      return (const Color(0xFFFF6259), 'จุดแขนฝั่งกล้องยังไม่ชัด');
    }
    final angle = posture.armToTorsoAngleDegrees!;
    if (angle < AssessmentConfig.functionalReachArmToTorsoAngleMinDegrees) {
      return (const Color(0xFFFFC247), 'แขนยังไม่ตั้งฉาก');
    }
    if (angle > AssessmentConfig.functionalReachArmToTorsoAngleMaxDegrees) {
      return (const Color(0xFFFFC247), 'แขนสูงเกินมุมตั้งฉาก');
    }
    if (!posture.elbowExtended) {
      return (const Color(0xFFFFC247), 'เหยียดข้อศอกให้ตรง');
    }
    if (!posture.reachPointVisible) {
      return (const Color(0xFFFFC247), 'ท่าแขนพร้อม รอข้อมือเพื่อวัด');
    }
    return (const Color(0xFF55D982), 'ท่าแขนพร้อม');
  }

  String _formatAngle(double? angle) =>
      angle == null ? '—' : '${angle.toStringAsFixed(0)}°';

  String _formatConfidence(double? confidence) =>
      confidence == null ? '—' : confidence.toStringAsFixed(2);

  double? _trackedArmConfidence(PoseFrame frame, PrimaryBodySide side) {
    final points = <NormalizedPoint?>[
      frame[side.shoulder],
      frame[side.elbow],
      frame[side.wrist],
      frame[side.hip],
    ].whereType<NormalizedPoint>().toList(growable: false);
    if (points.length != 4) return null;
    return points.fold(0.0, (sum, point) => sum + point.confidence) /
        points.length;
  }

  String _formatFps(double? fps) =>
      fps == null ? '— fps' : '${fps.toStringAsFixed(0)} fps';

  Widget _buildResult() {
    final result = _result!;
    final normal = result.status == AssessmentStatus.normal;
    return Scaffold(
      appBar: AppBar(title: const Text('ผลการทดสอบ')),
      body: AppScaffoldBody(
        child: Column(
          children: [
            Text(
              'ระยะที่เอื้อมได้',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              '${result.distanceInch.toStringAsFixed(1)} นิ้ว',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text('(${result.distanceCm.toStringAsFixed(1)} ซม.)'),
            const SizedBox(height: 20),
            StatusBanner(
              status: result.status,
              label: normal ? 'อยู่ในเกณฑ์' : 'ควรเฝ้าระวัง',
              detail: normal ? 'ระยะไม่น้อยกว่า 7 นิ้ว' : 'ระยะน้อยกว่า 7 นิ้ว',
            ),
            const SizedBox(height: 24),
            ReachThresholdBar(distanceInches: result.distanceInch),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: _retry,
              child: const Text('ทดสอบอีกครั้ง'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _saveResult,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'กำลังบันทึก' : 'บันทึกผล'),
            ),
          ],
        ),
      ),
    );
  }
}
