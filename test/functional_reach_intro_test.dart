import 'package:balance_detect/features/functional_reach/presentation/functional_reach_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Functional Reach intro matches step-1 layout', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: FunctionalReachIntroScreen(savedHeightCm: 158)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ขั้นที่ 1 จาก 3: เตรียมตัว'), findsOneWidget);
    expect(find.text('158'), findsOneWidget);
    expect(find.text('ใช้ส่วนสูงที่บันทึกไว้ในโปรไฟล์'), findsOneWidget);

    await tester.tap(find.byTooltip('ลดส่วนสูง'));
    await tester.pump();
    expect(find.text('157'), findsOneWidget);
    expect(find.text('ใช้ส่วนสูงที่บันทึกไว้ในโปรไฟล์'), findsNothing);

    await tester.enterText(find.byType(TextField), '99');
    await tester.tap(find.text('จัดตำแหน่งกล้อง'));
    await tester.pump();
    expect(find.text('กรุณากรอกส่วนสูง 100–230 ซม.'), findsOneWidget);
  });
}
