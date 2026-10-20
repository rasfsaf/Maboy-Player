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

    testWidgets('allows setting arbitrary frequency and clamps sub-20 Hz to 20 Hz via input and chips', (tester) async {
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

      // Enter 0 Hz directly -> clamped to safe 20 Hz minimum
      await tester.enterText(textFieldFinder, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 20.0);
      expect(tester.widget<TextField>(textFieldFinder).controller!.text, '20');

      // Tap 50 Hz quick chip
      final chip50 = find.text('50 Hz');
      expect(chip50, findsOneWidget);
      await tester.tap(chip50);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 50.0);
      expect(tester.widget<TextField>(textFieldFinder).controller!.text, '50');

      // Tap 20 Hz quick chip
      final chip20 = find.text('20 Hz');
      expect(chip20, findsOneWidget);
      await tester.tap(chip20);
      await tester.pumpAndSettle();

      expect(controller.bassBoostService.globalConfig.frequency, 20.0);
      expect(tester.widget<TextField>(textFieldFinder).controller!.text, '20');
    });

    testWidgets('preset chips activate bass boost and apply tuned frequency and gain', (tester) async {
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

      // Initially bass boost is disabled
      expect(controller.bassBoostService.globalConfig.enabled, isFalse);

      // Tap "Панч (+9 dB)" preset chip
      final punchChip = find.text('Панч (+9 dB)');
      expect(punchChip, findsOneWidget);
      await tester.tap(punchChip);
      await tester.pumpAndSettle();

      // Bass boost should be enabled and set to 80 Hz and 9 dB
      final config = controller.bassBoostService.globalConfig;
      expect(config.enabled, isTrue);
      expect(config.frequency, 80.0);
      expect(config.gainDb, 9.0);
      expect(config.presetId, 'punch');
      expect(config.matchingPreset?.name, 'Панч');

      // The description should be displayed
      expect(find.text(config.matchingPreset!.description), findsOneWidget);

      // Tap "Глубокий саб (+12 dB)" preset chip
      final subChip = find.text('Глубокий саб (+12 dB)');
      expect(subChip, findsOneWidget);
      await tester.tap(subChip);
      await tester.pumpAndSettle();

      final subConfig = controller.bassBoostService.globalConfig;
      expect(subConfig.frequency, 50.0);
      expect(subConfig.gainDb, 12.0);
      expect(subConfig.presetId, 'deep_sub');
      expect(find.text(subConfig.matchingPreset!.description), findsOneWidget);
    });
  });
}
