import 'dart:io';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import 'marquee_text.dart';

class _TrackActionsMenu extends StatelessWidget {
  const _TrackActionsMenu({
    required this.onSelected,
    required this.itemBuilder,
    this.dragIndex,
  });

  final ValueChanged<String> onSelected;
  final PopupMenuItemBuilder<String> itemBuilder;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final menu = PopupMenuButton<String>(
      tooltip: 'Действия',
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      icon: const Icon(Icons.more_vert),
    );
    if (dragIndex == null) return menu;
    // Android users start reordering by holding the three-dot button. A
    // delayed listener preserves the normal short-tap menu action.
    return ReorderableDelayedDragStartListener(index: dragIndex!, child: menu);
  }
}

Future<void> showAddToPlaylistDialog(
  BuildContext context,
  AppController controller,
  List<String> trackIds,
) async {
  if (trackIds.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Добавить в плейлист'),
      content: SizedBox(
        width: double.maxFinite,
        child: controller.playlists.isEmpty
            ? const Text('У вас пока нет плейлистов. Создайте новый.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: controller.playlists.length,
                itemBuilder: (context, index) {
                  final pl = controller.playlists[index];
                  return ListTile(
                    leading: const Icon(Icons.playlist_play),
                    title: Text('${pl['name']}'),
                    subtitle: Text(
                      '${(pl['track_ids'] as List?)?.length ?? 0} треков',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await controller.addTracksToPlaylist(
                        pl['id'] as String,
                        trackIds,
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Добавлено в «${pl['name']}»'),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

Future<void> confirmDeleteLocally(
  BuildContext context,
  AppController controller,
  List<String> trackIds,
) async {
  if (trackIds.isEmpty) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Удалить ${trackIds.length} файл(ов) с этого устройства?'),
      content: const Text(
        'Файлы будут физически удалены из памяти текущего устройства. '
        'Они останутся в вашей библиотеке на сервере и других устройствах, '
        'и не будут скачиваться снова автоматически.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Удалить с устройства'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    await controller.deleteLocally(trackIds);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Удалено файлов с устройства: ${trackIds.length}'),
        ),
      );
    }
  }
}

class TrackCover extends StatelessWidget {
  const TrackCover({
    super.key,
    required this.controller,
    required this.track,
    this.size = 44,
    this.radius = 6,
  });

  final AppController controller;
  final Map<String, dynamic> track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final id = track['id'] as String;
    final localArt = controller.artworkFiles[id];
    final thumbUrl = track['thumbnail_url'] as String?;

    Widget content;
    if (localArt != null && File(localArt).existsSync()) {
      content = Image.file(
        File(localArt),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    } else if (thumbUrl != null && thumbUrl.isNotEmpty) {
      content = Image.network(
        thumbUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    } else {
      content = _fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }

  Widget _fallback() => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [MaboyColors.surfaceHigh, Color(0xff244d7f)],
      ),
    ),
    child: Icon(
      track['provider'] == 'local' ? Icons.music_note : Icons.play_arrow,
      size: size * 0.5,
      color: MaboyColors.textMuted,
    ),
  );
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.controller,
    required this.track,
    this.folderId,
    this.playbackIds,
    this.isSelected = false,
    this.isSelecting = false,
    this.onSelect,
    this.onLongPress,
    this.onRemoveFromPlaylist,
    this.dragIndex,
  });

  final AppController controller;
  final Map<String, dynamic> track;
  final String? folderId;
  final List<String>? playbackIds;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;
  final VoidCallback? onRemoveFromPlaylist;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final id = track['id'] as String;
    final isPlaying = controller.playingId == id;
    final isDownloading = controller.downloadingIds.contains(id);
    final progress = controller.downloadProgress[id];
    final isDeletedLocally = controller.deletedLocallyIds.contains(id);
    final remoteStatus = controller.deviceTrackStatuses[id];
    final isRemoteDeleted =
        remoteStatus != null && remoteStatus['status'] == 'deleted';
    final remoteDevice = remoteStatus?['device_name'] ?? 'другом устройстве';

    String locationStatus;
    Color? statusColor;
    IconData? statusIcon;

    if (isDeletedLocally) {
      locationStatus = 'Удалено на этом устройстве';
      statusColor = MaboyColors.warning;
      statusIcon = Icons.cloud_off;
    } else if (isRemoteDeleted) {
      locationStatus = 'Удалено на $remoteDevice';
      statusColor = MaboyColors.textMuted;
      statusIcon = Icons.devices_other;
    } else if (controller.localFiles.containsKey(id)) {
      locationStatus = 'MP3';
    } else if (track['provider'] == 'youtube') {
      locationStatus = 'YouTube';
    } else {
      locationStatus = 'В облаке';
    }

    Widget leadingWidget;
    if (isSelecting) {
      leadingWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: isSelected, onChanged: (_) => onSelect?.call()),
          TrackCover(controller: controller, track: track, size: 36, radius: 4),
        ],
      );
    } else {
      leadingWidget = TrackCover(
        controller: controller,
        track: track,
        size: 44,
        radius: 6,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        selected: isSelected,
        selectedTileColor: MaboyColors.primary.withValues(alpha: 0.12),
        leading: leadingWidget,
        title: Row(
          children: [
            Expanded(
              child: MarqueeText(
                '${track['title']}',
                style: TextStyle(
                  color: isPlaying
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isDownloading)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: (progress != null && progress > 0) ? progress : null,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            if (statusIcon != null) ...[
              Icon(statusIcon, size: 13, color: statusColor),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: MarqueeText(
                [
                  track['artist'],
                  if (track['album'] != null &&
                      track['album'] != track['artist'])
                    track['album'],
                  locationStatus,
                ].where((v) => v != null && '$v'.isNotEmpty).join(' • '),
                style: TextStyle(color: statusColor),
              ),
            ),
          ],
        ),
        onTap: () {
          if (isSelecting) {
            onSelect?.call();
          } else {
            controller.playTrack(
              track,
              folderId: folderId,
              playbackIds: playbackIds,
            );
          }
        },
        onLongPress: onLongPress,
        trailing: isSelecting
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: controller.isFavorite(id)
                        ? 'Убрать из избранного'
                        : 'В избранное',
                    onPressed: () => controller.toggleFavorite(id),
                    icon: Icon(
                      controller.isFavorite(id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: controller.isFavorite(id)
                          ? MaboyColors.danger
                          : null,
                    ),
                  ),
                  _TrackActionsMenu(
                    dragIndex: dragIndex,
                    onSelected: (action) async {
                      if (action == 'next') {
                        controller.addToQueue(id, next: true);
                      } else if (action == 'last') {
                        controller.addToQueue(id, next: false);
                      } else if (action == 'add_to_playlist') {
                        await showAddToPlaylistDialog(context, controller, [
                          id,
                        ]);
                      } else if (action == 'remove_from_playlist') {
                        onRemoveFromPlaylist?.call();
                      } else if (action == 'delete_locally') {
                        await confirmDeleteLocally(context, controller, [id]);
                      } else if (action == 'restore_locally') {
                        await controller.restoreLocally(id);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'next',
                        child: Text('Играть следующим'),
                      ),
                      const PopupMenuItem(
                        value: 'last',
                        child: Text('Добавить в очередь'),
                      ),
                      const PopupMenuItem(
                        value: 'add_to_playlist',
                        child: Text('Добавить в плейлист...'),
                      ),
                      if (onRemoveFromPlaylist != null)
                        const PopupMenuItem(
                          value: 'remove_from_playlist',
                          child: Text('Убрать из плейлиста'),
                        ),
                      const PopupMenuDivider(),
                      if (isDeletedLocally)
                        const PopupMenuItem(
                          value: 'restore_locally',
                          child: Text('Скачать заново'),
                        )
                      else
                        const PopupMenuItem(
                          value: 'delete_locally',
                          child: Text(
                            'Удалить с этого устройства',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
