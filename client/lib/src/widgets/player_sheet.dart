import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../pages/equalizer_page.dart';
import 'marquee_text.dart';
import 'track_tile.dart';

class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({
    super.key,
    required this.controller,
    this.large = false,
  });

  final AppController controller;
  final bool large;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: controller.player.playingStream,
    initialData: controller.player.playing,
    builder: (context, snapshot) => IconButton.filled(
      tooltip: snapshot.data == true ? 'Пауза' : 'Воспроизвести',
      iconSize: large ? 38 : 24,
      onPressed: controller.togglePlayback,
      icon: Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
    ),
  );
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final AppController controller;
  final bool compact;

  String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration?>(
    stream: controller.player.durationStream,
    initialData: controller.player.duration,
    builder: (context, durationSnapshot) => StreamBuilder<Duration>(
      stream: controller.player.positionStream,
      initialData: controller.player.position,
      builder: (context, positionSnapshot) {
        final duration = durationSnapshot.data ?? Duration.zero;
        final position = positionSnapshot.data ?? Duration.zero;
        final maxMs = duration.inMilliseconds.toDouble();
        final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs);

        if (compact) {
          return LinearProgressIndicator(
            value: maxMs > 0 ? (currentMs / maxMs).clamp(0.0, 1.0) : 0.0,
            minHeight: 2,
          );
        }

        return Column(
          children: [
            Slider(
              value: maxMs > 0 ? currentMs : 0.0,
              max: maxMs > 0 ? maxMs : 1.0,
              onChanged: maxMs > 0
                  ? (value) =>
                        controller.seek(Duration(milliseconds: value.toInt()))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _time(position),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    _time(duration),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final track = controller.playingTrack;
    if (track == null) return const SizedBox.shrink();

    return Material(
      elevation: 10,
      color: MaboyColors.surfaceHigh,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => PlayerPage(controller: controller)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressBar(controller: controller, compact: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  TrackCover(
                    controller: controller,
                    track: track,
                    size: 44,
                    radius: 11,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MarqueeText(
                          '${track['title']}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        MarqueeText(
                          '${track['artist'] ?? 'Неизвестный исполнитель'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MaboyColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PlayPauseButton(controller: controller),
                  IconButton(
                    tooltip: 'Следующий трек',
                    onPressed: controller.hasNext ? controller.playNext : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: MaboyBackdrop(child: PlayerSheet(controller: controller)),
  );
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.playingTrack;
      if (track == null) return const SizedBox.shrink();
      final id = track['id'] as String;
      final isFav = controller.isFavorite(id);

      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Назад',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: MaboyBrand(size: 30)),
                    TextButton.icon(
                      onPressed: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EqualizerPage(controller: controller),
                        ),
                      ),
                      icon: const Icon(Icons.tune, size: 19),
                      label: const Text('EQ'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: MaboyColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 32,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: TrackCover(
                    controller: controller,
                    track: track,
                    size: constraints.maxWidth > 560 ? 330 : 250,
                    radius: 6,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  '${track['title']}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${track['artist'] ?? 'Неизвестный исполнитель'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: MaboyColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                ProgressBar(controller: controller),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: controller.isShuffle
                          ? 'Микс включен'
                          : 'Микс (без повторений)',
                      icon: Icon(
                        controller.isShuffle
                            ? Icons.shuffle_on_outlined
                            : Icons.shuffle,
                        color: controller.isShuffle
                            ? MaboyColors.primary
                            : MaboyColors.textMuted,
                      ),
                      iconSize: 26,
                      onPressed: controller.toggleShuffle,
                    ),
                    IconButton(
                      tooltip: 'Предыдущий трек',
                      iconSize: 36,
                      onPressed: controller.hasPrevious
                          ? controller.playPrevious
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    PlayPauseButton(controller: controller, large: true),
                    IconButton(
                      tooltip: 'Следующий трек',
                      iconSize: 36,
                      onPressed: controller.hasNext
                          ? controller.playNext
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton(
                      tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav
                            ? MaboyColors.danger
                            : MaboyColors.textMuted,
                      ),
                      iconSize: 26,
                      onPressed: () => controller.toggleFavorite(id),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // App-specific Volume Slider
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        controller.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_down,
                        size: 20,
                        color: MaboyColors.textMuted,
                      ),
                      tooltip: controller.volume == 0
                          ? 'Включить звук'
                          : 'Выключить звук',
                      onPressed: () => controller.setVolume(
                        controller.volume == 0 ? 1.0 : 0.0,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: controller.volume,
                        onChanged: controller.setVolume,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.volume_up,
                        size: 20,
                        color: MaboyColors.textMuted,
                      ),
                      tooltip: 'Максимальная громкость',
                      onPressed: () => controller.setVolume(1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 10),
                _PlaybackQueue(controller: controller),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PlaybackQueue extends StatelessWidget {
  const _PlaybackQueue({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.activePlaybackQueue;
    if (entries.isEmpty) return const SizedBox.shrink();

    final current = entries.first;
    final upcoming = entries.skip(1).toList();

    final visible = upcoming.length > 80 ? upcoming.take(80).toList() : upcoming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Далее в очереди',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        _PlaybackQueueTile(
          entry: current,
          controller: controller,
          current: true,
        ),
        if (upcoming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text(
              'Это последний трек',
              textAlign: TextAlign.center,
              style: TextStyle(color: MaboyColors.textMuted),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: visible.length,
            onReorder: controller.reorderUpcomingPlayback,
            itemBuilder: (context, index) {
              final entry = visible[index];
              return _PlaybackQueueTile(
                key: ValueKey(entry.queueKey),
                entry: entry,
                controller: controller,
                reorderIndex: index,
              );
            },
          ),
        if (upcoming.length > visible.length)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Показаны ближайшие 80 треков',
              textAlign: TextAlign.center,
              style: TextStyle(color: MaboyColors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PlaybackQueueTile extends StatelessWidget {
  const _PlaybackQueueTile({
    super.key,
    required this.entry,
    required this.controller,
    this.current = false,
    this.reorderIndex,
  });

  final PlaybackQueueEntry entry;
  final AppController controller;
  final bool current;
  final int? reorderIndex;

  @override
  Widget build(BuildContext context) {
    final track = entry.track;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: TrackCover(
        controller: controller,
        track: track,
        size: 46,
        radius: 5,
      ),
      title: MarqueeText(
        '${track['title']}',
        style: TextStyle(
          color: current ? MaboyColors.primary : null,
          fontWeight: current ? FontWeight.bold : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        current
            ? 'Сейчас играет'
            : '${track['artist'] ?? 'Неизвестный исполнитель'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: MaboyColors.textMuted),
      ),
      onTap: current ? null : () => controller.playPlaybackQueueEntry(entry),
      trailing: current
          ? const Icon(Icons.graphic_eq, color: MaboyColors.primary)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Убрать из очереди',
                  onPressed: () =>
                      controller.removeUpcomingPlayback(entry.playbackIndex),
                  icon: const Icon(Icons.close, size: 20),
                ),
                ReorderableDragStartListener(
                  index: reorderIndex!,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
              ],
            ),
    );
  }
}
