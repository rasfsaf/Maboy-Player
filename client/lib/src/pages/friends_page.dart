import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../design_system.dart';
import '../services/friends_service.dart';
import '../widgets/marquee_text.dart';
import '../widgets/track_tile.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _trackFilterController = TextEditingController();
  String _searchQuery = '';
  String _trackFilterQuery = '';
  FriendUser? _selectedFriendForTransfer;
  String? _statusMessage;
  Timer? _statusTimer;

  @override
  void dispose() {
    _statusTimer?.cancel();
    _searchController.dispose();
    _trackFilterController.dispose();
    super.dispose();
  }

  void _showInlineStatus(String message) {
    _statusTimer?.cancel();
    if (!mounted) return;
    setState(() => _statusMessage = message);
    _statusTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _statusMessage == message) {
        setState(() => _statusMessage = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final fs = c.friendsService;
    final myNick = c.userNickname;
    final friends = fs.friends;
    final pendingRequests = fs.pendingIncomingRequests;
    final pendingTransfers = fs.pendingIncomingTransfers;
    final receivedTransfers = fs.receivedCompletedTransfers;

    final trimmedSearch = _searchQuery.trim().toLowerCase();
    final isSearchingSelf = trimmedSearch == myNick.toLowerCase();
    final isAlreadyFriend = friends.any(
      (f) => f.nickname.toLowerCase() == trimmedSearch,
    );
    final isAlreadyRequested = fs.requests.any(
      (r) =>
          r.toNickname.toLowerCase() == trimmedSearch &&
          r.status == 'pending',
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MaboyBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile & Gateway Header
                    _buildProfileHeader(c, myNick),
                    const SizedBox(height: 16),

                    if (_statusMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: MaboyColors.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: MaboyColors.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: MaboyColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Search Users by Nick
                    _buildSearchCard(
                      trimmedSearch,
                      isSearchingSelf,
                      isAlreadyFriend,
                      isAlreadyRequested,
                      fs,
                    ),
                    const SizedBox(height: 16),

                    // Pending Confirmations Card (with Red Dot Badge)
                    if (pendingRequests.isNotEmpty || pendingTransfers.isNotEmpty) ...[
                      _buildPendingConfirmationsCard(
                        pendingRequests,
                        pendingTransfers,
                        fs,
                        c,
                      ),
                      const SizedBox(height: 16),
                    ],

                    // In-Page Track Picker (When transferring a track to a friend)
                    if (_selectedFriendForTransfer != null) ...[
                      _buildInPageTrackPicker(c, fs),
                      const SizedBox(height: 16),
                    ],

                    // Friends List
                    _buildFriendsList(friends, c),
                    const SizedBox(height: 20),

                    // Received Tracks History
                    if (receivedTransfers.isNotEmpty) ...[
                      _buildReceivedTracksSection(receivedTransfers, c),
                      const SizedBox(height: 20),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(AppController c, String myNick) => MaboyGlassPanel(
    padding: const EdgeInsets.all(18),
    child: Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: MaboyColors.primary.withValues(alpha: 0.25),
          child: Text(
            myNick.isNotEmpty ? myNick[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '@$myNick',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: MaboyColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Ваш ник',
                      style: TextStyle(
                        fontSize: 11,
                        color: MaboyColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                c.userEmail ?? 'Локальный режим (без аккаунта)',
                style: const TextStyle(
                  fontSize: 12,
                  color: MaboyColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (c.token != null)
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (c.token != null)
                  ? Colors.green.withValues(alpha: 0.6)
                  : Colors.amber.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: (c.token != null) ? Colors.green : Colors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                c.token != null ? 'Шлюз активен' : 'Локальный шлюз',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: c.token != null ? Colors.greenAccent : Colors.amberAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildSearchCard(
    String trimmedSearch,
    bool isSearchingSelf,
    bool isAlreadyFriend,
    bool isAlreadyRequested,
    FriendsService fs,
  ) => MaboyGlassPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Поиск людей по нику',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Ник формируется из email до знака @. Найдите человека и отправьте запрос в друзья.',
          style: TextStyle(fontSize: 12, color: MaboyColors.textMuted),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 20),
            hintText: 'Введите ник (например: alex или maria)',
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
          ),
        ),
        if (trimmedSearch.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: MaboyColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: MaboyColors.primary.withValues(alpha: 0.3),
                  child: Text(
                    trimmedSearch[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@$trimmedSearch',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        isSearchingSelf
                            ? 'Это вы'
                            : (isAlreadyFriend
                                  ? 'В вашем списке друзей'
                                  : (isAlreadyRequested
                                        ? 'Запрос уже отправлен'
                                        : 'Пользователь Maboy')),
                        style: const TextStyle(
                          fontSize: 12,
                          color: MaboyColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isSearchingSelf && !isAlreadyFriend && !isAlreadyRequested)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('В друзья'),
                    onPressed: () async {
                      final ok = await fs.sendFriendRequest(trimmedSearch);
                      if (ok) {
                        _showInlineStatus(
                          'Запрос в друзья отправлен @$trimmedSearch',
                        );
                      } else {
                        _showInlineStatus('Не удалось отправить запрос');
                      }
                    },
                  )
                else if (isAlreadyFriend)
                  const Chip(
                    avatar: Icon(Icons.check, size: 16, color: Colors.green),
                    label: Text('В друзьях'),
                  )
                else if (isAlreadyRequested)
                  const Chip(
                    avatar: Icon(Icons.schedule, size: 16),
                    label: Text('Запрос отправлен'),
                  ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildPendingConfirmationsCard(
    List<FriendRequest> pendingRequests,
    List<TrackTransfer> pendingTransfers,
    FriendsService fs,
    AppController c,
  ) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Colors.redAccent.withValues(alpha: 0.7),
        width: 1.5,
      ),
      color: Colors.redAccent.withValues(alpha: 0.08),
    ),
    child: MaboyGlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent,
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Требуется ваше подтверждение',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Friend requests
          for (final req in pendingRequests) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MaboyColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_add, color: MaboyColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Запрос в друзья от @${req.fromNickname}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await fs.acceptFriendRequest(req.id);
                      _showInlineStatus(
                        'Вы приняли запрос в друзья от @${req.fromNickname}',
                      );
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Принять'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await fs.declineFriendRequest(req.id);
                      _showInlineStatus(
                        'Запрос от @${req.fromNickname} отклонен',
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Отклонить'),
                  ),
                ],
              ),
            ),
          ],

          // Track transfer proposals (Permission required!)
          for (final transfer in pendingTransfers) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MaboyColors.surfaceHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: MaboyColors.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.music_note, color: MaboyColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '@${transfer.fromNickname} хочет передать вам трек по шлюзу:',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: MaboyColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      TrackCover(
                        controller: c,
                        track: transfer.track,
                        size: 48,
                        radius: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${transfer.track['title'] ?? 'Без названия'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${transfer.track['artist'] ?? 'Неизвестный исполнитель'}',
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Отклонить'),
                        onPressed: () async {
                          await fs.declineTrackTransfer(transfer.id);
                          _showInlineStatus(
                            'Передача трека «${transfer.track['title']}» отклонена',
                          );
                        },
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text('Разрешить и получить'),
                        onPressed: () async {
                          await fs.acceptTrackTransfer(transfer.id);
                          _showInlineStatus(
                            'Трек «${transfer.track['title']}» получен и добавлен в библиотеку!',
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _buildFriendsList(List<FriendUser> friends, AppController c) => MaboyGlassPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Твои друзья (${friends.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.people, color: MaboyColors.textMuted, size: 20),
          ],
        ),
        const SizedBox(height: 12),
        if (friends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'У вас пока нет друзей.\nНайдите друга по нику выше, чтобы отправлять друг другу треки по шлюзу.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MaboyColors.textMuted, height: 1.5),
            ),
          )
        else
          for (final friend in friends) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: MaboyColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: MaboyColors.primary.withValues(alpha: 0.25),
                    child: Text(
                      friend.nickname.isNotEmpty
                          ? friend.nickname[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${friend.nickname}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'В сети • Шлюз готов',
                              style: TextStyle(
                                fontSize: 11,
                                color: MaboyColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Отправить трек'),
                    onPressed: () {
                      setState(() {
                        _selectedFriendForTransfer = friend;
                        _trackFilterQuery = '';
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
      ],
    ),
  );

  Widget _buildInPageTrackPicker(AppController c, FriendsService fs) {
    final friend = _selectedFriendForTransfer!;
    final normalizedFilter = _trackFilterQuery.trim().toLowerCase();
    final availableTracks = c.tracks.where((t) {
      if (normalizedFilter.isEmpty) return true;
      final title = '${t['title'] ?? ''}'.toLowerCase();
      final artist = '${t['artist'] ?? ''}'.toLowerCase();
      return title.contains(normalizedFilter) || artist.contains(normalizedFilter);
    }).toList();

    final playingTrack = c.playingTrack;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MaboyColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MaboyColors.primary.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.send_rounded, color: MaboyColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Передача трека для @${friend.nickname}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть выбор трека',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _selectedFriendForTransfer = null),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Shortcut: Send currently playing track
          if (playingTrack != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MaboyColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  TrackCover(
                    controller: c,
                    track: playingTrack,
                    size: 40,
                    radius: 6,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'СЕЙЧАС ИГРАЕТ',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: MaboyColors.primary,
                          ),
                        ),
                        Text(
                          '${playingTrack['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      await fs.proposeTrackToFriend(
                        toNickname: friend.nickname,
                        track: playingTrack,
                      );
                      setState(() => _selectedFriendForTransfer = null);
                      _showInlineStatus(
                        'Запрос на передачу «${playingTrack['title']}» отправлен @${friend.nickname}. Ожидается разрешение.',
                      );
                    },
                    child: const Text('Отправить'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _trackFilterController,
            onChanged: (val) => setState(() => _trackFilterQuery = val),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Поиск по вашей библиотеке...',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),

          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: availableTracks.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Нет треков для передачи',
                        style: TextStyle(color: MaboyColors.textMuted),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableTracks.length > 50 ? 50 : availableTracks.length,
                    itemBuilder: (context, index) {
                      final track = availableTracks[index];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: TrackCover(
                          controller: c,
                          track: track,
                          size: 38,
                          radius: 5,
                        ),
                        title: MarqueeText('${track['title'] ?? 'Трек'}'),
                        subtitle: Text(
                          '${track['artist'] ?? 'Неизвестный исполнитель'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MaboyColors.textMuted,
                          ),
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            await fs.proposeTrackToFriend(
                              toNickname: friend.nickname,
                              track: track,
                            );
                            setState(() => _selectedFriendForTransfer = null);
                            _showInlineStatus(
                              'Запрос на передачу «${track['title']}» отправлен @${friend.nickname}. Ожидается разрешение.',
                            );
                          },
                          child: const Text('Отправить'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedTracksSection(
    List<TrackTransfer> receivedTransfers,
    AppController c,
  ) => MaboyGlassPanel(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Полученные треки по шлюзу',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final item in receivedTransfers.reversed.take(10)) ...[
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: TrackCover(
              controller: c,
              track: item.track,
              size: 40,
              radius: 6,
            ),
            title: Text(
              '${item.track['title'] ?? 'Трек'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'От @${item.fromNickname} • ${item.track['artist'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: MaboyColors.textMuted),
            ),
            trailing: IconButton(
              tooltip: 'Воспроизвести',
              icon: const Icon(Icons.play_circle_fill, color: MaboyColors.primary),
              onPressed: () => c.playTrack(item.track),
            ),
          ),
        ],
      ],
    ),
  );
}
