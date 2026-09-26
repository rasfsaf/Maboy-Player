import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/widgets/smart_sleep_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartSleepSheet UI Widget Tests', () {
    late AppController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = AppController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('SmartSleepSheet renders controls and updates settings', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: Scaffold(
            body: SmartSleepSheet(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title and description
      expect(find.text('Умный таймер сна'), findsOneWidget);
      expect(find.text('Мягкое затухание при засыпании'), findsOneWidget);
      expect(find.text('Базовое окно бездействия'), findsOneWidget);

      // Initially disabled
      expect(controller.smartSleepService.isEnabled, isFalse);

      // Toggle switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsWidgets);
      await tester.tap(switchFinder.first);
      await tester.pumpAndSettle();

      expect(controller.smartSleepService.isEnabled, isTrue);

      // Select 45 min chip
      final chip45Finder = find.text('45 мин');
      expect(chip45Finder, findsOneWidget);
      await tester.tap(chip45Finder);
      await tester.pumpAndSettle();

      expect(controller.smartSleepService.config.inactivityTimeoutMinutes, equals(45));

      // Select 90 sec fade chip
      final chip90sFinder = find.text('90 сек');
      expect(chip90sFinder, findsOneWidget);
      await tester.tap(chip90sFinder);
      await tester.pumpAndSettle();

      expect(controller.smartSleepService.config.fadeDurationSeconds, equals(90));
    });
  });
}
