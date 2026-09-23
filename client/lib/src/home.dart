import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'app_controller.dart';
import 'design_system.dart';
import 'pages/equalizer_page.dart';
import 'pages/playlist_detail_page.dart';
import 'pages/secondary_pages.dart';
import 'widgets/marquee_text.dart';
import 'widgets/player_sheet.dart';
import 'widgets/track_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int page = 0;
  final email = TextEditingController();
  final password = TextEditingController();
  final Set<String> _selectedTrackIds = {};

  bool get _isSelecting => _selectedTrackIds.isNotEmpty;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

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

  Future<void> addTrack() async {
    final link = TextEditingController();
    final title = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить трек'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: link,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Ссылка YouTube',
                hintText: 'https://youtube.com/watch?v=...',
              ),
            ),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'Название (опционально)',
                hintText: 'Определится автоматически',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    if (result == true && link.text.trim().isNotEmpty) {
      final addedId = await widget.controller.addYouTubeTrack(
        link.text.trim(),
        customTitle: title.text.trim().isEmpty ? null : title.text.trim(),
      );
      if (addedId == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверная ссылка YouTube')),
        );
      }
    }
    link.dispose();
    title.dispose();
  }

  Future<void> addPlaylist() async {
    final name = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый плейлист'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      await widget.controller.mutate('playlist.upsert', {
        'id': newId(),
        'name': name.text.trim(),
        'sort_key': widget.controller.playlists.length,
      });
    }
    name.dispose();
  }

  Future<void> renamePlaylist(Map<String, dynamic> playlist) async {
    final name = TextEditingController(text: '${playlist['name']}');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать плейлист'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (accepted == true && name.text.trim().isNotEmpty) {
      await widget.controller.renamePlaylist(playlist, name.text.trim());
    }
    name.dispose();
  }

  Future<void> deletePlaylist(Map<String, dynamic> playlist) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить плейлист?'),
        content: Text(
          '«${playlist['name']}» будет удалён на всех устройствах.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.controller.deletePlaylist(playlist['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final isDesktop = MediaQuery.sizeOf(context).width >= 760;
      if (c.token == null) {
        return Scaffold(
          body: MaboyBackdrop(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const MaboyBrand(size: 52),
                        const SizedBox(height: 10),
                        const Text(
                          'Вся твоя музыка. На каждом устройстве.',
                          style: TextStyle(color: MaboyColors.textMuted),
                        ),
                        const SizedBox(height: 32),
                        TextField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.alternate_email),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Пароль (от 12 символов)',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: c.busy
                              ? null
                              : () => c.signIn(email.text, password.text),
                          child: const Text('Войти'),
                        ),
                        TextButton(
                          onPressed: c.busy
                              ? null
                              : () => c.signIn(
                                  email.text,
                                  password.text,
                                  register: true,
                                ),
                          child: const Text('Создать аккаунт'),
                        ),
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              friendlyErrorMessage(c.error!),
                              style: const TextStyle(
                                color: MaboyColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

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
                      () => _selectedTrackIds.addAll(
                        c.tracks.map((t) => t['id'] as String),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Добавить в плейлист',
                    onPressed: () async {
                      final ids = _selectedTrackIds.toList();
                      await showAddToPlaylistDialog(context, c, ids);
                    },
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
                title: const MaboyBrand(),
                centerTitle: false,
                actions: [
                  if (c.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (page == 0 || page == 1)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      tooltip: page == 0
                          ? 'Добавить трек (YouTube)'
                          : 'Новый плейлист',
                      onPressed: page == 0 ? addTrack : addPlaylist,
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Меню',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (action) {
                      if (action == 'search') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SearchPage(controller: c),
                          ),
                        );
                      } else if (action == 'favorites') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => FavoritesPage(controller: c),
                          ),
                        );
                      } else if (action == 'history') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HistoryPage(controller: c),
                          ),
                        );
                      } else if (action == 'equalizer') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EqualizerPage(controller: c),
                          ),
                        );
                      } else if (action == 'scan') {
                        c.scanAndImportDeviceMusic(manual: true);
                      } else if (action == 'sync') {
                        c.transferNow();
                      } else if (action == 'transfer') {
                        c.transferNow();
                      } else if (action == 'logout') {
                        c.signOut();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'search',
                        child: Row(
                          children: [
                            Icon(Icons.search),
                            SizedBox(width: 12),
                            Text('Поиск'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'favorites',
                        child: Row(
                          children: [
                            Icon(Icons.favorite_border),
                            SizedBox(width: 12),
                            Text('Избранное'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'history',
                        child: Row(
                          children: [
                            Icon(Icons.history),
                            SizedBox(width: 12),
                            Text('История'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'equalizer',
                        child: Row(
                          children: [
                            Icon(Icons.tune),
                            SizedBox(width: 12),
                            Text('Эквалайзер'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'scan',
                        child: Row(
                          children: [
                            Icon(Icons.snippet_folder_outlined),
                            SizedBox(width: 12),
                            Text('Сканировать музыку устройства'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'sync',
                        child: Row(
                          children: [
                            Icon(Icons.sync),
                            SizedBox(width: 12),
                            Text('Синхронизировать'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'transfer',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz),
                            SizedBox(width: 12),
                            Text('Пробросить файлы'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(
                          children: [
                            Icon(Icons.logout, color: Colors.redAccent),
                            SizedBox(width: 12),
                            Text(
                              'Выйти',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: MaboyBackdrop(
          child: Row(
            children: [
              if (isDesktop)
                _DesktopSideNav(
                  controller: c,
                  selectedPage: page,
                  onSelect: (value) {
                    _clearSelection();
                    setState(() => page = value);
                  },
                  onAddPlaylist: addPlaylist,
                ),
              Expanded(
                child: Column(
                  children: [
                    // Все условные виджеты обёрнуты в AnimatedSize, чтобы их
                    // появление/исчезновение не прыгало — плавное изменение высоты
                    // не заставляет Expanded+CustomScrollView пересчитывать layout резко.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: c.error != null
                          ? MaterialBanner(
                              content: Text(friendlyErrorMessage(c.error!)),
                              actions: [
                                TextButton(
                                  onPressed: c.sync,
                                  child: const Text('Повторить'),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: c.pending.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Ожидают отправки: ${c.pending.length}',
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      // Ключевой фикс: длинный transferStatus (название трека)
                      // плавно раздвигает список вместо резкого скачка вниз.
                      child: c.transferStatus.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              child: Text(
                                c.transferStatus,
                                style: const TextStyle(
                                  color: MaboyColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      child: [
                        // PAGE 0: LIBRARY
                        CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _QuickActionCard(
                                        icon: Icons.create_new_folder_outlined,
                                        label: 'Папка',
                                        onTap: () =>
                                            c.importMusic(folder: true),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _QuickActionCard(
                                        icon: Icons.audio_file_outlined,
                                        label: 'Аудиофайлы',
                                        onTap: c.importMusic,
                                      ),
                                    ),
                                    if (c.tracks.isNotEmpty) ...[
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _QuickActionCard(
                                          icon: Icons.shuffle,
                                          label: 'Микс',
                                          accent: true,
                                          onTap: c.startShuffle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (c.tracks.isNotEmpty) ...[
                              if (c.recentlyPlayed.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _TrackRail(
                                    title: 'Недавно слушали',
                                    tracks: c.recentlyPlayed,
                                    controller: c,
                                    onSeeAll: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              HistoryPage(controller: c),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (c.favoriteIds.isNotEmpty)
                                SliverToBoxAdapter(
                                  child: _TrackRail(
                                    title: 'Избранное',
                                    tracks: c.tracks
                                        .where(
                                          (track) => c.favoriteIds.contains(
                                            '${track['id']}',
                                          ),
                                        )
                                        .toList(),
                                    controller: c,
                                    onSeeAll: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              FavoritesPage(controller: c),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                            if (c.tracks.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    14,
                                    18,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Все треки',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '${c.tracks.length}',
                                        style: const TextStyle(
                                          color: MaboyColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            if (c.tracks.isEmpty)
                              const SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text('В библиотеке пока нет треков'),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                                sliver: SliverReorderableList(
                                  proxyDecorator: maboyReorderProxyDecorator,
                                  itemCount: c.tracks.length,
                                  onReorderStart: (_) => c.beginReorder(),
                                  onReorderEnd: (_) => c.endReorder(),
                                  onReorder: c.reorderTracks,
                                  itemBuilder: (context, index) {
                                    final track = c.tracks[index];
                                    final id = track['id'] as String;
                                    return TrackTile(
                                      key: ValueKey(id),
                                      controller: c,
                                      track: track,
                                      dragIndex: index,
                                      isSelected: _selectedTrackIds.contains(
                                        id,
                                      ),
                                      isSelecting: _isSelecting,
                                      onSelect: () => _toggleSelect(id),
                                      onLongPress: () {
                                        if (!_isSelecting) {
                                          _toggleSelect(id);
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),

                        // PAGE 1: PLAYLISTS
                        c.playlists.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.album_outlined,
                                      size: 56,
                                      color: MaboyColors.textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text('Плейлистов пока нет'),
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: addPlaylist,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Создать плейлист'),
                                    ),
                                  ],
                                ),
                              )
                            : ReorderableListView.builder(
                                proxyDecorator: maboyReorderProxyDecorator,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                itemCount: c.playlists.length,
                                onReorder: c.reorderPlaylists,
                                itemBuilder: (context, index) {
                                  final p = c.playlists[index];
                                  final trackCount =
                                      (p['track_ids'] as List?)?.length ?? 0;
                                  return Card(
                                    key: ValueKey(p['id']),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: MaboyColors.primary.withValues(
                                            alpha: 0.16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.queue_music,
                                          color: MaboyColors.primary,
                                        ),
                                      ),
                                      title: Text(
                                        '${p['name']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Text('$trackCount треков'),
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => PlaylistDetailPage(
                                            controller: c,
                                            playlist: p,
                                          ),
                                        ),
                                      ),
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (action) {
                                          if (action == 'rename') {
                                            renamePlaylist(p);
                                          }
                                          if (action == 'delete') {
                                            deletePlaylist(p);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'rename',
                                            child: Text('Переименовать'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text(
                                              'Удалить',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                        // PAGE 2: QUEUE
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.shuffle),
                                  tooltip: 'Перемешать',
                                  onPressed: c.queue.length > 1
                                      ? c.shuffleQueue
                                      : null,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.clear_all),
                                  tooltip: 'Очистить очередь',
                                  onPressed: c.queue.isNotEmpty
                                      ? () => c.setQueue([])
                                      : null,
                                ),
                              ],
                            ),
                            Expanded(
                              child: c.queue.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'Очередь воспроизведения пуста',
                                      ),
                                    )
                                  : ReorderableListView(
                                      proxyDecorator:
                                          maboyReorderProxyDecorator,
                                      buildDefaultDragHandles: false,
                                      onReorder: (from, to) {
                                        if (to > from) to--;
                                        final items =
                                            List<Map<String, dynamic>>.from(
                                              c.queue,
                                            );
                                        items.insert(to, items.removeAt(from));
                                        c.setQueue(items);
                                      },
                                      children: c.queue.asMap().entries.map((
                                        entry,
                                      ) {
                                        final index = entry.key;
                                        final item = entry.value;
                                        final track = c.tracks
                                            .where(
                                              (entry) =>
                                                  entry['id'] ==
                                                  item['track_id'],
                                            )
                                            .firstOrNull;
                                        return ReorderableDelayedDragStartListener(
                                          key: ValueKey(item['id']),
                                          index: index,
                                          child: ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                ),
                                            leading: TrackCover(
                                              controller: c,
                                              track: track ?? const {},
                                              size: 44,
                                              radius: 6,
                                            ),
                                            title: MarqueeText(
                                              '${track?['title'] ?? 'Трек'}',
                                            ),
                                            subtitle: Text(
                                              '${track?['artist'] ?? ''}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: MaboyColors.textMuted,
                                                fontSize: 12,
                                              ),
                                            ),
                                            onTap: () => c.playQueueItem(item),
                                            trailing: IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () => c.setQueue(
                                                c.queue.where(
                                                  (q) => q['id'] != item['id'],
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ],
                        ),
                      ][page],
                    ),
                    // MiniPlayer тоже в AnimatedSize — чтобы список не прыгал
                    // при начале/завершении воспроизведения.
                    if (!isDesktop)
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.bottomCenter,
                        child: c.playingTrack != null
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                                child: MiniPlayer(controller: c),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: isDesktop
            ? (c.playingTrack == null ? null : MiniPlayer(controller: c))
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: (value) {
                  _clearSelection();
                  setState(() => page = value);
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.library_music_outlined),
                    selectedIcon: Icon(Icons.library_music),
                    label: 'Библиотека',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.album_outlined),
                    selectedIcon: Icon(Icons.album),
                    label: 'Плейлисты',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.queue_music_outlined),
                    selectedIcon: Icon(Icons.queue_music),
                    label: 'Очередь',
                  ),
                ],
              ),
      );
    },
  );
}

/// The desktop library stays visible while the bottom player spans the window.
class _DesktopSideNav extends StatelessWidget {
  const _DesktopSideNav({
    required this.controller,
    required this.selectedPage,
    required this.onSelect,
    required this.onAddPlaylist,
  });

  final AppController controller;
  final int selectedPage;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddPlaylist;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 222,
    child: MaboyGlassPanel(
      radius: 0,
      opacity: 0.84,
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 18),
            child: Text(
              'ТВОЯ МУЗЫКА',
              style: TextStyle(
                color: MaboyColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          _SideNavButton(
            icon: Icons.library_music_outlined,
            label: 'Библиотека',
            selected: selectedPage == 0,
            onTap: () => onSelect(0),
          ),
          _SideNavButton(
            icon: Icons.album_outlined,
            label: 'Плейлисты',
            selected: selectedPage == 1,
            onTap: () => onSelect(1),
          ),
          _SideNavButton(
            icon: Icons.queue_music_outlined,
            label: 'Очередь',
            selected: selectedPage == 2,
            onTap: () => onSelect(2),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 3, bottom: 7),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ПЛЕЙЛИСТЫ',
                    style: TextStyle(
                      color: MaboyColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Новый плейлист',
                  onPressed: onAddPlaylist,
                  icon: const Icon(Icons.add, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: controller.playlists.length,
              itemBuilder: (context, index) {
                final playlist = controller.playlists[index];
                return _SideNavButton(
                  icon: Icons.music_note_outlined,
                  label: '${playlist['name']}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailPage(
                        controller: controller,
                        playlist: playlist,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 20),
          _SideNavButton(
            icon: Icons.search,
            label: 'Поиск',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SearchPage(controller: controller),
              ),
            ),
          ),
          _SideNavButton(
            icon: Icons.favorite_border,
            label: 'Избранное',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FavoritesPage(controller: controller),
              ),
            ),
          ),
          _SideNavButton(
            icon: Icons.history,
            label: 'История',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HistoryPage(controller: controller),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SideNavButton extends StatelessWidget {
  const _SideNavButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? MaboyColors.primary.withValues(alpha: 0.15)
        : Colors.transparent,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? MaboyColors.primary : MaboyColors.textMuted,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TrackRail extends StatefulWidget {
  const _TrackRail({
    required this.title,
    required this.tracks,
    required this.controller,
    this.onSeeAll,
  });

  final String title;
  final List<Map<String, dynamic>> tracks;
  final AppController controller;
  final VoidCallback? onSeeAll;

  @override
  State<_TrackRail> createState() => _TrackRailState();
}

class _TrackRailState extends State<_TrackRail> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final newOffset = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      newOffset,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
          child: Row(
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${widget.tracks.length}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: MaboyColors.textMuted,
                ),
              ),
              const Spacer(),
              if (widget.onSeeAll != null)
                TextButton.icon(
                  onPressed: widget.onSeeAll,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_ios, size: 11),
                  label: const Text('Все'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: MaboyColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.arrow_back_ios_new),
                tooltip: 'Назад',
                onPressed: () => _scrollBy(-260),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.arrow_forward_ios),
                tooltip: 'Вперед',
                onPressed: () => _scrollBy(260),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 172,
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                final double delta = event.scrollDelta.dy != 0
                    ? event.scrollDelta.dy
                    : event.scrollDelta.dx;
                if (delta != 0 && _scrollController.hasClients) {
                  final double newOffset = (_scrollController.offset + delta)
                      .clamp(0.0, _scrollController.position.maxScrollExtent);
                  _scrollController.jumpTo(newOffset);
                }
              }
            },
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              child: ListView.separated(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: widget.tracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final track = widget.tracks[index];
                  final playing =
                      widget.controller.playingTrack?['id'] == track['id'];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => widget.controller.playTrack(track),
                    child: SizedBox(
                      width: 118,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TrackCover(
                            controller: widget.controller,
                            track: track,
                            size: 118,
                            radius: 8,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${track['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: playing ? MaboyColors.primary : null,
                            ),
                          ),
                          Text(
                            '${track['artist'] ?? 'Неизвестный'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: MaboyColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => MaboyGlassPanel(
    radius: 14,
    opacity: accent ? 0.88 : 0.66,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            children: [
              Icon(
                icon,
                color: accent ? MaboyColors.primary : MaboyColors.secondary,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
