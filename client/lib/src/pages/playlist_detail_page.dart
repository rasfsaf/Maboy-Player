import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../widgets/player_sheet.dart';
import '../widgets/track_tile.dart';

class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.controller,
    required this.playlist,
  });

  final AppController controller;
  final Map<String, dynamic> playlist;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  final Set<String> _selectedTrackIds = {};
  bool get _isSelecting => _selectedTrackIds.isNotEmpty;

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedTrackIds.contains(id)) {
        _selectedTrackIds.remove(id);
      } else {
        _selectedTrackIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedTrackIds.clear());
  }

  Future<void> _renamePlaylist() async {
    final nameCtrl = TextEditingController(text: '${widget.playlist['name']}');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать плейлист'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (accepted == true && nameCtrl.text.trim().isNotEmpty) {
      await widget.controller.renamePlaylist(
        widget.playlist,
        nameCtrl.text.trim(),
      );
    }
    nameCtrl.dispose();
  }

  Future<void> _deletePlaylist() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить плейлист?'),
        content: Text(
          '«${widget.playlist['name']}» будет удалён на всех устройствах.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.controller.deletePlaylist(widget.playlist['id'] as String);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _showAddTracksDialog(List<String> currentTrackIds) async {
    final availableTracks = widget.controller.tracks
        .where((t) => !currentTrackIds.contains(t['id']))
        .toList();

    if (availableTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Все треки из библиотеки уже добавлены в этот плейлист',
          ),
        ),
      );
      return;
    }

    final chosenIds = <String>{};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить треки из библиотеки'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: availableTracks.length,
              itemBuilder: (context, index) {
                final track = availableTracks[index];
                final id = track['id'] as String;
                final checked = chosenIds.contains(id);
                return CheckboxListTile(
                  value: checked,
                  onChanged: (val) {
                    setDialogState(() {
                      if (val == true) {
                        chosenIds.add(id);
                      } else {
                        chosenIds.remove(id);
                      }
                    });
                  },
                  title: Text(
                    '${track['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${track['artist'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: TrackCover(
                    controller: widget.controller,
                    track: track,
                    size: 36,
                    radius: 4,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: chosenIds.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await widget.controller.addTracksToPlaylist(
                        widget.playlist['id'] as String,
                        chosenIds,
                      );
                    },
              child: Text('Добавить (${chosenIds.length})'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeSelectedFromPlaylist(List<String> playlistTrackIds) {
    final updated = List<String>.from(playlistTrackIds)
      ..removeWhere((id) => _selectedTrackIds.contains(id));
    widget.controller.setPlaylistTracks(
      widget.playlist['id'] as String,
      updated,
    );
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      // Refresh playlist reference from controller
      final currentPlaylist =
          c.playlists
              .where((p) => p['id'] == widget.playlist['id'])
              .firstOrNull ??
          widget.playlist;
      final playlistTrackIds = List<String>.from(
        currentPlaylist['track_ids'] as List? ?? [],
      );

      final List<Map<String, dynamic>> playlistTracks = playlistTrackIds
          .map((id) => c.tracks.where((t) => t['id'] == id).firstOrNull)
          .whereType<Map<String, dynamic>>()
          .toList();
      final validTrackIds = playlistTracks
          .map((t) => t['id'] as String)
          .toList();

      return Scaffold(
        appBar: _isSelecting
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                ),
                title: Text('Выбрано: ${_selectedTrackIds.length}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Выбрать все',
                    onPressed: () => setState(
                      () => _selectedTrackIds.addAll(playlistTrackIds),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Убрать из плейлиста',
                    onPressed: () =>
                        _removeSelectedFromPlaylist(playlistTrackIds),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.redAccent,
                    tooltip: 'Удалить с этого устройства',
                    onPressed: () async {
                      final ids = _selectedTrackIds.toList();
                      _clearSelection();
                      await confirmDeleteLocally(context, c, ids);
                    },
                  ),
                ],
              )
            : AppBar(
                title: Text('${currentPlaylist['name']}'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Добавить треки',
                    onPressed: () => _showAddTracksDialog(playlistTrackIds),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (action) {
                      if (action == 'rename') _renamePlaylist();
                      if (action == 'delete') _deletePlaylist();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Переименовать'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Удалить плейлист',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: MaboyBackdrop(
          child: Column(
            children: [
              if (!_isSelecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      _PlaylistMosaic(
                        controller: c,
                        tracks: playlistTracks,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${currentPlaylist['name']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${playlistTracks.length} ${_songsLabel(playlistTracks.length)}',
                              style: const TextStyle(
                                color: MaboyColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: playlistTracks.isEmpty
                            ? null
                            : () => c.playTrack(
                                playlistTracks.first,
                                folderId: currentPlaylist['id'] as String,
                                playbackIds: validTrackIds,
                              ),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Слушать'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: playlistTracks.isEmpty
                            ? null
                            : () => c.startShuffle(
                                folderId: currentPlaylist['id'] as String,
                              ),
                        icon: const Icon(Icons.shuffle),
                        label: const Text('Микс'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: playlistTracks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.music_note,
                              size: 48,
                              color: Colors.white30,
                            ),
                            const SizedBox(height: 12),
                            const Text('В этом плейлисте пока нет песен'),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showAddTracksDialog(playlistTrackIds),
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить песни из библиотеки'),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        buildDefaultDragHandles: !_isSelecting,
                        itemCount: playlistTracks.length,
                        onReorder: (from, to) {
                          if (to > from) to--;
                          final ids = List<String>.from(validTrackIds);
                          ids.insert(to, ids.removeAt(from));
                          c.setPlaylistTracks(
                            currentPlaylist['id'] as String,
                            ids,
                          );
                        },
                        itemBuilder: (context, index) {
                          final track = playlistTracks[index];
                          final id = track['id'] as String;
                          return TrackTile(
                            key: ValueKey('${currentPlaylist['id']}:$id'),
                            controller: c,
                            track: track,
                            dragIndex: index,
                            folderId: currentPlaylist['id'] as String,
                            playbackIds: validTrackIds,
                            isSelected: _selectedTrackIds.contains(id),
                            isSelecting: _isSelecting,
                            onSelect: () => _toggleSelect(id),
                            onLongPress: () {
                              if (!_isSelecting) _toggleSelect(id);
                            },
                            onRemoveFromPlaylist: () {
                              final ids = List<String>.from(validTrackIds)
                                ..remove(id);
                              c.setPlaylistTracks(
                                currentPlaylist['id'] as String,
                                ids,
                              );
                            },
                          );
                        },
                      ),
              ),
              if (c.playingTrack != null) MiniPlayer(controller: c),
            ],
          ),
        ),
      );
    },
  );
}

class _PlaylistMosaic extends StatelessWidget {
  const _PlaylistMosaic({required this.controller, required this.tracks});

  final AppController controller;
  final List<Map<String, dynamic>> tracks;

  @override
  Widget build(BuildContext context) {
    final covers = tracks.take(4).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 84,
        height: 84,
        child: covers.isEmpty
            ? const ColoredBox(
                color: MaboyColors.surfaceHigh,
                child: Icon(Icons.queue_music, color: MaboyColors.textMuted),
              )
            : covers.length == 1
            ? TrackCover(controller: controller, track: covers.first, size: 84)
            : GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var index = 0; index < 4; index++)
                    index < covers.length
                        ? TrackCover(
                            controller: controller,
                            track: covers[index],
                            size: 42,
                            radius: 0,
                          )
                        : const ColoredBox(color: MaboyColors.surfaceHigh),
                ],
              ),
      ),
    );
  }
}

String _songsLabel(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'песен';
  if (mod10 == 1) return 'песня';
  if (mod10 >= 2 && mod10 <= 4) return 'песни';
  return 'песен';
}
