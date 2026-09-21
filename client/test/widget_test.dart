import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/app_controller.dart';

void main() {
  test('Generated operation IDs are distinct UUIDs', () {
    final ids = List.generate(100, (_) => newId());
    expect(ids.toSet().length, 100);
    expect(ids.every((id) => RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    ).hasMatch(id)), isTrue);
  });

  test('Queue allows duplicates and respects explicit order', () {
    final controller = AppController();
    controller.apply('queue.set', {'items': [
      {'id': 'first', 'track_id': 'song'},
      {'id': 'second', 'track_id': 'song'},
    ]});
    expect(controller.queue.map((e) => e['id']), ['first', 'second']);
    controller.apply('queue.set', {'items': [
      {'id': 'second', 'track_id': 'song'},
      {'id': 'first', 'track_id': 'song'},
    ]});
    expect(controller.queue.map((e) => e['id']), ['second', 'first']);
  });

  test('Playlist track order is applied from the operation', () {
    final controller = AppController();
    controller.apply('playlist.upsert', {'id': 'playlist', 'name': 'Mix', 'sort_key': 0});
    controller.apply('playlist.set_tracks', {
      'playlist_id': 'playlist', 'track_ids': ['second', 'first'],
    });
    expect(controller.playlists.single['track_ids'], ['second', 'first']);
  });
}