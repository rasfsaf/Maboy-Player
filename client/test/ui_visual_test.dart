import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/home.dart';
import 'package:maboy/src/pages/equalizer_page.dart';
import 'package:maboy/src/pages/playlist_detail_page.dart';
import 'package:maboy/src/widgets/player_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // The marquee keeps animating on narrow labels; capture a fixed frame.
    await tester.pump(const Duration(milliseconds: 500));
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/library_desktop.png'),
    );
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile library keeps navigation and mini player', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    final controller = _previewController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(412, 915)),
          child: RepaintBoundary(child: HomePage(controller: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(MiniPlayer), findsOneWidget);
    await expectLater(
      find.byType(HomePage),
      matchesGoldenFile('goldens/library_mobile.png'),
    );
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('mobile playlist keeps track actions and playback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    final controller = _previewController();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(412, 915)),
          child: RepaintBoundary(
            child: PlaylistDetailPage(
              controller: controller,
              playlist: controller.playlists.single,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Слушать'), findsOneWidget);
    expect(find.text('Микс'), findsOneWidget);
    await expectLater(
      find.byType(PlaylistDetailPage),
      matchesGoldenFile('goldens/playlist_mobile.png'),
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

  testWidgets(
    'mobile player keeps a decorative ring and separate seek slider',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      final controller = _previewController();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMaboyTheme(),
          home: RepaintBoundary(child: PlayerPage(controller: controller)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final ring = tester.widget<IgnorePointer>(
        find.byKey(const Key('decorativePlaybackRing')),
      );
      expect(ring.ignoring, isTrue);
      expect(
        find.descendant(
          of: find.byType(ProgressBar),
          matching: find.byType(Slider),
        ),
        findsOneWidget,
      );
      await expectLater(
        find.byType(PlayerPage),
        matchesGoldenFile('goldens/player_mobile.png'),
      );
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('desktop player retains playback queue alongside controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    final controller = _previewController();
    await controller.toggleShuffle();
    await controller.toggleShuffle();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: RepaintBoundary(child: PlayerPage(controller: controller)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Далее в очереди'), findsOneWidget);
    await expectLater(
      find.byType(PlayerPage),
      matchesGoldenFile('goldens/player_desktop.png'),
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
