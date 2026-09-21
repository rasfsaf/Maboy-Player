import 'package:flutter/material.dart';

import 'app_controller.dart';

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

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    email.dispose(); password.dispose();
    super.dispose();
  }

  Future<void> addTrack() async {
    final link = TextEditingController();
    final title = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Добавить трек'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: link, decoration: const InputDecoration(labelText: 'Ссылка YouTube')),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Добавить'))],
    ));
    if (result == true) {
      final uri = Uri.tryParse(link.text.trim());
      final videoId = uri?.queryParameters['v'] ??
          ((uri?.host == 'youtu.be') ? uri?.pathSegments.firstOrNull : null);
      if (videoId == null || videoId.isEmpty || title.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите ссылку YouTube и название')));
        }
      } else {
        final existing = widget.controller.tracks.where((e) => e['provider'] == 'youtube' && e['source_id'] == videoId).firstOrNull;
        if (existing == null) {
          await widget.controller.mutate('track.upsert', {'id': newId(), 'provider': 'youtube',
            'source_id': videoId, 'title': title.text.trim(), 'artist': null});
        }
      }
    }
    link.dispose(); title.dispose();
  }

  Future<void> addPlaylist() async {
    final name = TextEditingController();
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Новый плейлист'),
      content: TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Создать'))],
    ));
    if (result == true && name.text.trim().isNotEmpty) {
      await widget.controller.mutate('playlist.upsert', {'id': newId(), 'name': name.text.trim(),
        'sort_key': widget.controller.playlists.length});
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (c.token == null) {
        return Scaffold(body: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('maboy', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12), const Text('Твоя музыка, твой порядок.'),
            const SizedBox(height: 36),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль (от 12 символов)')),
            const SizedBox(height: 20),
            FilledButton(onPressed: c.busy ? null : () => c.signIn(email.text, password.text), child: const Text('Войти')),
            TextButton(onPressed: c.busy ? null : () => c.signIn(email.text, password.text, register: true), child: const Text('Создать аккаунт')),
            if (c.error != null) Text(c.error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        )),
      )));
      }
      return Scaffold(
        appBar: AppBar(title: const Text('maboy'), actions: [
          if (c.busy) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(tooltip: 'Синхронизировать', onPressed: c.busy ? null : c.sync, icon: const Icon(Icons.sync)),
          IconButton(tooltip: 'Пробросить файлы сейчас', onPressed: c.transferNow, icon: const Icon(Icons.swap_horiz)),
          IconButton(tooltip: 'Выйти', onPressed: c.signOut, icon: const Icon(Icons.logout)),
        ]),
        body: Column(children: [
          if (c.error != null) MaterialBanner(content: Text(c.error!), actions: [TextButton(onPressed: c.sync, child: const Text('Повторить'))]),
          if (c.pending.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('Ожидают отправки: ${c.pending.length}')),
          if (c.transferStatus.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Text(c.transferStatus)),
          Expanded(child: [
            ListView(children: [
              ListTile(leading: const Icon(Icons.create_new_folder), title: const Text('Загрузить папку с музыкой'), onTap: () => c.importMusic(folder: true)),
              ListTile(leading: const Icon(Icons.audio_file), title: const Text('Загрузить песни'), onTap: c.importMusic),
              ...c.tracks.map((t) => ListTile(
              leading: const Icon(Icons.music_note), title: Text('${t['title']}'),
              subtitle: Text('${t['artist'] ?? (t['provider'] == 'local' ? (c.localFiles.containsKey(t['id']) ? 'На устройстве' : 'Ожидает проброса') : 'YouTube')}'),
              onTap: t['provider'] == 'local' ? () => c.playTrack(t) : null,
              trailing: IconButton(tooltip: 'В очередь', icon: const Icon(Icons.playlist_add), onPressed: () => c.mutate('queue.set', {
                'items': [...c.queue, {'id': newId(), 'track_id': t['id']}],
              })),
            ))]),
            ListView(children: c.playlists.map((p) => ExpansionTile(
              title: Text('${p['name']}'), children: [
                ...((p['track_ids'] as List?) ?? []).map((id) {
                  final track = c.tracks.where((t) => t['id'] == id).firstOrNull;
                  return ListTile(title: Text('${track?['title'] ?? id}'),
                    onTap: track?['provider'] == 'local' ? () => c.playTrack(track!, folderId: p['id'] as String) : null);
                }),
                PopupMenuButton<String>(onSelected: (id) => c.mutate('playlist.set_tracks', {
                  'playlist_id': p['id'], 'track_ids': [...(p['track_ids'] as List? ?? []), id],
                }), itemBuilder: (_) => c.tracks.where((t) => !(p['track_ids'] as List? ?? []).contains(t['id']))
                    .map((t) => PopupMenuItem(value: t['id'] as String, child: Text('${t['title']}'))).toList(), child: const ListTile(title: Text('Добавить трек'), leading: Icon(Icons.add))),
              ],
            )).toList()),
            ReorderableListView(onReorderItem: (from, to) {
              final items = List<Map<String, dynamic>>.from(c.queue);
              items.insert(to, items.removeAt(from));
              c.mutate('queue.set', {'items': items});
            }, children: c.queue.map((item) => ListTile(key: ValueKey(item['id']),
              leading: const Icon(Icons.drag_handle), title: Text('${c.tracks.where((t) => t['id'] == item['track_id']).firstOrNull?['title'] ?? 'Трек'}'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => c.mutate('queue.set', {
                'items': c.queue.where((q) => q['id'] != item['id']).toList(),
              })),
            )).toList()),
          ][page]),
        ]),
        floatingActionButton: page == 2 ? null : FloatingActionButton(
          onPressed: page == 0 ? addTrack : addPlaylist, child: const Icon(Icons.add)),
        bottomNavigationBar: NavigationBar(selectedIndex: page, onDestinationSelected: (value) => setState(() => page = value), destinations: const [
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Библиотека'),
          NavigationDestination(icon: Icon(Icons.album), label: 'Плейлисты'),
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Очередь'),
        ]),
      );
    },
  );
}