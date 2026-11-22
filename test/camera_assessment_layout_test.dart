import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_assessment_layout.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_check_chips.dart';
import 'package:balance_detect/features/pose/presentation/camera_assessment/camera_debug_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const checks = [
    CameraCheck(label: 'ทั้งตัว', passed: false, metric: null),
    CameraCheck(label: 'ไหล่–ศอก', passed: true),
    CameraCheck(label: 'เท้า 2 ข้าง', passed: false),
    CameraCheck(label: 'หันข้าง', passed: false),
  ];

  Widget buildLayout({
    bool developerMode = false,
    bool debugVisible = true,
    VoidCallback? onToggleDebug,
    VoidCallback? onToggleVoice,
    List<CameraCheck> chips = checks,
  }) {
    final showDebug = developerMode && debugVisible;
    return MaterialApp(
      home: CameraAssessmentLayout(
        stepLabel: 'ขั้นที่ 1 จาก 5: จัดตำแหน่งกล้อง',
        guidanceIcon: Icons.arrow_downward_rounded,
        headline: 'ถอยหลังอีก',
        subline: 'จนกล้องเห็นตั้งแต่หัวถึงเท้า',
        preview: const ColoredBox(color: Colors.black),
        previewAspectRatio: 3 / 4,
        voiceEnabled: true,
        onToggleVoice: onToggleVoice ?? () {},
        developerMode: developerMode,
        debugVisible: debugVisible,
        onToggleDebug: onToggleDebug,
        cameraTopRight: showDebug ? const FpsBadge(framesPerSecond: 7) : null,
        cameraBottom: showDebug
            ? const CameraDebugPanel(
                statusColor: Colors.red,
                status: 'จุดแขนฝั่งกล้องยังไม่ชัด',
                confidence: 0.22,
                logEventName: 'camera_debug_snapshot',
                rows: [CameraDebugRow('สถานะระบบ', 'WAIT_POSE')],
              )
            : null,
        bottom: CameraCheckChips(checks: chips),
      ),
    );
  }

  testWidgets('user view shows header, guidance and chips only', (
    tester,
  ) async {
    await tester.pumpWidget(buildLayout());

    expect(find.text('ขั้นที่ 1 จาก 5: จัดตำแหน่งกล้อง'), findsOneWidget);
    expect(find.text('ถอยหลังอีก'), findsOneWidget);
    expect(find.text('จนกล้องเห็นตั้งแต่หัวถึงเท้า'), findsOneWidget);
    expect(find.text('กลับ'), findsOneWidget);
    expect(find.text('เปิด'), findsOneWidget);
    for (final check in checks) {
      expect(find.text(check.label), findsOneWidget);
    }
    expect(find.text('ฟังเสียงแล้วทำตาม ไม่ต้องกดปุ่ม'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('โหมดนักพัฒนา'), findsNothing);
    expect(find.byType(CameraDebugPanel), findsNothing);
    expect(find.byType(FpsBadge), findsNothing);
  });

  testWidgets('voice pill calls the toggle callback', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(buildLayout(onToggleVoice: () => toggled++));
    await tester.tap(find.text('เปิด'));
    expect(toggled, 1);
  });

  testWidgets('developer view shows dev bar, fps, panel and chip metrics', (
    tester,
  ) async {
    var toggled = 0;
    await tester.pumpWidget(
      buildLayout(
        developerMode: true,
        onToggleDebug: () => toggled++,
        chips: const [
          CameraCheck(label: 'ทั้งตัว', passed: false, metric: 'ankle 0.12'),
        ],
      ),
    );

    expect(find.text('โหมดนักพัฒนา'), findsOneWidget);
    expect(find.text('7 fps'), findsOneWidget);
    expect(find.text('ankle 0.12'), findsOneWidget);
    expect(find.text('conf 0.22'), findsOneWidget);
    expect(find.text('WAIT_POSE'), findsOneWidget);
    expect(find.text('คัดลอกค่า'), findsOneWidget);
    expect(find.text('บันทึก log'), findsOneWidget);

    await tester.tap(find.text('ซ่อนดีบัก'));
    expect(toggled, 1);
  });

  testWidgets('hidden debug keeps the dev bar but drops the panel', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLayout(developerMode: true, debugVisible: false),
    );
    expect(find.text('โหมดนักพัฒนา'), findsOneWidget);
    expect(find.text('แสดงดีบัก'), findsOneWidget);
    expect(find.byType(CameraDebugPanel), findsNothing);
  });

  testWidgets('ย่อ collapses the debug panel rows and buttons', (tester) async {
    await tester.pumpWidget(buildLayout(developerMode: true));
    expect(find.text('WAIT_POSE'), findsOneWidget);

    await tester.tap(find.text('ย่อ'));
    await tester.pump();

    expect(find.text('WAIT_POSE'), findsNothing);
    expect(find.text('คัดลอกค่า'), findsNothing);
    expect(find.text('ขยาย'), findsOneWidget);
  });
}
