import 'package:balance_detect/app/balance_detect_app.dart';
import 'package:balance_detect/features/fullerton/presentation/fullerton_intro_screen.dart';
import 'package:balance_detect/features/functional_reach/presentation/functional_reach_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Balance Detect splash screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BalanceDetectApp()));

    expect(find.text('Balance Detect'), findsOneWidget);
    expect(find.text('ประเมินการทรงตัวอย่างเป็นขั้นตอน'), findsOneWidget);
  });

  testWidgets('shows clear assessment choices and preparation flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: BalanceDetectApp()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('เลือกแบบทดสอบ'), findsOneWidget);
    expect(find.text('เพื่อความปลอดภัย'), findsOneWidget);
    expect(find.text('วัดระยะเอื้อม'), findsOneWidget);
    expect(find.text('ทดสอบเอื้อมหยิบ'), findsOneWidget);
    expect(find.text('ทดสอบลุก–เดิน–นั่ง'), findsOneWidget);
    expect(find.text('ใช้กล้องหน้าของมือถือ'), findsNWidgets(2));
    expect(find.text('คาดมือถือไว้ที่เอว'), findsOneWidget);
    expect(find.text('เตรียมเก้าอี้ 1 ตัว'), findsOneWidget);
    expect(find.text('เริ่มทดสอบ'), findsNWidgets(3));

    final startReach = find.bySemanticsLabel('เริ่มทดสอบ วัดระยะเอื้อม');
    await tester.ensureVisible(startReach);
    await tester.pumpAndSettle();
    await tester.tap(startReach);
    await tester.pumpAndSettle();

    expect(find.text('ขั้นที่ 1 จาก 3: เตรียมตัว'), findsOneWidget);
    expect(find.text('ส่วนสูงของคุณ'), findsOneWidget);
    expect(find.text('160'), findsOneWidget);
    expect(find.text('ทำตามทีละขั้น'), findsOneWidget);
    expect(find.text('จัดตำแหน่งกล้อง'), findsOneWidget);

    await tester.tap(find.byTooltip('เพิ่มส่วนสูง'));
    await tester.pump();
    expect(find.text('161'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('เพื่อความปลอดภัย'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(FunctionalReachIntroScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('เพื่อความปลอดภัย'), findsOneWidget);
  });

  testWidgets(
    'Fullerton preparation requires height and labels one-foot mode',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: FullertonIntroScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Fullerton Advanced Balance Scale — Item 2'),
        findsOneWidget,
      );
      expect(find.text('ส่วนสูงผู้ทดสอบ'), findsOneWidget);
      expect(find.text('ใช้ระยะ 1 ฟุตตามที่กำหนด'), findsOneWidget);
      expect(find.textContaining('Modified FAB'), findsOneWidget);
      expect(find.text('จัดตำแหน่งและคาลิเบรต'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '99');
      await tester.ensureVisible(find.text('จัดตำแหน่งและคาลิเบรต'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('จัดตำแหน่งและคาลิเบรต'));
      await tester.pump();

      expect(find.text('กรุณากรอกส่วนสูง 100–230 ซม.'), findsOneWidget);
    },
  );
}
