import 'package:balance_detect/core/constants/assessment_config.dart';
import 'package:balance_detect/core/services/voice_guidance_service.dart';
import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:balance_detect/core/widgets/app_scaffold_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Step 1 of 3 ("เตรียมตัว") of the Functional Reach Test.
class FunctionalReachIntroScreen extends StatefulWidget {
  const FunctionalReachIntroScreen({
    super.key,
    this.savedHeightCm,
    this.voiceGuidance,
  });

  /// Height stored in the user's profile, if any. Shown as already chosen.
  final double? savedHeightCm;

  /// Speech output for the "ฟังวิธีเตรียมตัว" button. Created lazily when null.
  final VoiceGuidanceService? voiceGuidance;

  @override
  State<FunctionalReachIntroScreen> createState() =>
      _FunctionalReachIntroScreenState();
}

class _FunctionalReachIntroScreenState
    extends State<FunctionalReachIntroScreen> {
  static const _defaultHeightCm = 160;
  static const _subtitle =
      'ยืนนิ่ง แล้วยื่นแขนไปข้างหน้าให้ไกลที่สุด โดยไม่ขยับเท้า';
  static const _steps = <String>[
    'ตั้งมือถือให้มั่นคง ไม่ล้มง่าย และให้กล้องหน้าเห็นทั้งตัวรวมถึงมือ',
    'ยืนหันข้างให้กล้อง ให้แขนข้างที่จะทดสอบอยู่ฝั่งกล้อง',
    'ยกแขนข้างนั้นไปข้างหน้า ระดับไหล่ แล้วกำมือ',
    'ปล่อยแขนอีกข้างไว้ข้างลำตัว',
    'เอื้อมไปข้างหน้าให้ไกลที่สุด โดยไม่ก้าวหรือขยับเท้า',
  ];
  static const _safetyTitle = 'เพื่อความปลอดภัย';
  static const _safetyMessage =
      'ให้มีคนอยู่ข้างๆ ตลอดการทดสอบ และยืนใกล้ผนังหรือโต๊ะที่จับได้ ถ้ารู้สึกเสียการทรงตัว ให้หยุดทันที';
  static const _autoTitle = 'หลังจากนี้ ไม่ต้องกดปุ่มใด ๆ';
  static const _autoMessage =
      'แอปจะเริ่มวัดเองเมื่อเห็นท่าครบ และบอกทุกขั้นด้วยเสียง ไม่ต้องเดินกลับมาแตะหน้าจอระหว่างทดสอบ';

  /// Chosen height; null until the user picks one (or a saved one exists).
  int? _heightCm;

  /// True after "จัดตำแหน่งกล้อง" was pressed with no height chosen.
  bool _heightMissing = false;
  final _heightKey = GlobalKey();
  VoiceGuidanceService? _voice;
  bool _listening = false;
  bool _atBottom = false;

  /// Measured footer content height (without the system bottom inset); grows
  /// with the system text size.
  double _footerExtent = _defaultFooterExtent;

  void _onFooterSize(Size size) {
    if (!mounted) return;
    final extent = size.height - MediaQuery.paddingOf(context).bottom;
    if ((extent - _footerExtent).abs() > 0.5) {
      setState(() => _footerExtent = extent);
    }
  }

  void _updateAtBottom(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical) return;
    final atBottom = metrics.extentAfter <= 24;
    if (atBottom != _atBottom) setState(() => _atBottom = atBottom);
  }

  int get _minHeight => AssessmentConfig.anthropometricMinHeightCm.round();
  int get _maxHeight => AssessmentConfig.anthropometricMaxHeightCm.round();

  @override
  void initState() {
    super.initState();
    _heightCm = widget.savedHeightCm?.round().clamp(_minHeight, _maxHeight);
  }

  @override
  void dispose() {
    // Only dispose a service this screen created itself.
    if (widget.voiceGuidance == null) _voice?.dispose();
    super.dispose();
  }

  /// Opens the picker; returns true when a height was confirmed.
  Future<bool> _pickHeight() async {
    final picked = await showDialog<int>(
      context: context,
      barrierColor: _Design.ink.withValues(alpha: .45),
      builder: (_) => _HeightPickerDialog(
        initial: (_heightCm ?? _defaultHeightCm).clamp(_minHeight, _maxHeight),
        min: _minHeight,
        max: _maxHeight,
      ),
    );
    if (picked == null || !mounted) return false;
    setState(() {
      _heightCm = picked;
      _heightMissing = false;
    });
    return true;
  }

  Future<void> _toggleListen() async {
    final voice = _voice ??= widget.voiceGuidance ?? VoiceGuidanceService();
    final start = !_listening;
    setState(() => _listening = start);
    if (start) {
      final script = [
        _subtitle,
        '$_safetyTitle. $_safetyMessage',
        for (final (i, step) in _steps.indexed) 'ขั้นที่ ${i + 1}. $step',
        '$_autoTitle. $_autoMessage',
      ].join(' ');
      await voice.announce(script, force: true);
    } else {
      await voice.stop();
    }
  }

  Future<void> _continue() async {
    final heightCm = _heightCm;
    if (heightCm == null) {
      // A height is required: scroll back to the field and mark it red.
      setState(() => _heightMissing = true);
      final fieldContext = _heightKey.currentContext;
      if (fieldContext != null) {
        await Scrollable.ensureVisible(
          fieldContext,
          alignment: 0.2,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOutCubic,
        );
      }
      return;
    }
    if (_listening) {
      _voice?.stop();
      setState(() => _listening = false);
    }
    context.push(
      '/functional-reach/test?height=${heightCm.toDouble().toStringAsFixed(1)}',
      extra: heightCm.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final content = AppScaffoldBody(
      // Extra bottom space so the last card stays clear of the footer bar.
      // AppScaffoldBody's SafeArea already adds the system bottom inset.
      padding: EdgeInsets.fromLTRB(20, 22, 20, 28 + _footerExtent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepProgress(current: 1, total: 3, label: 'เตรียมตัว'),
          const SizedBox(height: 14),
          Text(
            'วัดระยะการเอื้อม',
            style: textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _Design.ink,
            ),
          ),
          const SizedBox(height: 22),
          const _SafetyCard(title: _safetyTitle, message: _safetyMessage),
          const SizedBox(height: 22),
          _HeightCard(
            key: _heightKey,
            heightCm: _heightCm,
            missing: _heightMissing,
            onPressed: _pickHeight,
          ),
          const SizedBox(height: 26),
          Text(
            'ทำตามทีละขั้นตอน',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: _Design.ink,
            ),
          ),
          const SizedBox(height: 12),
          _ListenButton(listening: _listening, onPressed: _toggleListen),
          const SizedBox(height: 12),
          for (final (index, step) in _steps.indexed) ...[
            _NumberedStepCard(number: index + 1, text: step),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          const _AutoStartCard(title: _autoTitle, message: _autoMessage),
        ],
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Transparent status bar over the white top bar, with dark icons.
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: _Design.bg,
        body: Column(
          children: [
            const _TopBar(),
            const Divider(height: 2, thickness: 2, color: _Design.cardBorder),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: Stack(
                  children: [
                    NotificationListener<ScrollMetricsNotification>(
                      onNotification: (n) {
                        _updateAtBottom(n.metrics);
                        return false;
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          _updateAtBottom(n.metrics);
                          return false;
                        },
                        child: content,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _SizeReporter(
                        onSize: _onFooterSize,
                        child: _FooterBar(
                          visible: _atBottom,
                          onPressed: _continue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer bar height at default text size, used until the real bar is
/// measured (excludes the system bottom inset).
const double _defaultFooterExtent = 14 + 68 + 20;

/// System text-size factor for non-text sizes (boxes, icons, circles).
/// Text itself always follows the system scaler unclamped; boxes and icons
/// grow with it but are capped so the layout stays usable on a phone.
double _uiScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

/// Colors of the "วัดระยะเอื้อม – เตรียมตัว" design artboard.
abstract final class _Design {
  static const ink = Color(0xFF13302D);
  static const teal = Color(0xFF0E5A53);
  static const tealDark = Color(0xFF0A4A44);
  static const muted = Color(0xFF3B524F);
  static const bg = Color(0xFFEDF3F1);
  static const card = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFD3E2DE);
  static const trackOff = Color(0xFFC9DAD5);
  static const tealSoft = Color(0xFFDDEFEB);
  static const listenBg = Color(0xFFE4F0ED);
  static const valueBg = Color(0xFFF2F2F7);
  static const placeholder = Color(0xFF6E6E73);
  static const valueArrow = Color(0xFF808085);

  /// Required / missing-height marks. Same red as [AppColors.risk].
  static const error = AppColors.risk;
  static const errorSoft = AppColors.riskContainer;
  static const wheelOff = Color(0xFF8A9894);
  static const bandBg = Color(0xFFF1F5F4);
  static const dialogBorder = Color(0xFF6B7C78);

  /// Shadow of the "กลับ" button in the top bar.
  /// Design `.back-btn`: box-shadow: 0 2px 8px rgba(0,0,0,0.18).
  static const backButtonShadow = [
    BoxShadow(
      color: Color(0x40000000), // black @ 18%
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// Shadow of the "จัดตำแหน่งกล้อง" button in the bottom bar.
  /// Tune independently of [backButtonShadow].
  /// Design `.cta-btn`: box-shadow: 0 2px 8px rgba(0,0,0,0.18).
  static const ctaButtonShadow = [
    BoxShadow(
      color: Color(0x80000000), // black @ 25%
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];
}

/// Amber palette of the safety card.
abstract final class _Amber {
  static const background = Color(0xFFFFF1D2);
  static const ink = Color(0xFF4A3300);
}

/// Reports its child's laid-out size whenever it changes.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSizeReporter renderObject,
  ) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}

/// White top banner with the outlined "กลับ" button. Fills behind the
/// status bar, like the Home header.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _Design.card,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 14),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _Design.backButtonShadow,
              ),
              child: OutlinedButton(
                onPressed: () => context.pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(112, 56),
                  padding: const EdgeInsets.fromLTRB(12, 0, 20, 0),
                  // Solid fill so the shadow doesn't show through the button.
                  backgroundColor: _Design.card,
                  foregroundColor: _Design.tealDark,
                  side: const BorderSide(color: _Design.teal, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFamily: AppFonts.button,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 28 * _uiScale(context),
                    ),
                    const SizedBox(width: 6),
                    const Text('กลับ'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "จัดตำแหน่งกล้อง" bar that slides up once the page is scrolled to the end.
class _FooterBar extends StatelessWidget {
  const _FooterBar({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          // No bar background: only the floating button is shown.
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              20 + MediaQuery.paddingOf(context).bottom,
            ),
            // Grows with the system text size instead of clipping the label.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _Design.ctaButtonShadow,
              ),
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(68),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  backgroundColor: _Design.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: AppFonts.button,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text(
                  'จัดตำแหน่งกล้อง',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'ขั้นที่ $current จาก $total $label',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ขั้นที่ $current จาก $total: $label',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _Design.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= total; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: i <= current ? _Design.teal : _Design.trackOff,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.listening, required this.onPressed});

  final bool listening;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: listening,
    // ShapeDecoration so the shadow follows the pill (StadiumBorder) shape.
    child: DecoratedBox(
      decoration: const ShapeDecoration(
        shape: StadiumBorder(),
        shadows: _Design.backButtonShadow,
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(60),
          padding: const EdgeInsets.fromLTRB(8, 6, 20, 6),
          backgroundColor: _Design.listenBg,
          foregroundColor: _Design.teal,
          side: const BorderSide(color: _Design.teal, width: 2),
          shape: const StadiumBorder(),
          textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFamily: AppFonts.button,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              listening ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
              size: 26 * _uiScale(context),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                listening ? 'กำลังอ่าน… แตะเพื่อหยุด' : 'ฟังวิธีเตรียมตัว',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// "ส่วนสูงของคุณ" card: the chosen height shown big (or a "เลือกส่วนสูง"
/// placeholder); tapping it opens the picker. Marked "จำเป็น"; turns red
/// when the user tried to continue without a height ([missing]).
class _HeightCard extends StatelessWidget {
  const _HeightCard({
    super.key,
    required this.heightCm,
    required this.missing,
    required this.onPressed,
  });

  static const _missingMessage = 'กรุณาเลือกส่วนสูงก่อนเริ่มทดสอบ';

  final int? heightCm;
  final bool missing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final height = heightCm;
    final showError = missing && height == null;
    final baseSize = textTheme.titleLarge?.fontSize ?? 20;
    final Widget value = height == null
        ? Text(
            'เลือกส่วนสูง',
            style: textTheme.titleLarge?.copyWith(
              fontSize: baseSize * 1.2,
              fontWeight: FontWeight.w700,
              color: showError ? _Design.error : _Design.placeholder,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$height',
                style: textTheme.headlineLarge?.copyWith(
                  fontSize: 52,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: _Design.ink,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'ซม.',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _Design.ink,
                ),
              ),
            ],
          );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Design.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _Design.cardBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wraps under the title at large text sizes.
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'ส่วนสูงของคุณ',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _Design.ink,
                  ),
                ),
              ),
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _Design.errorSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'จำเป็น',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _Design.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: height == null
                ? 'ส่วนสูง จำเป็นต้องเลือก ยังไม่ได้เลือก แตะเพื่อเลือก'
                : 'ส่วนสูง $height เซนติเมตร แตะเพื่อเปลี่ยน',
            excludeSemantics: true,
            onTap: onPressed,
            child: Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onPressed,
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(96),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 64,
                        vertical: 12,
                      ),
                      backgroundColor: _Design.valueBg,
                      foregroundColor: _Design.ink,
                      side: showError
                          ? const BorderSide(color: _Design.error, width: 2)
                          : BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                    // Shrinks instead of clipping at very large text sizes.
                    child: FittedBox(fit: BoxFit.scaleDown, child: value),
                  ),
                ),
                // Warning sign at the left edge while the height is missing.
                if (showError)
                  const Positioned(
                    left: 18,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Icon(
                          Icons.error_rounded,
                          size: 28,
                          color: _Design.error,
                        ),
                      ),
                    ),
                  ),
                // Up/down hint at the right edge of the button.
                Positioned(
                  right: 18,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.unfold_more_rounded,
                        size: 28,
                        color: showError ? _Design.error : _Design.valueArrow,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showError) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _missingMessage,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _Design.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pop-up scroll wheel for choosing the height. Pops the chosen value on
/// "ตกลง", or null on "ยกเลิก" / tapping outside.
class _HeightPickerDialog extends StatefulWidget {
  const _HeightPickerDialog({
    required this.initial,
    required this.min,
    required this.max,
  });

  final int initial;
  final int min;
  final int max;

  @override
  State<_HeightPickerDialog> createState() => _HeightPickerDialogState();
}

class _HeightPickerDialogState extends State<_HeightPickerDialog> {
  static const double _wheelHeight = 280;
  static const double _rowHeight = 56;

  late final FixedExtentScrollController _controller;
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _controller = FixedExtentScrollController(
      initialItem: widget.initial - widget.min,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpTo(int value) {
    final v = value.clamp(widget.min, widget.max);
    _controller.animateToItem(
      v - widget.min,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rowHeight = _rowHeight * _uiScale(context);
    final bandTop = (_wheelHeight - rowHeight) / 2;
    final baseSize = textTheme.titleLarge?.fontSize ?? 20;
    final buttonText = textTheme.titleMedium?.copyWith(
      fontFamily: AppFonts.button,
      fontWeight: FontWeight.w700,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: _Design.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: _Design.dialogBorder, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'เลือกส่วนสูง',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _Design.ink,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Semantics(
              label: 'เลือกส่วนสูง',
              value: '$_value เซนติเมตร',
              increasedValue:
                  '${(_value + 1).clamp(widget.min, widget.max)} เซนติเมตร',
              decreasedValue:
                  '${(_value - 1).clamp(widget.min, widget.max)} เซนติเมตร',
              onIncrease: () => _jumpTo(_value + 1),
              onDecrease: () => _jumpTo(_value - 1),
              child: SizedBox(
                height: _wheelHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // Highlight band behind the selected row.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: bandTop,
                        height: rowHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _Design.bandBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _Design.teal, width: 2),
                          ),
                        ),
                      ),
                      ExcludeSemantics(
                        child: ListWheelScrollView.useDelegate(
                          controller: _controller,
                          itemExtent: rowHeight,
                          physics: const FixedExtentScrollPhysics(),
                          diameterRatio: 100,
                          onSelectedItemChanged: (i) =>
                              setState(() => _value = widget.min + i),
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: widget.max - widget.min + 1,
                            builder: (context, i) {
                              final n = widget.min + i;
                              final d = (n - _value).abs();
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _jumpTo(n),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '$n',
                                      style: TextStyle(
                                        fontFamily: AppFonts.body,
                                        fontSize:
                                            baseSize *
                                            (d == 0
                                                ? 2
                                                : d == 1
                                                ? 1.3
                                                : 1.1),
                                        fontWeight: d == 0
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: d == 0
                                            ? _Design.ink
                                            : _Design.wheelOff,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      // Fixed unit label at the right of the band.
                      Positioned(
                        right: 18,
                        top: bandTop,
                        height: rowHeight,
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              'ซม.',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: _Design.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // White fades at the top and bottom edges.
                      const Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        height: 84,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_Design.card, Color(0x00FFFFFF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 84,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [_Design.card, Color(0x00FFFFFF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: Colors.transparent,
                      foregroundColor: _Design.teal,
                      side: const BorderSide(color: _Design.teal, width: 2),
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_value),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: _Design.teal,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      textStyle: buttonText,
                    ),
                    child: const Text('ตกลง'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberedStepCard extends StatelessWidget {
  const _NumberedStepCard({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Circle grows with the system text size so the digit never overflows.
    final circle = 36 * _uiScale(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Design.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _Design.cardBorder, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: circle,
            height: circle,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _Design.tealSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: textTheme.titleMedium?.copyWith(
                color: _Design.tealDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: textTheme.bodyLarge?.copyWith(color: _Design.ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + title + message callout used by the safety and auto-start cards.
class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.title,
    required this.message,
    required this.background,
    required this.iconColor,
    required this.titleColor,
    required this.messageColor,
    this.iconSize = 32,
    this.radius = 18,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color background;
  final Color iconColor;
  final Color titleColor;
  final Color messageColor;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              color: iconColor,
              size: iconSize * _uiScale(context),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: textTheme.bodyLarge?.copyWith(color: messageColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _Callout(
    icon: Icons.people_outline_rounded,
    title: title,
    message: message,
    background: _Amber.background,
    iconColor: _Amber.ink,
    titleColor: _Amber.ink,
    messageColor: _Amber.ink,
  );
}

class _AutoStartCard extends StatelessWidget {
  const _AutoStartCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => _Callout(
    icon: Icons.do_not_touch_outlined,
    iconSize: 36,
    radius: 12,
    title: title,
    message: message,
    background: _Design.tealSoft,
    iconColor: _Design.tealDark,
    titleColor: _Design.tealDark,
    messageColor: _Design.ink,
  );
}
