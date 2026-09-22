import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/audio_player.dart';
import 'package:maboy/src/services/playback_manager.dart';
import 'package:maboy/src/services/youtube_playlist_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YouTube Playlist Service URL Extraction', () {
    test('extracts playlist ID from standard playlist URL', () {
      const url =
          'https://www.youtube.com/playlist?list=PL4fGSI1pDJn6jXS_PEO306_56xOmvgL38';
      final id = YouTubePlaylistService.extractPlaylistId(url);
      expect(id, 'PL4fGSI1pDJn6jXS_PEO306_56xOmvgL38');
      expect(YouTubePlaylistService.isPlaylistUrl(url), isTrue);
    });

    test('extracts playlist ID from video URL containing list parameter', () {
      const url =
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj';
      final id = YouTubePlaylistService.extractPlaylistId(url);
      expect(id, 'PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj');
      expect(YouTubePlaylistService.isPlaylistUrl(url), isTrue);
    });

    test('extracts playlist ID from youtu.be URL with list parameter', () {
      const url =
          'https://youtu.be/dQw4w9WgXcQ?list=PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj';
      final id = YouTubePlaylistService.extractPlaylistId(url);
      expect(id, 'PLMC9KNkIncKtPzgY-5rmhvj7fax8fdxoj');
    });

    test('extracts raw playlist ID if provided directly', () {
      const id = 'PL4fGSI1pDJn6jXS_PEO306_56xOmvgL38';
      expect(YouTubePlaylistService.extractPlaylistId(id), id);
    });

    test('returns null for plain video URL without list parameter', () {
      const url = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      expect(YouTubePlaylistService.extractPlaylistId(url), isNull);
      expect(YouTubePlaylistService.isPlaylistUrl(url), isFalse);
    });
  });

  group('PlaybackManager Duration Formatting', () {
    test('formats null or zero duration safely', () {
      expect(PlaybackManager.formatDuration(null), '--:--');
      expect(PlaybackManager.formatDuration(0), '--:--');
      expect(PlaybackManager.formatDuration(-100), '--:--');
    });

    test('formats mm:ss correctly', () {
      expect(PlaybackManager.formatDuration(65000), '1:05');
      expect(PlaybackManager.formatDuration(225000), '3:45');
    });

    test('formats hh:mm:ss for longer tracks', () {
      expect(PlaybackManager.formatDuration(3725000), '1:02:05');
    });
  });

  group('PlaybackManager RepeatMode & Speed', () {
    test('cycles RepeatMode correctly (off -> all -> one -> off)', () {
      expect(RepeatMode.off.next(), RepeatMode.all);
      expect(RepeatMode.all.next(), RepeatMode.one);
      expect(RepeatMode.one.next(), RepeatMode.off);
    });

    test('controls sleep timer and track completion trigger', () async {
      bool stopped = false;
      final player = MaboyAudioPlayer();
      final manager = PlaybackManager(
        player: player,
        onStopPlayback: () async {
          stopped = true;
        },
      );

      expect(manager.isSleepTimerActive, isFalse);

      manager.startSleepTimer(
        const Duration(minutes: 30),
        afterCurrentTrack: true,
      );
      expect(manager.isSleepTimerActive, isTrue);
      expect(manager.sleepAfterCurrentTrack, isTrue);

      manager.onTrackCompleted();
      expect(stopped, isTrue);
      expect(manager.isSleepTimerActive, isFalse);

      manager.dispose();
      await player.dispose();
    });
  });
}
