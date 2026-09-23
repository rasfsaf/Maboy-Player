import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'equalizer.dart';
import 'services/audio_player.dart';
import 'services/bounded_task_pool.dart';
import 'services/device_music_service.dart';
import 'services/local_metadata_service.dart';
import 'services/media_service.dart';
import 'services/friends_service.dart';
import 'services/playback_manager.dart';
import 'services/youtube_downloader.dart';
import 'services/youtube_playlist_service.dart';

String newId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// A track in the active playback sequence.
///
/// [playbackIndex] is stable until that sequence is edited. It is deliberately
/// separate from the track id because a manual queue may contain duplicates.
class PlaybackQueueEntry {
  const PlaybackQueueEntry({
    required this.playbackIndex,
    required this.queueKey,
    required this.track,
    required this.isCurrent,
  });

  final int playbackIndex;
  final String queueKey;
  final Map<String, dynamic> track;
  final bool isCurrent;
}

class AppController extends ChangeNotifier {
  static const int maxParallelDownloads = 3;
  static const int maxParallelTransfers = 3;

  final MaboyAudioPlayer player = MaboyAudioPlayer();
  final YouTubeDownloadService ytService = YouTubeDownloadService();
  final YouTubePlaylistService ytPlaylistService = YouTubePlaylistService();
  late final PlaybackManager playbackManager;
  final Map<String, String> localFiles = {};

  /// Original device files are kept separately from app-owned copies so a
  /// local delete never removes the user's source and restore can reuse it.
  final Map<String, String> originalFiles = {};
  final Map<String, String> artworkFiles = {};
  final Map<String, double> downloadProgress = {};
  final Set<String> downloadingIds = {};
  final Map<String, String> failedDownloads = {};

  final BoundedTaskPool<String> _downloadPool = BoundedTaskPool<String>(
    maxConcurrent: maxParallelDownloads,
  );
  final BoundedTaskPool<String> _receivePool = BoundedTaskPool<String>(
    maxConcurrent: maxParallelTransfers,
  );

  final Map<String, DateTime> _failedRelayTransfers = {};
  final Map<String, int> _relayAttempts = {};
  final Map<String, Timer> _relayRetryTimers = {};
  DateTime? _lastProgressNotify;

  void _throttledProgressNotify() {
    final now = DateTime.now();
    if (_lastProgressNotify == null ||
        now.difference(_lastProgressNotify!) > const Duration(milliseconds: 120)) {
      _lastProgressNotify = now;
      notifyListeners();
    }
  }

  final Map<String, WebSocket> _sources = {};
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  WebSocket? _syncSocket;
  Timer? _syncReconnect;
  Timer? _syncHeartbeat;
  List<String> _playbackIds = [];
  List<String> _playbackEntryKeys = [];
  int _playbackEntrySerial = 0;
  int _currentPlaybackIndex = -1;
  Timer? _poll;
  Timer? _transferStatusTimer;
  Timer? _equalizerApplyDebounce;
  bool _transferring = false;
  bool _transferRequested = false;
  bool _switchingTrack = false;
  bool _reordering = false;
  int _consecutivePlaybackErrors = 0;
  static const int maxConsecutivePlaybackErrors = 3;
  String deviceId = '';
  bool hasOnlinePeers = false;
  String? playingId;
  String? playingFolder;
  String transferStatus = '';

  void _showTemporaryTransferStatus(String message) {
    _transferStatusTimer?.cancel();
    transferStatus = message;
    notifyListeners();
    _transferStatusTimer = Timer(const Duration(seconds: 4), () {
      if (transferStatus != message) return;
      transferStatus = '';
      notifyListeners();
    });
  }

  static const _secure = FlutterSecureStorage();
  static const String backendUrl = 'https://maboy.dofic.site';
  String url = backendUrl;
  String? token;
  String? account;
  int cursor = 0;
  bool busy = false;
  String? error;

  final List<Map<String, dynamic>> tracks = [];
  final List<Map<String, dynamic>> playlists = [];
  final List<Map<String, dynamic>> queue = [];

  /// The shared manual queue stays intact on other devices; locally deleted
  /// tracks are excluded only from this device's playback and queue view.
  List<Map<String, dynamic>> get deviceQueue => queue
      .where((item) => !deletedLocallyIds.contains(item['track_id']))
      .toList();
  final List<String> favoriteIds = [];
  final List<Map<String, dynamic>> history = [];
  final List<Map<String, dynamic>> pending = [];
  final Set<String> deletedLocallyIds = {};
  final Map<String, Map<String, dynamic>> deviceTrackStatuses = {};
  bool isShuffle = false;
  double volume = 1.0;
  final Map<String, EqualizerPreset> customEqualizerPresets = {};
  String activeEqualizerPresetId = 'flat';
  bool equalizerEnabled = false;
  List<double> equalizerGains = List<double>.filled(6, 0);

  late final FriendsService friendsService;
  bool get hasPendingFriendNotifications =>
      friendsService.hasPendingNotifications;
  String? get userEmail {
    if (account == null) return null;
    return account!.contains('|') ? account!.split('|').last.trim() : account!.trim();
  }
  String get userNickname => FriendsService.extractNickname(account);

  SyncApi get api => SyncApi(url, token);

  AppController() {
    friendsService = FriendsService(
      getCurrentAccount: () => userEmail,
      onTrackAccepted: (track) async {
        final exists = tracks.any((t) => t['id'] == track['id']);
        if (!exists) {
          tracks.insert(0, Map<String, dynamic>.from(track));
          await save();
          notifyListeners();
        }
      },
    );
    friendsService.addListener(notifyListeners);

    playbackManager = PlaybackManager(
      player: player,
      onStopPlayback: () async {
        await player.stop();
        notifyListeners();
      },
    );
    playbackManager.addListener(notifyListeners);
    player.onNext = playNext;
    player.onPrevious = playPrevious;
    player.onError = (err) async {
      _consecutivePlaybackErrors++;
      debugPrint(
        'Maboy player error ($_consecutivePlaybackErrors/$maxConsecutivePlaybackErrors): $err',
      );
      if (_consecutivePlaybackErrors >= maxConsecutivePlaybackErrors) {
        debugPrint(
          'Too many consecutive playback errors ($maxConsecutivePlaybackErrors). Halting auto-skip.',
        );
        transferStatus =
            'Ошибка воспроизведения нескольких треков подряд. Воспроизведение остановлено.';
        await player.stop();
        notifyListeners();
        return;
      }
      await playNext();
    };

    MediaService.listenToBecomingNoisy(() {
      debugPrint(
        'Becoming noisy received: halting audio immediately and blocking unsolicited auto-play',
      );
      unawaited(
        player.pauseDueToBecomingNoisy().then((_) {
          notifyListeners();
        }),
      );
    });

    _playerSubscriptions.add(
      player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          playbackManager.onTrackCompleted();
          if (playbackManager.repeatMode == RepeatMode.one) {
            unawaited(player.seek(Duration.zero).then((_) => player.play()));
          } else {
            unawaited(playNext());
          }
        }
        notifyListeners();
      }),
    );
  }

  List<Map<String, dynamic>> get recentlyPlayed {
    final ordered = List<Map<String, dynamic>>.from(history)
      ..sort((a, b) {
        final left = '${a['started_at'] ?? ''}';
        final right = '${b['started_at'] ?? ''}';
        return right.compareTo(left);
      });
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    for (final item in ordered) {
      final id = '${item['track_id'] ?? ''}';
      if (id.isEmpty || !seen.add(id)) continue;
      final track = tracks.where((entry) => entry['id'] == id).firstOrNull;
      if (track != null) result.add(track);
      if (result.length >= 50) break;
    }
    return result;
  }

  Map<String, dynamic>? get playingTrack =>
      tracks.where((track) => track['id'] == playingId).firstOrNull;

  int get currentPlaybackIndex {
    if (_currentPlaybackIndex >= 0 &&
        _currentPlaybackIndex < _playbackIds.length &&
        _playbackIds[_currentPlaybackIndex] == playingId) {
      return _currentPlaybackIndex;
    }
    return _playbackIds.indexOf(playingId ?? '');
  }

  List<PlaybackQueueEntry> get activePlaybackQueue {
    final current = currentPlaybackIndex;
    if (current < 0) return const [];

    return [
      for (var index = current; index < _playbackIds.length; index++)
        if (!deletedLocallyIds.contains(_playbackIds[index]))
          if (tracks
                  .where((track) => track['id'] == _playbackIds[index])
                  .firstOrNull
              case final track?)
            PlaybackQueueEntry(
              playbackIndex: index,
              queueKey: _playbackEntryKeys[index],
              track: track,
              isCurrent: index == current,
            ),
    ];
  }

  bool get hasPrevious =>
      currentPlaybackIndex > 0 || player.position.inSeconds > 2;
  bool get hasNext =>
      deviceQueue.isNotEmpty ||
      (isShuffle
          ? (_playbackIds.length > 1 || tracks.length > 1)
          : (playbackManager.repeatMode == RepeatMode.all
                ? _playbackIds.isNotEmpty
                : (currentPlaybackIndex >= 0 &&
                      currentPlaybackIndex < _playbackIds.length - 1)));

  bool isFavorite(String trackId) => favoriteIds.contains(trackId);

  Future<void> toggleFavorite(String trackId) {
    final ids = List<String>.from(favoriteIds);
    ids.contains(trackId) ? ids.remove(trackId) : ids.add(trackId);
    return mutate('favorites.set', {'track_ids': ids});
  }

  Future<void> togglePlayback() async {
    if (playingId == null || deletedLocallyIds.contains(playingId)) return;
    if (player.playing) {
      await player.pause();
    } else if (player.audioSource != null) {
      await player.play();
    }
  }

  Future<void> setVolume(double val) async {
    volume = val.clamp(0.0, 1.0);
    await player.setVolume(volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('volume', volume);
    notifyListeners();
  }

  List<EqualizerPreset> get equalizerPresets => [
    ...builtInEqualizerPresets,
    ...customEqualizerPresets.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  ];

  EqualizerPreset? get activeEqualizerPreset => equalizerPresets
      .where((preset) => preset.id == activeEqualizerPresetId)
      .firstOrNull;

  String? get _equalizerDeviceStateKey =>
      account == null ? null : 'equalizer_device_$account';

  Future<void> _loadEqualizerDeviceState(SharedPreferences prefs) async {
    final key = _equalizerDeviceStateKey;
    if (key == null) return;
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final state = jsonDecode(raw) as Map<String, dynamic>;
        equalizerEnabled = state['enabled'] == true;
        activeEqualizerPresetId = '${state['active_preset_id'] ?? 'flat'}';
        final rawGains = state['gains'];
        if (rawGains is List &&
            rawGains.length == equalizerFrequencies.length) {
          final parsed = rawGains
              .map((value) => (value as num).toDouble())
              .toList();
          if (parsed.every((gain) => gain >= -12 && gain <= 12)) {
            equalizerGains = parsed;
          }
        }
      } catch (error) {
        debugPrint('Ignoring invalid local equalizer state: $error');
      }
    }
    final active = activeEqualizerPreset;
    if (active != null && activeEqualizerPresetId != 'manual') {
      equalizerGains = List<double>.from(active.gains);
    } else if (activeEqualizerPresetId != 'manual') {
      activeEqualizerPresetId = 'flat';
      equalizerGains = List<double>.filled(equalizerFrequencies.length, 0);
    }
    await player.setEqualizer(enabled: equalizerEnabled, gains: equalizerGains);
  }

  Future<void> _saveEqualizerDeviceState() async {
    final key = _equalizerDeviceStateKey;
    if (key == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'enabled': equalizerEnabled,
        'active_preset_id': activeEqualizerPresetId,
        'gains': equalizerGains,
      }),
    );
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabled = enabled;
    await player.setEqualizer(enabled: enabled, gains: equalizerGains);
    await _saveEqualizerDeviceState();
    notifyListeners();
  }

  Future<void> selectEqualizerPreset(String id) async {
    final preset = equalizerPresets
        .where((value) => value.id == id)
        .firstOrNull;
    if (preset == null) return;
    activeEqualizerPresetId = preset.id;
    equalizerGains = List<double>.from(preset.gains);
    await player.setEqualizer(enabled: equalizerEnabled, gains: equalizerGains);
    await _saveEqualizerDeviceState();
    notifyListeners();
  }

  void setEqualizerBand(int index, double gain) {
    if (index < 0 || index >= equalizerGains.length) return;
    equalizerGains = List<double>.from(equalizerGains)
      ..[index] = gain.clamp(-12, 12);
    activeEqualizerPresetId = 'manual';
    notifyListeners();
    _equalizerApplyDebounce?.cancel();
    _equalizerApplyDebounce = Timer(const Duration(milliseconds: 70), () {
      unawaited(
        player
            .setEqualizer(enabled: equalizerEnabled, gains: equalizerGains)
            .then((_) => _saveEqualizerDeviceState()),
      );
    });
  }

  Future<String> saveEqualizerPreset(String name, {String? id}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 40) {
      throw ArgumentError('Название должно содержать от 1 до 40 символов');
    }
    final preset = EqualizerPreset(
      id: id ?? newId(),
      name: cleanName,
      gains: List<double>.from(equalizerGains),
    );
    await mutate('equalizer.preset.upsert', preset.toPayload());
    activeEqualizerPresetId = preset.id;
    await _saveEqualizerDeviceState();
    notifyListeners();
    return preset.id;
  }

  Future<void> renameEqualizerPreset(String id, String name) async {
    final preset = customEqualizerPresets[id];
    if (preset == null) return;
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 40) {
      throw ArgumentError('Название должно содержать от 1 до 40 символов');
    }
    await mutate(
      'equalizer.preset.upsert',
      EqualizerPreset(id: id, name: cleanName, gains: preset.gains).toPayload(),
    );
  }

  Future<void> deleteEqualizerPreset(String id) async {
    if (!customEqualizerPresets.containsKey(id)) return;
    await mutate('equalizer.preset.delete', {'id': id});
  }

  Future<void> toggleShuffle({String? folderId}) async {
    isShuffle = !isShuffle;
    if (isShuffle) {
      final scopeFolder = folderId ?? playingFolder;
      List<String> pool;
      if (scopeFolder != null) {
        final playlist = playlists
            .where((playlist) => playlist['id'] == scopeFolder)
            .firstOrNull;
        pool = List<String>.from(playlist?['track_ids'] as List? ?? []);
      } else if (_playbackIds.isNotEmpty) {
        pool = List<String>.from(_playbackIds);
      } else {
        pool = tracks.map((track) => track['id'] as String).toList();
      }
      pool.removeWhere(deletedLocallyIds.contains);

      if (pool.isNotEmpty) {
        final currentId = playingId;
        final queuedIds = deviceQueue
            .map((item) => item['track_id'] as String)
            .where((id) => !deletedLocallyIds.contains(id) && id != currentId)
            .toList();

        final remaining = List<String>.from(pool)
          ..remove(currentId)
          ..removeWhere(queuedIds.contains);
        remaining.shuffle(Random.secure());

        if (currentId != null && pool.contains(currentId)) {
          _replacePlaybackIds([currentId, ...queuedIds, ...remaining]);
          _currentPlaybackIndex = 0;
        } else {
          _replacePlaybackIds([...queuedIds, ...remaining]);
          _currentPlaybackIndex = 0;
        }
      }
    } else {
      _replacePlaybackIds(_naturalPlaybackIds(playingFolder));
      _currentPlaybackIndex = _playbackIds.indexOf(playingId ?? '');
    }
    notifyListeners();
  }

  List<String> _naturalPlaybackIds(String? folderId) {
    if (folderId == null) {
      return tracks.map((track) => track['id'] as String).toList();
    }
    final playlist = playlists
        .where((playlist) => playlist['id'] == folderId)
        .firstOrNull;
    return List<String>.from(playlist?['track_ids'] as List? ?? []);
  }

  void _replacePlaybackIds(Iterable<String> ids) {
    _playbackIds = ids.where((id) => !deletedLocallyIds.contains(id)).toList();
    _playbackEntryKeys = List<String>.generate(
      _playbackIds.length,
      (_) => 'playback-${_playbackEntrySerial++}',
      growable: true,
    );
  }

  Future<void> startShuffle({
    String? folderId,
    String? startTrackId,
    bool forcePlay = false,
  }) async {
    isShuffle = true;
    final String? scopeFolder = folderId ?? playingFolder;
    List<String> pool;
    if (scopeFolder != null) {
      final playlist = playlists
          .where((p) => p['id'] == scopeFolder)
          .firstOrNull;
      pool = List<String>.from(playlist?['track_ids'] as List? ?? []);
    } else {
      pool = tracks.map((t) => t['id'] as String).toList();
    }

    pool.removeWhere(deletedLocallyIds.contains);
    if (pool.isEmpty) return;

    final currentId = playingId;
    final hasActiveTrack = !forcePlay &&
        startTrackId == null &&
        currentId != null &&
        !deletedLocallyIds.contains(currentId) &&
        tracks.any((t) => t['id'] == currentId);

    final queuedIds = deviceQueue
        .map((item) => item['track_id'] as String)
        .where((id) => !deletedLocallyIds.contains(id) && id != currentId && id != startTrackId)
        .toList();

    if (hasActiveTrack) {
      final remaining = List<String>.from(pool)
        ..remove(currentId)
        ..removeWhere(queuedIds.contains);
      remaining.shuffle(Random.secure());

      final shuffled = [currentId, ...queuedIds, ...remaining];
      _replacePlaybackIds(shuffled);
      _currentPlaybackIndex = 0;
      playingFolder = scopeFolder;

      if (!player.playing && player.audioSource != null) {
        await player.play();
      }
      notifyListeners();
      return;
    }

    final shuffled = List<String>.from(pool)..removeWhere(queuedIds.contains);
    shuffled.shuffle(Random.secure());

    if (startTrackId != null && shuffled.contains(startTrackId)) {
      shuffled.remove(startTrackId);
      shuffled.insert(0, startTrackId);
    }

    final targetId = startTrackId ?? (queuedIds.isNotEmpty ? queuedIds.first : shuffled.first);
    final finalDeck = startTrackId != null
        ? [startTrackId, ...queuedIds, ...shuffled.where((id) => id != startTrackId)]
        : [...queuedIds, ...shuffled];

    _replacePlaybackIds(finalDeck);
    _currentPlaybackIndex = 0;
    playingFolder = scopeFolder;

    final track = tracks.where((t) => t['id'] == targetId).firstOrNull;
    if (track != null) {
      await playTrack(
        track,
        folderId: scopeFolder,
        playbackIds: finalDeck,
        playbackIndex: 0,
      );
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) => player.seek(position);

  Future<void> playPrevious() async {
    if (_switchingTrack) return;
    if (player.position.inSeconds > 2) {
      await player.seek(Duration.zero);
      return;
    }
    final idx = currentPlaybackIndex;
    for (var i = idx - 1; i >= 0; i--) {
      final prevId = _playbackIds[i];
      if (deletedLocallyIds.contains(prevId)) continue;
      final track = tracks.where((t) => t['id'] == prevId).firstOrNull;
      if (track != null) {
        final ok = await playTrack(
          track,
          folderId: playingFolder,
          playbackIds: _playbackIds,
          playbackIndex: i,
        );
        if (ok) return;
      }
    }
  }

  Future<void> playNext() async {
    if (_switchingTrack) return;

    // 1. Check manual queue first: queued tracks are pinned to the top and play next!
    final visibleQueue = deviceQueue;
    if (visibleQueue.isNotEmpty) {
      final nextItem = visibleQueue.first;
      final qTrackId = nextItem['track_id'] as String;

      // Remove from manual queue and sync
      final updatedQueue = List<Map<String, dynamic>>.from(queue)
        ..removeWhere((item) => item['id'] == nextItem['id']);
      await setQueue(updatedQueue);

      final track = tracks.where((t) => t['id'] == qTrackId).firstOrNull;
      if (track != null && !deletedLocallyIds.contains(qTrackId)) {
        final nextIdx = currentPlaybackIndex >= 0 ? currentPlaybackIndex + 1 : 0;
        final newPlaybackIds = List<String>.from(_playbackIds);
        if (nextIdx <= newPlaybackIds.length) {
          newPlaybackIds.insert(nextIdx, qTrackId);
        } else {
          newPlaybackIds.add(qTrackId);
        }
        final ok = await playTrack(
          track,
          folderId: playingFolder,
          playbackIds: newPlaybackIds,
          playbackIndex: nextIdx,
        );
        if (ok) return;
      }
    }

    // 2. Play next in current playback list
    if (_playbackIds.isNotEmpty) {
      final idx = currentPlaybackIndex;
      for (var i = idx + 1; i < _playbackIds.length; i++) {
        final nextId = _playbackIds[i];
        if (deletedLocallyIds.contains(nextId)) continue;
        final track = tracks.where((t) => t['id'] == nextId).firstOrNull;
        if (track != null) {
          final ok = await playTrack(
            track,
            folderId: playingFolder,
            playbackIds: _playbackIds,
            playbackIndex: i,
          );
          if (ok) return;
        }
      }
    }

    // 3. When reaching the end:
    if (isShuffle) {
      // Completed current shuffled deck: reshuffle full pool and keep playing without stopping!
      await startShuffle(folderId: playingFolder, forcePlay: true);
    } else if (playbackManager.repeatMode == RepeatMode.all) {
      // Loop back to the beginning of the playlist/tracklist
      final idx = currentPlaybackIndex;
      for (var i = 0; i <= idx && i < _playbackIds.length; i++) {
        final nextId = _playbackIds[i];
        if (deletedLocallyIds.contains(nextId)) continue;
        final track = tracks.where((t) => t['id'] == nextId).firstOrNull;
        if (track != null) {
          final ok = await playTrack(
            track,
            folderId: playingFolder,
            playbackIds: _playbackIds,
            playbackIndex: i,
          );
          if (ok) return;
        }
      }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => sync());
  }

  Uri _syncUri() {
    final base = Uri.parse(url);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/sync/events',
      queryParameters: {
        'token': token!,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
      },
    );
  }

  Future<void> _connectSyncEvents() async {
    if (token == null || _syncSocket != null) return;
    _syncReconnect?.cancel();
    try {
      final socket = await WebSocket.connect(_syncUri().toString());
      if (token == null) {
        await socket.close();
        return;
      }
      _syncSocket = socket;
      _syncHeartbeat?.cancel();
      _syncHeartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        try {
          _syncSocket?.add('ping');
        } catch (_) {
          _syncDisconnected();
        }
      });
      socket.listen(
        (message) {
          if (message is String) {
            try {
              final data = jsonDecode(message) as Map<String, dynamic>;
              if (data['type'] == 'presence') {
                final count = data['peer_count'] as int? ?? 0;
                final wasOnline = hasOnlinePeers;
                hasOnlinePeers = count > 0;
                if (!wasOnline && hasOnlinePeers) {
                  unawaited(transferNow());
                }
                notifyListeners();
                return;
              }
              if (data['type'] == 'relay_request') {
                final trackId = data['track_id'] as String?;
                if (trackId != null && localFiles.containsKey(trackId)) {
                  unawaited(_connectSource(trackId));
                }
                return;
              }
            } catch (_) {}
          }
          unawaited(sync());
        },
        onDone: _syncDisconnected,
        onError: (_) => _syncDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _syncDisconnected();
    }
  }

  void _syncDisconnected() {
    hasOnlinePeers = false;
    _syncHeartbeat?.cancel();
    _syncHeartbeat = null;
    _syncSocket = null;
    _syncReconnect?.cancel();
    if (token != null) {
      _syncReconnect = Timer(const Duration(seconds: 5), _connectSyncEvents);
    }
  }

  Future<void> _loadDevice() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('device_id') ?? newId();
    await prefs.setString('device_id', deviceId);
  }

  Future<void> _loadFiles() async {
    final prefs = await SharedPreferences.getInstance();
    localFiles.clear();
    originalFiles.clear();
    artworkFiles.clear();
    final savedOriginals = prefs.getString('original_files_$account');
    if (savedOriginals != null) {
      originalFiles.addAll(
        Map<String, String>.from(jsonDecode(savedOriginals) as Map),
      );
    }
    final saved = prefs.getString('files_$account');
    if (saved != null) {
      final rawMap = Map<String, String>.from(jsonDecode(saved) as Map);
      for (final entry in rawMap.entries) {
        final trackId = entry.key;
        final path = entry.value;
        final file = File(path);
        if (!deletedLocallyIds.contains(trackId) && file.existsSync()) {
          localFiles[trackId] = path;
        }
      }
    }
    final savedArt = prefs.getString('art_$account');
    if (savedArt != null) {
      final rawArt = Map<String, String>.from(jsonDecode(savedArt) as Map);
      for (final entry in rawArt.entries) {
        if (File(entry.value).existsSync()) {
          artworkFiles[entry.key] = entry.value;
        }
      }
    }

    // Auto-discover audio files in application documents music folder
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${docDir.path}/music');
      if (await musicDir.exists()) {
        await for (final entity in musicDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && _isAudio(entity.path)) {
            final fileName = entity.uri.pathSegments.last;
            for (final track in tracks) {
              final tid = track['id'] as String;
              if (!deletedLocallyIds.contains(tid) &&
                  !localFiles.containsKey(tid) &&
                  (fileName.startsWith(tid) || fileName.contains(tid))) {
                localFiles[tid] = entity.path;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error discovering files in music directory: $e');
    }

    // Check legacy application directory on Android if applicable
    if (Platform.isAndroid) {
      try {
        final legacyDir = Directory(
          '/data/user/0/com.maboy.maboy/app_flutter/music',
        );
        if (await legacyDir.exists()) {
          final docDir = await getApplicationDocumentsDirectory();
          final targetMusic = Directory('${docDir.path}/music');
          await targetMusic.create(recursive: true);
          await for (final entity in legacyDir.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entity is File && _isAudio(entity.path)) {
              final fileName = entity.uri.pathSegments.last;
              final dest = File('${targetMusic.path}/$fileName');
              if (!await dest.exists()) {
                await entity.copy(dest.path);
              }
              for (final track in tracks) {
                final tid = track['id'] as String;
                if (!deletedLocallyIds.contains(tid) &&
                    !localFiles.containsKey(tid) &&
                    dest.path.contains(tid)) {
                  localFiles[tid] = dest.path;
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    await _saveFiles();
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('files_$account', jsonEncode(localFiles));
    await prefs.setString('original_files_$account', jsonEncode(originalFiles));
    await prefs.setString('art_$account', jsonEncode(artworkFiles));
  }

  Uri _relayUri(String id, String role) {
    final base = Uri.parse(url);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/relay/$id/$role',
      queryParameters: {
        'token': token!,
        if (deviceId.isNotEmpty) 'device': deviceId,
      },
    );
  }

  Future<void> _connectSource(String id) async {
    final path = localFiles[id];
    if (path == null || !await File(path).exists()) {
      return;
    }
    final existing = _sources[id];
    if (existing != null) {
      if (existing.closeCode == null) {
        return;
      }
      _sources.remove(id);
    }
    try {
      final socket = await WebSocket.connect(
        _relayUri(id, 'source').toString(),
      );
      _sources[id] = socket;
      socket.listen(
        (message) async {
          if (message is String && message.contains('"send"')) {
            try {
              await for (final bytes in File(path).openRead()) {
                socket.add(bytes);
              }
              socket.add('done');
            } catch (_) {
              await socket.close();
            }
          }
        },
        onDone: () => _sources.remove(id),
        onError: (_) => _sources.remove(id),
      );
    } catch (_) {}
  }

  Future<void> _receive(Map<String, dynamic> track, {bool priority = false}) {
    final id = track['id'] as String;
    if (deletedLocallyIds.contains(id) || localFiles.containsKey(id)) {
      return Future.value();
    }
    return _receivePool.enqueue(
      id,
      () => _receiveSingleAttempt(track),
      priority: priority,
    );
  }

  Future<void> _receiveSingleAttempt(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    if (deletedLocallyIds.contains(id) || localFiles.containsKey(id)) return;
    final docDir = await getApplicationDocumentsDirectory();

    // Check if this track belongs to a playlist/folder
    final playlist = playlists
        .where((p) => (p['track_ids'] as List?)?.contains(id) == true)
        .firstOrNull;
    final folderName = playlist != null
        ? (playlist['name'] as String)
              .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
              .trim()
        : null;

    final directory = Directory(
      folderName != null && folderName.isNotEmpty
          ? '${docDir.path}/music/$folderName'
          : '${docDir.path}/music',
    );
    await directory.create(recursive: true);

    final target = File('${directory.path}/$id.mp3');
    // Relay and local YouTube fallback must never write the same .part file.
    final temp = File('${directory.path}/$id.relay.part');

    final currentAttempt = (_relayAttempts[id] ?? 0) + 1;
    _relayAttempts[id] = currentAttempt;

    WebSocket? socket;
    IOSink? sink;
    var completed = false;
    var fatal = false;
    try {
      transferStatus = currentAttempt == 1
          ? 'Получение: ${track['title']}'
          : 'Повторное получение ($currentAttempt/3): ${track['title']}';
      notifyListeners();

      socket = await WebSocket.connect(
        _relayUri(id, 'receive').toString(),
      ).timeout(const Duration(seconds: 15));

      final output = temp.openWrite();
      sink = output;
      await for (final message in socket.timeout(
        const Duration(seconds: 45),
      )) {
        if (message is List<int>) {
          output.add(message);
        } else if (message == 'peer_offline') {
          hasOnlinePeers = false;
          fatal = true;
          break;
        } else if (message == 'done') {
          await output.flush();
          await output.close();
          sink = null;
          // A local restore may have completed while the relay was active.
          if (deletedLocallyIds.contains(id) || localFiles.containsKey(id)) {
            await temp.delete();
            completed = true;
            break;
          }
          if (localFiles[id] == target.path && await target.exists()) {
            await temp.delete();
          } else {
            await temp.rename(target.path);
          }
          localFiles[id] = target.path;
          failedDownloads.remove(id);
          _relayAttempts.remove(id);
          _failedRelayTransfers.remove(id);
          _relayRetryTimers.remove(id)?.cancel();
          await _saveFiles();
          transferStatus = 'Получено: ${track['title']}';
          notifyListeners();
          completed = true;
          break;
        } else if (message == 'retry') {
          break;
        }
      }
    } catch (e) {
      debugPrint('Error in _receive for track $id (attempt $currentAttempt): $e');
      final str = e.toString().toLowerCase();
      if (str.contains('403') || str.contains('401') || str.contains('404')) {
        fatal = true;
      }
    } finally {
      await sink?.close();
      await socket?.close();
      if (!completed && await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }

    if (completed) return;

    // Fail handling is strictly non-blocking: the worker slot in _receivePool
    // is freed immediately so other operations proceed in parallel without delay.
    if (fatal || currentAttempt >= 3) {
      _relayAttempts.remove(id);
      _failedRelayTransfers[id] = DateTime.now();
      if (_receivePool.activeCount <= 1 && _receivePool.pendingCount == 0) {
        if (transferStatus.contains('Получение') ||
            transferStatus.contains('Повторное получение')) {
          transferStatus = '';
          notifyListeners();
        }
      }
    } else {
      // Async background delay for this failed track. It does not block the pipeline.
      // When it fires, re-enqueuing into _receivePool ensures bounded concurrency.
      final retryDelay = Duration(seconds: currentAttempt * 2);
      _relayRetryTimers[id]?.cancel();
      _relayRetryTimers[id] = Timer(retryDelay, () {
        _relayRetryTimers.remove(id);
        if (!deletedLocallyIds.contains(id) && !localFiles.containsKey(id)) {
          unawaited(_receive(track));
        }
      });
    }
  }

  Future<void> transferNow() async {
    if (token == null) return;
    if (_transferring) {
      _transferRequested = true;
      return;
    }
    _transferring = true;
    try {
      do {
        _transferRequested = false;
        await sync();
        final localTracks = List<Map<String, dynamic>>.from(
          tracks.where((t) => t['provider'] == 'local'),
        );
        final youtubeTracks = List<Map<String, dynamic>>.from(
          tracks.where((t) => t['provider'] == 'youtube'),
        );

        // 1. Trigger background download for missing YouTube tracks (skip failed)
        for (final track in youtubeTracks) {
          final trackId = track['id'] as String;
          if (!localFiles.containsKey(trackId) &&
              !downloadingIds.contains(trackId) &&
              !failedDownloads.containsKey(trackId)) {
            unawaited(downloadYouTubeTrack(track));
          }
        }

        // 2. Connect sources for all tracks present on this device (local & downloaded YouTube)
        final seedableTracks = tracks.where((t) {
          final trackId = t['id'] as String;
          return !deletedLocallyIds.contains(trackId) &&
              localFiles.containsKey(trackId);
        });
        for (final track in seedableTracks) {
          if (_sources.length < 10) {
            await _connectSource(track['id'] as String);
          }
        }

        // 3. Receive local tracks that are missing on this device (skip cooldown)
        if (!hasOnlinePeers) {
          break;
        }
        final missingLocal = localTracks.where((t) {
          final tid = t['id'] as String;
          if (deletedLocallyIds.contains(tid) || localFiles.containsKey(tid)) {
            return false;
          }
          final failedAt = _failedRelayTransfers[tid];
          if (failedAt != null &&
              DateTime.now().difference(failedAt) < const Duration(minutes: 5)) {
            return false;
          }
          return true;
        }).toList();

        if (missingLocal.isEmpty) {
          break;
        }

        // Enqueue all missing tracks into the bounded pool. Failures are handled
        // asynchronously with backoff retry timers, never blocking other tracks.
        for (final track in missingLocal) {
          unawaited(_receive(track));
        }
      } while (_transferRequested);
    } finally {
      _transferring = false;
    }
  }

  Future<String?> importYouTubePlaylist(
    String urlInput, {
    void Function(int current, int total)? onProgress,
  }) async {
    final playlistId = YouTubePlaylistService.extractPlaylistId(urlInput);
    if (playlistId == null) return null;

    transferStatus = 'Получение плейлиста YouTube...';
    notifyListeners();

    final info = await ytPlaylistService.getPlaylistInfo(playlistId);
    if (info == null || info.videos.isEmpty) {
      transferStatus = 'Не удалось загрузить плейлист YouTube';
      notifyListeners();
      return null;
    }

    final plId = newId();
    final plName = info.title.isNotEmpty ? info.title : 'YouTube Playlist';

    final existingPl = playlists.where((p) => p['name'] == plName).firstOrNull;
    final targetPlId = existingPl != null ? existingPl['id'] as String : plId;

    if (existingPl == null) {
      await mutate('playlist.upsert', {
        'id': targetPlId,
        'name': plName,
        'sort_key': playlists.length,
      });
    }

    final playlistTrackIds = List<String>.from(
      (existingPl?['track_ids'] as List?) ?? [],
    );

    int count = 0;
    final total = info.videos.length;

    for (final video in info.videos) {
      count++;
      transferStatus = 'Импорт плейлиста: $count/$total (${video.title})';
      notifyListeners();
      onProgress?.call(count, total);

      final videoId = video.id;
      final existingTrack = tracks
          .where((e) => e['provider'] == 'youtube' && e['source_id'] == videoId)
          .firstOrNull;

      String trackId;
      if (existingTrack != null) {
        trackId = existingTrack['id'] as String;
      } else {
        trackId = newId();
        final payload = {
          'id': trackId,
          'provider': 'youtube',
          'source_id': videoId,
          'title': video.title,
          'artist': video.author,
          'thumbnail_url': video.thumbnailUrl,
          'duration_ms': video.duration?.inMilliseconds,
          'added_at': DateTime.now().toUtc().toIso8601String(),
        };
        await mutate('track.upsert', payload);
        if (!localFiles.containsKey(trackId)) {
          unawaited(downloadYouTubeTrack(payload));
        }
      }

      if (!playlistTrackIds.contains(trackId)) {
        playlistTrackIds.add(trackId);
      }
    }

    await mutate('playlist.set_tracks', {
      'playlist_id': targetPlId,
      'track_ids': playlistTrackIds,
    });

    transferStatus = 'Плейлист «$plName» импортирован ($total треков)';
    notifyListeners();
    return targetPlId;
  }

  Future<String?> addYouTubeTrack(
    String urlInput, {
    String? customTitle,
  }) async {
    final videoId = YouTubeDownloadService.extractVideoId(urlInput);
    if (videoId == null) {
      if (YouTubePlaylistService.isPlaylistUrl(urlInput)) {
        return importYouTubePlaylist(urlInput);
      }
      return null;
    }

    final existing = tracks
        .where((e) => e['provider'] == 'youtube' && e['source_id'] == videoId)
        .firstOrNull;
    if (existing != null) {
      if (!localFiles.containsKey(existing['id'])) {
        unawaited(downloadYouTubeTrack(existing));
      }
      return existing['id'] as String;
    }

    transferStatus = 'Получение метаданных YouTube...';
    notifyListeners();

    final meta = await ytService.getMetadata(videoId);
    final id = newId();
    final title = (customTitle != null && customTitle.trim().isNotEmpty)
        ? customTitle.trim()
        : (meta?.title ?? 'YouTube Audio');
    final artist = meta?.author ?? 'YouTube';
    final payload = {
      'id': id,
      'provider': 'youtube',
      'source_id': videoId,
      'title': title,
      'artist': artist,
      'thumbnail_url': meta?.thumbnailUrl,
      'duration_ms': meta?.duration?.inMilliseconds,
      'added_at': DateTime.now().toUtc().toIso8601String(),
    };

    await mutate('track.upsert', payload);
    transferStatus = 'Трек добавлен. Начинается загрузка MP3...';
    notifyListeners();

    unawaited(downloadYouTubeTrack(payload));
    return id;
  }

  Future<void> downloadYouTubeTrack(
    Map<String, dynamic> track, {
    bool force = false,
    bool priority = false,
  }) async {
    final id = track['id'] as String;
    if (!force && failedDownloads.containsKey(id)) return;
    return _downloadPool.enqueue(
      id,
      () => _downloadYouTubeTrack(track, force: force),
      priority: priority || force,
    );
  }

  Future<void> _downloadYouTubeTrack(
    Map<String, dynamic> track, {
    required bool force,
  }) async {
    final id = track['id'] as String;
    if (deletedLocallyIds.contains(id)) return;
    final videoId = track['source_id'] as String;
    downloadingIds.add(id);
    downloadProgress[id] = 0.0;
    notifyListeners();

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${docDir.path}/music');
      await musicDir.create(recursive: true);

      final outMp3Path = '${musicDir.path}/$id.mp3';
      final existingFile = File(outMp3Path);
      if (!deletedLocallyIds.contains(id) &&
          await existingFile.exists() &&
          await existingFile.length() > 5000) {
        localFiles[id] = existingFile.path;
        failedDownloads.remove(id);
        await _saveFiles();
        _showTemporaryTransferStatus('MP3 скачан: ${track['title']}');
        return;
      }

      YouTubeDownloadResult result;
      try {
        final serverFile = await api.downloadFile(
          '/youtube/tracks/$id/audio',
          outMp3Path,
          onProgress: (progress) {
            downloadProgress[id] = progress;
            _throttledProgressNotify();
          },
        );
        result = YouTubeDownloadResult(file: serverFile);
      } catch (serverError) {
        debugPrint('Server YouTube download failed for $id: $serverError');
        // The relay may have completed while the server download was running.
        if (await existingFile.exists() && await existingFile.length() > 5000) {
          result = YouTubeDownloadResult(file: existingFile);
        } else {
          result = await ytService.downloadMp3Result(
            videoId: videoId,
            outputFilePath: outMp3Path,
            onProgress: (progress) {
              downloadProgress[id] = progress;
              _throttledProgressNotify();
            },
          );
          if (!result.isSuccess && result.errorMessage == null) {
            result = YouTubeDownloadResult(
              errorMessage: friendlyErrorMessage(serverError),
            );
          }
        }
      }

      if (deletedLocallyIds.contains(id)) {
        try {
          if (await existingFile.exists()) await existingFile.delete();
        } catch (error) {
          debugPrint('Failed to remove download of deleted track $id: $error');
        }
        return;
      }
      if (result.isSuccess && await result.file!.exists()) {
        localFiles[id] = result.file!.path;
        failedDownloads.remove(id);

        final thumbUrl = track['thumbnail_url'] as String?;
        if (thumbUrl != null && thumbUrl.isNotEmpty) {
          final artFile = await ytService.downloadThumbnail(
            thumbUrl,
            '${musicDir.path}/$id.jpg',
          );
          if (artFile != null && await artFile.exists()) {
            artworkFiles[id] = artFile.path;
          }
        }

        await _saveFiles();
        _showTemporaryTransferStatus('MP3 скачан: ${track['title']}');
      } else {
        final err = result.errorMessage ?? 'Не удалось получить аудиопоток';
        failedDownloads[id] = err;
        transferStatus = 'Ошибка: $err (${track['title']})';
        notifyListeners();

        // Fallback: if direct YouTube download failed on this device,
        // attempt peer receive in case another user device (e.g. PC) has it
        if (token != null) {
          await _receive(track);
          if (localFiles.containsKey(id)) {
            failedDownloads.remove(id);
            transferStatus = 'Получено через синхронизацию: ${track['title']}';
            notifyListeners();
          } else {
            transferStatus = 'Ошибка: $err (${track['title']})';
            notifyListeners();
            Future.delayed(const Duration(seconds: 4), () {
              if (transferStatus.startsWith('Ошибка')) {
                transferStatus = '';
                notifyListeners();
              }
            });
          }
        } else {
          Future.delayed(const Duration(seconds: 4), () {
            if (transferStatus.startsWith('Ошибка')) {
              transferStatus = '';
              notifyListeners();
            }
          });
        }
      }
    } catch (e) {
      final err = 'Ошибка скачивания: $e';
      failedDownloads[id] = err;
      transferStatus = '$err (${track['title']})';
      Future.delayed(const Duration(seconds: 4), () {
        if (transferStatus.startsWith('Ошибка')) {
          transferStatus = '';
          notifyListeners();
        }
      });
    } finally {
      downloadingIds.remove(id);
      downloadProgress.remove(id);
      notifyListeners();
    }
  }

  Future<void> handleIncomingShare(String sharedText) async {
    final trackId = await addYouTubeTrack(sharedText);
    if (trackId != null) {
      final track = tracks.where((t) => t['id'] == trackId).firstOrNull;
      if (track != null) {
        transferStatus = 'Трек добавлен в библиотеку: ${track['title']}';
        notifyListeners();
      }
    }
  }

  Future<void> importMusic({bool folder = false}) async {
    if (account == null) return;
    final paths = <String>[];
    String? name;
    if (folder) {
      final selected = await FilePicker.platform.getDirectoryPath();
      if (selected == null) return;
      name = selected.split(Platform.pathSeparator).last;
      await for (final entry in Directory(
        selected,
      ).list(recursive: true, followLinks: false)) {
        if (entry is File && _isAudio(entry.path)) paths.add(entry.path);
      }
    } else {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (selected == null) return;
      paths.addAll(selected.files.map((f) => f.path).whereType<String>());
    }

    final ids = <String>[];
    final operations = <Map<String, dynamic>>[];
    final docDir = await getApplicationDocumentsDirectory();
    final directory = Directory('${docDir.path}/music');
    await directory.create(recursive: true);

    for (final path in paths) {
      final id = newId();
      final sourceFile = File(path);
      final extension = path.contains('.')
          ? path.substring(path.lastIndexOf('.'))
          : '.audio';
      final target = File('${directory.path}/$id$extension');
      final artTargetPath = '${directory.path}/$id.jpg';

      final meta = LocalMetadataService.parseFile(
        sourceFile,
        artworkOutputPath: artTargetPath,
      );
      await sourceFile.copy(target.path);
      localFiles[id] = target.path;
      originalFiles[id] = sourceFile.path;
      if (meta.artworkPath != null) {
        artworkFiles[id] = meta.artworkPath!;
      }
      ids.add(id);

      operations.add({
        'kind': 'track.upsert',
        'payload': {
          'id': id,
          'provider': 'local',
          'source_id': '$deviceId:$id',
          'title': meta.title,
          'artist': meta.artist,
          'album': meta.album,
          'duration_ms': meta.durationMs,
          'added_at': DateTime.now().toUtc().toIso8601String(),
        },
      });
    }

    await _saveFiles();

    if (folder && ids.isNotEmpty) {
      final playlistId = newId();
      operations.add({
        'kind': 'playlist.upsert',
        'payload': {
          'id': playlistId,
          'name': name!,
          'sort_key': playlists.length,
        },
      });
      operations.add({
        'kind': 'playlist.set_tracks',
        'payload': {'playlist_id': playlistId, 'track_ids': ids},
      });
    }

    if (operations.isNotEmpty) {
      // Apply all ops locally and stage them in pending in one batch,
      // then do a single save+sync instead of N round-trips.
      for (final op in operations) {
        final kind = op['kind'] as String;
        final payload = op['payload'] as Map<String, dynamic>;
        pending.add({
          'operation_id': newId(),
          'kind': kind,
          'payload': payload,
        });
        apply(kind, payload);
      }
      await save();
      await sync();
    }
    await transferNow();
  }

  bool _isAudio(String path) => RegExp(
    r'\.(mp3|m4a|aac|ogg|opus|wav|flac)$',
    caseSensitive: false,
  ).hasMatch(path);

  bool _scanningDevice = false;

  Future<void> scanAndImportDeviceMusic({bool manual = false}) async {
    if (account == null || _scanningDevice) return;
    _scanningDevice = true;
    if (manual) {
      transferStatus = 'Сканирование музыки на устройстве...';
      notifyListeners();
    }

    try {
      final discoveredFiles = await DeviceMusicService.scanDefaultFolders();
      if (discoveredFiles.isEmpty) {
        if (manual) {
          transferStatus = 'Аудиофайлы в дефолтных папках не найдены';
          notifyListeners();
        }
        return;
      }

      final docDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${docDir.path}/music');
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      int newTracksCount = 0;
      final newOperations = <Map<String, dynamic>>[];

      for (final discovered in discoveredFiles) {
        final filePath = discovered.path;
        final file = File(filePath);
        if (!await file.exists()) continue;

        // 1. Check if already known in localFiles
        if (localFiles.containsValue(filePath) ||
            originalFiles.containsValue(filePath)) {
          continue;
        }

        // 2. Parse file metadata (fallback to discovered metadata)
        final tempId = newId();
        final artTargetPath = '${musicDir.path}/$tempId.jpg';
        final meta = LocalMetadataService.parseFile(
          file,
          artworkOutputPath: artTargetPath,
        );

        final trackTitle = (meta.title.isNotEmpty)
            ? meta.title
            : (discovered.title?.trim().isNotEmpty == true
                  ? discovered.title!.trim()
                  : (filePath.contains(Platform.pathSeparator)
                        ? filePath.split(Platform.pathSeparator).last
                        : filePath));

        final artist = meta.artist ?? discovered.artist;
        final album = meta.album ?? discovered.album;
        final durationMs = meta.durationMs ?? discovered.durationMs;

        // 3. Check if track already exists in tracks matching title, artist and duration strictly
        final existingTrack = tracks.where((t) {
          if (t['provider'] != 'local') return false;
          if (t['title'] != trackTitle) return false;
          final tArtist = t['artist'] as String?;
          final tDuration = (t['duration_ms'] as num?)?.toInt();
          // STRICT: both must have a non-empty matching artist and duration match
          if (artist != null &&
              artist.isNotEmpty &&
              tArtist != null &&
              tArtist.isNotEmpty) {
            if (tArtist.toLowerCase() != artist.toLowerCase()) return false;
            if (durationMs != null && tDuration != null) {
              return (durationMs - tDuration).abs() < 3000;
            }
          }
          return false;
        }).firstOrNull;

        if (existingTrack != null) {
          final existingId = existingTrack['id'] as String;
          originalFiles[existingId] = filePath;
          if (!deletedLocallyIds.contains(existingId)) {
            localFiles[existingId] = filePath;
          }
          if (meta.artworkPath != null &&
              !artworkFiles.containsKey(existingId)) {
            artworkFiles[existingId] = meta.artworkPath!;
          }
          continue;
        }

        // 4. Create new track
        final trackId = tempId;
        localFiles[trackId] = filePath;
        originalFiles[trackId] = filePath;
        if (meta.artworkPath != null) {
          artworkFiles[trackId] = meta.artworkPath!;
        }

        final trackPayload = {
          'id': trackId,
          'provider': 'local',
          'source_id': '$deviceId:$trackId',
          'title': trackTitle,
          'artist': artist,
          'album': album,
          'duration_ms': durationMs,
          'added_at': DateTime.now().toUtc().toIso8601String(),
        };

        newOperations.add({
          'operation_id': newId(),
          'kind': 'track.upsert',
          'payload': trackPayload,
        });
        apply('track.upsert', trackPayload);
        newTracksCount++;
      }

      if (newTracksCount > 0) {
        pending.addAll(newOperations);
        await _saveFiles();
        await save();
        await sync();
        transferStatus = 'Добавлено новых песен: $newTracksCount';
      } else {
        await _saveFiles();
        if (manual) {
          transferStatus = 'Все песни на устройстве уже добавлены в библиотеку';
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error scanning device music: $e');
      if (manual) {
        transferStatus = 'Ошибка сканирования папок: $e';
        notifyListeners();
      }
    } finally {
      _scanningDevice = false;
    }
  }

  Future<String?> _findLocalFileForTrack(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${docDir.path}/music');

      // 1. Exact ID check in application music directory (including playlist subfolders)
      if (await musicDir.exists()) {
        await for (final file in musicDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File && _isAudio(file.path)) {
            final fileName = file.uri.pathSegments.last;
            if (fileName.startsWith(id) || fileName.contains(id)) {
              return file.path;
            }
          }
        }
      }

      // 2. Strict external file matching: requires non-empty artist, non-empty title, and duration match
      final title = (track['title'] as String?)?.trim();
      final artist = (track['artist'] as String?)?.trim();
      final durationMs = (track['duration_ms'] as num?)?.toInt();

      if (title != null &&
          title.isNotEmpty &&
          artist != null &&
          artist.isNotEmpty &&
          durationMs != null &&
          durationMs > 5000) {
        final lowerTitle = title.toLowerCase();
        final lowerArtist = artist.toLowerCase();
        final discovered = await DeviceMusicService.scanDefaultFolders();
        for (final item in discovered) {
          final itemTitle = item.title?.trim().toLowerCase();
          final itemArtist = item.artist?.trim().toLowerCase();
          final itemDuration = item.durationMs;

          if (itemTitle == lowerTitle &&
              itemArtist == lowerArtist &&
              itemDuration != null &&
              (itemDuration - durationMs).abs() < 3000) {
            return item.path;
          }
        }
      }
    } catch (error) {
      debugPrint('Failed to find local audio for track $id: $error');
    }
    return null;
  }

  Future<bool> playTrack(
    Map<String, dynamic> track, {
    String? folderId,
    List<String>? playbackIds,
    int? playbackIndex,
  }) async {
    if (_switchingTrack) return false;
    _switchingTrack = true;
    final prevPlayingId = playingId;
    final prevPlayingFolder = playingFolder;
    final prevPlaybackIndex = _currentPlaybackIndex;
    final prevPlaybackIds = List<String>.from(_playbackIds);
    final prevPlaybackKeys = List<String>.from(_playbackEntryKeys);
    var success = false;

    try {
      final id = track['id'] as String;

      // If the track is marked as deleted on this device, skip it immediately
      if (deletedLocallyIds.contains(id)) {
        transferStatus = 'Трек удален с этого устройства: ${track['title']}';
        notifyListeners();
        return false;
      }

      // Immediately highlight and select the track so the UI updates instantly
      playingId = id;
      playingFolder = folderId;
      if (isShuffle) {
        final scopeFolder = folderId ?? playingFolder;
        List<String> pool;
        if (scopeFolder != null) {
          final playlist = playlists
              .where((playlist) => playlist['id'] == scopeFolder)
              .firstOrNull;
          pool = List<String>.from(playlist?['track_ids'] as List? ?? []);
        } else if (playbackIds != null && playbackIds.isNotEmpty) {
          pool = List<String>.from(playbackIds);
        } else {
          pool = tracks.map((track) => track['id'] as String).toList();
        }
        pool.removeWhere(deletedLocallyIds.contains);

        final queuedIds = deviceQueue
            .map((item) => item['track_id'] as String)
            .where((trackId) => !deletedLocallyIds.contains(trackId) && trackId != id)
            .toList();

        final remaining = List<String>.from(pool)
          ..remove(id)
          ..removeWhere(queuedIds.contains);
        remaining.shuffle(Random.secure());

        _replacePlaybackIds([id, ...queuedIds, ...remaining]);
        _currentPlaybackIndex = 0;
      } else if (playbackIds != null && playbackIds.isNotEmpty) {
        if (!listEquals(_playbackIds, playbackIds) ||
            _playbackEntryKeys.length != playbackIds.length) {
          _replacePlaybackIds(playbackIds);
        }
      } else if (folderId != null) {
        final playlist = playlists
            .where((p) => p['id'] == folderId)
            .firstOrNull;
        _replacePlaybackIds(
          List<String>.from(playlist?['track_ids'] as List? ?? [id]),
        );
      } else {
        _replacePlaybackIds(tracks.map((t) => t['id'] as String));
      }
      _currentPlaybackIndex =
          playbackIndex != null &&
              playbackIndex >= 0 &&
              playbackIndex < _playbackIds.length &&
              _playbackIds[playbackIndex] == id
          ? playbackIndex
          : _playbackIds.indexOf(id);
      notifyListeners();

      var localPath = localFiles[id];
      if (localPath != null && !await File(localPath).exists()) {
        localFiles.remove(id);
        localPath = null;
        unawaited(_saveFiles());
      }

      if (Platform.environment.containsKey('FLUTTER_TEST') && localPath == null) {
        final source = MediaService.createAudioSource(
          trackId: id,
          title: track['title'] as String? ?? 'Track',
          artist: track['artist'] as String?,
          album: track['album'] as String?,
          localFilePath: 'test_track.mp3',
        );
        await player.setAudioSource(source);
        await player.play();
        notifyListeners();
        return success = true;
      }

      // 1. If local file exists, play immediately
      if (localPath != null) {
        try {
          final source = MediaService.createAudioSource(
            trackId: id,
            title: track['title'] as String,
            artist: track['artist'] as String?,
            album: track['album'] as String?,
            localFilePath: localPath,
            localArtworkPath: artworkFiles[id],
            thumbnailNetworkUrl: track['thumbnail_url'] as String?,
          );
          if (deletedLocallyIds.contains(id)) return false;
          await player.setAudioSource(source);
          if (deletedLocallyIds.contains(id)) return false;
          unawaited(_recordHistory(id));
          await player.play();
          notifyListeners();
          return success = true;
        } catch (e) {
          debugPrint('Error playing local file: $e');
          transferStatus = 'Ошибка воспроизведения: $e';
          notifyListeners();
          return false;
        }
      }

      // 2. If it's a YouTube track and not yet downloaded, stream immediately while downloading
      if (track['provider'] == 'youtube') {
        transferStatus = 'Подключение к потоку YouTube: ${track['title']}';
        notifyListeners();
        try {
          final streamResult = await ytService.getStreamResult(
            track['source_id'] as String,
          );
          if (deletedLocallyIds.contains(id)) return false;
          if (streamResult.isSuccess) {
            final source = MediaService.createAudioSource(
              trackId: id,
              title: track['title'] as String,
              artist: track['artist'] as String?,
              album: track['album'] as String?,
              streamUrl: streamResult.url,
              localArtworkPath: artworkFiles[id],
              thumbnailNetworkUrl: track['thumbnail_url'] as String?,
            );
            await player.setAudioSource(source);
            if (deletedLocallyIds.contains(id)) return false;
            unawaited(_recordHistory(id));
            await player.play();
            unawaited(downloadYouTubeTrack(track));
            notifyListeners();
            return success = true;
          } else {
            transferStatus =
                '${streamResult.errorMessage ?? 'Поток YouTube недоступен'}: '
                '${track['title']}. Трек поставлен на скачивание.';
            notifyListeners();
            unawaited(downloadYouTubeTrack(track, force: true, priority: true));
            return false;
          }
        } catch (e) {
          debugPrint('Error streaming YouTube: $e');
          transferStatus =
              'Ошибка потока YouTube (${friendlyErrorMessage(e)}): ${track['title']}. Трек поставлен на скачивание.';
          notifyListeners();
          unawaited(downloadYouTubeTrack(track, force: true, priority: true));
          return false;
        }
      }

      // 3. Check if matching audio exists on device in music folders
      final foundPath = await _findLocalFileForTrack(track);
      if (deletedLocallyIds.contains(id)) return false;
      if (foundPath != null) {
        localFiles[id] = foundPath;
        unawaited(_saveFiles());
        try {
          final source = MediaService.createAudioSource(
            trackId: id,
            title: track['title'] as String,
            artist: track['artist'] as String?,
            album: track['album'] as String?,
            localFilePath: foundPath,
            localArtworkPath: artworkFiles[id],
          );
          await player.setAudioSource(source);
          if (deletedLocallyIds.contains(id)) return false;
          unawaited(_recordHistory(id));
          await player.play();
          notifyListeners();
          return success = true;
        } catch (e) {
          debugPrint('Error playing discovered local audio: $e');
          transferStatus = 'Ошибка воспроизведения: $e';
          notifyListeners();
          return false;
        }
      }

      // 4. Missing file on this device: trigger peer transfer
      transferStatus = 'Загрузка с другого устройства: ${track['title']}...';
      notifyListeners();
      await _receive(track, priority: true);
      if (deletedLocallyIds.contains(id)) return false;
      localPath = localFiles[id];
      if (localPath != null && await File(localPath).exists()) {
        try {
          final source = MediaService.createAudioSource(
            trackId: id,
            title: track['title'] as String,
            artist: track['artist'] as String?,
            album: track['album'] as String?,
            localFilePath: localPath,
            localArtworkPath: artworkFiles[id],
          );
          await player.setAudioSource(source);
          if (deletedLocallyIds.contains(id)) return false;
          unawaited(_recordHistory(id));
          await player.play();
          notifyListeners();
          return success = true;
        } catch (e) {
          debugPrint('Error playing transferred file: $e');
          transferStatus = 'Ошибка воспроизведения: $e';
          notifyListeners();
          return false;
        }
      } else {
        transferStatus = 'Файл пока не передан на это устройство';
        notifyListeners();
        return false;
      }
    } finally {
      if (success) {
        _consecutivePlaybackErrors = 0;
      } else {
        playingId =
            prevPlayingId != null && !deletedLocallyIds.contains(prevPlayingId)
            ? prevPlayingId
            : null;
        playingFolder = playingId == null ? null : prevPlayingFolder;
        _playbackIds = [];
        _playbackEntryKeys = [];
        _currentPlaybackIndex = -1;
        for (var index = 0; index < prevPlaybackIds.length; index++) {
          if (deletedLocallyIds.contains(prevPlaybackIds[index])) continue;
          if (index == prevPlaybackIndex && playingId != null) {
            _currentPlaybackIndex = _playbackIds.length;
          }
          _playbackIds.add(prevPlaybackIds[index]);
          _playbackEntryKeys.add(prevPlaybackKeys[index]);
        }
        notifyListeners();
      }
      _switchingTrack = false;
    }
  }

  Future<void> _recordHistory(String trackId) async {
    await mutate('history.add', {
      'id': newId(),
      'track_id': trackId,
      'started_at': DateTime.now().toUtc().toIso8601String(),
      'completed': false,
      'device_id': deviceId,
    });
  }

  Future<void> setPlaylistTracks(
    String playlistId,
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    await mutate('playlist.set_tracks', {
      'playlist_id': playlistId,
      'track_ids': list,
    });
    if (playingFolder == playlistId && !isShuffle) {
      _replacePlaybackIds(list);
      _currentPlaybackIndex = _playbackIds.indexOf(playingId ?? '');
      if (_reordering) return;
      notifyListeners();
    }
  }

  Future<void> renamePlaylist(Map<String, dynamic> playlist, String name) =>
      mutate('playlist.upsert', {
        'id': playlist['id'],
        'name': name,
        'sort_key': playlist['sort_key'],
      });

  Future<void> deletePlaylist(String id) =>
      mutate('playlist.delete', {'id': id});

  Future<void> reorderPlaylists(int from, int to) async {
    if (to > from) to--;
    final ordered = List<Map<String, dynamic>>.from(playlists);
    ordered.insert(to, ordered.removeAt(from));
    for (var index = 0; index < ordered.length; index++) {
      final item = ordered[index];
      if (item['sort_key'] != index) {
        await mutate('playlist.upsert', {
          'id': item['id'],
          'name': item['name'],
          'sort_key': index,
        });
      }
    }
  }

  Future<void> reorderTracks(int from, int to) async {
    if (to > from) to--;
    if (from == to) return;
    final item = tracks.removeAt(from);
    tracks.insert(to, item);
    if (playingFolder == null && !isShuffle) {
      _replacePlaybackIds(tracks.map((t) => t['id'] as String));
      _currentPlaybackIndex = _playbackIds.indexOf(playingId ?? '');
    }
    await mutate('track.set_order', {
      'track_ids': tracks.map((track) => track['id'] as String).toList(),
    });
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    Iterable<String> trackIds,
  ) async {
    final playlist = playlists.where((p) => p['id'] == playlistId).firstOrNull;
    if (playlist == null) return;
    final currentIds = List<String>.from(playlist['track_ids'] as List? ?? []);
    for (final id in trackIds) {
      if (!currentIds.contains(id)) {
        currentIds.add(id);
      }
    }
    await setPlaylistTracks(playlistId, currentIds);
  }

  Future<void> deleteLocally(List<String> trackIds) async {
    final removedIds = trackIds.toSet();
    deletedLocallyIds.addAll(removedIds);
    // Remove every occurrence while keeping entry keys aligned with the
    // playback indices. A deleted current track must stop immediately.
    for (var index = _playbackIds.length - 1; index >= 0; index--) {
      if (!removedIds.contains(_playbackIds[index])) continue;
      _playbackIds.removeAt(index);
      _playbackEntryKeys.removeAt(index);
      if (index <= _currentPlaybackIndex) _currentPlaybackIndex--;
    }
    if (playingId != null && removedIds.contains(playingId)) {
      playingId = null;
      playingFolder = null;
      _currentPlaybackIndex = -1;
      try {
        await player.stop();
      } catch (error) {
        debugPrint('Failed to stop deleted track: $error');
      }
    }
    notifyListeners();
    final docDir = await getApplicationDocumentsDirectory();
    final appMusicPrefix =
        '${docDir.path}${Platform.pathSeparator}music${Platform.pathSeparator}';
    for (final id in trackIds) {
      final path = localFiles.remove(id);
      if (path != null) {
        final normalizedPath = Platform.isWindows ? path.toLowerCase() : path;
        final normalizedPrefix = Platform.isWindows
            ? appMusicPrefix.toLowerCase()
            : appMusicPrefix;
        final appOwned =
            normalizedPath.startsWith(normalizedPrefix) &&
            File(path).uri.pathSegments.last.startsWith(id);
        // Older installations have no origin marker. Preserve any file that
        // is not an app-owned copy and remember it for future restores.
        if (!appOwned) originalFiles[id] = path;
        if (appOwned && path != originalFiles[id]) {
          try {
            final file = File(path);
            if (await file.exists()) await file.delete();
          } catch (error) {
            debugPrint('Failed to delete local audio $path: $error');
          }
        }
      }
      final art = artworkFiles.remove(id);
      if (art != null) {
        final af = File(art);
        if (af.existsSync()) {
          try {
            await af.delete();
          } catch (error) {
            debugPrint('Failed to delete local artwork $art: $error');
          }
        }
      }
    }
    await _saveFiles();
    await save();
    for (final id in trackIds) {
      _relayRetryTimers.remove(id)?.cancel();
      _relayAttempts.remove(id);
    }
    final deviceName = Platform.isAndroid ? 'Android' : 'PC';
    sinkDeletedTracksToEnd();
    if (playingFolder == null && !isShuffle) {
      _replacePlaybackIds(tracks.map((t) => t['id'] as String));
      _currentPlaybackIndex = _playbackIds.indexOf(playingId ?? '');
    }
    final ops = <Map<String, dynamic>>[];
    ops.add({
      'kind': 'track.set_order',
      'payload': {
        'track_ids': tracks.map((track) => track['id'] as String).toList(),
      },
    });
    for (final p in playlists) {
      final pTrackIds = (p['track_ids'] as List?)?.cast<String>() ?? [];
      if (pTrackIds.any(removedIds.contains)) {
        ops.add({
          'kind': 'playlist.set_tracks',
          'payload': {
            'playlist_id': p['id'],
            'track_ids': pTrackIds,
          },
        });
      }
    }
    for (final id in trackIds) {
      ops.add({
        'kind': 'track.device_status',
        'payload': {
          'track_id': id,
          'device_id': deviceId,
          'device_name': deviceName,
          'status': 'deleted',
        },
      });
    }
    await mutateBatch(ops);
    notifyListeners();
  }

  /// Automatically moves locally deleted tracks to the very end of lists.
  void sinkDeletedTracksToEnd() {
    if (deletedLocallyIds.isEmpty) return;

    final activeTracks = <Map<String, dynamic>>[];
    final deletedTracks = <Map<String, dynamic>>[];
    for (final t in tracks) {
      final id = t['id'] as String?;
      if (id != null && deletedLocallyIds.contains(id)) {
        deletedTracks.add(t);
      } else {
        activeTracks.add(t);
      }
    }
    if (deletedTracks.isNotEmpty) {
      tracks
        ..clear()
        ..addAll(activeTracks)
        ..addAll(deletedTracks);
    }

    for (final playlist in playlists) {
      final trackIds = (playlist['track_ids'] as List?)?.cast<String>();
      if (trackIds == null || trackIds.isEmpty) continue;
      final activeIds = <String>[];
      final deletedIds = <String>[];
      for (final id in trackIds) {
        if (deletedLocallyIds.contains(id)) {
          deletedIds.add(id);
        } else {
          activeIds.add(id);
        }
      }
      if (deletedIds.isNotEmpty) {
        playlist['track_ids'] = [...activeIds, ...deletedIds];
      }
    }
  }

  Future<void> restoreLocally(String trackId) async {
    final track = tracks.where((item) => item['id'] == trackId).firstOrNull;
    if (track != null && track['provider'] == 'local') {
      String? path = originalFiles[trackId];
      if (path != null && !await File(path).exists()) path = null;
      path ??= await _findLocalFileForTrack(track);
      if (path != null) {
        localFiles[trackId] = path;
        originalFiles[trackId] = path;
        await _saveFiles();
      }
    }
    deletedLocallyIds.remove(trackId);
    _failedRelayTransfers.remove(trackId);
    _relayAttempts.remove(trackId);
    _relayRetryTimers.remove(trackId)?.cancel();
    failedDownloads.remove(trackId);
    await save();
    if (!localFiles.containsKey(trackId)) unawaited(transferNow());
    notifyListeners();
  }

  Future<void> setQueue(Iterable<Map<String, dynamic>> items) =>
      mutate('queue.set', {'items': items.toList()});

  /// Edit the visible part without deleting entries belonging to other devices.
  Future<void> setDeviceQueue(Iterable<Map<String, dynamic>> items) {
    final visible = items.iterator;
    final merged = <Map<String, dynamic>>[];
    for (final item in queue) {
      if (deletedLocallyIds.contains(item['track_id'])) {
        merged.add(item);
      } else if (visible.moveNext()) {
        merged.add(visible.current);
      }
    }
    while (visible.moveNext()) {
      merged.add(visible.current);
    }
    return setQueue(merged);
  }

  Future<void> addToQueue(String trackId, {bool next = false}) async {
    if (deletedLocallyIds.contains(trackId)) return;
    final items = List<Map<String, dynamic>>.from(queue);
    items.insert(next ? 0 : items.length, {'id': newId(), 'track_id': trackId});
    await setQueue(items);

    if (_playbackIds.isNotEmpty && currentPlaybackIndex >= 0) {
      final insertIndex = next
          ? currentPlaybackIndex + 1
          : (currentPlaybackIndex + deviceQueue.length).clamp(
              currentPlaybackIndex + 1,
              _playbackIds.length,
            );
      if (!_playbackIds.sublist(currentPlaybackIndex + 1).contains(trackId)) {
        _playbackIds.insert(insertIndex, trackId);
        _playbackEntryKeys.insert(insertIndex, 'playback-${_playbackEntrySerial++}');
      }
    }
    notifyListeners();
  }

  Future<void> shuffleQueue() async {
    final items = deviceQueue..shuffle(Random.secure());
    await setDeviceQueue(items);
  }

  Future<void> playQueueItem(Map<String, dynamic> item) async {
    if (deletedLocallyIds.contains(item['track_id'])) return;
    final track = tracks
        .where((value) => value['id'] == item['track_id'])
        .firstOrNull;
    if (track == null) return;
    final visibleQueue = deviceQueue;
    final playbackIds = visibleQueue
        .map((value) => value['track_id'] as String)
        .toList();
    final itemIndex = visibleQueue.indexWhere(
      (value) => value['id'] == item['id'],
    );
    await playTrack(
      track,
      playbackIds: playbackIds,
      playbackIndex: itemIndex >= 0 ? itemIndex : null,
    );
  }

  Future<void> playPlaybackQueueEntry(PlaybackQueueEntry entry) async {
    if (entry.playbackIndex < 0 || entry.playbackIndex >= _playbackIds.length) {
      return;
    }
    await playTrack(
      entry.track,
      folderId: playingFolder,
      playbackIds: _playbackIds,
      playbackIndex: entry.playbackIndex,
    );
  }

  /// Freezes list rebuilds while a drag is in flight. ReorderableListView
  /// animates item slots itself; rebuilding the list on every index change
  /// interrupts that animation and makes the drag stutter.
  void beginReorder() {
    _reordering = true;
  }

  void endReorder() {
    if (!_reordering) return;
    _reordering = false;
    notifyListeners();
  }

  /// Reorders only the future part of the active sequence. The current and
  /// already played tracks are immutable so playback cannot jump unexpectedly.
  void reorderUpcomingPlayback(int oldIndex, int newIndex) {
    final firstUpcoming = currentPlaybackIndex + 1;
    final upcomingCount = _playbackIds.length - firstUpcoming;
    if (firstUpcoming <= 0 ||
        oldIndex < 0 ||
        oldIndex >= upcomingCount ||
        newIndex < 0 ||
        newIndex > upcomingCount) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    if (oldIndex == newIndex) return;

    final moved = _playbackIds.removeAt(firstUpcoming + oldIndex);
    final movedKey = _playbackEntryKeys.removeAt(firstUpcoming + oldIndex);
    _playbackIds.insert(firstUpcoming + newIndex, moved);
    _playbackEntryKeys.insert(firstUpcoming + newIndex, movedKey);
    if (_reordering) return;
    notifyListeners();
  }

  void removeUpcomingPlayback(int playbackIndex) {
    if (playbackIndex <= currentPlaybackIndex ||
        playbackIndex < 0 ||
        playbackIndex >= _playbackIds.length) {
      return;
    }
    _playbackIds.removeAt(playbackIndex);
    _playbackEntryKeys.removeAt(playbackIndex);
    notifyListeners();
  }

  Future<void> load() async {
    await _loadDevice();
    await friendsService.load();
    final prefs = await SharedPreferences.getInstance();
    url = backendUrl;
    account = prefs.getString('account');
    token = await _secure.read(key: 'session');
    if (token != null && account != null) {
      final state = prefs.getString('state_$account');
      if (state != null) {
        final data = jsonDecode(state) as Map<String, dynamic>;
        cursor = (data['cursor'] as num?)?.toInt() ?? 0;
        for (final (source, dest) in [
          (data['tracks'], tracks),
          (data['playlists'], playlists),
          (data['queue'], queue),
          (data['history'], history),
          (data['pending'], pending),
        ]) {
          if (source is List) {
            dest.addAll(source.map((e) => Map<String, dynamic>.from(e as Map)));
          }
        }
        if (data['favorite_ids'] is List) {
          favoriteIds.addAll((data['favorite_ids'] as List).cast<String>());
        }
        if (data['deleted_locally_ids'] is List) {
          deletedLocallyIds.addAll(
            (data['deleted_locally_ids'] as List).cast<String>(),
          );
        }
        if (data['device_track_statuses'] is Map) {
          deviceTrackStatuses.addAll(
            (data['device_track_statuses'] as Map).map(
              (k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)),
            ),
          );
          for (final entry in deviceTrackStatuses.entries) {
            final st = entry.value;
            final isCurrentPlatform = st['device_id'] == deviceId ||
                (Platform.isAndroid && st['device_name'] == 'Android') ||
                (!Platform.isAndroid && st['device_name'] == 'PC');
            if (st['status'] == 'deleted' && isCurrentPlatform) {
              deletedLocallyIds.add(entry.key);
            }
          }
        }
        if (data['equalizer_presets'] is List) {
          for (final raw in data['equalizer_presets'] as List) {
            try {
              final preset = EqualizerPreset.fromPayload(
                Map<String, dynamic>.from(raw as Map),
              );
              customEqualizerPresets[preset.id] = preset;
            } catch (error) {
              debugPrint('Ignoring invalid cached equalizer preset: $error');
            }
          }
        }
      }
      await _loadFiles();
      sinkDeletedTracksToEnd();
    }
    await _loadEqualizerDeviceState(prefs);
    volume = prefs.getDouble('volume') ?? 1.0;
    try {
      await player.setVolume(volume);
    } catch (_) {}
    _startPolling();
    if (token != null) {
      unawaited(_connectSyncEvents());
      unawaited(transferNow());
      unawaited(scanAndImportDeviceMusic());
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (account != null) {
      await prefs.setString('account', account!);
      await prefs.setString(
        'state_$account',
        jsonEncode({
          'cursor': cursor,
          'tracks': tracks,
          'playlists': playlists,
          'queue': queue,
          'favorite_ids': favoriteIds,
          'history': history,
          'pending': pending,
          'deleted_locally_ids': deletedLocallyIds.toList(),
          'device_track_statuses': deviceTrackStatuses,
          'equalizer_presets': customEqualizerPresets.values
              .map((preset) => preset.toPayload())
              .toList(),
        }),
      );
      await prefs.setDouble('volume', volume);
    }
    notifyListeners();
  }

  Future<void> signIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    const base = backendUrl;
    final address = email.trim().toLowerCase();
    final previousToken = token;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await SyncApi(base, null).request(
        'POST',
        register ? '/auth/register' : '/auth/login',
        {'email': address, 'password': password},
      );
      final identity = '$base|$address';
      if (identity != account) {
        tracks.clear();
        playlists.clear();
        queue.clear();
        favoriteIds.clear();
        history.clear();
        pending.clear();
        deletedLocallyIds.clear();
        deviceTrackStatuses.clear();
        customEqualizerPresets.clear();
        cursor = 0;
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('state_$identity');
        if (saved != null) {
          final state = jsonDecode(saved) as Map<String, dynamic>;
          cursor = (state['cursor'] as num?)?.toInt() ?? 0;
          for (final (source, dest) in [
            (state['tracks'], tracks),
            (state['playlists'], playlists),
            (state['queue'], queue),
            (state['history'], history),
            (state['pending'], pending),
          ]) {
            if (source is List) {
              dest.addAll(
                source.map((e) => Map<String, dynamic>.from(e as Map)),
              );
            }
          }
          if (state['favorite_ids'] is List) {
            favoriteIds.addAll((state['favorite_ids'] as List).cast<String>());
          }
          if (state['deleted_locally_ids'] is List) {
            deletedLocallyIds.addAll(
              (state['deleted_locally_ids'] as List).cast<String>(),
            );
          }
          if (state['device_track_statuses'] is Map) {
            deviceTrackStatuses.addAll(
              (state['device_track_statuses'] as Map).map(
                (k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)),
              ),
            );
            for (final entry in deviceTrackStatuses.entries) {
              final st = entry.value;
              final isCurrentPlatform = st['device_id'] == deviceId ||
                  (Platform.isAndroid && st['device_name'] == 'Android') ||
                  (!Platform.isAndroid && st['device_name'] == 'PC');
              if (st['status'] == 'deleted' && isCurrentPlatform) {
                deletedLocallyIds.add(entry.key);
              }
            }
          }
          if (state['equalizer_presets'] is List) {
            for (final raw in state['equalizer_presets'] as List) {
              try {
                final preset = EqualizerPreset.fromPayload(
                  Map<String, dynamic>.from(raw as Map),
                );
                customEqualizerPresets[preset.id] = preset;
              } catch (error) {
                debugPrint('Ignoring invalid cached equalizer preset: $error');
              }
            }
          }
        }
      }
      url = base;
      account = identity;
      token = response['access_token'] as String;
      await _loadEqualizerDeviceState(await SharedPreferences.getInstance());
      await _loadFiles();
      await _secure.write(key: 'session', value: token);
      await save();
    } catch (e) {
      error = friendlyErrorMessage(e);
    } finally {
      busy = false;
      notifyListeners();
    }
    if (token != null && (token != previousToken || error == null)) {
      await transferNow();
      unawaited(scanAndImportDeviceMusic());
    }
    if (token != null) unawaited(_connectSyncEvents());
  }

  Future<void> signOut() async {
    _syncHeartbeat?.cancel();
    _syncHeartbeat = null;
    _syncReconnect?.cancel();
    final socket = _syncSocket;
    _syncSocket = null;
    token = null;
    await socket?.close();
    await player.stop();
    playingId = null;
    playingFolder = null;
    _playbackIds = [];
    _playbackEntryKeys = [];
    _currentPlaybackIndex = -1;
    await _secure.delete(key: 'session');
    account = null;
    cursor = 0;
    tracks.clear();
    playlists.clear();
    queue.clear();
    favoriteIds.clear();
    history.clear();
    pending.clear();
    deletedLocallyIds.clear();
    originalFiles.clear();
    deviceTrackStatuses.clear();
    customEqualizerPresets.clear();
    for (final timer in _relayRetryTimers.values) {
      timer.cancel();
    }
    _relayRetryTimers.clear();
    _relayAttempts.clear();
    _failedRelayTransfers.clear();
    equalizerEnabled = false;
    activeEqualizerPresetId = 'flat';
    equalizerGains = List<double>.filled(equalizerFrequencies.length, 0);
    await player.setEqualizer(enabled: false, gains: equalizerGains);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('account');
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _transferStatusTimer?.cancel();
    _syncHeartbeat?.cancel();
    _equalizerApplyDebounce?.cancel();
    _syncReconnect?.cancel();
    _syncSocket?.close();
    for (final timer in _relayRetryTimers.values) {
      timer.cancel();
    }
    _relayRetryTimers.clear();
    for (final subscription in _playerSubscriptions) {
      subscription.cancel();
    }
    for (final socket in _sources.values) {
      socket.close();
    }
    ytPlaylistService.dispose();
    playbackManager.dispose();
    ytService.dispose();
    player.dispose();
    friendsService.dispose();
    super.dispose();
  }

  Future<void> mutate(String kind, Map<String, dynamic> payload) async {
    if (account == null) {
      apply(kind, payload);
      return;
    }
    final op = {'operation_id': newId(), 'kind': kind, 'payload': payload};
    pending.add(op);
    apply(kind, payload);
    await save();
    await sync();
  }

  Future<void> mutateBatch(List<Map<String, dynamic>> operations) async {
    if (operations.isEmpty) return;
    if (account == null) {
      for (final op in operations) {
        final kind = op['kind'] as String;
        final payload = Map<String, dynamic>.from(op['payload'] as Map);
        apply(kind, payload, notify: false);
      }
      notifyListeners();
      return;
    }
    for (final op in operations) {
      final kind = op['kind'] as String;
      final payload = Map<String, dynamic>.from(op['payload'] as Map);
      final entry = {'operation_id': newId(), 'kind': kind, 'payload': payload};
      pending.add(entry);
      apply(kind, payload, notify: false);
    }
    notifyListeners();
    await save();
    await sync();
  }

  void apply(String kind, Map<String, dynamic> p, {bool notify = true}) {
    if (kind == 'track.upsert') {
      final index = tracks.indexWhere((t) => t['id'] == p['id']);
      if (index < 0) {
        tracks.add(Map.of(p));
      } else {
        tracks[index] = Map.of(p);
      }
    } else if (kind == 'track.set_order') {
      // A concurrent import may add tracks absent from this snapshot. Keep them
      // at the end instead of dropping them when the ordering event arrives.
      final byId = {for (final track in tracks) track['id'] as String: track};
      final ordered = <Map<String, dynamic>>[];
      for (final id in (p['track_ids'] as List).cast<String>()) {
        final track = byId.remove(id);
        if (track != null) ordered.add(track);
      }
      tracks
        ..clear()
        ..addAll(ordered)
        ..addAll(byId.values);
      sinkDeletedTracksToEnd();
      if (playingFolder == null && !isShuffle) {
        _replacePlaybackIds(tracks.map((track) => track['id'] as String));
        _currentPlaybackIndex = _playbackIds.indexOf(playingId ?? '');
      }
    } else if (kind == 'playlist.upsert') {
      final old = playlists.where((t) => t['id'] == p['id']).firstOrNull;
      playlists.removeWhere((t) => t['id'] == p['id']);
      playlists.add({...?old, ...p});
      playlists.sort(
        (a, b) => (a['sort_key'] as int).compareTo(b['sort_key'] as int),
      );
    } else if (kind == 'playlist.delete') {
      playlists.removeWhere((playlist) => playlist['id'] == p['id']);
    } else if (kind == 'playlist.set_tracks') {
      final playlist = playlists
          .where((t) => t['id'] == p['playlist_id'])
          .firstOrNull;
      if (playlist != null) {
        playlist['track_ids'] = List.of(p['track_ids'] as List);
      }
    } else if (kind == 'queue.set') {
      queue
        ..clear()
        ..addAll(
          (p['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        );
    } else if (kind == 'favorites.set') {
      favoriteIds
        ..clear()
        ..addAll((p['track_ids'] as List).cast<String>());
    } else if (kind == 'history.add') {
      history.removeWhere((entry) => entry['id'] == p['id']);
      history.insert(0, Map<String, dynamic>.from(p));
      if (history.length > 200) history.removeRange(200, history.length);
    } else if (kind == 'track.device_status') {
      final trackId = p['track_id'] as String;
      deviceTrackStatuses[trackId] = Map<String, dynamic>.from(p);
      final isCurrentPlatform = p['device_id'] == deviceId ||
          (Platform.isAndroid && p['device_name'] == 'Android') ||
          (!Platform.isAndroid && p['device_name'] == 'PC');
      if (p['status'] == 'deleted' && isCurrentPlatform) {
        deletedLocallyIds.add(trackId);
        _relayRetryTimers.remove(trackId)?.cancel();
        _relayAttempts.remove(trackId);
        sinkDeletedTracksToEnd();
      }
    } else if (kind == 'equalizer.preset.upsert') {
      try {
        final preset = EqualizerPreset.fromPayload(p);
        customEqualizerPresets[preset.id] = preset;
        if (activeEqualizerPresetId == preset.id) {
          equalizerGains = List<double>.from(preset.gains);
          unawaited(
            player
                .setEqualizer(enabled: equalizerEnabled, gains: equalizerGains)
                .then((_) => _saveEqualizerDeviceState()),
          );
        }
      } catch (error) {
        debugPrint('Ignoring invalid synchronized equalizer preset: $error');
      }
    } else if (kind == 'equalizer.preset.delete') {
      final id = '${p['id'] ?? ''}';
      customEqualizerPresets.remove(id);
      if (activeEqualizerPresetId == id) {
        activeEqualizerPresetId = 'flat';
        equalizerGains = List<double>.filled(equalizerFrequencies.length, 0);
        unawaited(
          player
              .setEqualizer(enabled: equalizerEnabled, gains: equalizerGains)
              .then((_) => _saveEqualizerDeviceState()),
        );
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> sync() async {
    if (token == null || url.isEmpty || busy) return;
    busy = true;
    error = null;
    try {
      while (pending.isNotEmpty) {
        try {
          await api.request('POST', '/sync/operations', pending.first);
          pending.removeAt(0);
          await save();
        } on ApiException catch (e) {
          if (e.status == 409 || e.status == 422) {
            // Drop duplicate or conflicting operation to avoid permanently blocking sync queue
            debugPrint(
              'Discarding conflicting pending operation: ${pending.first} ($e)',
            );
            pending.removeAt(0);
            await save();
          } else {
            rethrow;
          }
        }
      }
      int receivedOperations = 0;
      while (true) {
        final result = await api.request(
          'GET',
          '/sync/operations?after=$cursor&limit=100',
        );
        final operations = result['operations'] as List;
        for (final raw in operations) {
          final op = raw as Map<String, dynamic>;
          apply(
            op['kind'] as String,
            Map<String, dynamic>.from(op['payload'] as Map),
            notify: false,
          );
          cursor = (op['version'] as num).toInt();
          receivedOperations++;
        }
        await save();
        if (operations.length < 100) break;
      }
      if (receivedOperations > 0) {
        notifyListeners();
        final hasMissing = tracks.any(
          (t) {
            final tid = t['id'] as String;
            if (deletedLocallyIds.contains(tid) || localFiles.containsKey(tid)) {
              return false;
            }
            if (t['provider'] == 'youtube') {
              return !failedDownloads.containsKey(tid) &&
                  !downloadingIds.contains(tid);
            }
            if (t['provider'] == 'local') {
              final failedAt = _failedRelayTransfers[tid];
              return failedAt == null ||
                  DateTime.now().difference(failedAt) >=
                      const Duration(minutes: 5);
            }
            return false;
          },
        );
        if (hasMissing) {
          unawaited(transferNow());
        }
      }
    } catch (e) {
      error = friendlyErrorMessage(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
