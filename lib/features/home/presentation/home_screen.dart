import 'dart:math' as math;

import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Home page: header, safety notice, three assessment cards and a clinical
/// notice. On tall screens the card illustrations grow so the page fills the
/// viewport exactly (no empty gap above the bottom navigation); on short
/// screens the page scrolls with each illustration at its minimum height.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    // Transparent status bar over the white banner, with dark icons.
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
    ),
    child: Scaffold(
      body: Column(
        children: [
          const _BrandHeader(),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: SafeArea(
              top: false,
              bottom: false,
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
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineLarge,
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _AssessmentCard(
                                  title: 'ทดสอบวัดระยะการเอื้อม',
                                  standardName: 'Functional Reach Test',
                                  illustration: _ReachPainter(),
                                  semanticsLabel:
                                      'ภาพคนยืนเหยียดแขนเอื้อมไปข้างหน้า',
                                  onStart: () =>
                                      context.push('/functional-reach'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: _AssessmentCard(
                                  title: 'ทดสอบการเอื้อมหยิบ',
                                  standardName: 'Fullerton Advanced Balance',
                                  illustration: _PickUpPainter(),
                                  semanticsLabel:
                                      'ภาพคนยืนเหยียดแขนเอื้อมหยิบของ',
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
                                  onStart: () => context.push('/tug'),
                                ),
                              ),
                              const SizedBox(height: 14),
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
          ),
        ],
      ),
    ),
  );
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) => ColoredBox(
    // Fills behind the status bar too, so it matches the banner.
    color: AppColors.surface,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              // Steady Stand mark. Decorative: the app name is read from the title text beside it.
              child: Image.asset(
                'assets/logo/logo_mark_white.png',
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // lang="en": English font shaping + English screen-reader voice.
                  Text.rich(
                    const TextSpan(
                      text: 'Balance Detect',
                      locale: Locale('en'),
                    ),
                    locale: const Locale('en'),
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
      ),
    ),
  );
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({
    required this.title,
    required this.standardName,
    required this.illustration,
    required this.semanticsLabel,
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
                const SizedBox(height: 16),
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
    // Feet plate.
    canvas.drawLine(
      const Offset(94, 96),
      const Offset(106, 96),
      s..strokeWidth = 5,
    );
    s.strokeWidth = 3.2;
    // Upright body with the arm straight forward, hand marked by a dot.
    canvas
      ..drawCircle(const Offset(100, 28), 9, s)
      ..drawLine(const Offset(100, 37), const Offset(100, 96), s)
      ..drawLine(const Offset(100, 46), const Offset(150, 46), s)
      ..drawCircle(
        const Offset(152, 46),
        4,
        Paint()..color = AppColors.primaryDark,
      );
    // Dashed reach toward the object.
    dashedLine(canvas, const Offset(158, 46), const Offset(182, 46), s);
    arrowHead(canvas, const Offset(185, 46), 0, s);
    // Pencil-shaped object to pick up.
    final pencil = Path()
      ..moveTo(190, 40)
      ..lineTo(222, 40)
      ..lineTo(234, 46)
      ..lineTo(222, 52)
      ..lineTo(190, 52)
      ..close();
    canvas
      ..drawPath(pencil, s)
      ..drawLine(const Offset(198, 40), const Offset(198, 52), s)
      ..drawLine(const Offset(222, 40), const Offset(222, 52), s);
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
      ..arcToPoint(const Offset(242, 52), radius: const Radius.circular(15))
      ..lineTo(232, 52);
    canvas.drawPath(turn, s);
    arrowHead(canvas, const Offset(228, 52), math.pi, s);
  }
}
