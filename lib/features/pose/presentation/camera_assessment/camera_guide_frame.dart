import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:flutter/material.dart';

/// Dashed rounded frame that shows where the whole body should fit, with an
/// optional grey stick figure while no body is detected yet.
class CameraGuideFrame extends StatelessWidget {
  const CameraGuideFrame({this.showSilhouette = false, super.key});

  final bool showSilhouette;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      painter: CameraGuideFramePainter(showSilhouette: showSilhouette),
    ),
  );
}

class CameraGuideFramePainter extends CustomPainter {
  const CameraGuideFramePainter({required this.showSilhouette});

  final bool showSilhouette;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Rect.fromLTRB(
      size.width * 0.19,
      size.height * 0.07,
      size.width * 0.81,
      size.height * 0.93,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(rect.width * 0.12),
    );
    final framePaint = Paint()
      ..color = CameraColors.guideFrame
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      const dash = 16.0;
      const gap = 10.0;
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), framePaint);
        distance += dash + gap;
      }
    }

    if (showSilhouette) _paintSilhouette(canvas, rect);
  }

  void _paintSilhouette(Canvas canvas, Rect frame) {
    final unit = frame.height;
    final cx = frame.center.dx;
    final paint = Paint()
      ..color = CameraColors.silhouette
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.026
      ..strokeCap = StrokeCap.round;
    final headCenter = Offset(cx, frame.top + unit * 0.14);
    final headRadius = unit * 0.065;
    canvas.drawCircle(headCenter, headRadius, paint);
    final neck = Offset(cx, headCenter.dy + headRadius + unit * 0.02);
    final hip = Offset(cx, frame.top + unit * 0.52);
    final shoulder = Offset(cx, neck.dy + unit * 0.06);
    canvas
      ..drawLine(neck, hip, paint)
      ..drawLine(
        shoulder,
        Offset(cx - unit * 0.12, frame.top + unit * 0.47),
        paint,
      )
      ..drawLine(
        shoulder,
        Offset(cx + unit * 0.12, frame.top + unit * 0.47),
        paint,
      )
      ..drawLine(hip, Offset(cx - unit * 0.075, frame.top + unit * 0.86), paint)
      ..drawLine(
        hip,
        Offset(cx + unit * 0.075, frame.top + unit * 0.86),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant CameraGuideFramePainter oldDelegate) =>
      oldDelegate.showSilhouette != showSilhouette;
}
