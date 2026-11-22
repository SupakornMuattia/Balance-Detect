import 'package:balance_detect/core/constants/assessment_config.dart';
import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:balance_detect/core/widgets/app_scaffold_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Step 1 of 3 ("เตรียมตัว") of the Functional Reach Test.
class FunctionalReachIntroScreen extends StatefulWidget {
  const FunctionalReachIntroScreen({super.key, this.savedHeightCm});

  /// Height stored in the user's profile, if any. When provided, the height
  /// field is pre-filled and a "using saved height" chip is shown.
  final double? savedHeightCm;

  @override
  State<FunctionalReachIntroScreen> createState() =>
      _FunctionalReachIntroScreenState();
}

class _FunctionalReachIntroScreenState
    extends State<FunctionalReachIntroScreen> {
  static const _defaultHeightCm = 160;
  static const _steps = <String>[
    'วางมือถือตั้งตรงให้มั่นคง อย่าให้หน้าจอเอียง',
    'ถอยออกมายืนให้กล้องหน้าเห็นทั้งร่างกาย',
    'ยืนหันข้าง ให้กล้องมองเห็นด้านข้างของลำตัว',
    'ยกแขน 1 ข้างเหยียดตรงไปข้างหน้า ให้สูงระดับหัวไหล่ แล้วกำมือไว้',
    'ปล่อยแขนอีกข้าง ลงตามสบายแนบข้างลำตัว',
    'ค่อยๆโน้มตัวเอื้อมมือไปข้างหน้าให้ไกลที่สุดเท่าที่ทำได้ โดยไม่ก้าวหรือขยับเท้า',
  ];

  late final TextEditingController _heightController;
  String? _heightError;

  double get _minHeight => AssessmentConfig.anthropometricMinHeightCm;
  double get _maxHeight => AssessmentConfig.anthropometricMaxHeightCm;

  bool get _usingSavedHeight {
    final saved = widget.savedHeightCm;
    return saved != null &&
        double.tryParse(_heightController.text.trim()) == saved.roundToDouble();
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.savedHeightCm?.round() ?? _defaultHeightCm;
    _heightController = TextEditingController(text: '$initial');
  }

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  void _stepHeight(int delta) {
    final current =
        double.tryParse(_heightController.text.trim())?.round() ??
        _defaultHeightCm;
    final next = (current + delta).clamp(
      _minHeight.round(),
      _maxHeight.round(),
    );
    setState(() {
      _heightController.text = '$next';
      _heightError = null;
    });
  }

  void _continue() {
    final heightCm = double.tryParse(_heightController.text.trim());
    if (heightCm == null || heightCm < _minHeight || heightCm > _maxHeight) {
      setState(
        () => _heightError =
            'กรุณากรอกส่วนสูง ${_minHeight.toStringAsFixed(0)}–${_maxHeight.toStringAsFixed(0)} ซม.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    context.push(
      '/functional-reach/test?height=${heightCm.toStringAsFixed(1)}',
      extra: heightCm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: TextButton.icon(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          label: const Text('กลับ'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryDark,
            textStyle: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: AppScaffoldBody(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepProgress(current: 1, total: 3, label: 'เตรียมตัว'),
            const SizedBox(height: 16),
            Text(
              'วัดระยะเอื้อม',
              style: textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ยืนนิ่ง แล้วยื่นแขนไปข้างหน้าให้ไกลที่สุด โดยไม่ขยับเท้า',
              style: textTheme.bodyLarge?.copyWith(color: AppColors.outline),
            ),
            const SizedBox(height: 20),
            _HeightStepperCard(
              controller: _heightController,
              minHeight: _minHeight,
              maxHeight: _maxHeight,
              errorText: _heightError,
              showSavedChip: _usingSavedHeight,
              onDecrement: () => _stepHeight(-1),
              onIncrement: () => _stepHeight(1),
              onChanged: (_) => setState(() => _heightError = null),
            ),
            const SizedBox(height: 28),
            Text(
              'ทำตามทีละขั้น',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final (index, step) in _steps.indexed) ...[
              _NumberedStepCard(number: index + 1, text: step),
              const SizedBox(height: 12),
            ],
            const _InfoNote(
              icon: Icons.visibility_outlined,
              message:
                  'ระหว่างเอื้อม ให้กล้องเห็นมือของคุณตลอด แอปจะเริ่มวัดเองเมื่อเห็นท่าครบ',
            ),
            const SizedBox(height: 24),
            const _SafetyCard(
              title: 'เพื่อความปลอดภัย',
              message:
                  'ให้มีคนอยู่ข้าง ๆ ตลอดการทดสอบ และยืนใกล้ผนังหรือโต๊ะที่จับได้ ถ้ารู้สึกเสียการทรงตัว ให้หยุดทันที',
            ),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          child: FilledButton.icon(
            onPressed: _continue,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('จัดตำแหน่งกล้อง'),
          ),
        ),
      ),
    );
  }
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
              color: AppColors.outline,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= total; i++) ...[
                if (i > 1) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: i <= current
                          ? AppColors.primaryDark
                          : AppColors.surfaceStrong,
                      borderRadius: BorderRadius.circular(4),
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

class _HeightStepperCard extends StatelessWidget {
  const _HeightStepperCard({
    required this.controller,
    required this.minHeight,
    required this.maxHeight,
    required this.showSavedChip,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final double minHeight;
  final double maxHeight;
  final bool showSavedChip;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ส่วนสูงของคุณ',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove_rounded,
                tooltip: 'ลดส่วนสูง',
                onPressed: onDecrement,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: errorText != null
                          ? AppColors.risk
                          : AppColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: IntrinsicWidth(
                          child: TextField(
                            controller: controller,
                            onChanged: onChanged,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            style: textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              semanticCounterText: '',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'ซม.',
                        style: textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _StepperButton(
                icon: Icons.add_rounded,
                tooltip: 'เพิ่มส่วนสูง',
                onPressed: onIncrement,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            errorText ??
                'แตะที่ตัวเลขเพื่อพิมพ์ ใส่ได้ ${minHeight.toStringAsFixed(0)}–${maxHeight.toStringAsFixed(0)} ซม. หรือ กดปุ่ม − หรือ +',
            style: textTheme.bodyMedium?.copyWith(
              color: errorText != null ? AppColors.risk : AppColors.outline,
            ),
          ),
          if (showSavedChip) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.normalContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ใช้ส่วนสูงที่บันทึกไว้ในโปรไฟล์',
                      style: textTheme.labelLarge?.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 64,
    child: Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(64, 64),
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.primaryDark, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Icon(icon, size: 30),
      ),
    ),
  );
}

class _NumberedStepCard extends StatelessWidget {
  const _NumberedStepCard({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surfaceStrong,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primaryDark),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.title, required this.message});

  static const _background = Color(0xFFFFF1D3);
  static const _borderColor = Color(0xFFE6C36A);
  static const _ink = Color(0xFF4A3300);

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.people_outline_rounded, color: _ink, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: textTheme.bodyLarge?.copyWith(color: _ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
