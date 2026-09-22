import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/home.dart';
import 'package:maboy/src/pages/equalizer_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Headless tests have no network — disable Google Fonts fetching so the
  // build falls back to the platform default typeface.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('desktop library production layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final controller = _previewController();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildMaboyTheme(),
        home: RepaintBoundary(child: HomePage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/library_desktop.png'),
    );
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile equalizer production layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    final controller = _previewController();
    controller.activeEqualizerPresetId = 'metal_plus';
    controller.equalizerGains = const [5.5, 2.5, -0.5, 0, 2, 3.5];
    controller.equalizerEnabled = true;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildMaboyTheme(),
        home: RepaintBoundary(child: EqualizerPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(EqualizerPage),
      matchesGoldenFile('goldens/equalizer_mobile.png'),
    );
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });
}

AppController _previewController() {
  final controller = AppController()
    ..token = 'preview-token'
    ..account = 'preview-account'
    ..tracks.addAll([
      {
        'id': 'one',
        'title': 'Blackened Horizon',
        'artist': 'Northern Signal',
        'album': 'Afterlight',
        'provider': 'local',
      },
      {
        'id': 'two',
        'title': 'Static Hearts',
        'artist': 'Maboy Sessions',
        'album': 'Night Drive',
        'provider': 'youtube',
      },
      {
        'id': 'three',
        'title': 'Nocturne 06',
        'artist': 'Electric Rooms',
        'album': 'Zero',
        'provider': 'local',
      },
    ])
    ..playlists.add({
      'id': 'playlist',
      'name': 'Heavy rotation',
      'sort_key': 0,
      'track_ids': ['one', 'two'],
    })
    ..playingId = 'one';
  return controller;
}
