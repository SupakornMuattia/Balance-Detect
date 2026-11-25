import 'dart:async';
import 'dart:math' as math;

import 'package:balance_detect/core/constants/assessment_config.dart';
import 'package:balance_detect/core/domain/assessment_enums.dart';
import 'package:balance_detect/core/errors/user_facing_exception.dart';
import 'package:balance_detect/core/logging/app_logger.dart';
import 'package:balance_detect/core/providers/app_providers.dart';
import 'package:balance_detect/core/services/proximity_tone_service.dart';
import 'package:balance_detect/core/services/screen_awake_service.dart';
import 'package:balance_detect/core/services/voice_guidance_service.dart';
import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:balance_detect/core/utils/id_generator.dart';
import 'package:balance_detect/core/widgets/app_scaffold_body.dart';
import 'package:balance_detect/core/widgets/error_screens.dart';
import 'package:balance_detect/core/widgets/loading_view.dart';
import 'package:balance_detect/features/assessment/domain/assessment_session.dart';
import 'package:balance_detect/features/assessment/domain/calibration_record.dart';
import 'package:balance_detect/features/fullerton/domain/fullerton_logic.dart';
import 'package:balance_detect/features/fullerton/domain/fullerton_reach_calibration_service.dart';
import 'package:balance_detect/features/fullerton/domain/fullerton_result.dart';
import 'package:balance_detect/features/fullerton/domain/step_detection_service.dart';
import 'package:balance_detect/features/fullerton/presentation/fullerton_reach_overlay.dart';
import 'package:balance_detect/features/functional_reach/domain/distance_calibration_service.dart';
import 'package:balance_detect/features/functional_reach/domain/functional_reach_posture_service.dart';
import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:balance_detect/features/pose/domain/pose_validation.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_assessment_layout.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_check_chips.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_debug_panel.dart';
import 'package:balance_detect/features/pose/presentation/pose_skeleton_overlay.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service.dart';
import 'package:balance_detect/features/pose/services/camera_pose_service_factory.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class FullertonAssessmentScreen extends ConsumerStatefulWidget {
  const FullertonAssessmentScreen({
    required this.heightCm,
    required this.protocolVariant,
    super.key,
  });

  final double heightCm;
  final FullertonProtocolVariant protocolVariant;

  @override
  ConsumerState<FullertonAssessmentScreen> createState() =>
      _FullertonAssessmentScreenState();
}

class _FullertonAssessmentScreenState
    extends ConsumerState<FullertonAssessmentScreen>
    with WidgetsBindingObserver {
  final String _sessionId = IdGenerator.generate('session');
  final _stateMachine = FullertonStateMachine();
  final _validator = const PoseValidationService();
  final _postureService = const FunctionalReachPostureService();
  final _anthropometricCalibration =
      const AnthropometricHeightCalibrationService();
  final _targetGeometry = const FullertonTargetGeometry();
  late final CameraPoseService _cameraService;
  StepDetectionService _stepDetector = StepDetectionService();
  FullertonArmCalibrationService _armCalibration =
      FullertonArmCalibrationService();
  final List<double> _heightSpanSamples = <double>[];
  StreamSubscription<PoseFrame>? _frameSubscription;
  StreamSubscription<Object>? _errorSubscription;
  StreamSubscription<PoseDebugMetrics>? _metricsSubscription;
  PoseValidation? _validation;
  FunctionalReachPostureValidation? _postureValidation;
  PoseFrame? _lastFrame;
  PoseDebugMetrics? _metrics;
  StepDetectionSnapshot? _snapshot;
  CalibrationRecord? _calibration;
  FullertonReachTarget? _reachTarget;
  PrimaryBodySide? _trackedArmSide;
  Duration? _baselineStart;
  Duration? _armCalibrationStart;
  InvalidReason? _invalidReason;
  Object? _initializationError;
  FullertonResult? _result;
  bool _initialized = false;
  bool _saving = false;
  bool _voiceEnabled = true;
  bool _readyPoseValid = false;
  bool _targetReached = false;
  int _lostFrames = 0;
  int _processingErrors = 0;
  int _armFootMismatchFrames = 0;
  int _readyFootMismatchFrames = 0;
  int _targetHitFrames = 0;
  double _baselineProgress = 0;
  double _armCalibrationProgress = 0;
  double? _currentTargetDistanceCm;
  String _armCalibrationMessage = 'ยกแขนข้างเดียวให้ตั้งฉากกับลำตัว';
  final _screenAwake = ScreenAwakeService.instance.createLease();
  final _voiceGuidance = VoiceGuidanceService();
  final _targetTone = ProximityToneService();
  Timer? _positioningCountdownTimer;
  Timer? _readyCountdownTimer;
  Timer? _stepPermissionTimer;
  Timer? _completionTimer;
  int? _positioningCountdown;
  int? _readyCountdown;
  bool _debugVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_screenAwake.acquire());
    _cameraService = createCameraPoseService(ref.read(poseEngineProvider));
    _stateMachine.transitionTo(FullertonState.positioning);
    unawaited(_voiceGuidance.initialize());
    _frameSubscription = _cameraService.frames.listen(_onFrame);
    _errorSubscription = _cameraService.errors.listen(_onError);
    _metricsSubscription = _cameraService.debugMetrics.listen((value) {
      if (mounted) setState(() => _metrics = value);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _cameraService.initialize();
      if (mounted) setState(() => _initialized = true);
    } catch (error) {
      _initializationError = error;
      if (_stateMachine.canTransitionTo(FullertonState.error)) {
        _stateMachine.transitionTo(FullertonState.error);
      }
      unawaited(_screenAwake.release());
      if (mounted) setState(() {});
    }
  }

  void _onError(Object error) {
    _processingErrors += 1;
    if (_processingErrors < 5) return;
    _initializationError = error;
    if (_stateMachine.canTransitionTo(FullertonState.error)) {
      _stateMachine.transitionTo(FullertonState.error);
      unawaited(_screenAwake.release());
      if (mounted) setState(() {});
    }
  }

  void _onFrame(PoseFrame frame) {
    if (!mounted) return;
    _lastFrame = frame;
    final validation = _validator.validate(
      frame,
      requireSideView: true,
      trackedSide: _trackedArmSide,
    );
    _validation = validation;
    final side = _trackedArmSide ?? validation.primarySide;
    _postureValidation = _postureService.validate(frame, side);
    final state = _stateMachine.state;

    if (state == FullertonState.positioning) {
      final positioningReady = _positioningReady(frame, validation);
      unawaited(
        _voiceGuidance.announce(
          positioningReady ? validation.guidance : _positioningGuidance(frame),
        ),
      );
      if (positioningReady) {
        _schedulePositioningStart();
      } else {
        _cancelPositioningCountdown();
      }
    }

    if (_requiresContinuousBodyTracking(state)) {
      if (!(validation.bodyVisible && validation.feetVisible)) {
        _lostFrames += 1;
        if (_lostFrames >= AssessmentConfig.poseLostFrameLimit) {
          _invalidate(InvalidReason.poseLost);
          return;
        }
      } else {
        _lostFrames = 0;
      }
    }

    switch (state) {
      case FullertonState.footBaseline:
        _processFootBaseline(frame, validation);
      case FullertonState.armCalibration:
        _processArmCalibration(frame, validation, side);
      case FullertonState.ready:
        _processReadyFrame(frame, validation, side);
      case FullertonState.reaching:
        _processReachFrame(frame, validation, side);
      case FullertonState.idle ||
          FullertonState.positioning ||
          FullertonState.supervisionQuestion ||
          FullertonState.completed ||
          FullertonState.invalid ||
          FullertonState.error:
        break;
    }
    if (mounted) setState(() {});
  }

  bool _requiresContinuousBodyTracking(FullertonState state) =>
      state == FullertonState.footBaseline ||
      state == FullertonState.armCalibration ||
      state == FullertonState.ready ||
      (state == FullertonState.reaching && !_targetReached);

  bool _positioningReady(PoseFrame frame, PoseValidation validation) {
    final fingertip = frame[validation.primarySide.indexFinger];
    return validation.canStart &&
        _stepDetector.canObserveBothFeet(frame) &&
        fingertip != null &&
        fingertip.confidence >= AssessmentConfig.poseConfidenceThreshold;
  }

  String _positioningGuidance(PoseFrame frame) {
    final validation = _validation;
    if (validation == null) return 'กำลังค้นหาร่างกาย';
    if (!validation.canStart) return validation.guidance;
    if (!_stepDetector.canObserveBothFeet(frame)) {
      return 'ขยับมุมกล้องเล็กน้อยให้เห็นข้อเท้า ส้นเท้า และปลายเท้าทั้งสองข้างแยกกัน';
    }
    final fingertip = frame[validation.primarySide.indexFinger];
    if (fingertip == null ||
        fingertip.confidence < AssessmentConfig.poseConfidenceThreshold) {
      return 'ขยับให้เห็นปลายนิ้วของแขนฝั่งที่หันเข้ากล้องชัดเจน';
    }
    return 'ตำแหน่งพร้อมแล้ว อยู่นิ่ง ระบบกำลังเริ่มอัตโนมัติ';
  }

  void _processFootBaseline(PoseFrame frame, PoseValidation validation) {
    if (!validation.canStart || !_stepDetector.canObserveBothFeet(frame)) {
      _resetFootCapture();
      unawaited(
        _voiceGuidance.announce(
          validation.canStart
              ? 'ขยับมุมกล้องเล็กน้อยให้เห็นเท้าทั้งสองข้างแยกกัน'
              : validation.guidance,
        ),
      );
      return;
    }
    _baselineStart ??= frame.timestamp;
    _stepDetector.addBaselineFrame(frame);
    final span = _shoulderToAnkleSpan(
      frame,
      _trackedArmSide ?? validation.primarySide,
    );
    if (span != null) _heightSpanSamples.add(span);
    final elapsed = frame.timestamp - _baselineStart!;
    _baselineProgress =
        elapsed.inMilliseconds /
        AssessmentConfig.fullertonBaselineDuration.inMilliseconds;
    if (elapsed < AssessmentConfig.fullertonBaselineDuration) return;

    final feetReady = _stepDetector.finalizeBaseline();
    if (!feetReady) {
      _resetFootCapture();
      unawaited(
        _voiceGuidance.announce(
          'เท้ายังไม่นิ่ง กรุณาวางเท้าตามสบายแล้วอยู่นิ่งอีกครั้ง',
          force: true,
        ),
      );
      return;
    }
    try {
      _calibration = _anthropometricCalibration.calibrate(
        sessionId: _sessionId,
        heightCm: widget.heightCm,
        visibleSpanSamples: _heightSpanSamples,
        imageAspectRatio: frame.imageAspectRatio,
      );
    } on FormatException catch (error) {
      _resetFootCapture();
      unawaited(_voiceGuidance.announce(error.message, force: true));
      return;
    }
    _beginArmCalibration(frame.timestamp);
  }

  double? _shoulderToAnkleSpan(PoseFrame frame, PrimaryBodySide side) {
    final shoulder = frame[side.shoulder];
    final ankle = frame[side.ankle];
    if (shoulder == null || ankle == null) return null;
    final span = (ankle.y - shoulder.y).abs();
    return span > AssessmentConfig.calibrationMinNormalizedSpan ? span : null;
  }

  void _resetFootCapture() {
    _stepDetector = StepDetectionService();
    _heightSpanSamples.clear();
    _baselineStart = null;
    _baselineProgress = 0;
    _calibration = null;
  }

  void _beginArmCalibration(Duration timestamp) {
    _armCalibration = FullertonArmCalibrationService();
    _armCalibrationStart = null;
    _armCalibrationProgress = 0;
    _armFootMismatchFrames = 0;
    _armCalibrationMessage =
        'ยกแขนข้างเดียวที่หันเข้ากล้องให้ตั้งฉากกับลำตัว เหยียดข้อศอกและนิ้ว';
    _stateMachine.transitionTo(FullertonState.armCalibration);
    unawaited(
      _voiceGuidance.announce(
        'จำตำแหน่งเท้าแล้ว ยกแขนข้างเดียวให้ตั้งฉากกับลำตัว เหยียดข้อศอกและนิ้ว',
        force: true,
      ),
    );
    AppLogger.event('fullerton_foot_calibration_success', <String, Object?>{
      'height_cm': widget.heightCm,
      'foot_confidence': _stepDetector.baseline?.confidence,
      'scale_confidence': _calibration?.confidence,
      'timestamp_ms': timestamp.inMilliseconds,
    });
  }

  void _processArmCalibration(
    PoseFrame frame,
    PoseValidation validation,
    PrimaryBodySide side,
  ) {
    if (!validation.canStart) {
      _armCalibration.reset();
      _armCalibrationStart = null;
      _armCalibrationProgress = 0;
      _armCalibrationMessage = validation.guidance;
      unawaited(_voiceGuidance.announce(validation.guidance));
      return;
    }
    if (!_stepDetector.feetRemainAtBaseline(frame)) {
      _armFootMismatchFrames += 1;
      _armCalibration.reset();
      _armCalibrationStart = null;
      _armCalibrationProgress = 0;
      _armCalibrationMessage = 'วางเท้ากลับตำแหน่งเดิมและอยู่นิ่ง';
      if (_armFootMismatchFrames >= AssessmentConfig.stepConfirmationFrames) {
        _restartFootCalibration('ตำแหน่งเท้าเปลี่ยน ระบบจะจำตำแหน่งเท้าใหม่');
      } else {
        unawaited(_voiceGuidance.announce(_armCalibrationMessage));
      }
      return;
    }
    _armFootMismatchFrames = 0;
    final status = _armCalibration.addFrame(frame, side);
    _armCalibrationMessage = status.guidance;
    if (status.acceptedFrameCount == 0) {
      _armCalibrationStart = null;
      _armCalibrationProgress = 0;
      unawaited(_voiceGuidance.announce(status.guidance));
      return;
    }
    _armCalibrationStart ??= frame.timestamp;
    final elapsed = frame.timestamp - _armCalibrationStart!;
    _armCalibrationProgress =
        elapsed.inMilliseconds /
        AssessmentConfig.fullertonArmCalibrationDuration.inMilliseconds;
    if (elapsed < AssessmentConfig.fullertonArmCalibrationDuration ||
        !status.canCalibrate) {
      return;
    }
    final calibration = _calibration;
    if (calibration == null) {
      _invalidate(InvalidReason.calibrationFailed);
      return;
    }
    try {
      _reachTarget = _armCalibration.finalize(
        calibration: calibration,
        protocolVariant: widget.protocolVariant,
      );
    } on FormatException catch (error) {
      _armCalibration.reset();
      _armCalibrationStart = null;
      _armCalibrationProgress = 0;
      _armCalibrationMessage = error.message;
      unawaited(_voiceGuidance.announce(error.message, force: true));
      return;
    }
    _stateMachine.transitionTo(FullertonState.ready);
    _readyPoseValid = true;
    _readyFootMismatchFrames = 0;
    unawaited(
      _voiceGuidance.announce(
        'สร้างเป้าหมายแล้ว ค้างแขนและเท้าไว้ ระบบจะนับถอยหลัง',
        force: true,
      ),
    );
    AppLogger.event('fullerton_target_calibration_success', <String, Object?>{
      'target_distance_cm': _reachTarget!.targetDistanceCm,
      'protocol_variant': widget.protocolVariant.name,
      'confidence': _reachTarget!.confidence,
      'tracked_side': side.name,
    });
    _scheduleReachStart();
  }

  void _restartFootCalibration(String message) {
    if (_stateMachine.state != FullertonState.armCalibration) return;
    _stateMachine.transitionTo(FullertonState.footBaseline);
    _resetFootCapture();
    _armCalibration = FullertonArmCalibrationService();
    _reachTarget = null;
    _armFootMismatchFrames = 0;
    unawaited(_voiceGuidance.announce(message, force: true));
  }

  void _processReadyFrame(
    PoseFrame frame,
    PoseValidation validation,
    PrimaryBodySide side,
  ) {
    final feetStable = _stepDetector.feetRemainAtBaseline(frame);
    if (!feetStable) {
      _readyFootMismatchFrames += 1;
    } else {
      _readyFootMismatchFrames = 0;
    }
    if (_readyFootMismatchFrames >= AssessmentConfig.stepConfirmationFrames) {
      _cancelReadyCountdown();
      _stateMachine.transitionTo(FullertonState.armCalibration);
      _armCalibration = FullertonArmCalibrationService();
      _armCalibrationStart = null;
      _armCalibrationProgress = 0;
      _reachTarget = null;
      _armCalibrationMessage =
          'เท้าขยับก่อนเริ่ม กรุณากลับตำแหน่งเดิมและคาลิเบรตแขนใหม่';
      unawaited(_voiceGuidance.announce(_armCalibrationMessage, force: true));
      return;
    }
    final posture = _postureService.validate(frame, side);
    final fingertip = frame[side.indexFinger];
    final target = _reachTarget;
    var fingertipAtStart = false;
    if (fingertip != null &&
        target != null &&
        _calibration != null &&
        fingertip.confidence >= AssessmentConfig.poseConfidenceThreshold) {
      fingertipAtStart =
          _targetGeometry.metricDistanceCm(
            fingertip,
            target.startFingertip,
            calibration: _calibration!,
            imageAspectRatio: frame.imageAspectRatio,
          ) <=
          AssessmentConfig.fullertonReturnRadiusCm;
    }
    _readyPoseValid =
        validation.canStart &&
        posture.canMeasure &&
        feetStable &&
        fingertipAtStart;
    if (_readyPoseValid) {
      _scheduleReachStart();
      return;
    }
    _cancelReadyCountdown();
    final guidance = !validation.canStart
        ? validation.guidance
        : !posture.canMeasure
        ? posture.guidance
        : !feetStable
        ? 'วางเท้ากลับตำแหน่งที่มีเครื่องหมาย'
        : 'นำปลายนิ้วกลับจุดเริ่มสีขาวและค้างไว้';
    unawaited(_voiceGuidance.announce(guidance));
  }

  void _processReachFrame(
    PoseFrame frame,
    PoseValidation validation,
    PrimaryBodySide side,
  ) {
    // Steps are counted only until the target is touched; the brief
    // completion cue afterwards must not change the score.
    if (_targetReached) return;
    if (!(validation.bodyVisible && validation.feetVisible)) return;
    final previousSteps = _snapshot?.stepCount ?? 0;
    _snapshot = _stepDetector.addFrame(frame);
    if (_snapshot!.stepCount > previousSteps) {
      AppLogger.event('fullerton_step_detected', <String, Object?>{
        'stepCount': _snapshot!.stepCount,
      });
    }
    _processTargetContact(frame, side);
  }

  void _processTargetContact(PoseFrame frame, PrimaryBodySide side) {
    final fingertip = frame[side.indexFinger];
    final target = _reachTarget;
    final calibration = _calibration;
    if (fingertip == null ||
        fingertip.confidence < AssessmentConfig.poseConfidenceThreshold ||
        target == null ||
        calibration == null) {
      _targetHitFrames = 0;
      return;
    }
    final targetDistance = _targetGeometry.metricDistanceCm(
      fingertip,
      target.targetPoint,
      calibration: calibration,
      imageAspectRatio: frame.imageAspectRatio,
    );
    _currentTargetDistanceCm = targetDistance;
    // Measure the audio cue to the edge of the hit zone so the gentlest
    // tone is reached exactly where contact starts counting.
    const hitRadius = AssessmentConfig.fullertonTargetHitRadiusCm;
    _targetTone.updateDistance(
      distanceCm: math.max(0, targetDistance - hitRadius),
      referenceDistanceCm: math.max(1, target.targetDistanceCm - hitRadius),
    );
    _targetHitFrames = targetDistance <= hitRadius ? _targetHitFrames + 1 : 0;
    if (_targetHitFrames >=
        AssessmentConfig.fullertonTargetConfirmationFrames) {
      _onTargetTouched();
    }
  }

  /// Touching the target ends the reach: completion chime, then the spoken
  /// "เสร็จสิ้น", then the score screen.
  void _onTargetTouched() {
    _targetReached = true;
    _targetHitFrames = 0;
    _stepPermissionTimer?.cancel();
    _stepPermissionTimer = null;
    AppLogger.event('fullerton_target_touched', <String, Object?>{
      'stepCount': _snapshot?.stepCount ?? 0,
    });
    unawaited(_targetTone.playComplete());
    _completionTimer?.cancel();
    // Let the chime finish before speaking so the two do not overlap.
    _completionTimer = Timer(
      ProximityToneService.completionChimeDuration +
          const Duration(milliseconds: 100),
      () {
        if (!mounted || _stateMachine.state != FullertonState.reaching) return;
        unawaited(_voiceGuidance.announce('เสร็จสิ้น', force: true));
        _completionTimer = Timer(const Duration(milliseconds: 900), () {
          _completionTimer = null;
          if (mounted) _finishReach();
        });
      },
    );
  }

  void _startBaseline() {
    final frame = _lastFrame;
    final validation = _validation;
    if (_stateMachine.state != FullertonState.positioning ||
        frame == null ||
        validation == null ||
        !_positioningReady(frame, validation)) {
      return;
    }
    _trackedArmSide = validation.primarySide;
    _stateMachine.transitionTo(FullertonState.footBaseline);
    _resetFootCapture();
    unawaited(
      _voiceGuidance.announce(
        'เริ่มจำตำแหน่งเท้าจริงและคำนวณสเกลจากส่วนสูง',
        force: true,
      ),
    );
    setState(() {});
  }

  void _schedulePositioningStart() {
    final frame = _lastFrame;
    final validation = _validation;
    if (_stateMachine.state != FullertonState.positioning ||
        _positioningCountdownTimer != null ||
        frame == null ||
        validation == null ||
        !_positioningReady(frame, validation)) {
      return;
    }
    _positioningCountdown = 3;
    unawaited(
      _voiceGuidance.announce('ตำแหน่งพร้อมแล้ว เริ่มในสามวินาที', force: true),
    );
    if (mounted) setState(() {});
    _positioningCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      final currentFrame = _lastFrame;
      final currentValidation = _validation;
      if (!mounted ||
          _stateMachine.state != FullertonState.positioning ||
          currentFrame == null ||
          currentValidation == null ||
          !_positioningReady(currentFrame, currentValidation)) {
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
        _startBaseline();
      } else {
        _positioningCountdown = next;
        unawaited(_voiceGuidance.announce(_countdownWord(next), force: true));
      }
      if (mounted) setState(() {});
    });
  }

  void _scheduleReachStart() {
    if (_stateMachine.state != FullertonState.ready ||
        _readyCountdownTimer != null ||
        !_readyPoseValid) {
      return;
    }
    _readyCountdown = 3;
    unawaited(
      _voiceGuidance.announce('พร้อมแล้ว เริ่มเอื้อมในสามวินาที', force: true),
    );
    if (mounted) setState(() {});
    _readyCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted ||
          _stateMachine.state != FullertonState.ready ||
          !_readyPoseValid) {
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
    if (_stateMachine.state != FullertonState.ready) return;
    _stateMachine.transitionTo(FullertonState.reaching);
    _targetReached = false;
    _targetHitFrames = 0;
    _currentTargetDistanceCm = null;
    _targetTone.start();
    unawaited(
      _voiceGuidance.announce(
        'เริ่มเอื้อมแตะดินสอเสมือน โดยพยายามไม่เลื่อนเท้า',
        force: true,
      ),
    );
    _stepPermissionTimer?.cancel();
    _stepPermissionTimer = Timer(
      AssessmentConfig.fullertonStepPermissionDelay,
      () {
        if (!mounted ||
            _stateMachine.state != FullertonState.reaching ||
            _targetReached) {
          return;
        }
        unawaited(
          _voiceGuidance.announce(
            'หากยังเอื้อมไม่ถึง สามารถก้าวเท้าเพื่อไปถึงเป้าหมายได้',
            force: true,
          ),
        );
      },
    );
    AppLogger.event('fullerton_reach_started', <String, Object?>{
      'protocol_variant': widget.protocolVariant.name,
      'target_distance_cm': _reachTarget?.targetDistanceCm,
    });
    setState(() {});
  }

  void _finishReach() {
    if (_stateMachine.state != FullertonState.reaching) return;
    _stepPermissionTimer?.cancel();
    _stepPermissionTimer = null;
    final snapshot = _stepDetector.snapshot;
    _snapshot = snapshot;
    if (snapshot.confidence < AssessmentConfig.stepMinimumResultConfidence) {
      _invalidate(InvalidReason.stepConfidenceLow);
      return;
    }
    unawaited(_cameraService.dispose());
    if (snapshot.stepCount == 0) {
      _stateMachine.transitionTo(FullertonState.supervisionQuestion);
      setState(() {});
    } else {
      _complete(supervisionRequired: null);
    }
  }

  void _complete({required bool? supervisionRequired}) {
    final snapshot = _snapshot ?? _stepDetector.snapshot;
    final score = FullertonScoring.calculate(
      stepCount: snapshot.stepCount,
      supervisionRequired: supervisionRequired,
    );
    final targetConfidence = _reachTarget?.confidence ?? 0;
    _result = FullertonResult(
      id: IdGenerator.generate('fullerton'),
      sessionId: _sessionId,
      timestamp: DateTime.now(),
      score: score,
      stepCount: snapshot.stepCount,
      supervisionRequired: supervisionRequired,
      confidence: math.min(snapshot.confidence, targetConfidence),
      valid: true,
      protocolVariant: widget.protocolVariant,
      targetDistanceCm: _reachTarget?.targetDistanceCm,
      heightCm: widget.heightCm,
    );
    _stateMachine.transitionTo(FullertonState.completed);
    unawaited(_screenAwake.release());
    unawaited(_cameraService.dispose());
    setState(() {});
  }

  void _invalidate(InvalidReason reason) {
    if (!_stateMachine.canTransitionTo(FullertonState.invalid)) return;
    _cancelPositioningCountdown();
    _cancelReadyCountdown();
    _stepPermissionTimer?.cancel();
    _stepPermissionTimer = null;
    _completionTimer?.cancel();
    _completionTimer = null;
    unawaited(_targetTone.stop());
    _invalidReason = reason;
    _stateMachine.transitionTo(FullertonState.invalid);
    unawaited(_screenAwake.release());
    unawaited(_cameraService.dispose());
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(assessmentRepositoryProvider);
      final profile = await repository.getProfile();
      final session = AssessmentSession(
        id: _sessionId,
        profileId: profile?.id,
        timestamp: result.timestamp,
        valid: true,
        fullerton: result,
      );
      await repository.saveFullerton(session, result);
      ref.read(historyRevisionProvider.notifier).bump();
      if (mounted) context.go('/history');
    } catch (error) {
      AppLogger.error('save_fullerton_failed', error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกผลไม่สำเร็จ กรุณาลองอีกครั้ง')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _retry() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FullertonAssessmentScreen(
          heightCm: widget.heightCm,
          protocolVariant: widget.protocolVariant,
        ),
      ),
    );
  }

  void _toggleVoice() {
    final enabled = !_voiceEnabled;
    setState(() => _voiceEnabled = enabled);
    unawaited(_voiceGuidance.setEnabled(enabled));
    unawaited(_targetTone.setEnabled(enabled));
    if (enabled) {
      unawaited(_voiceGuidance.announce(_currentGuidance, force: true));
    }
  }

  String get _currentGuidance => switch (_stateMachine.state) {
    FullertonState.positioning =>
      _lastFrame == null
          ? 'กำลังค้นหาร่างกาย'
          : _positioningGuidance(_lastFrame!),
    FullertonState.footBaseline => 'ยืนวางเท้านิ่ง ระบบกำลังจำตำแหน่งเท้า',
    FullertonState.armCalibration => _armCalibrationMessage,
    FullertonState.ready => 'ค้างท่าเดิม ระบบกำลังนับถอยหลัง',
    FullertonState.reaching =>
      _targetReached
          ? 'เสร็จสิ้น'
          : 'เอื้อมแตะดินสอเสมือนโดยพยายามไม่เลื่อนเท้า',
    _ => 'เปิดเสียงคำแนะนำแล้ว',
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final current = _stateMachine.state;
    if (current == FullertonState.positioning ||
        current == FullertonState.footBaseline ||
        current == FullertonState.armCalibration ||
        current == FullertonState.ready ||
        current == FullertonState.reaching ||
        current == FullertonState.supervisionQuestion) {
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
    _stepPermissionTimer?.cancel();
    _completionTimer?.cancel();
    unawaited(_screenAwake.release());
    unawaited(_voiceGuidance.dispose());
    unawaited(_targetTone.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stateMachine.state == FullertonState.invalid) {
      return InvalidTestScreen(reason: _invalidMessage, onRetry: _retry);
    }
    if (_stateMachine.state == FullertonState.error) {
      final error = _initializationError;
      return PermissionErrorScreen(
        message: error is UserFacingException
            ? error.message
            : 'เปิดกล้องหรือตรวจจับท่าทางไม่สำเร็จ',
        canOpenSettings: error is UserFacingException && error.canOpenSettings,
        onRetry: _retry,
      );
    }
    if (_stateMachine.state == FullertonState.supervisionQuestion) {
      return _buildSupervisionQuestion();
    }
    if (_stateMachine.state == FullertonState.completed) return _buildResult();
    if (!_initialized) {
      return const Scaffold(
        body: LoadingView(label: 'กำลังเปิดกล้องและเตรียมระบบคาลิเบรต'),
      );
    }
    final developerMode = ref.watch(debugOverlayProvider);
    final showDebug = developerMode && _debugVisible;
    final controller = _cameraService.cameraController!;
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final ratio = portrait
        ? 1 / controller.value.aspectRatio
        : controller.value.aspectRatio;
    final overlaySide = _trackedArmSide ?? _validation?.primarySide;
    final (icon, headline, subline) = _headerGuidance;
    return CameraAssessmentLayout(
      stepLabel: 'ขั้นที่ $_currentStep จาก 5: $_title',
      guidanceIcon: icon,
      headline: headline,
      subline: subline,
      voiceEnabled: _voiceEnabled,
      onToggleVoice: _toggleVoice,
      developerMode: developerMode,
      debugVisible: _debugVisible,
      onToggleDebug: () => setState(() => _debugVisible = !_debugVisible),
      preview: CameraPreview(controller),
      previewAspectRatio: ratio,
      previewLayers: [
        if (showDebug)
          PoseSkeletonOverlay(frame: _lastFrame, trackedSide: overlaySide),
        FullertonReachOverlay(
          footBaseline: _stepDetector.baseline,
          target: _reachTarget,
          targetReached: _targetReached,
        ),
      ],
      cameraTopRight: showDebug
          ? FpsBadge(framesPerSecond: _metrics?.framesPerSecond)
          : null,
      cameraBottom: showDebug ? _buildDebugPanel() : null,
      caption:
          _stateMachine.state == FullertonState.reaching &&
              !_targetReached &&
              _voiceEnabled
          ? 'ยิ่งใกล้เป้าหมาย เสียงยิ่งเบาและช้าลง'
          : 'ฟังเสียงแล้วทำตาม ไม่ต้องกดปุ่ม',
      bottom: _buildBottom(showDebug),
    );
  }

  String get _title => switch (_stateMachine.state) {
    FullertonState.positioning => 'จัดกล้องด้านข้าง',
    FullertonState.footBaseline => 'จำตำแหน่งเท้า',
    FullertonState.armCalibration => 'คาลิเบรตแขนและปลายนิ้ว',
    FullertonState.ready => 'เป้าหมายพร้อม',
    FullertonState.reaching =>
      _targetReached ? 'เสร็จสิ้น' : 'เอื้อมไปยังเป้าหมาย',
    _ => 'Fullerton',
  };

  int get _currentStep => switch (_stateMachine.state) {
    FullertonState.positioning => 1,
    FullertonState.footBaseline => 2,
    FullertonState.armCalibration => 3,
    FullertonState.ready => 4,
    FullertonState.reaching => 5,
    _ => 1,
  };

  String get _invalidMessage => switch (_invalidReason) {
    InvalidReason.poseLost =>
      'ระบบมองไม่เห็นร่างกาย ปลายนิ้ว หรือเท้าครบระหว่างการทดสอบ',
    InvalidReason.calibrationFailed =>
      'คาลิเบรตตำแหน่งเท้า ปลายนิ้ว หรือสเกลจากส่วนสูงไม่สำเร็จ',
    InvalidReason.stepConfidenceLow =>
      'ข้อมูลตำแหน่งเท้าไม่ชัดพอที่จะสรุปจำนวนก้าวอย่างน่าเชื่อถือ',
    InvalidReason.interrupted => 'แอปถูกพักหรือหน้าจอถูกล็อกระหว่างการทดสอบ',
    _ => 'ลำดับการทดสอบไม่สมบูรณ์ กรุณาลองอีกครั้ง',
  };

  bool _fingertipVisible(PoseFrame? frame, PrimaryBodySide? side) {
    final fingertip = frame == null || side == null
        ? null
        : frame[side.indexFinger];
    return fingertip != null &&
        fingertip.confidence >= AssessmentConfig.poseConfidenceThreshold;
  }

  /// Icon, short headline and subline for the yellow guidance header.
  (IconData, String, String?) get _headerGuidance {
    switch (_stateMachine.state) {
      case FullertonState.positioning:
        final validation = _validation;
        final frame = _lastFrame;
        if (validation == null || frame == null) {
          return (
            Icons.search_rounded,
            'กำลังค้นหา',
            'ยืนด้านข้างให้กล้องเห็นตั้งแต่หัวถึงเท้า',
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
        if (!validation.feetVisible ||
            !_stepDetector.canObserveBothFeet(frame)) {
          return (
            Icons.arrow_downward_rounded,
            'ให้เห็นเท้า 2 ข้าง',
            'เห็นข้อเท้า ส้นเท้า และปลายเท้าแยกกัน',
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
        if (!_fingertipVisible(frame, validation.primarySide)) {
          return (
            Icons.back_hand_outlined,
            'ให้เห็นปลายนิ้ว',
            'ของแขนฝั่งที่หันเข้ากล้อง',
          );
        }
        final countdown = _positioningCountdown;
        return (
          Icons.check_rounded,
          countdown == null ? 'อยู่นิ่ง' : 'อยู่นิ่ง $countdown',
          'ตำแหน่งพร้อมแล้ว ระบบจะเริ่มเอง',
        );
      case FullertonState.footBaseline:
        return (
          Icons.accessibility_rounded,
          'ยืนนิ่ง',
          'ระบบกำลังจำตำแหน่งเท้า',
        );
      case FullertonState.armCalibration:
        return (Icons.front_hand_outlined, 'ยกแขน 90°', _armCalibrationMessage);
      case FullertonState.ready:
        final countdown = _readyCountdown;
        return (
          Icons.timer_outlined,
          countdown == null ? 'ค้างท่าไว้' : 'เริ่มใน $countdown',
          _readyPoseValid
              ? 'ค้างท่าเดิม ระบบกำลังนับถอยหลัง'
              : 'นำปลายนิ้วกลับจุดขาวและวางเท้าที่เดิม',
        );
      case FullertonState.reaching:
        return _targetReached
            ? (Icons.check_rounded, 'เสร็จสิ้น', 'กำลังแสดงผลคะแนน')
            : (
                Icons.ads_click_rounded,
                'แตะดินสอเสมือน',
                'เอื้อมโดยพยายามไม่เลื่อนเท้า',
              );
      default:
        return (Icons.info_outline_rounded, _title, null);
    }
  }

  Widget _buildBottom(bool showDebug) {
    switch (_stateMachine.state) {
      case FullertonState.positioning:
        return CameraCheckChips(checks: _positioningChecks(showDebug));
      case FullertonState.footBaseline:
        return CameraStageStatus(
          title: 'ยืนวางเท้าตามสบายแล้วอยู่นิ่ง',
          progress: _baselineProgress,
          message:
              'ใช้ส่วนสูง ${widget.heightCm.toStringAsFixed(0)} ซม. คำนวณสเกลภาพ · ถ้าเท้าไม่นิ่ง ระบบจะเก็บใหม่เอง',
        );
      case FullertonState.armCalibration:
        final posture = _postureValidation;
        return CameraStageStatus(
          title: 'คาลิเบรตแขน',
          progress: _armCalibrationProgress,
          message:
              'มุมแขน ${posture?.armToTorsoAngleDegrees?.toStringAsFixed(0) ?? '—'}° · '
              'ข้อศอก ${posture?.elbowAngleDegrees?.toStringAsFixed(0) ?? '—'}°',
          checks: [
            CameraCheck(
              label: 'แขน 90°',
              passed: posture?.armPerpendicularToTorso ?? false,
              pending: posture == null,
            ),
            CameraCheck(
              label: 'ศอกตรง',
              passed: posture?.elbowExtended ?? false,
              pending: posture == null,
            ),
            CameraCheck(
              label: 'ปลายนิ้ว',
              passed: _fingertipVisible(_lastFrame, _trackedArmSide),
              pending: _lastFrame == null,
            ),
            CameraCheck(
              label: 'เท้าที่เดิม',
              passed: _armFootMismatchFrames == 0,
              pending: _stepDetector.baseline == null,
            ),
          ],
        );
      case FullertonState.ready:
        return CameraStageStatus(
          title: 'เป้าหมายเสมือนพร้อม',
          value: _readyCountdown?.toString(),
          message: widget.protocolVariant.isStandard
              ? '${widget.protocolVariant.thaiLabel} · จุดเป้าหมายถูกตรึงแล้ว'
              : '${widget.protocolVariant.thaiLabel} · โหมด 1 ฟุตเป็น Modified FAB; ระยะมาตรฐานคือ 10 นิ้ว',
        );
      case FullertonState.reaching:
        return CameraStageStatus(
          title: _targetReached ? 'แตะเป้าหมายแล้ว' : 'เหลือถึงเป้าหมาย',
          value: _targetReached || _currentTargetDistanceCm == null
              ? null
              : '${_currentTargetDistanceCm!.toStringAsFixed(1)} ซม.',
          message: 'ตรวจพบ ${_snapshot?.stepCount ?? 0} ก้าว',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<CameraCheck> _positioningChecks(bool showDebug) {
    final validation = _validation;
    final frame = _lastFrame;
    final side = validation?.primarySide;
    final pending = validation == null || frame == null;
    final fingertip = frame == null || side == null
        ? null
        : frame[side.indexFinger];
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
        label: 'แขน–นิ้ว',
        passed:
            (validation?.armVisible ?? false) && _fingertipVisible(frame, side),
        pending: pending,
        metric: metric(
          () =>
              '$sideLetter finger ${_formatConfidence(fingertip?.confidence)}',
        ),
      ),
      CameraCheck(
        label: 'เท้า 2 ข้าง',
        passed: frame != null && _stepDetector.canObserveBothFeet(frame),
        pending: pending,
        metric: metric(() => 'heel ${_heelConfidenceLabel(frame)}'),
      ),
      CameraCheck(
        label: 'หันข้าง',
        passed: validation?.sideView ?? false,
        pending: pending,
        metric: metric(
          () => 'conf ${_formatConfidence(validation?.confidence)}',
        ),
      ),
    ];
  }

  String _formatConfidence(double? value) =>
      value == null ? '—' : value.toStringAsFixed(2);

  String _heelConfidenceLabel(PoseFrame? frame) {
    final left = frame?[BodyLandmark.leftHeel];
    final right = frame?[BodyLandmark.rightHeel];
    if (left == null || right == null) return 'n/a';
    return math.min(left.confidence, right.confidence).toStringAsFixed(2);
  }

  Widget _buildDebugPanel() {
    final frame = _lastFrame;
    final validation = _validation;
    final side = _trackedArmSide ?? validation?.primarySide;
    final fingertip = frame == null || side == null
        ? null
        : frame[side.indexFinger];
    final sideLabel = side == null
        ? null
        : side == PrimaryBodySide.left
        ? 'ซ้าย'
        : 'ขวา';
    final (statusColor, status) = frame == null || validation == null
        ? (Colors.white, 'กำลังค้นหาร่างกาย')
        : validation.canStart
        ? (CameraColors.devGood, 'ตรวจจับร่างกายครบ')
        : (CameraColors.devBad, 'ร่างกายยังไม่ครบหรือไม่ชัด');
    final confidenceOk =
        (validation?.confidence ?? 0) >=
        AssessmentConfig.poseConfidenceThreshold;
    final posture = _postureValidation;
    final stateLabel = _stateMachine.state.name
        .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}')
        .toUpperCase();
    return CameraDebugPanel(
      logEventName: 'camera_debug_snapshot',
      statusColor: statusColor,
      status: status,
      confidence: validation?.confidence,
      rows: [
        CameraDebugRow('สถานะระบบ', stateLabel),
        CameraDebugRow(
          'แขนที่ติดตาม',
          sideLabel == null ? '—' : '$sideLabel (ฝั่งกล้อง)',
        ),
        CameraDebugRow(
          'ความมั่นใจท่า',
          '${_formatConfidence(validation?.confidence)} / '
              '${AssessmentConfig.poseConfidenceThreshold.toStringAsFixed(2)}',
          color: confidenceOk ? CameraColors.devGood : CameraColors.devBad,
        ),
        CameraDebugRow(
          'ปลายนิ้ว',
          fingertip == null
              ? '—'
              : '${fingertip.x.toStringAsFixed(3)}, ${fingertip.y.toStringAsFixed(3)}',
        ),
        CameraDebugRow(
          'มุมแขน–ลำตัว',
          posture?.armToTorsoAngleDegrees == null
              ? '—'
              : '${posture!.armToTorsoAngleDegrees!.toStringAsFixed(0)}°',
        ),
        CameraDebugRow(
          'มุมศอก',
          posture?.elbowAngleDegrees == null
              ? '—'
              : '${posture!.elbowAngleDegrees!.toStringAsFixed(0)}°',
        ),
        CameraDebugRow(
          'ระยะถึงเป้า',
          '${_currentTargetDistanceCm?.toStringAsFixed(1) ?? '—'} ซม.',
        ),
        CameraDebugRow(
          'จำนวนก้าว',
          '${_snapshot?.stepCount ?? 0}',
          color: (_snapshot?.stepCount ?? 0) > 0
              ? CameraColors.devBad
              : CameraColors.devGood,
        ),
        CameraDebugRow(
          'เท้า L / R',
          '${_snapshot?.leftFootMovement.toStringAsFixed(3) ?? '—'} / '
              '${_snapshot?.rightFootMovement.toStringAsFixed(3) ?? '—'}',
        ),
        CameraDebugRow('เอนจิน', _cameraService.engineLabel),
        CameraDebugRow(
          'อัตราเฟรม',
          _metrics == null
              ? '— fps'
              : '${_metrics!.framesPerSecond.toStringAsFixed(0)} fps',
          color: CameraColors.devBad,
        ),
      ],
    );
  }

  Widget _buildSupervisionQuestion() => Scaffold(
    appBar: AppBar(title: const Text('คำถามจากผู้ประเมิน')),
    body: AppScaffoldBody(
      child: Column(
        children: [
          const SizedBox(height: 36),
          const Icon(Icons.health_and_safety_outlined, size: 74),
          const SizedBox(height: 20),
          Text(
            'ระหว่างเอื้อม ผู้ทดสอบต้องมีคนคอยควบคุมใกล้ชิดหรือไม่?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'ระบบแยกคะแนน 3 กับ 4 จาก skeleton อย่างเดียวไม่ได้ ผู้ประเมินต้องยืนยันข้อนี้',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () => _complete(supervisionRequired: true),
            child: const Text('ต้องมีผู้ควบคุมใกล้ชิด'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _complete(supervisionRequired: false),
            child: const Text('ทำได้อย่างอิสระและปลอดภัย'),
          ),
        ],
      ),
    ),
  );

  Widget _buildResult() {
    final result = _result!;
    const references = <(int, String)>[
      (4, 'ไม่ขยับเท้า ทำได้อย่างอิสระและปลอดภัย'),
      (3, 'ไม่ขยับเท้า แต่ต้องมีผู้ควบคุมใกล้ชิด'),
      (2, 'ใช้ 1 ก้าว'),
      (1, 'ใช้ 2 ก้าว'),
      (0, 'มากกว่า 2 ก้าว'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.protocolVariant.isStandard
              ? 'ผล Fullerton Item 2'
              : 'ผล Modified Fullerton',
        ),
      ),
      body: AppScaffoldBody(
        child: Column(
          children: [
            Text(
              '${result.score} / 4 คะแนน',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              result.stepCount == 0
                  ? result.supervisionRequired == true
                        ? 'ไม่ขยับเท้า แต่ต้องมีผู้ควบคุมใกล้ชิด'
                        : 'ไม่ขยับเท้า และทำได้อย่างอิสระ'
                  : 'ตรวจพบการใช้ ${result.stepCount} ก้าว',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.protocolVariant.thaiLabel} · เป้าหมายเสมือนจากส่วนสูง ${widget.heightCm.toStringAsFixed(0)} ซม.',
              textAlign: TextAlign.center,
            ),
            if (!widget.protocolVariant.isStandard) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ผลนี้ใช้ระยะ 1 ฟุต จึงเป็นการทดลองและไม่ควรเทียบกับค่าอ้างอิง FAB มาตรฐานโดยตรง',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    for (final reference in references)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: reference.$1 == result.score
                              ? AppColors.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 70,
                              child: Text(
                                '${reference.$1} คะแนน',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(child: Text(reference.$2)),
                            if (reference.$1 == result.score)
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _retry,
              child: const Text('ทดสอบอีกครั้ง'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'กำลังบันทึก' : 'บันทึกผล'),
            ),
          ],
        ),
      ),
    );
  }
}
