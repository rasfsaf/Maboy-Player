import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/widgets/edit_track_dialog.dart';

void main() {
  testWidgets('EditTrackDialog renders prefilled title and artist and updates track', (tester) async {
    final controller = AppController();
    final track = {
      'id': 'test-track-1',
      'provider': 'youtube',
      'source_id': 'dQw4w9WgXcQ',
      'title': 'YouTube Audio',
      'artist': 'YouTube',
    };
    controller.tracks.add(track);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditTrackDialog(
            controller: controller,
            track: track,
          ),
        ),
      ),
    );

    expect(find.text('Редактировать трек'), findsOneWidget);
    expect(find.text('YouTube Audio'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Пересобрать из YouTube'), findsOneWidget);

    // Change title
    await tester.enterText(find.byType(TextField).first, 'Never Gonna Give You Up');
    await tester.enterText(find.byType(TextField).last, 'Rick Astley');
    await tester.pump();

    // Tap Save
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final updated = controller.tracks.firstWhere((t) => t['id'] == 'test-track-1');
    expect(updated['title'], 'Never Gonna Give You Up');
    expect(updated['artist'], 'Rick Astley');
  });

  testWidgets('EditTrackDialog validates empty title', (tester) async {
    final controller = AppController();
    final track = {
      'id': 'test-track-2',
      'provider': 'local',
      'title': 'Original',
      'artist': 'Artist',
    };
    controller.tracks.add(track);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditTrackDialog(
            controller: controller,
            track: track,
          ),
        ),
      ),
    );

    // Clear title
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();

    // Tap Save
    await tester.tap(find.text('Сохранить'));
    await tester.pump();

    expect(find.text('Название не может быть пустым'), findsOneWidget);

    // Track should NOT have updated to empty
    final current = controller.tracks.firstWhere((t) => t['id'] == 'test-track-2');
    expect(current['title'], 'Original');
  });
}
