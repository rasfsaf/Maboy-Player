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
import 'services/device_music_service.dart';
import 'services/local_metadata_service.dart';
import 'services/media_service.dart';
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
  final MaboyAudioPlayer player = MaboyAudioPlayer();
  final YouTubeDownloadService ytService = YouTubeDownloadService();
  final YouTubePlaylistService ytPlaylistService = YouTubePlaylistService();
  late final PlaybackManager playbackManager;
  final Map<String, String> localFiles = {};
  final Map<String, String> artworkFiles = {};
  final Map<String, double> downloadProgress = {};
  final Set<String> downloadingIds = {};

  final Map<String, WebSocket> _sources = {};
  final Map<String, Future<void>> _receives = {};
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  WebSocket? _syncSocket;
  Timer? _syncReconnect;
  List<String> _playbackIds = [];
  List<String> _playbackEntryKeys = [];
  int _playbackEntrySerial = 0;
  int _currentPlaybackIndex = -1;
  Timer? _poll;
  Timer? _equalizerApplyDebounce;
  bool _transferring = false;
  bool _switchingTrack = false;
  String deviceId = '';
  String? playingId;
  String? playingFolder;
  String transferStatus = '';

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

  SyncApi get api => SyncApi(url, token);

  AppController() {
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

    MediaService.listenToBecomingNoisy(() {
      if (player.playing) {
        unawaited(player.pause());
      }
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
      if (result.length == 12) break;
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
  bool get hasNext => isShuffle
      ? _playbackIds.isNotEmpty
      : (playbackManager.repeatMode == RepeatMode.all
            ? _playbackIds.isNotEmpty
            : (currentPlaybackIndex >= 0 &&
                  currentPlaybackIndex < _playbackIds.length - 1));

  bool isFavorite(String trackId) => favoriteIds.contains(trackId);

  Future<void> toggleFavorite(String trackId) {
    final ids = List<String>.from(favoriteIds);
    ids.contains(trackId) ? ids.remove(trackId) : ids.add(trackId);
    return mutate('favorites.set', {'track_ids': ids});
  }

  Future<void> togglePlayback() async {
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
      var current = currentPlaybackIndex;
      if (current < 0 && playingId != null) {
        playingFolder = folderId ?? playingFolder;
        _replacePlaybackIds(_naturalPlaybackIds(playingFolder));
        _currentPlaybackIndex = _playbackIds.indexOf(playingId!);
        current = _currentPlaybackIndex;
      }
      if (current >= 0 && current < _playbackIds.length - 1) {
        // Shuffle only what has not played yet. Replacing the audio source here
        // would restart the current track, so this operation only edits order.
        final random = Random.secure();
        for (
          var index = _playbackIds.length - 1;
          index > current + 1;
          index--
        ) {
          final swapWith = current + 1 + random.nextInt(index - current);
          final id = _playbackIds[index];
          _playbackIds[index] = _playbackIds[swapWith];
          _playbackIds[swapWith] = id;
          final key = _playbackEntryKeys[index];
          _playbackEntryKeys[index] = _playbackEntryKeys[swapWith];
          _playbackEntryKeys[swapWith] = key;
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
    _playbackIds = List<String>.from(ids);
    _playbackEntryKeys = List<String>.generate(
      _playbackIds.length,
      (_) => 'playback-${_playbackEntrySerial++}',
      growable: true,
    );
  }

  Future<void> startShuffle({String? folderId, String? startTrackId}) async {
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

    if (pool.isEmpty) return;

    final rng = Random.secure();
    final shuffled = List<String>.from(pool);
    for (var i = shuffled.length - 1; i > 0; i--) {
      var n = rng.nextInt(i + 1);
      var temp = shuffled[i];
      shuffled[i] = shuffled[n];
      shuffled[n] = temp;
    }

    if (startTrackId != null && shuffled.contains(startTrackId)) {
      shuffled.remove(startTrackId);
      shuffled.insert(0, startTrackId);
    }

    _replacePlaybackIds(shuffled);
    _currentPlaybackIndex = startTrackId != null ? 0 : -1;
    playingFolder = scopeFolder;

    final targetId = shuffled.first;
    final track = tracks.where((t) => t['id'] == targetId).firstOrNull;
    if (track != null) {
      await playTrack(
        track,
        folderId: scopeFolder,
        playbackIds: shuffled,
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
      final track = tracks.where((t) => t['id'] == prevId).firstOrNull;
      if (track != null) {
        await playTrack(
          track,
          folderId: playingFolder,
          playbackIds: _playbackIds,
          playbackIndex: i,
        );
        return;
      }
    }
  }

  Future<void> playNext() async {
    if (_switchingTrack) return;
    if (_playbackIds.isEmpty) return;
    final idx = currentPlaybackIndex;
    for (var i = idx + 1; i < _playbackIds.length; i++) {
      final nextId = _playbackIds[i];
      final track = tracks.where((t) => t['id'] == nextId).firstOrNull;
      if (track != null) {
        await playTrack(
          track,
          folderId: playingFolder,
          playbackIds: _playbackIds,
          playbackIndex: i,
        );
        return;
      }
    }
    if (isShuffle) {
      // Completed current shuffled deck: reshuffle without repeats for next cycle
      await startShuffle(folderId: playingFolder);
    } else if (playbackManager.repeatMode == RepeatMode.all) {
      // Loop back to the beginning of the playlist/tracklist
      for (var i = 0; i <= idx && i < _playbackIds.length; i++) {
        final nextId = _playbackIds[i];
        final track = tracks.where((t) => t['id'] == nextId).firstOrNull;
        if (track != null) {
          await playTrack(
            track,
            folderId: playingFolder,
            playbackIds: _playbackIds,
            playbackIndex: i,
          );
          return;
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
      queryParameters: {'token': token!},
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
      socket.listen(
        (message) {
          if (message is String) {
            try {
              final data = jsonDecode(message) as Map<String, dynamic>;
              if (data['type'] == 'relay_request') {
                final trackId = data['track_id'] as String?;
                if (trackId != null && localFiles.containsKey(trackId)) {
                  final track = tracks
                      .where((t) => t['id'] == trackId)
                      .firstOrNull;
                  if (track != null) {
                    unawaited(_connectSource(track));
                  }
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
    artworkFiles.clear();
    final saved = prefs.getString('files_$account');
    if (saved != null) {
      final rawMap = Map<String, String>.from(jsonDecode(saved) as Map);
      for (final entry in rawMap.entries) {
        final trackId = entry.key;
        final path = entry.value;
        final file = File(path);
        if (file.existsSync()) {
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
              if (!localFiles.containsKey(tid) &&
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
                if (!localFiles.containsKey(tid) && (dest.path.contains(tid))) {
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
    await prefs.setString('art_$account', jsonEncode(artworkFiles));
  }

  Uri _relayUri(String id, String role) {
    final base = Uri.parse(url);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/relay/$id/$role',
      queryParameters: {
        'token': token!,
        if (role == 'source') 'device': deviceId,
      },
    );
  }

  Future<void> _connectSource(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    final path = localFiles[id];
    if (path == null ||
        !await File(path).exists() ||
        _sources.containsKey(id)) {
      return;
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

  Future<void> _receive(Map<String, dynamic> track) {
    final id = track['id'] as String;
    final existing = _receives[id];
    if (existing != null) return existing;

    final receive = _receiveImpl(track);
    _receives[id] = receive;
    return receive.whenComplete(() => _receives.remove(id));
  }

  Future<void> _receiveImpl(Map<String, dynamic> track) async {
    final id = track['id'] as String;
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
    final temp = File('${directory.path}/$id.part');
    for (var attempt = 1; attempt <= 3; attempt++) {
      WebSocket? socket;
      IOSink? sink;
      var completed = false;
      var fatal = false;
      try {
        transferStatus = attempt == 1
            ? 'Получение: ${track['title']}'
            : 'Повторное получение ($attempt/3): ${track['title']}';
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
          } else if (message == 'done') {
            await output.flush();
            await output.close();
            sink = null;
            await temp.rename(target.path);
            localFiles[id] = target.path;
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
        debugPrint('Error in _receive for track $id (attempt $attempt): $e');
        final str = e.toString().toLowerCase();
        if (str.contains('403') || str.contains('401') || str.contains('404')) {
          fatal = true;
        }
      } finally {
        await sink?.close();
        await socket?.close();
      }
      if (completed || fatal) return;
      if (await temp.exists()) await temp.delete();
      if (attempt < 3) {
        await Future<void>.delayed(Duration(seconds: attempt));
      }
    }
  }

  Future<void> transferNow() async {
    if (_transferring || token == null) return;
    _transferring = true;
    try {
      await sync();
      final localTracks = List<Map<String, dynamic>>.from(
        tracks.where((t) => t['provider'] == 'local'),
      );
      final youtubeTracks = List<Map<String, dynamic>>.from(
        tracks.where((t) => t['provider'] == 'youtube'),
      );

      // 1. Trigger background download for missing YouTube tracks
      for (final track in youtubeTracks) {
        final trackId = track['id'] as String;
        if (!localFiles.containsKey(trackId) &&
            !downloadingIds.contains(trackId)) {
          unawaited(downloadYouTubeTrack(track));
        }
      }

      // 2. Connect sources for local tracks present on this device
      for (final track in localTracks) {
        final trackId = track['id'] as String;
        if (deletedLocallyIds.contains(trackId)) continue;
        if (localFiles.containsKey(trackId)) {
          // Keep up to 10 active connections simultaneously; remaining tracks seed on-demand via relay_request
          if (_sources.length < 10) {
            await _connectSource(track);
          }
        }
      }

      // 3. Receive local tracks that are missing on this device
      final missingLocal = localTracks.where((t) {
        final tid = t['id'] as String;
        return !deletedLocallyIds.contains(tid) && !localFiles.containsKey(tid);
      }).toList();

      int receivedCount = 0;
      int consecutiveFailures = 0;
      for (int i = 0; i < missingLocal.length; i++) {
        final track = missingLocal[i];
        final tid = track['id'] as String;
        transferStatus =
            'Получение (${i + 1}/${missingLocal.length}): ${track['title']}';
        notifyListeners();
        await _receive(track);
        if (localFiles.containsKey(tid)) {
          receivedCount++;
          consecutiveFailures = 0;
        } else {
          consecutiveFailures++;
          // If 3 consecutive tracks fail and none were received, the remote source is offline
          if (consecutiveFailures >= 3 && receivedCount == 0) {
            transferStatus = 'Устройство-источник пока недоступно в сети';
            notifyListeners();
            break;
          }
        }
      }

      if (missingLocal.isNotEmpty && consecutiveFailures < 3) {
        transferStatus = receivedCount > 0
            ? 'Передано треков: $receivedCount из ${missingLocal.length}'
            : 'Устройство-источник пока недоступно в сети';
        notifyListeners();
      }
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

  Future<void> downloadYouTubeTrack(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    final videoId = track['source_id'] as String;
    if (downloadingIds.contains(id)) return;
    downloadingIds.add(id);
    downloadProgress[id] = 0.0;
    notifyListeners();

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${docDir.path}/music');
      await musicDir.create(recursive: true);

      final outMp3Path = '${musicDir.path}/$id.mp3';
      final file = await ytService.downloadMp3(
        videoId: videoId,
        outputFilePath: outMp3Path,
        onProgress: (progress) {
          downloadProgress[id] = progress;
          notifyListeners();
        },
      );

      if (file != null && await file.exists()) {
        localFiles[id] = file.path;
      }

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
      transferStatus = 'MP3 скачан: ${track['title']}';
    } catch (_) {
      transferStatus = 'Ошибка скачивания: ${track['title']}';
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
        await playTrack(track);
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
      if (meta.artworkPath != null) {
        artworkFiles[id] = meta.artworkPath!;
      }

      await _saveFiles();
      ids.add(id);

      await mutate('track.upsert', {
        'id': id,
        'provider': 'local',
        'source_id': '$deviceId:$id',
        'title': meta.title,
        'artist': meta.artist,
        'album': meta.album,
        'duration_ms': meta.durationMs,
        'added_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (folder && ids.isNotEmpty) {
      final playlistId = newId();
      await mutate('playlist.upsert', {
        'id': playlistId,
        'name': name!,
        'sort_key': playlists.length,
      });
      await mutate('playlist.set_tracks', {
        'playlist_id': playlistId,
        'track_ids': ids,
      });
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
        if (localFiles.containsValue(filePath)) {
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
          localFiles[existingId] = filePath;
          if (meta.artworkPath != null &&
              !artworkFiles.containsKey(existingId)) {
            artworkFiles[existingId] = meta.artworkPath!;
          }
          continue;
        }

        // 4. Create new track
        final trackId = tempId;
        localFiles[trackId] = filePath;
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
    } catch (_) {}
    return null;
  }

  Future<void> playTrack(
    Map<String, dynamic> track, {
    String? folderId,
    List<String>? playbackIds,
    int? playbackIndex,
  }) async {
    if (_switchingTrack) return;
    _switchingTrack = true;
    try {
    final id = track['id'] as String;

    // Immediately highlight and select the track so the UI updates instantly
    playingId = id;
    playingFolder = folderId;
    if (playbackIds != null && playbackIds.isNotEmpty) {
      if (!listEquals(_playbackIds, playbackIds) ||
          _playbackEntryKeys.length != playbackIds.length) {
        _replacePlaybackIds(playbackIds);
      }
    } else if (folderId != null) {
      final playlist = playlists.where((p) => p['id'] == folderId).firstOrNull;
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
        await player.setAudioSource(source);
        unawaited(_recordHistory(id));
        await player.play();
      } catch (e) {
        debugPrint('Error playing local file: $e');
        transferStatus = 'Ошибка воспроизведения: $e';
      }
      notifyListeners();
      return;
    }

    // 2. If it's a YouTube track and not yet downloaded, stream immediately while downloading
    if (track['provider'] == 'youtube') {
      transferStatus = 'Подключение к потоку YouTube: ${track['title']}';
      notifyListeners();
      try {
        final streamUrl = await ytService.getStreamUrl(
          track['source_id'] as String,
        );
        if (streamUrl != null) {
          final source = MediaService.createAudioSource(
            trackId: id,
            title: track['title'] as String,
            artist: track['artist'] as String?,
            album: track['album'] as String?,
            streamUrl: streamUrl,
            localArtworkPath: artworkFiles[id],
            thumbnailNetworkUrl: track['thumbnail_url'] as String?,
          );
          await player.setAudioSource(source);
          unawaited(_recordHistory(id));
          await player.play();
          unawaited(downloadYouTubeTrack(track));
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('Error streaming YouTube: $e');
        transferStatus = 'Ошибка YouTube: $e';
      }
      notifyListeners();
      return;
    }

    // 3. Check if matching audio exists on device in music folders
    final foundPath = await _findLocalFileForTrack(track);
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
        unawaited(_recordHistory(id));
        await player.play();
      } catch (e) {
        debugPrint('Error playing discovered local audio: $e');
        transferStatus = 'Ошибка воспроизведения: $e';
      }
      notifyListeners();
      return;
    }

    // 4. Missing file on this device: trigger peer transfer
    transferStatus = 'Загрузка с другого устройства: ${track['title']}...';
    notifyListeners();
    // Do not wait for the whole batch here. The selected track can be
    // available while transferNow is still receiving other tracks.
    await _receive(track);
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
        unawaited(_recordHistory(id));
        await player.play();
      } catch (e) {
        debugPrint('Error playing transferred file: $e');
        transferStatus = 'Ошибка воспроизведения: $e';
      }
    } else {
      transferStatus = 'Файл пока не передан на это устройство';
    }
    notifyListeners();
    } finally {
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

  Future<void> setPlaylistTracks(String playlistId, Iterable<String> ids) =>
      mutate('playlist.set_tracks', {
        'playlist_id': playlistId,
        'track_ids': ids.toList(),
      });

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
    final item = tracks.removeAt(from);
    tracks.insert(to, item);
    await save();
    notifyListeners();
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
    for (final id in trackIds) {
      deletedLocallyIds.add(id);
      final path = localFiles.remove(id);
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      final art = artworkFiles.remove(id);
      if (art != null) {
        final af = File(art);
        if (af.existsSync()) {
          try {
            await af.delete();
          } catch (_) {}
        }
      }
    }
    await _saveFiles();
    await save();
    for (final id in trackIds) {
      await mutate('track.device_status', {
        'track_id': id,
        'device_id': deviceId,
        'device_name': Platform.isAndroid ? 'Android' : 'PC',
        'status': 'deleted',
      });
    }
    notifyListeners();
  }

  Future<void> restoreLocally(String trackId) async {
    deletedLocallyIds.remove(trackId);
    await save();
    unawaited(transferNow());
    notifyListeners();
  }

  Future<void> setQueue(Iterable<Map<String, dynamic>> items) =>
      mutate('queue.set', {'items': items.toList()});

  Future<void> addToQueue(String trackId, {bool next = false}) {
    final items = List<Map<String, dynamic>>.from(queue);
    items.insert(next ? 0 : items.length, {'id': newId(), 'track_id': trackId});
    return setQueue(items);
  }

  Future<void> shuffleQueue() async {
    final items = List<Map<String, dynamic>>.from(queue)
      ..shuffle(Random.secure());
    await setQueue(items);
  }

  Future<void> playQueueItem(Map<String, dynamic> item) async {
    final track = tracks
        .where((value) => value['id'] == item['track_id'])
        .firstOrNull;
    if (track == null) return;
    final playbackIds = queue
        .map((value) => value['track_id'] as String)
        .toList();
    final itemIndex = queue.indexWhere((value) => value['id'] == item['id']);
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
    final prefs = await SharedPreferences.getInstance();
    url = backendUrl;
    account = prefs.getString('account');
    token = await _secure.read(key: 'session');
    if (token != null && account != null) {
      await _loadFiles();
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
      error = '$e';
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
    deviceTrackStatuses.clear();
    customEqualizerPresets.clear();
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
    _equalizerApplyDebounce?.cancel();
    _syncReconnect?.cancel();
    _syncSocket?.close();
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
    super.dispose();
  }

  Future<void> mutate(String kind, Map<String, dynamic> payload) async {
    if (account == null) return;
    final op = {'operation_id': newId(), 'kind': kind, 'payload': payload};
    pending.add(op);
    apply(kind, payload);
    await save();
    await sync();
  }

  void apply(String kind, Map<String, dynamic> p) {
    if (kind == 'track.upsert') {
      tracks.removeWhere((t) => t['id'] == p['id']);
      tracks.add(Map.of(p));
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
    notifyListeners();
  }

  Future<void> sync() async {
    if (token == null || url.isEmpty || busy) return;
    busy = true;
    error = null;
    notifyListeners();
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
          );
          cursor = (op['version'] as num).toInt();
        }
        await save();
        if (operations.length < 100) break;
      }
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
