import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/track_metadata_service.dart';
import 'package:maboy/src/services/youtube_downloader.dart';

void main() {
  group('TrackMetadataService tests', () {
    const service = TrackMetadataService();

    test('buildManualMetadataUpdate updates title and artist cleanly', () {
      final initialTrack = {
        'id': 'track-1',
        'provider': 'youtube',
        'title': 'YouTube Audio',
        'artist': 'YouTube',
      };

      final updated = service.buildManualMetadataUpdate(
        track: initialTrack,
        title: '  In the End  ',
        artist: '  Linkin Park  ',
      );

      expect(updated['id'], 'track-1');
      expect(updated['provider'], 'youtube');
      expect(updated['title'], 'In the End');
      expect(updated['artist'], 'Linkin Park');
    });

    test('buildManualMetadataUpdate sets empty artist to null', () {
      final initialTrack = {
        'id': 'track-2',
        'provider': 'local',
        'title': 'Song',
        'artist': 'Artist',
      };

      final updated = service.buildManualMetadataUpdate(
        track: initialTrack,
        title: 'New Title',
        artist: '   ',
      );

      expect(updated['title'], 'New Title');
      expect(updated['artist'], isNull);
    });

    test('YouTubeDownloadService extracts videoId from standard and share URLs', () {
      expect(
        YouTubeDownloadService.extractVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeDownloadService.extractVideoId('https://youtu.be/dQw4w9WgXcQ?si=test1234'),
        'dQw4w9WgXcQ',
      );
      expect(
        YouTubeDownloadService.extractVideoId('https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=abc'),
        'dQw4w9WgXcQ',
      );
    });

    test('YouTubeDownloadService extracts title candidate from Android share text', () {
      expect(
        YouTubeDownloadService.extractTitleCandidate(
          'Rick Astley - Never Gonna Give You Up https://youtu.be/dQw4w9WgXcQ?si=123',
        ),
        'Rick Astley - Never Gonna Give You Up',
      );
      expect(
        YouTubeDownloadService.extractTitleCandidate(
          'Watch "Queen - Bohemian Rhapsody" on YouTube: https://youtu.be/fJ9rUzIMcZQ',
        ),
        'Queen - Bohemian Rhapsody',
      );
      expect(
        YouTubeDownloadService.extractTitleCandidate(
          'https://youtu.be/dQw4w9WgXcQ',
        ),
        isNull,
      );
    });
  });
}
