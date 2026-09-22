import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:maboy/src/app_controller.dart';
import 'package:maboy/src/design_system.dart';
import 'package:maboy/src/services/local_metadata_service.dart';
import 'package:maboy/src/services/youtube_downloader.dart';
import 'package:maboy/src/widgets/player_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('Ocean theme keeps the Maboy brand bold and blue', (
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
        {'2', '3'},
      );
      expect(controller.activePlaybackQueue.first.isCurrent, isTrue);
      expect(controller.hasNext, isTrue);
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
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
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
}
