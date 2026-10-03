import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/widgets/bass_boost_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BassBoostSection UI Widget Tests', () {
    late AppController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      controller = AppController();
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets('allows setting arbitrary frequency and setting 0 Hz via input and chips', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BassBoostSection(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enable Bass Boost via switch
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(controller.bassBoostService.globalConfig.enabled, isTrue);

      // Find the frequency TextField
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      expect(find.text('150'), findsOneWidget);

      // Enter arbitrary frequency (e.g. 64)
      await tester.enterText(textFieldFinder, '64');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 64.0);

      // Enter 0 Hz directly
      await tester.enterText(textFieldFinder, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 0.0);

      // Tap 50 Hz quick chip
      final chip50 = find.text('50 Hz');
      expect(chip50, findsOneWidget);
      await tester.tap(chip50);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 50.0);
      expect(tester.widget<TextField>(textFieldFinder).controller!.text, '50');

      // Tap 0 Hz quick chip
      final chip0 = find.text('0 Hz');
      expect(chip0, findsOneWidget);
      await tester.tap(chip0);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 0.0);
      expect(tester.widget<TextField>(textFieldFinder).controller!.text, '0');
    });
  });
}
