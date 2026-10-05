import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/pages/equalizer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('EqualizerPage renders scope selector and folder overrides', (
    tester,
  ) async {
    final controller = AppController();
    await controller.equalizerService.init('test-account');
    controller.playlists.add({
      'id': 'folder-synthwave',
      'name': 'Synthwave Vibes',
      'track_ids': <String>[],
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: EqualizerPage(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header and title
    expect(find.text('Эквалайзер'), findsOneWidget);
    expect(find.text('EQ / 06 BAND'), findsOneWidget);
    expect(find.text('Область действия:'), findsOneWidget);

    // Verify default scope dropdown has global selected
    expect(
      find.text('Глобально (по умолчанию для всех треков)'),
      findsOneWidget,
    );

    // Tap dropdown to open items
    await tester.tap(find.text('Глобально (по умолчанию для всех треков)'));
    await tester.pumpAndSettle();

    // Verify folder item is in the dropdown
    final folderItem = find.text('Папка: Synthwave Vibes').last;
    expect(folderItem, findsOneWidget);

    // Select the folder
    await tester.tap(folderItem);
    await tester.pumpAndSettle();

    // Verify banner offering to configure folder separately
    expect(
      find.text('Используются общие глобальные настройки для этой папки'),
      findsOneWidget,
    );
    expect(find.text('Настроить отдельно'), findsOneWidget);

    // Tap "Настроить отдельно"
    await tester.tap(find.text('Настроить отдельно'));
    await tester.pumpAndSettle();

    // Verify folder now has its own override banner
    expect(
      find.text('Для «Synthwave Vibes» задана индивидуальная настройка эквалайзера'),
      findsOneWidget,
    );
    expect(find.text('Сбросить к глобальным'), findsOneWidget);
    expect(controller.equalizerService.hasFolderOverride('folder-synthwave'), isTrue);

    // Tap "Сбросить к глобальным"
    await tester.tap(find.text('Сбросить к глобальным'));
    await tester.pumpAndSettle();

    expect(controller.equalizerService.hasFolderOverride('folder-synthwave'), isFalse);
    expect(
      find.text('Используются общие глобальные настройки для этой папки'),
      findsOneWidget,
    );

    controller.dispose();
  });
}
