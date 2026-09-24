import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/track_formatter.dart';

void main() {
  group('TrackFormatter.split', () {
    test('Standard "Artist - Title" is separated into artist and title', () {
      final res = TrackFormatter.split(
        rawTitle: 'Linkin Park - Numb',
        rawArtist: 'Warner Records',
      );
      expect(res.artist, 'Linkin Park');
      expect(res.title, 'Numb');
    });

    test('Works with en-dash (–) and em-dash (—)', () {
      final res1 = TrackFormatter.split(
        rawTitle: 'Queen – Bohemian Rhapsody',
        rawArtist: 'Queen Official',
      );
      expect(res1.artist, 'Queen');
      expect(res1.title, 'Bohemian Rhapsody');

      final res2 = TrackFormatter.split(
        rawTitle: 'AC/DC — Back In Black',
        rawArtist: 'ACDC',
      );
      expect(res2.artist, 'AC/DC');
      expect(res2.title, 'Back In Black');
    });

    test('If no dash is present, does not touch title or artist', () {
      final res = TrackFormatter.split(
        rawTitle: 'Bohemian Rhapsody',
        rawArtist: 'Queen',
      );
      expect(res.artist, 'Queen');
      expect(res.title, 'Bohemian Rhapsody');
    });

    test('If dash is at the very beginning before text, does not touch', () {
      final res1 = TrackFormatter.split(
        rawTitle: '- Track With Dash At Start',
        rawArtist: 'Original Artist',
      );
      expect(res1.title, '- Track With Dash At Start');
      expect(res1.artist, 'Original Artist');

      final res2 = TrackFormatter.split(
        rawTitle: '  – Leading En Dash',
        rawArtist: 'Original Artist',
      );
      expect(res2.title, '  – Leading En Dash');
      expect(res2.artist, 'Original Artist');
    });

    test('If dash is at the end with no title after, does not touch', () {
      final res = TrackFormatter.split(
        rawTitle: 'Artist Name -',
        rawArtist: 'Fallback',
      );
      expect(res.title, 'Artist Name -');
      expect(res.artist, 'Fallback');
    });

    test('Strips quotes around title when formatted', () {
      final res = TrackFormatter.split(
        rawTitle: 'The Beatles - "Yesterday"',
        rawArtist: 'The Beatles',
      );
      expect(res.artist, 'The Beatles');
      expect(res.title, 'Yesterday');
    });

    test('Multi-dash splits at the first dash', () {
      final res = TrackFormatter.split(
        rawTitle: 'Artist - Song Name - Remastered 2020',
        rawArtist: '',
      );
      expect(res.artist, 'Artist');
      expect(res.title, 'Song Name - Remastered 2020');
    });
  });
}
