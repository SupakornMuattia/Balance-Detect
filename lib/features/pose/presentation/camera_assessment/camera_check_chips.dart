import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:flutter/material.dart';

class CameraCheck {
  const CameraCheck({
    required this.label,
    required this.passed,
    this.pending = false,
    this.metric,
  });

  final String label;
  final bool passed;
  final bool pending;

  /// Small developer metric under the label. Shown only when non-null.
  final String? metric;
}

/// Row of status chips shown in the dark bottom bar of the camera screen.
class CameraCheckChips extends StatelessWidget {
  const CameraCheckChips({required this.checks, super.key});

  final List<CameraCheck> checks;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < checks.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _CheckChip(check: checks[i])),
      ],
    ],
  );
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.check});

  final CameraCheck check;

  @override
  Widget build(BuildContext context) {
    final passed = check.passed && !check.pending;
    return Semantics(
      label: '${check.label} ${passed ? 'ผ่าน' : 'ยังไม่ผ่าน'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        decoration: BoxDecoration(
          color: CameraColors.chipBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: passed
                    ? CameraColors.chipPassed
                    : CameraColors.chipPending,
                shape: BoxShape.circle,
              ),
              child: Icon(
                passed ? Icons.check_rounded : Icons.remove_rounded,
                color: passed ? Colors.white : Colors.black87,
                size: 26,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              check.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CameraColors.chipLabel,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            if (check.metric != null)
              Text(
                check.metric!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: CameraColors.chipMetric,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-bar content for stages that show progress instead of chips.
class CameraStageStatus extends StatelessWidget {
  const CameraStageStatus({
    required this.title,
    super.key,
    this.value,
    this.progress,
    this.message,
    this.checks = const <CameraCheck>[],
  });

  final String title;
  final String? value;
  final double? progress;
  final String? message;
  final List<CameraCheck> checks;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (checks.isNotEmpty) ...[
        CameraCheckChips(checks: checks),
        const SizedBox(height: 10),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          if (value != null)
            Text(
              value!,
              style: const TextStyle(
                color: CameraColors.chipPending,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
        ],
      ),
      if (progress != null) ...[
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress!.clamp(0.0, 1.0),
            minHeight: 8,
            color: CameraColors.chipPending,
            backgroundColor: Colors.white.withValues(alpha: .14),
          ),
        ),
      ],
      if (message != null && message!.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          message!,
          style: const TextStyle(
            color: CameraColors.caption,
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    ],
  );
}
