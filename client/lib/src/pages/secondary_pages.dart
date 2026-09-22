import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../widgets/player_sheet.dart';
import '../widgets/track_tile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String query = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final normalized = query.trim().toLowerCase();
      final results = widget.controller.tracks
          .where(
            (track) =>
                normalized.isNotEmpty &&
                ['title', 'artist', 'album'].any(
                  (field) => '${track[field] ?? ''}'.toLowerCase().contains(
                    normalized,
                  ),
                ),
          )
          .toList();

      return Scaffold(
        appBar: AppBar(title: const Text('Поиск')),
        body: MaboyBackdrop(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  autofocus: true,
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Трек, исполнитель или альбом',
                  ),
                ),
              ),
              Expanded(
                child: normalized.isEmpty
                    ? const Center(
                        child: Text('Введите запрос для поиска по библиотеке'),
                      )
                    : results.isEmpty
                    ? const Center(child: Text('Ничего не найдено'))
                    : ListView(
                        children: results
                            .map(
                              (track) => TrackTile(
                                controller: widget.controller,
                                track: track,
                              ),
                            )
                            .toList(),
                      ),
              ),
              if (widget.controller.playingTrack != null)
                MiniPlayer(controller: widget.controller),
            ],
          ),
        ),
      );
    },
  );
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final tracks = controller.favoriteIds
          .map(
            (id) => controller.tracks.where((t) => t['id'] == id).firstOrNull,
          )
          .whereType<Map<String, dynamic>>()
          .toList();

      return Scaffold(
        appBar: AppBar(title: const Text('Избранное')),
        body: MaboyBackdrop(
          child: Column(
            children: [
              Expanded(
                child: tracks.isEmpty
                    ? const Center(
                        child: Text(
                          'Добавляйте любимые треки кнопкой с сердцем',
                        ),
                      )
                    : ListView(
                        children: tracks
                            .map(
                              (track) => TrackTile(
                                controller: controller,
                                track: track,
                              ),
                            )
                            .toList(),
                      ),
              ),
              if (controller.playingTrack != null)
                MiniPlayer(controller: controller),
            ],
          ),
        ),
      );
    },
  );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('История')),
      body: MaboyBackdrop(
        child: Column(
          children: [
            Expanded(
              child: controller.history.isEmpty
                  ? const Center(
                      child: Text('Здесь появятся прослушанные треки'),
                    )
                  : ListView(
                      children: controller.history.map((entry) {
                        final track = controller.tracks
                            .where((t) => t['id'] == entry['track_id'])
                            .firstOrNull;
                        final started = DateTime.tryParse(
                          '${entry['started_at']}',
                        )?.toLocal();
                        final stamp = started == null
                            ? ''
                            : '${started.day.toString().padLeft(2, '0')}.${started.month.toString().padLeft(2, '0')} '
                                  '${started.hour.toString().padLeft(2, '0')}:${started.minute.toString().padLeft(2, '0')}';
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            '${track?['title'] ?? 'Недоступный трек'}',
                          ),
                          subtitle: Text(
                            [track?['artist'], stamp]
                                .where(
                                  (value) =>
                                      value != null && '$value'.isNotEmpty,
                                )
                                .join(' • '),
                          ),
                          onTap: track == null
                              ? null
                              : () => controller.playTrack(track),
                        );
                      }).toList(),
                    ),
            ),
            if (controller.playingTrack != null)
              MiniPlayer(controller: controller),
          ],
        ),
      ),
    ),
  );
}
