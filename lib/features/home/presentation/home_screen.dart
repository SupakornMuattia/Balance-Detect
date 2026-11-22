import 'dart:math' as math;

import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Home page: header, safety notice, three assessment cards and a clinical
/// notice. On tall screens the card illustrations grow so the page fills the
/// viewport exactly (no empty gap above the bottom navigation); on short
/// screens the page scrolls with each illustration at its minimum height.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          const _BrandHeader(),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'เลือกแบบทดสอบ',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 16),
                            const _SafetyNotice(),
                            const SizedBox(height: 14),
                            Expanded(
                              child: _AssessmentCard(
                                title: 'วัดระยะเอื้อม',
                                standardName: 'Functional Reach Test',
                                illustration: _ReachPainter(),
                                semanticsLabel:
                                    'ภาพคนยืนเหยียดแขนเอื้อมไปข้างหน้า',
                                setupItems: const <_SetupItem>[
                                  _SetupItem(
                                    Icons.smartphone_outlined,
                                    'ใช้กล้องหน้าของมือถือ',
                                  ),
                                ],
                                onStart: () => context.push('/functional-reach'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: _AssessmentCard(
                                title: 'ทดสอบเอื้อมหยิบ',
                                standardName: 'Fullerton Advanced Balance',
                                illustration: _PickUpPainter(),
                                semanticsLabel: 'ภาพคนก้าวเท้าและเอื้อมหยิบของ',
                                setupItems: const <_SetupItem>[
                                  _SetupItem(
                                    Icons.smartphone_outlined,
                                    'ใช้กล้องหน้าของมือถือ',
                                  ),
                                ],
                                onStart: () => context.push('/fullerton'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: _AssessmentCard(
                                title: 'ทดสอบลุก–เดิน–นั่ง',
                                standardName: 'Timed Up and Go (TUG)',
                                illustration: _TugPainter(),
                                semanticsLabel:
                                    'ภาพลุกจากเก้าอี้ เดิน 3 เมตร หมุนตัวกลับ',
                                setupItems: const <_SetupItem>[
                                  _SetupItem(
                                    Icons.phone_android_rounded,
                                    'คาดมือถือไว้ที่เอว',
                                  ),
                                  _SetupItem(
                                    Icons.chair_outlined,
                                    'เตรียมเก้าอี้ 1 ตัว',
                                  ),
                                ],
                                onStart: () => context.push('/tug'),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _SummaryLink(onTap: () => context.push('/summary')),
                            const SizedBox(height: 12),
                            const _ClinicalNotice(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.monitor_heart_outlined,
            color: AppColors.surface,
            semanticLabel: 'Balance Detect',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balance Detect',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'คัดกรองการทรงตัวเบื้องต้น',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.outline),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  static const _background = Color(0xFFFFF4D6);
  static const _border = Color(0xFFF0D58C);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: _background,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.people_outline, color: AppColors.ink, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'เพื่อความปลอดภัย',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'ให้มีคนอยู่ข้าง ๆ ขณะทดสอบ และยืนใกล้ผนังหรือโต๊ะที่จับได้',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.title,
    required this.standardName,
    required this.illustration,
    required this.semanticsLabel,
    required this.setupItems,
    required this.onStart,
  });

  /// Smallest illustration band; used when the page has to scroll.
  static const _minIllustrationHeight = 96.0;

  /// Largest illustration drawing, so tablets don't get giant stick figures.
  static const _maxIllustrationHeight = 150.0;

  final String title;
  final String standardName;
  final CustomPainter illustration;
  final String semanticsLabel;
  final List<_SetupItem> setupItems;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: _minIllustrationHeight,
              ),
              child: ColoredBox(
                color: AppColors.primaryContainer,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: _maxIllustrationHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Semantics(
                        label: semanticsLabel,
                        image: true,
                        child: AspectRatio(
                          aspectRatio: _IllustrationPainter.aspectRatio,
                          child: CustomPaint(painter: illustration),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: textTheme.titleLarge),
                Text(
                  standardName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.outline,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.border,
                  ),
                ),
                Text('ต้องเตรียม', style: textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final item in setupItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 20, color: AppColors.ink),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.label, style: textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Semantics(
                    label: 'เริ่มทดสอบ $title',
                    excludeSemantics: true,
                    child: const Text('เริ่มทดสอบ'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupItem {
  const _SetupItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _SummaryLink extends StatelessWidget {
  const _SummaryLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(
              Icons.insert_chart_outlined_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'ดูสรุปผลการทดสอบล่าสุด',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.outline,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClinicalNotice extends StatelessWidget {
  const _ClinicalNotice();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppColors.ink, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'แอปนี้ใช้คัดกรองเบื้องต้นเท่านั้น ไม่ใช่การวินิจฉัยของแพทย์ '
            'หากกังวลเรื่องการหกล้ม ควรปรึกษาแพทย์',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Card illustrations. Each painter draws on a fixed 300×110 design canvas that
// is scaled uniformly to the available size.
// ---------------------------------------------------------------------------

abstract class _IllustrationPainter extends CustomPainter {
  static const designWidth = 300.0;
  static const designHeight = 110.0;
  static const aspectRatio = designWidth / designHeight;

  Paint get stroke => Paint()
    ..color = AppColors.primaryDark
    ..strokeWidth = 3.2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  Paint get floor => Paint()
    ..color = AppColors.primary.withValues(alpha: .45)
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  void drawDesign(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / designWidth, size.height / designHeight);
    drawDesign(canvas);
    canvas.restore();
  }

  void dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final total = (to - from).distance;
    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
    }
  }

  void arrowHead(Canvas canvas, Offset tip, double angle, Paint paint) {
    const length = 9.0;
    for (final side in [-1, 1]) {
      final a = angle + math.pi + side * math.pi / 5;
      canvas.drawLine(
        tip,
        tip + Offset(math.cos(a), math.sin(a)) * length,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReachPainter extends _IllustrationPainter {
  @override
  void drawDesign(Canvas canvas) {
    final s = stroke;
    canvas.drawLine(const Offset(50, 98), const Offset(250, 98), floor);
    // Feet plate.
    canvas.drawLine(
      const Offset(72, 96),
      const Offset(108, 96),
      s..strokeWidth = 5,
    );
    s.strokeWidth = 3.2;
    // Body.
    canvas
      ..drawCircle(const Offset(90, 30), 9, s)
      ..drawLine(const Offset(90, 39), const Offset(90, 70), s)
      ..drawLine(const Offset(90, 70), const Offset(80, 95), s)
      ..drawLine(const Offset(90, 70), const Offset(100, 95), s)
      ..drawLine(const Offset(90, 48), const Offset(140, 48), s);
    // Dashed reach arrow.
    dashedLine(canvas, const Offset(146, 48), const Offset(205, 48), s);
    arrowHead(canvas, const Offset(208, 48), 0, s);
    // Ruler above.
    canvas
      ..drawLine(const Offset(150, 18), const Offset(210, 18), s)
      ..drawLine(const Offset(150, 12), const Offset(150, 24), s)
      ..drawLine(const Offset(210, 12), const Offset(210, 24), s);
  }
}

class _PickUpPainter extends _IllustrationPainter {
  @override
  void drawDesign(Canvas canvas) {
    final s = stroke;
    canvas.drawLine(const Offset(50, 98), const Offset(250, 98), floor);
    // Leaning body with stepping legs.
    canvas
      ..drawCircle(const Offset(112, 26), 9, s)
      ..drawLine(const Offset(115, 35), const Offset(122, 64), s)
      ..drawLine(const Offset(122, 64), const Offset(100, 95), s)
      ..drawLine(const Offset(122, 64), const Offset(140, 80), s)
      ..drawLine(const Offset(140, 80), const Offset(150, 95), s)
      ..drawLine(const Offset(117, 44), const Offset(98, 64), s)
      ..drawLine(const Offset(118, 44), const Offset(150, 64), s);
    dashedLine(canvas, const Offset(156, 67), const Offset(180, 76), s);
    // Box to pick up.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(184, 72, 32, 24),
        const Radius.circular(3),
      ),
      s,
    );
    canvas.drawLine(const Offset(184, 81), const Offset(216, 81), s);
  }
}

class _TugPainter extends _IllustrationPainter {
  @override
  void drawDesign(Canvas canvas) {
    final s = stroke;
    // Chair.
    canvas
      ..drawLine(const Offset(36, 30), const Offset(36, 98), s)
      ..drawLine(const Offset(36, 66), const Offset(66, 66), s)
      ..drawLine(const Offset(66, 66), const Offset(66, 98), s);
    // 3 m dashed walkway.
    dashedLine(canvas, const Offset(74, 98), const Offset(244, 98), s);
    // Walking figure.
    canvas
      ..drawCircle(const Offset(150, 28), 8, s)
      ..drawLine(const Offset(150, 36), const Offset(150, 66), s)
      ..drawLine(const Offset(150, 46), const Offset(138, 60), s)
      ..drawLine(const Offset(150, 46), const Offset(162, 60), s)
      ..drawLine(const Offset(150, 66), const Offset(138, 96), s)
      ..drawLine(const Offset(150, 66), const Offset(162, 96), s);
    // Distance label.
    final label = TextPainter(
      text: const TextSpan(
        text: '3 เมตร',
        style: TextStyle(
          fontFamily: 'IBMPlexSansThaiLooped',
          color: AppColors.primaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, const Offset(176, 76));
    // Cone.
    canvas
      ..drawLine(const Offset(250, 98), const Offset(258, 80), s)
      ..drawLine(const Offset(258, 80), const Offset(266, 98), s)
      ..drawLine(const Offset(250, 98), const Offset(266, 98), s);
    // Turn-around arrow.
    final turn = Path()
      ..moveTo(240, 22)
      ..arcToPoint(
        const Offset(242, 52),
        radius: const Radius.circular(15),
      )
      ..lineTo(232, 52);
    canvas.drawPath(turn, s);
    arrowHead(canvas, const Offset(228, 52), math.pi, s);
  }
}
