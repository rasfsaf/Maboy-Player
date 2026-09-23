import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deleted tracks ordering', () {
    test('sinkDeletedTracksToEnd moves locally deleted tracks to the end of library and playlists', () {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
      ]);
      controller.playlists.add({
        'id': 'pl-1',
        'name': 'My Playlist',
        'sort_key': 0,
        'track_ids': ['1', '2', '3', '4'],
      });

      // Mark '2' and '4' as deleted locally
      controller.deletedLocallyIds.addAll(['2']);
      controller.sinkDeletedTracksToEnd();

      expect(
        controller.tracks.map((t) => t['id']).toList(),
        ['1', '3', '4', '2'],
      );
      expect(
        controller.playlists.first['track_ids'],
        ['1', '3', '4', '2'],
      );

      // Now also mark '1' as deleted
      controller.deletedLocallyIds.add('1');
      controller.sinkDeletedTracksToEnd();

      // Active tracks '3' and '4' must be at the top, deleted '2' and '1' at the bottom
      expect(
        controller.tracks.sublist(0, 2).map((t) => t['id']).toList(),
        ['3', '4'],
      );
      expect(
        controller.tracks.sublist(2).map((t) => t['id']).toSet(),
        {'1', '2'},
      );
    });
  });

  group('Playback queue priority & Shuffle', () {
    test('playNext plays from deviceQueue first even when isShuffle is enabled', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': 'q1', 'title': 'Queued Track'},
      ]);

      // Set playback to track 1
      controller.playingId = '1';
      controller.isShuffle = true;

      // Add q1 to queue
      await controller.addToQueue('q1');
      expect(controller.deviceQueue.isNotEmpty, isTrue);
      expect(controller.hasNext, isTrue);

      // Next track must consume from deviceQueue
      await controller.playNext();
      expect(controller.playingId, 'q1');
      expect(controller.deviceQueue.isEmpty, isTrue);
    });

    test('Queued track stays pinned at the top when toggleShuffle is turned on', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
        {'id': 'q1', 'title': 'Queued Track'},
      ]);

      controller.playingId = '1';
      await controller.addToQueue('q1');

      // Turn on shuffle
      await controller.toggleShuffle();
      expect(controller.isShuffle, isTrue);

      // Current track must be '1' and first upcoming track must be 'q1' (pinned at the top)
      final upcoming = controller.activePlaybackQueue;
      expect(upcoming.first.track['id'], '1');
      expect(upcoming[1].track['id'], 'q1');
      expect(controller.hasNext, isTrue);
    });

    test('Shuffle does not stop and mixes the full pool when selecting a track near the end', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
        {'id': '5', 'title': 'Five'},
      ]);

      controller.isShuffle = true;
      // Play track 4 near the end
      await controller.playTrack(controller.tracks[3]);
      expect(controller.playingId, '4');

      // The active playback queue must contain all 5 tracks (not just 4 and 5)
      final ids = controller.activePlaybackQueue.map((e) => e.track['id']).toSet();
      expect(ids, {'1', '2', '3', '4', '5'});
      expect(controller.hasNext, isTrue);
    });
  });
}
