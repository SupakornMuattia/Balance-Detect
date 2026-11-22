import 'package:balance_detect/core/logging/app_logger.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraDebugRow {
  const CameraDebugRow(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

/// Developer-only diagnostics card shown over the lower part of the camera.
class CameraDebugPanel extends StatefulWidget {
  const CameraDebugPanel({
    required this.statusColor,
    required this.status,
    required this.rows,
    required this.logEventName,
    super.key,
    this.confidence,
  });

  final Color statusColor;
  final String status;
  final double? confidence;
  final List<CameraDebugRow> rows;

  /// Name of the AppLogger event written by the save-log button.
  final String logEventName;

  @override
  State<CameraDebugPanel> createState() => _CameraDebugPanelState();
}

class _CameraDebugPanelState extends State<CameraDebugPanel> {
  bool _collapsed = false;

  String get _snapshotText => [
    'status: ${widget.status}',
    if (widget.confidence != null)
      'conf: ${widget.confidence!.toStringAsFixed(2)}',
    for (final row in widget.rows) '${row.label}: ${row.value}',
  ].join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _snapshotText));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('คัดลอกค่าแล้ว')));
  }

  void _saveLog() {
    AppLogger.event(widget.logEventName, <String, Object?>{
      'status': widget.status,
      'confidence': widget.confidence,
      for (final row in widget.rows) row.label: row.value,
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('บันทึก log แล้ว')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: CameraColors.devPanel.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: widget.statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.confidence != null) ...[
                const SizedBox(width: 8),
                Text(
                  'conf ${widget.confidence!.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: CameraColors.devBad,
                    fontSize: 14,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Text(
                    _collapsed ? 'ขยาย' : 'ย่อ',
                    style: const TextStyle(
                      color: CameraColors.devAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_collapsed) ...[
            const SizedBox(height: 8),
            for (final row in widget.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          color: CameraColors.devKey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      row.value,
                      style: TextStyle(
                        color: row.color ?? CameraColors.devValue,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PanelButton(label: 'คัดลอกค่า', onPressed: _copy),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PanelButton(label: 'บันทึก log', onPressed: _saveLog),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: Colors.white,
      side: const BorderSide(color: CameraColors.devAccent, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

/// Small red frame-rate pill shown at the top-right of the camera.
class FpsBadge extends StatelessWidget {
  const FpsBadge({required this.framesPerSecond, super.key});

  final double? framesPerSecond;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: CameraColors.fpsBadge,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      framesPerSecond == null
          ? '— fps'
          : '${framesPerSecond!.toStringAsFixed(0)} fps',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
    ),
  );
}
