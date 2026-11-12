import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:balance_detect/features/fullerton/domain/fullerton_reach_calibration_service.dart';
import 'package:balance_detect/features/fullerton/domain/step_detection_service.dart';
import 'package:balance_detect/features/pose/domain/pose_frame.dart';
import 'package:flutter/material.dart';

/// Draws the participant-specific footprint and fixed virtual pencil in the
/// same preview-normalized coordinate space as the pose landmarks.
class FullertonReachOverlay extends StatelessWidget {
  const FullertonReachOverlay({
    required this.footBaseline,
    required this.target,
    required this.targetReached,
    super.key,
  });

  final FullertonFootBaseline? footBaseline;
  final FullertonReachTarget? target;
  final bool targetReached;

  @override
  Widget build(BuildContext context) => Semantics(
    label: target == null
        ? 'กำลังคาลิเบรตตำแหน่งเท้าจริง'
        : 'เป้าหมายเสมือนอยู่ห่างจากปลายนิ้ว ${target!.targetDistanceCm.toStringAsFixed(1)} เซนติเมตร',
    child: IgnorePointer(
      child: CustomPaint(
        painter: FullertonReachOverlayPainter(
          footBaseline: footBaseline,
          target: target,
          targetReached: targetReached,
        ),
      ),
    ),
  );
}

class FullertonReachOverlayPainter extends CustomPainter {
  const FullertonReachOverlayPainter({
    required this.footBaseline,
    required this.target,
    required this.targetReached,
  });

  final FullertonFootBaseline? footBaseline;
  final FullertonReachTarget? target;
  final bool targetReached;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final baseline = footBaseline;
    if (baseline != null) {
      _drawFoot(canvas, size, baseline.left);
      _drawFoot(canvas, size, baseline.right);
    }
    final currentTarget = target;
    if (currentTarget != null) {
      _drawTarget(canvas, size, currentTarget);
    }
  }

  void _drawFoot(Canvas canvas, Size size, FullertonFootAnchor foot) {
    final heel = _toOffset(foot.heel, size);
    final toe = _toOffset(foot.toe, size);
    final ankle = _toOffset(foot.ankle, size);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .62)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    final footprint = Paint()
      ..color = AppColors.primary.withValues(alpha: .92)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(heel, toe, shadow);
    canvas.drawLine(heel, toe, footprint);
    canvas.drawCircle(ankle, 7, shadow);
    canvas.drawCircle(ankle, 4.5, footprint);
  }

  void _drawTarget(Canvas canvas, Size size, FullertonReachTarget reachTarget) {
    final start = _toOffset(reachTarget.startFingertip, size);
    final targetPoint = _toOffset(reachTarget.targetPoint, size);
    final targetColor = targetReached
        ? AppColors.normal
        : const Color(0xFFFFC247);
    final guide = Paint()
      ..color = targetColor.withValues(alpha: .82)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final guideOutline = Paint()
      ..color = Colors.black.withValues(alpha: .55)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, targetPoint, guideOutline);
    canvas.drawLine(start, targetPoint, guide);

    final startPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final startOutline = Paint()
      ..color = Colors.black.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(start, 6, startPaint);
    canvas.drawCircle(start, 6, startOutline);

    final halo = Paint()
      ..color = targetColor.withValues(alpha: .24)
      ..style = PaintingStyle.fill;
    final haloOutline = Paint()
      ..color = targetColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(targetPoint, 25, halo);
    canvas.drawCircle(targetPoint, 25, haloOutline);

    // Target marker: a red dot at the target point (replaces the pencil icon).
    final dotOutline = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(targetPoint, 9, Paint()..color = const Color(0xFFE53935));
    canvas.drawCircle(targetPoint, 9, dotOutline);

    final label = TextPainter(
      text: TextSpan(
        text: reachTarget.protocolVariant == FullertonProtocolVariant.oneFoot
            ? '1 ฟุต'
            : '10 นิ้ว',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          shadows: <Shadow>[Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(
        (targetPoint.dx - label.width / 2).clamp(0, size.width - label.width),
        (targetPoint.dy + 30).clamp(0, size.height - label.height),
      ),
    );
  }

  Offset _toOffset(NormalizedPoint point, Size size) =>
      Offset(point.x * size.width, point.y * size.height);

  @override
  bool shouldRepaint(covariant FullertonReachOverlayPainter oldDelegate) =>
      oldDelegate.footBaseline != footBaseline ||
      oldDelegate.target != target ||
      oldDelegate.targetReached != targetReached;
}
