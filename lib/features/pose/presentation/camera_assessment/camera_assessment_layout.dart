import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_colors.dart';
import 'package:flutter/material.dart';

/// Full-screen layout shared by the camera-based assessments:
/// optional developer bar, yellow guidance header, live camera area and a
/// dark bottom bar with status chips.
class CameraAssessmentLayout extends StatelessWidget {
  const CameraAssessmentLayout({
    required this.stepLabel,
    required this.guidanceIcon,
    required this.headline,
    required this.preview,
    required this.previewAspectRatio,
    required this.bottom,
    required this.voiceEnabled,
    required this.onToggleVoice,
    super.key,
    this.subline,
    this.onBack,
    this.previewLayers = const <Widget>[],
    this.cameraTopRight,
    this.cameraBottom,
    this.developerMode = false,
    this.debugVisible = true,
    this.onToggleDebug,
    this.caption = 'ฟังเสียงแล้วทำตาม ไม่ต้องกดปุ่ม',
  });

  final String stepLabel;
  final IconData guidanceIcon;
  final String headline;
  final String? subline;

  /// The camera feed. Laid out at [previewAspectRatio] so that overlays in
  /// [previewLayers] share its normalized coordinate space.
  final Widget preview;
  final double previewAspectRatio;
  final List<Widget> previewLayers;

  /// Widgets placed over the whole camera area, outside the preview box.
  final Widget? cameraTopRight;
  final Widget? cameraBottom;

  final Widget bottom;
  final String? caption;
  final bool voiceEnabled;
  final VoidCallback onToggleVoice;
  final VoidCallback? onBack;
  final bool developerMode;
  final bool debugVisible;
  final VoidCallback? onToggleDebug;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: developerMode
          ? CameraColors.devBar
          : CameraColors.headerBackground,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: CameraColors.bottomBackground,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (developerMode)
                _DeveloperBar(
                  debugVisible: debugVisible,
                  onToggleDebug: onToggleDebug,
                ),
              _GuidanceHeader(
                stepLabel: stepLabel,
                icon: guidanceIcon,
                headline: headline,
                subline: subline,
                voiceEnabled: voiceEnabled,
                onToggleVoice: onToggleVoice,
                onBack: onBack ?? () => Navigator.of(context).maybePop(),
              ),
              Expanded(child: _buildCameraArea()),
              _BottomBar(caption: caption, child: bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraArea() => ColoredBox(
    color: CameraColors.cameraBackground,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: previewAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [preview, ...previewLayers],
            ),
          ),
        ),
        if (cameraTopRight != null)
          Positioned(top: 10, right: 10, child: cameraTopRight!),
        if (cameraBottom != null)
          Positioned(left: 0, right: 0, bottom: 0, child: cameraBottom!),
      ],
    ),
  );
}

class _DeveloperBar extends StatelessWidget {
  const _DeveloperBar({required this.debugVisible, this.onToggleDebug});

  final bool debugVisible;
  final VoidCallback? onToggleDebug;

  @override
  Widget build(BuildContext context) => Container(
    color: CameraColors.devBar,
    padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
    child: Row(
      children: [
        const Icon(Icons.code_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'โหมดนักพัฒนา',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onToggleDebug,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: CameraColors.devBar,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(debugVisible ? 'ซ่อนดีบัก' : 'แสดงดีบัก'),
        ),
      ],
    ),
  );
}

class _GuidanceHeader extends StatelessWidget {
  const _GuidanceHeader({
    required this.stepLabel,
    required this.icon,
    required this.headline,
    required this.voiceEnabled,
    required this.onToggleVoice,
    required this.onBack,
    this.subline,
  });

  final String stepLabel;
  final IconData icon;
  final String headline;
  final String? subline;
  final bool voiceEnabled;
  final VoidCallback onToggleVoice;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Container(
    color: CameraColors.headerBackground,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderPill(
              icon: Icons.chevron_left_rounded,
              label: 'กลับ',
              tooltip: 'กลับ',
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  stepLabel,
                  style: const TextStyle(
                    color: CameraColors.headerInk,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _HeaderPill(
              icon: voiceEnabled
                  ? Icons.volume_up_outlined
                  : Icons.volume_off_outlined,
              label: voiceEnabled ? 'เปิด' : 'ปิด',
              tooltip: voiceEnabled ? 'ปิดเสียงคำแนะนำ' : 'เปิดเสียงคำแนะนำ',
              onPressed: onToggleVoice,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          label: '$headline ${subline ?? ''}',
          excludeSemantics: true,
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: CameraColors.guidanceIconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 36),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CameraColors.headerInk,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    if (subline != null && subline!.isNotEmpty)
                      Text(
                        subline!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CameraColors.headerInk,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: TextButton.styleFrom(
        backgroundColor: CameraColors.headerPill,
        foregroundColor: CameraColors.headerInk,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.child, this.caption});

  final Widget child;
  final String? caption;

  @override
  Widget build(BuildContext context) => Container(
    color: CameraColors.bottomBackground,
    padding: EdgeInsets.fromLTRB(
      10,
      12,
      10,
      12 + MediaQuery.paddingOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        if (caption != null) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.volume_up_outlined,
                color: CameraColors.caption,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  caption!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CameraColors.caption,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
