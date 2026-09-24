import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../pages/equalizer_page.dart';
import '../services/track_formatter.dart';
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

    return RepaintBoundary(
      child: SizedBox(
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
                    const SizedBox(width: 8),
                    _GlowingQueueButton(onPressed: openPlayer),
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
                        const SizedBox(width: 4),
                        _GlowingQueueButton(
                          onPressed: openPlayer,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}

class _GlowingQueueButton extends StatefulWidget {
  const _GlowingQueueButton({
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  State<_GlowingQueueButton> createState() => _GlowingQueueButtonState();
}

class _GlowingQueueButtonState extends State<_GlowingQueueButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.45, end: 0.90).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, _) {
        final glowFactor = _isHovered ? 1.0 : _glowAnimation.value;
        final blur = _isHovered ? 20.0 : 13.0;
        final spread = _isHovered ? 2.5 : 1.2;

        return Tooltip(
          message: 'Открыть плеер и очередь',
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: widget.compact
                    ? const EdgeInsets.all(7)
                    : const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      MaboyColors.primary.withValues(
                        alpha: _isHovered ? 0.38 : 0.22,
                      ),
                      const Color(0xfff36d79).withValues(
                        alpha: _isHovered ? 0.26 : 0.12,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(widget.compact ? 12 : 20),
                  border: Border.all(
                    color: MaboyColors.primary.withValues(
                      alpha: _isHovered ? 1.0 : 0.8,
                    ),
                    width: _isHovered ? 1.6 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MaboyColors.primary.withValues(alpha: glowFactor * 0.65),
                      blurRadius: blur,
                      spreadRadius: spread,
                    ),
                    BoxShadow(
                      color: const Color(0xfff36d79).withValues(alpha: glowFactor * 0.35),
                      blurRadius: blur * 1.5,
                      spreadRadius: spread * 1.1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.queue_music,
                      size: widget.compact ? 19 : 20,
                      color: Colors.white,
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(width: 7),
                      const Text(
                        'Очередь',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
}

class _MiniTrackDetails extends StatelessWidget {
  const _MiniTrackDetails({required this.track});

  final Map<String, dynamic> track;

  @override
  Widget build(BuildContext context) {
    final formatted = TrackFormatter.split(
      rawTitle: '${track['title'] ?? ''}',
      rawArtist: track['artist'] as String?,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarqueeText(
          formatted.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 2),
        Text(
          formatted.artist.isNotEmpty
              ? formatted.artist
              : '${track['artist'] ?? 'Неизвестный исполнитель'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: MaboyColors.textMuted),
        ),
      ],
    );
  }
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

  Widget _buildPlayerControls(
    BuildContext context,
    Map<String, dynamic> track,
    double artSize,
  ) {
    final id = track['id'] as String;
    final isFav = controller.isFavorite(id);

    final formatted = TrackFormatter.split(
      rawTitle: '${track['title'] ?? ''}',
      rawArtist: track['artist'] as String?,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DecorativeProgressCover(
          controller: controller,
          track: track,
          size: artSize,
        ),
        const SizedBox(height: 18),
        Text(
          formatted.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatted.artist.isNotEmpty
              ? formatted.artist
              : '${track['artist'] ?? 'Неизвестный исполнитель'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: MaboyColors.textMuted),
        ),
        const SizedBox(height: 18),
        ProgressBar(controller: controller),
        const SizedBox(height: 12),
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
        const SizedBox(height: 10),
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
  }

  Widget _buildTopBar(BuildContext context) => Row(
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
            builder: (_) => EqualizerPage(controller: controller),
          ),
        ),
        icon: const Icon(Icons.tune, size: 19),
        label: const Text('EQ'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final track = controller.playingTrack;
      if (track == null) return const SizedBox.shrink();

      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 820;

            if (desktop) {
              final availableHeight = constraints.maxHeight;
              final desktopArtSize = (availableHeight * 0.33).clamp(160.0, 260.0);

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      children: [
                        _buildTopBar(context),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Fixed Player Column
                              Expanded(
                                flex: 5,
                                child: MaboyGlassPanel(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 16,
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, panelConstraints) => Center(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.center,
                                        child: SizedBox(
                                          width: panelConstraints.maxWidth.clamp(300.0, 480.0),
                                          child: _buildPlayerControls(
                                            context,
                                            track,
                                            desktopArtSize,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              // Independent Scrollable Queue Column
                              Expanded(
                                flex: 6,
                                child: MaboyGlassPanel(
                                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                                  child: _PlaybackQueue(
                                    controller: controller,
                                    isDesktop: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final artSize = (constraints.maxWidth - 100).clamp(190.0, 280.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    children: [
                      _buildTopBar(context),
                      const SizedBox(height: 12),
                      _buildPlayerControls(context, track, artSize),
                      const SizedBox(height: 22),
                      MaboyGlassPanel(
                        padding: const EdgeInsets.all(14),
                        child: _PlaybackQueue(
                          controller: controller,
                          isDesktop: false,
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
        return RepaintBoundary(
          child: IgnorePointer(
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
        ),
      );
    },
    ),
  );
}

class _PlaybackQueue extends StatelessWidget {
  const _PlaybackQueue({
    required this.controller,
    this.isDesktop = false,
  });

  final AppController controller;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final deviceQueue = controller.deviceQueue;
    final entries = controller.activePlaybackQueue;
    if (entries.isEmpty && deviceQueue.isEmpty) return const SizedBox.shrink();

    final current = entries.firstOrNull;
    final queuedTrackIds = deviceQueue.map((q) => q['track_id']).toSet();
    final upcoming = entries.length > 1
        ? entries
            .skip(1)
            .where((e) => !queuedTrackIds.contains(e.track['id']))
            .toList()
        : <PlaybackQueueEntry>[];
    final visibleUpcoming = upcoming.length > 80
        ? upcoming.take(80).toList()
        : upcoming;

    final headerRow = Row(
      children: [
        Expanded(
          child: Text(
            deviceQueue.isNotEmpty
                ? 'Очередь воспроизведения'
                : 'Далее в очереди',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (upcoming.length > 1)
          IconButton(
            icon: const Icon(Icons.shuffle, size: 20),
            tooltip: 'Перемешать следующие треки',
            onPressed: controller.shuffleUpcomingPlayback,
          ),
        if (deviceQueue.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            tooltip: 'Очистить закрепленные',
            onPressed: () => controller.setDeviceQueue([]),
          ),
      ],
    );

    Widget buildDeviceQueue() {
      return ReorderableListView.builder(
        proxyDecorator: maboyReorderProxyDecorator,
        shrinkWrap: !isDesktop || upcoming.isNotEmpty,
        physics: (isDesktop && upcoming.isEmpty)
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: deviceQueue.length,
        onReorderStart: (_) => controller.beginReorder(),
        onReorderEnd: (_) => controller.endReorder(),
        onReorder: (from, to) {
          if (to > from) to--;
          final items = List<Map<String, dynamic>>.from(deviceQueue);
          items.insert(to, items.removeAt(from));
          controller.setDeviceQueue(items);
        },
        itemBuilder: (context, index) {
          final item = deviceQueue[index];
          final track = controller.tracks
              .where((t) => t['id'] == item['track_id'])
              .firstOrNull;
          final isCurrent =
              current != null && current.track['id'] == item['track_id'];
          final formatted = TrackFormatter.split(
            rawTitle: '${track?['title'] ?? 'Трек'}',
            rawArtist: track?['artist'] as String?,
          );

          return ReorderableDelayedDragStartListener(
            key: ValueKey(item['id']),
            index: index,
            child: RepaintBoundary(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 2,
                ),
                leading: TrackCover(
                  controller: controller,
                  track: track ?? const {},
                  size: 46,
                  radius: 5,
                ),
                title: isCurrent
                    ? MarqueeText(
                        formatted.title,
                        style: const TextStyle(
                          color: MaboyColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Text(
                        formatted.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                subtitle: Text(
                  isCurrent
                      ? 'Сейчас играет'
                      : (formatted.artist.isNotEmpty
                          ? formatted.artist
                          : '${track?['artist'] ?? 'Неизвестный исполнитель'}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MaboyColors.textMuted),
                ),
                onTap: () => controller.playQueueItem(item),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Убрать из очереди',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => controller.setDeviceQueue(
                        deviceQueue.where((q) => q['id'] != item['id']),
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 20,
                            color: MaboyColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    Widget buildUpcoming() {
      return ReorderableListView.builder(
        proxyDecorator: maboyReorderProxyDecorator,
        shrinkWrap: !isDesktop || deviceQueue.isNotEmpty,
        physics: (isDesktop && deviceQueue.isEmpty)
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: visibleUpcoming.length,
        onReorderStart: (_) => controller.beginReorder(),
        onReorderEnd: (_) => controller.endReorder(),
        onReorder: controller.reorderUpcomingPlayback,
        itemBuilder: (context, index) {
          final entry = visibleUpcoming[index];
          return _PlaybackQueueTile(
            key: ValueKey(entry.queueKey),
            entry: entry,
            controller: controller,
            reorderIndex: index,
          );
        },
      );
    }

    Widget buildQueueList() {
      if (deviceQueue.isEmpty && upcoming.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'Это последний трек',
            textAlign: TextAlign.center,
            style: TextStyle(color: MaboyColors.textMuted),
          ),
        );
      }

      if (deviceQueue.isEmpty) {
        return buildUpcoming();
      }

      if (upcoming.isEmpty) {
        return buildDeviceQueue();
      }

      return ListView(
        shrinkWrap: !isDesktop,
        physics: isDesktop
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Закреплено в очереди (${deviceQueue.length})',
                    style: const TextStyle(
                      color: MaboyColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (deviceQueue.length > 1)
                  IconButton(
                    icon: const Icon(Icons.shuffle, size: 18),
                    tooltip: 'Перемешать закрепленные',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: controller.shuffleQueue,
                  ),
              ],
            ),
          ),
          buildDeviceQueue(),
          const Divider(height: 16),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Далее (${visibleUpcoming.length})',
                    style: const TextStyle(
                      color: MaboyColors.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (upcoming.length > 1)
                  IconButton(
                    icon: const Icon(Icons.shuffle, size: 18),
                    tooltip: 'Перемешать следующие треки',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: controller.shuffleUpcomingPlayback,
                  ),
              ],
            ),
          ),
          buildUpcoming(),
        ],
      );
    }

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headerRow,
          const SizedBox(height: 8),
          if (current != null && deviceQueue.isEmpty) ...[
            _PlaybackQueueTile(
              entry: current,
              controller: controller,
              current: true,
            ),
            const Divider(height: 16),
          ],
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: buildQueueList(),
            ),
          ),
          if (upcoming.length > visibleUpcoming.length)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Показаны ближайшие 80 треков',
                textAlign: TextAlign.center,
                style: TextStyle(color: MaboyColors.textMuted, fontSize: 12),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headerRow,
        const SizedBox(height: 8),
        if (current != null && deviceQueue.isEmpty)
          _PlaybackQueueTile(
            entry: current,
            controller: controller,
            current: true,
          ),
        buildQueueList(),
        if (upcoming.length > visibleUpcoming.length)
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
    final formatted = TrackFormatter.split(
      rawTitle: '${track['title'] ?? ''}',
      rawArtist: track['artist'] as String?,
    );
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: TrackCover(
        controller: controller,
        track: track,
        size: 46,
        radius: 5,
      ),
      title: current
          ? MarqueeText(
              formatted.title,
              style: const TextStyle(
                color: MaboyColors.primary,
                fontWeight: FontWeight.bold,
              ),
            )
          : Text(
              formatted.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
      subtitle: Text(
        current
            ? 'Сейчас играет'
            : (formatted.artist.isNotEmpty
                ? formatted.artist
                : '${track['artist'] ?? 'Неизвестный исполнитель'}'),
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
                if (reorderIndex != null)
                  ReorderableDragStartListener(
                    index: reorderIndex!,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: MaboyColors.textMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
    final wrappedTile = RepaintBoundary(child: tile);
    return reorderIndex == null
        ? wrappedTile
        : ReorderableDelayedDragStartListener(
            index: reorderIndex!,
            child: wrappedTile,
          );
  }
}
