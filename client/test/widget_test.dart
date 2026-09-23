import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/services/local_metadata_service.dart';
import 'package:maboy/src/services/youtube_downloader.dart';
import 'package:maboy/src/widgets/player_sheet.dart';
import 'package:maboy/src/widgets/track_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('Maboy theme keeps the brand bold and the coral accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: const Scaffold(body: MaboyBrand()),
      ),
    );

    final brand = tester.widget<Text>(find.text('maboy'));
    expect(brand.style?.fontWeight, FontWeight.w900);
    expect(
      Theme.of(tester.element(find.byType(Scaffold))).colorScheme.primary,
      MaboyColors.primary,
    );
  });

  test('Generated operation IDs are distinct UUIDs', () {
    final ids = List.generate(100, (_) => newId());
    expect(ids.toSet().length, 100);
    expect(
      ids.every(
        (id) => RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
      ),
      isTrue,
    );
  });

  test('Queue allows duplicates and respects explicit order', () {
    final controller = AppController();
    controller.apply('queue.set', {
      'items': [
        {'id': 'first', 'track_id': 'song'},
        {'id': 'second', 'track_id': 'song'},
      ],
    });
    expect(controller.queue.map((e) => e['id']), ['first', 'second']);
    controller.apply('queue.set', {
      'items': [
        {'id': 'second', 'track_id': 'song'},
        {'id': 'first', 'track_id': 'song'},
      ],
    });
    expect(controller.queue.map((e) => e['id']), ['second', 'first']);
  });

  test('Playlist track order is applied from the operation', () {
    final controller = AppController();
    controller.apply('playlist.upsert', {
      'id': 'playlist',
      'name': 'Mix',
      'sort_key': 0,
    });
    controller.apply('playlist.set_tracks', {
      'playlist_id': 'playlist',
      'track_ids': ['second', 'first'],
    });
    expect(controller.playlists.single['track_ids'], ['second', 'first']);
  });

  test('YouTube URL extraction handles diverse formats', () {
    expect(
      YouTubeDownloadService.extractVideoId(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      ),
      'dQw4w9WgXcQ',
    );
    expect(
      YouTubeDownloadService.extractVideoId('https://youtu.be/dQw4w9WgXcQ'),
      'dQw4w9WgXcQ',
    );
    expect(
      YouTubeDownloadService.extractVideoId(
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
      ),
      'dQw4w9WgXcQ',
    );
    expect(YouTubeDownloadService.extractVideoId('dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(YouTubeDownloadService.extractVideoId('https://google.com'), isNull);
  });

  test('yt-dlp rotated cookies error is actionable', () {
    final result = YouTubeDownloadService.classifyYtDlpError(
      'The provided YouTube account cookies are no longer valid. '
      'They have likely been rotated in the browser.',
    );

    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('cookies.txt устарел'));
  });

  test('yt-dlp age restriction explains required authentication', () {
    final result = YouTubeDownloadService.classifyYtDlpError(
      'Sign in to confirm your age. This video may be inappropriate.',
    );

    expect(result.isAgeRestricted, isTrue);
    expect(result.errorMessage, contains('Видео 18+'));
  });

  test('LocalMetadataService extracts title fallback correctly', () {
    final tempFile = File('non_existent_track_file.mp3');
    final parsed = LocalMetadataService.parseFile(tempFile);
    expect(parsed.title, 'non_existent_track_file');
  });

  test('reorderTracks reorders items correctly', () async {
    final controller = AppController();
    controller.tracks.addAll([
      {'id': 't1', 'title': 'Track 1'},
      {'id': 't2', 'title': 'Track 2'},
      {'id': 't3', 'title': 'Track 3'},
    ]);
    await controller.reorderTracks(0, 2);
    expect(controller.tracks.map((t) => t['id']), ['t2', 't1', 't3']);
  });

  test(
    'Shuffle keeps current track and only mixes upcoming playlist',
    () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
        {'id': '5', 'title': 'Five'},
      ]);
      controller.playlists.add({
        'id': 'pl-1',
        'name': 'Folder',
        'sort_key': 0,
        'track_ids': ['1', '2', '3'],
      });

      controller.playingId = '2';
      controller.playingFolder = 'pl-1';
      final sourceBeforeShuffle = controller.player.audioSource;

      await controller.toggleShuffle();

      expect(controller.isShuffle, isTrue);
      expect(controller.playingFolder, 'pl-1');
      expect(controller.playingId, '2');
      expect(controller.player.audioSource, same(sourceBeforeShuffle));
      expect(
        controller.activePlaybackQueue
            .map((entry) => entry.track['id'])
            .toSet(),
        {'1', '2', '3'},
      );
      expect(controller.activePlaybackQueue.first.isCurrent, isTrue);
      expect(controller.hasNext, isTrue);
    },
  );

  test(
    'startShuffle keeps current track and mixes upcoming tracks',
    () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
      ]);

      controller.playingId = '2';
      final sourceBeforeShuffle = controller.player.audioSource;

      await controller.startShuffle();

      expect(controller.isShuffle, isTrue);
      expect(controller.playingId, '2');
      expect(controller.player.audioSource, same(sourceBeforeShuffle));
      expect(controller.activePlaybackQueue.first.track['id'], '2');
      expect(controller.activePlaybackQueue.first.isCurrent, isTrue);
      expect(
        controller.activePlaybackQueue.map((entry) => entry.track['id']).toSet(),
        {'1', '2', '3', '4'},
      );
    },
  );

  test(
    'startShuffle with playlist keeps current track and mixes playlist tracks',
    () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
      ]);
      controller.playlists.add({
        'id': 'pl-1',
        'name': 'Folder',
        'sort_key': 0,
        'track_ids': ['1', '2', '3'],
      });

      controller.playingId = '1';
      controller.playingFolder = 'pl-1';

      await controller.startShuffle(folderId: 'pl-1');

      expect(controller.isShuffle, isTrue);
      expect(controller.playingId, '1');
      expect(controller.playingFolder, 'pl-1');
      expect(controller.activePlaybackQueue.first.track['id'], '1');
      expect(
        controller.activePlaybackQueue.map((entry) => entry.track['id']).toSet(),
        {'1', '2', '3'},
      );
    },
  );

  test('Upcoming playback queue supports reorder and removal', () async {
    final controller = AppController();
    controller.tracks.addAll([
      {'id': '1', 'title': 'One'},
      {'id': '2', 'title': 'Two'},
      {'id': '3', 'title': 'Three'},
      {'id': '4', 'title': 'Four'},
    ]);
    controller.playingId = '1';
    await controller.toggleShuffle();

    final before = controller.activePlaybackQueue.skip(1).toList();
    controller.reorderUpcomingPlayback(0, before.length);
    final reordered = controller.activePlaybackQueue.skip(1).toList();
    expect(reordered.last.track['id'], before.first.track['id']);

    final removedIndex = reordered.first.playbackIndex;
    final removedId = reordered.first.track['id'];
    controller.removeUpcomingPlayback(removedIndex);
    expect(
      controller.activePlaybackQueue.map((entry) => entry.track['id']),
      isNot(contains(removedId)),
    );
    expect(controller.playingId, '1');
  });

  testWidgets('Full player renders the editable active playback queue', (
    tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.tracks.addAll([
      {'id': '1', 'title': 'One', 'artist': 'Artist'},
      {'id': '2', 'title': 'Two', 'artist': 'Artist'},
      {'id': '3', 'title': 'Three', 'artist': 'Artist'},
    ]);
    controller.playingId = '1';
    await controller.toggleShuffle();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMaboyTheme(),
        home: Scaffold(body: PlayerSheet(controller: controller)),
      ),
    );

    expect(find.text('Далее в очереди'), findsOneWidget);
    expect(find.text('Сейчас играет'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  test('track.device_status mutation records remote device status', () {
    final controller = AppController();
    controller.apply('track.device_status', {
      'track_id': 'track-abc',
      'device_id': 'phone-123',
      'device_name': 'Android',
      'status': 'deleted',
    });
    expect(controller.deviceTrackStatuses['track-abc']?['status'], 'deleted');
    expect(
      controller.deviceTrackStatuses['track-abc']?['device_name'],
      'Android',
    );
  });

  test('track order survives metadata updates and keeps new tracks', () {
    final controller = AppController();
    addTearDown(controller.dispose);
    controller.tracks.addAll([
      {'id': 'a', 'title': 'A'},
      {'id': 'b', 'title': 'B'},
      {'id': 'c', 'title': 'C'},
    ]);
    controller.apply('track.set_order', {
      'track_ids': ['b', 'a'],
    });
    expect(controller.tracks.map((track) => track['id']), ['b', 'a', 'c']);
    controller.apply('track.upsert', {'id': 'a', 'title': 'Updated'});
    expect(controller.tracks.map((track) => track['id']), ['b', 'a', 'c']);
  });

  testWidgets('actions tap opens menu and drag reorders without scrolling', (
    tester,
  ) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    final listScrollController = ScrollController();
    addTearDown(listScrollController.dispose);
    final tracks = List.generate(
      10,
      (index) => {'id': '$index', 'title': 'Track $index', 'artist': 'Artist'},
    );
    var dragStarted = false;
    int? movedFrom;
    int? movedTo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReorderableListView.builder(
            scrollController: listScrollController,
            buildDefaultDragHandles: false,
            itemCount: tracks.length,
            onReorderStart: (_) => dragStarted = true,
            onReorder: (from, to) {
              movedFrom = from;
              movedTo = to;
            },
            itemBuilder: (context, index) => TrackTile(
              key: ValueKey(tracks[index]['id']),
              controller: controller,
              track: tracks[index],
              dragIndex: index,
            ),
          ),
        ),
      ),
    );

    final actions = find.byIcon(Icons.more_vert).first;
    await tester.tap(actions);
    await tester.pumpAndSettle();
    expect(find.text('Играть следующим'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(dragStarted, isFalse);

    final gesture = await tester.startGesture(tester.getCenter(actions));
    for (var step = 0; step < 8; step++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(dragStarted, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(movedFrom, 0);
    expect(movedTo, greaterThan(0));
    expect(listScrollController.offset, 0);
  });

  test('playTrack returns false when track is deleted locally', () async {
    final controller = AppController();
    controller.deletedLocallyIds.add('deleted-1');
    final played = await controller.playTrack({
      'id': 'deleted-1',
      'title': 'Deleted Track',
      'provider': 'local',
      'source_id': 's1',
    });
    expect(played, isFalse);
  });
}
