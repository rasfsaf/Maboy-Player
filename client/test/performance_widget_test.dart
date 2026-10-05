import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/services/performance_service.dart';
import 'package:maboy/src/widgets/performance_settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PerformanceSettingsDialog switches modes and updates controller',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await PerformanceService.instance.init(prefs: prefs);

    final controller = AppController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PerformanceSettingsDialog(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Производительность'), findsOneWidget);
    expect(find.text('Авто (рекомендуется)'), findsOneWidget);
    expect(find.text('Высокая производительность'), findsOneWidget);
    expect(find.text('Максимальные эффекты'), findsOneWidget);

    // Tap "Высокая производительность"
    await tester.tap(find.text('Высокая производительность'));
    await tester.pumpAndSettle();

    expect(
      controller.performanceService.mode,
      PerformanceMode.highPerformance,
    );
    expect(controller.performanceService.isOptimized, isTrue);
    expect(controller.performanceService.enableBackdropBlur, isFalse);

    // Tap "Максимальные эффекты"
    await tester.tap(find.text('Максимальные эффекты'));
    await tester.pumpAndSettle();

    expect(
      controller.performanceService.mode,
      PerformanceMode.highQuality,
    );
    expect(controller.performanceService.isOptimized, isFalse);
    expect(controller.performanceService.enableBackdropBlur, isTrue);

    // Tap "Авто (рекомендуется)"
    await tester.tap(find.text('Авто (рекомендуется)'));
    await tester.pumpAndSettle();

    expect(controller.performanceService.mode, PerformanceMode.auto);
  });
}
