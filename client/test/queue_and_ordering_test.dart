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

    test('Selecting track in activePlaybackQueue preserves sequence and does not reshuffle', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
        {'id': '5', 'title': 'Five'},
      ]);

      controller.isShuffle = true;
      await controller.playTrack(controller.tracks[0]);
      final initialUpcoming = controller.activePlaybackQueue.map((e) => e.track['id']).toList();
      expect(initialUpcoming.first, '1');
      expect(initialUpcoming.length, 5);

      // Select track at index 2 from active queue
      final targetEntry = controller.activePlaybackQueue[2];
      final targetId = targetEntry.track['id'];
      final expectedFollowing = initialUpcoming.sublist(3);

      await controller.playPlaybackQueueEntry(targetEntry);

      expect(controller.playingId, targetId);
      final newUpcoming = controller.activePlaybackQueue.map((e) => e.track['id']).toList();
      // First in new activePlaybackQueue is the selected track
      expect(newUpcoming.first, targetId);
      // Following tracks must preserve their exact order from before
      expect(newUpcoming.sublist(1), expectedFollowing);
    });

    test('shuffleUpcomingPlayback shuffles only upcoming tracks without touching deviceQueue or current track', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': '4', 'title': 'Four'},
        {'id': '5', 'title': 'Five'},
        {'id': '6', 'title': 'Six'},
        {'id': 'q1', 'title': 'Queued'},
      ]);

      await controller.playTrack(controller.tracks[0], playbackIds: ['1', '2', '3', '4', '5', '6'], playbackIndex: 0);
      await controller.addToQueue('q1');

      expect(controller.playingId, '1');
      expect(controller.deviceQueue.length, 1);
      expect(controller.deviceQueue.first['track_id'], 'q1');

      // Shuffle upcoming playback
      controller.shuffleUpcomingPlayback();

      // Current track and deviceQueue must remain untouched
      expect(controller.playingId, '1');
      expect(controller.deviceQueue.length, 1);
      expect(controller.deviceQueue.first['track_id'], 'q1');

      // Upcoming tracks (excluding pinned tracks) must still contain all original tracks
      final queuedIds = controller.deviceQueue.map((q) => q['track_id']).toSet();
      final upcomingIds = controller.activePlaybackQueue
          .skip(1)
          .where((e) => !queuedIds.contains(e.track['id']))
          .map((e) => e.track['id'])
          .toSet();
      expect(upcomingIds, {'2', '3', '4', '5', '6'});
      expect(controller.isShuffle, isTrue);
    });

    test('Multiple tracks in deviceQueue play in order without dropping items', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': 'q1', 'title': 'Queued 1'},
        {'id': 'q2', 'title': 'Queued 2'},
        {'id': 'q3', 'title': 'Queued 3'},
      ]);

      await controller.playTrack(controller.tracks[0], playbackIds: ['1', '2', '3'], playbackIndex: 0);
      await controller.addToQueue('q1');
      await controller.addToQueue('q2');
      await controller.addToQueue('q3');

      expect(controller.deviceQueue.length, 3);
      expect(controller.deviceQueue.map((e) => e['track_id']).toList(), ['q1', 'q2', 'q3']);

      // 1st playNext: consumes q1, q2 and q3 remain
      await controller.playNext();
      expect(controller.playingId, 'q1');
      expect(controller.deviceQueue.length, 2);
      expect(controller.deviceQueue.map((e) => e['track_id']).toList(), ['q2', 'q3']);

      // 2nd playNext: consumes q2, q3 remains
      await controller.playNext();
      expect(controller.playingId, 'q2');
      expect(controller.deviceQueue.length, 1);
      expect(controller.deviceQueue.map((e) => e['track_id']).toList(), ['q3']);

      // 3rd playNext: consumes q3, queue is empty
      await controller.playNext();
      expect(controller.playingId, 'q3');
      expect(controller.deviceQueue.isEmpty, isTrue);

      // 4th playNext: continues with the ambient album (track 2)
      await controller.playNext();
      expect(controller.playingId, '2');
      expect(controller.deviceQueue.isEmpty, isTrue);
    });

    test('playNext is protected against concurrent calls without dropping multiple queued items', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': 'q1', 'title': 'Queued 1'},
        {'id': 'q2', 'title': 'Queued 2'},
      ]);

      await controller.playTrack(controller.tracks[0], playbackIds: ['1', '2'], playbackIndex: 0);
      await controller.addToQueue('q1');
      await controller.addToQueue('q2');
      expect(controller.deviceQueue.length, 2);

      // Fire playNext concurrently
      await Future.wait([
        controller.playNext(),
        controller.playNext(),
      ]);

      // Only one item must have been consumed; second item must NOT be dropped
      expect(controller.playingId, 'q1');
      expect(controller.deviceQueue.length, 1);
      expect(controller.deviceQueue.first['track_id'], 'q2');
    });

    test('playQueueItem consumes item from deviceQueue and preserves ambient playlist', () async {
      final controller = AppController();
      controller.tracks.addAll([
        {'id': '1', 'title': 'One'},
        {'id': '2', 'title': 'Two'},
        {'id': '3', 'title': 'Three'},
        {'id': 'q1', 'title': 'Queued 1'},
        {'id': 'q2', 'title': 'Queued 2'},
      ]);

      await controller.playTrack(controller.tracks[0], playbackIds: ['1', '2', '3'], playbackIndex: 0);
      await controller.addToQueue('q1');
      await controller.addToQueue('q2');

      // Click on q2 directly from queue
      final itemQ2 = controller.deviceQueue[1];
      await controller.playQueueItem(itemQ2);

      expect(controller.playingId, 'q2');
      // q2 consumed, q1 remains in queue
      expect(controller.deviceQueue.length, 1);
      expect(controller.deviceQueue.first['track_id'], 'q1');

      // Next track should consume q1
      await controller.playNext();
      expect(controller.playingId, 'q1');
      expect(controller.deviceQueue.isEmpty, isTrue);

      // Next track resumes ambient playlist at track 2
      await controller.playNext();
      expect(controller.playingId, '2');
    });
  });
}
