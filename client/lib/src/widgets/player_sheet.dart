import 'dart:ui' show ImageFilter;
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
    final desktop = MediaQuery.sizeOf(context).width >= 760;

    void openPlayer() => Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => PlayerPage(controller: controller)),
    );

    return SizedBox(
      height: desktop ? 90 : null,
      child: MaboyGlassPanel(
        radius: desktop ? 0 : 16,
        opacity: 0.86,
        child: desktop
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: openPlayer,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        children: [
                          TrackCover(
                            controller: controller,
                            track: track,
                            size: 48,
                            radius: 6,
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 185,
                            child: _MiniTrackDetails(track: track),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      tooltip: 'Предыдущий трек',
                      onPressed: controller.hasPrevious
                          ? controller.playPrevious
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    PlayPauseButton(controller: controller),
                    IconButton(
                      tooltip: 'Следующий трек',
                      onPressed: controller.hasNext
                          ? controller.playNext
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    const SizedBox(width: 22),
                    Expanded(child: ProgressBar(controller: controller)),
                    const SizedBox(width: 20),
                    const Icon(Icons.volume_down, size: 19),
                    SizedBox(
                      width: 100,
                      child: Slider(
                        value: controller.volume,
                        onChanged: controller.setVolume,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Открыть плеер и очередь',
                      onPressed: openPlayer,
                      icon: const Icon(Icons.queue_music),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProgressBar(controller: controller, compact: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: openPlayer,
                          child: TrackCover(
                            controller: controller,
                            track: track,
                            size: 44,
                            radius: 8,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: openPlayer,
                            child: _MiniTrackDetails(track: track),
                          ),
                        ),
                        PlayPauseButton(controller: controller),
                        IconButton(
                          tooltip: 'Следующий трек',
                          onPressed: controller.hasNext
                              ? controller.playNext
                              : null,
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

class _MiniTrackDetails extends StatelessWidget {
  const _MiniTrackDetails({required this.track});

  final Map<String, dynamic> track;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      MarqueeText(
        '${track['title']}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      const SizedBox(height: 2),
      MarqueeText(
        '${track['artist'] ?? 'Неизвестный исполнитель'}',
        style: const TextStyle(fontSize: 12, color: MaboyColors.textMuted),
      ),
    ],
  );
}

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.playingTrack;
      final id = track?['id'] as String?;
      final hasArtwork =
          id != null &&
          (controller.artworkFiles.containsKey(id) ||
              ('${track?['thumbnail_url'] ?? ''}').isNotEmpty);
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: MaboyBackdrop(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasArtwork)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRect(
                      child: Opacity(
                        opacity: 0.3,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: TrackCover(
                              controller: controller,
                              track: track!,
                              size: 800,
                              radius: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Color(0x770b0d11)),
                ),
              ),
              PlayerSheet(controller: controller),
            ],
          ),
        ),
      );
    },
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
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;
            final artSize = desktop
                ? 276.0
                : (constraints.maxWidth - 100).clamp(190.0, 280.0);

            final playerContent = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DecorativeProgressCover(
                  controller: controller,
                  track: track,
                  size: artSize,
                ),
                const SizedBox(height: 26),
                Text(
                  '${track['title']}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${track['artist'] ?? 'Неизвестный исполнитель'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaboyColors.textMuted),
                ),
                const SizedBox(height: 24),
                // This bottom slider is the only seek control. The ring above
                // displays the same stream and intentionally ignores gestures.
                ProgressBar(controller: controller),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: controller.isShuffle
                          ? 'Микс включен'
                          : 'Микс (без повторений)',
                      onPressed: controller.toggleShuffle,
                      icon: Icon(
                        Icons.shuffle,
                        color: controller.isShuffle
                            ? MaboyColors.primary
                            : MaboyColors.textMuted,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Предыдущий трек',
                      iconSize: 32,
                      onPressed: controller.hasPrevious
                          ? controller.playPrevious
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    PlayPauseButton(controller: controller, large: true),
                    IconButton(
                      tooltip: 'Следующий трек',
                      iconSize: 32,
                      onPressed: controller.hasNext
                          ? controller.playNext
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton(
                      tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
                      onPressed: () => controller.toggleFavorite(id),
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav
                            ? MaboyColors.primary
                            : MaboyColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: controller.volume == 0
                          ? 'Включить звук'
                          : 'Выключить звук',
                      onPressed: () => controller.setVolume(
                        controller.volume == 0 ? 1.0 : 0.0,
                      ),
                      icon: Icon(
                        controller.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_down,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: controller.volume,
                        onChanged: controller.setVolume,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Максимальная громкость',
                      onPressed: () => controller.setVolume(1.0),
                      icon: const Icon(Icons.volume_up),
                    ),
                  ],
                ),
              ],
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Назад',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(child: MaboyBrand(size: 27)),
                          TextButton.icon(
                            onPressed: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    EqualizerPage(controller: controller),
                              ),
                            ),
                            icon: const Icon(Icons.tune, size: 19),
                            label: const Text('EQ'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (desktop)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: MaboyGlassPanel(
                                padding: const EdgeInsets.all(24),
                                child: playerContent,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: MaboyGlassPanel(
                                padding: const EdgeInsets.all(22),
                                child: _PlaybackQueue(controller: controller),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        playerContent,
                        const SizedBox(height: 22),
                        MaboyGlassPanel(
                          padding: const EdgeInsets.all(14),
                          child: _PlaybackQueue(controller: controller),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Playback progress is visual here; seeking is handled by ProgressBar below.
class _DecorativeProgressCover extends StatelessWidget {
  const _DecorativeProgressCover({
    required this.controller,
    required this.track,
    required this.size,
  });

  final AppController controller;
  final Map<String, dynamic> track;
  final double size;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration?>(
    stream: controller.player.durationStream,
    initialData: controller.player.duration,
    builder: (context, durationSnapshot) => StreamBuilder<Duration>(
      stream: controller.player.positionStream,
      initialData: controller.player.position,
      builder: (context, positionSnapshot) {
        final durationMs = durationSnapshot.data?.inMilliseconds ?? 0;
        final positionMs = positionSnapshot.data?.inMilliseconds ?? 0;
        final fraction = durationMs > 0
            ? (positionMs / durationMs).clamp(0.0, 1.0)
            : 0.0;
        return IgnorePointer(
          key: const Key('decorativePlaybackRing'),
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: size + 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x44f36d79),
                          blurRadius: 42,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: TrackCover(
                        controller: controller,
                        track: track,
                        size: size,
                        radius: size / 2,
                      ),
                    ),
                  ),
                  SizedBox.square(
                    dimension: size + 24,
                    child: CircularProgressIndicator(
                      value: fraction,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: MaboyColors.primary,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
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

    final visible = upcoming.length > 80
        ? upcoming.take(80).toList()
        : upcoming;

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
            proxyDecorator: maboyReorderProxyDecorator,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: visible.length,
            onReorderStart: (_) => controller.beginReorder(),
            onReorderEnd: (_) => controller.endReorder(),
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
    final tile = ListTile(
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
          : IconButton(
              tooltip: 'Убрать из очереди',
              onPressed: () =>
                  controller.removeUpcomingPlayback(entry.playbackIndex),
              icon: const Icon(Icons.close, size: 20),
            ),
    );
    return reorderIndex == null
        ? tile
        : ReorderableDelayedDragStartListener(
            index: reorderIndex!,
            child: tile,
          );
  }
}
