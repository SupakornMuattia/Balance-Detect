import 'package:balance_detect/core/services/voice_guidance_service.dart';
import 'package:balance_detect/core/theme/app_theme.dart';
import 'package:balance_detect/features/functional_reach/presentation/functional_reach_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeVoice extends VoiceGuidanceService {
  final announced = <String>[];
  int stops = 0;

  @override
  Future<void> announce(String message, {bool force = false}) async =>
      announced.add(message);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> scrollToEnd(WidgetTester tester) async {
    final scrollView = find.byType(SingleChildScrollView);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: scrollView, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    while (position.extentAfter > 0) {
      await tester.drag(scrollView, const Offset(0, -600));
      await tester.pumpAndSettle();
    }
  }

  void useSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('Functional Reach intro matches step-1 layout', (tester) async {
    useSize(tester);
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: FunctionalReachIntroScreen(
          savedHeightCm: 158,
          voiceGuidance: voice,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ขั้นที่ 1 จาก 3: เตรียมตัว'), findsOneWidget);
    expect(find.text('วัดระยะการเอื้อม'), findsOneWidget);
    expect(find.text('158'), findsOneWidget);
    expect(find.text('เพื่อความปลอดภัย'), findsOneWidget);
    expect(find.text('หลังจากนี้ ไม่ต้องกดปุ่มใด ๆ'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'กลับ'), findsOneWidget);

    // Footer bar stays hidden until the page is scrolled to the end.
    final continueButton = find.text('จัดตำแหน่งกล้อง');
    expect(continueButton.hitTestable(), findsNothing);

    // Listen toggle (sits under the "ทำตามทีละขั้นตอน" heading).
    await tester.ensureVisible(find.text('ฟังวิธีเตรียมตัว'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ฟังวิธีเตรียมตัว'));
    await tester.pump();
    expect(voice.announced, hasLength(1));
    expect(voice.announced.single, contains('ขั้นที่ 5.'));
    expect(find.text('กำลังอ่าน… แตะเพื่อหยุด'), findsOneWidget);
    await tester.tap(find.text('กำลังอ่าน… แตะเพื่อหยุด'));
    await tester.pump();
    expect(voice.stops, 1);
    expect(find.text('ฟังวิธีเตรียมตัว'), findsOneWidget);

    // Picker: cancel keeps the old value.
    await tester.ensureVisible(find.text('158'));
    await tester.tap(find.text('158'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.drag(
      find.byType(ListWheelScrollView),
      const Offset(0, -56 * 3),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('158'), findsOneWidget);

    // Picker: scroll up 3 rows and confirm.
    await tester.tap(find.text('158'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(ListWheelScrollView),
      const Offset(0, -56 * 3),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('161'), findsOneWidget);

    await scrollToEnd(tester);
    expect(continueButton.hitTestable(), findsOneWidget);
  });

  testWidgets('No saved height: continue scrolls back and marks it red', (
    tester,
  ) async {
    useSize(tester);
    String? pushedHeight;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              FunctionalReachIntroScreen(voiceGuidance: _FakeVoice()),
        ),
        GoRoute(
          path: '/functional-reach/test',
          builder: (_, state) {
            pushedHeight = state.uri.queryParameters['height'];
            return const Text('test page');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('เลือกส่วนสูง'), findsOneWidget);
    expect(find.text('จำเป็น'), findsOneWidget);
    expect(find.text('ซม.'), findsNothing);
    const missing = 'กรุณาเลือกส่วนสูงก่อนเริ่มทดสอบ';
    expect(find.text(missing), findsNothing);

    // Continue with no height: no navigation, back to the field, in red.
    await scrollToEnd(tester);
    await tester.tap(find.text('จัดตำแหน่งกล้อง'));
    await tester.pumpAndSettle();
    expect(pushedHeight, isNull);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text(missing), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    expect(find.text('เลือกส่วนสูง').hitTestable(), findsOneWidget);
    final placeholder = tester.widget<Text>(find.text('เลือกส่วนสูง'));
    expect(placeholder.style?.color, AppColors.risk);

    // Picking a height clears the error; continue then navigates.
    await tester.tap(find.text('เลือกส่วนสูง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.text(missing), findsNothing);
    expect(find.byIcon(Icons.error_rounded), findsNothing);
    expect(find.text('160'), findsOneWidget);
    await scrollToEnd(tester);
    await tester.tap(find.text('จัดตำแหน่งกล้อง'));
    await tester.pumpAndSettle();
    expect(pushedHeight, '160.0');
  });

  testWidgets('Saved height outside the range is clamped', (tester) async {
    useSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: FunctionalReachIntroScreen(
          savedHeightCm: 260,
          voiceGuidance: _FakeVoice(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('230'), findsOneWidget);
  });

  for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
    testWidgets('Functional Reach intro adapts to text scale $scale', (
      tester,
    ) async {
      useSize(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: FunctionalReachIntroScreen(
            savedHeightCm: 230,
            voiceGuidance: _FakeVoice(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The picker opens and closes without overflow.
      await tester.ensureVisible(find.text('230'));
      await tester.tap(find.text('230'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ตกลง').hitTestable(), findsOneWidget);
      await tester.tap(find.text('ตกลง'));
      await tester.pumpAndSettle();
      expect(find.text('230'), findsOneWidget);

      // Scroll to the end: the footer appears and never covers the last card.
      await scrollToEnd(tester);
      expect(tester.takeException(), isNull);

      final button = find.ancestor(
        of: find.text('จัดตำแหน่งกล้อง'),
        matching: find.byType(FilledButton),
      );
      expect(button.hitTestable(), findsOneWidget);
      final lastCard = find.text('หลังจากนี้ ไม่ต้องกดปุ่มใด ๆ');
      final footerTop = tester.getTopLeft(button).dy - 14;
      final cardBottom = tester
          .getBottomLeft(
            find.ancestor(of: lastCard, matching: find.byType(Container)).first,
          )
          .dy;
      expect(cardBottom, lessThanOrEqualTo(footerTop));

      // The button label sits fully inside the button.
      final buttonRect = tester.getRect(button);
      final labelRect = tester.getRect(find.text('จัดตำแหน่งกล้อง'));
      expect(labelRect.top, greaterThanOrEqualTo(buttonRect.top));
      expect(labelRect.bottom, lessThanOrEqualTo(buttonRect.bottom));
    });
  }
}
