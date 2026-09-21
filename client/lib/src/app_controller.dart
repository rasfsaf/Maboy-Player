import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

String newId() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

class AppController extends ChangeNotifier {
  final AudioPlayer player = AudioPlayer();
  final Map<String, String> localFiles = {};
  final Map<String, WebSocket> _sources = {};
  Timer? _poll;
  bool _transferring = false;
  String deviceId = '';
  String? playingId;
  String? playingFolder;
  String transferStatus = '';

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => sync());
  }

  Future<void> _loadDevice() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('device_id') ?? newId();
    await prefs.setString('device_id', deviceId);
  }

  Future<void> _loadFiles() async {
    final prefs = await SharedPreferences.getInstance();
    localFiles.clear();
    final saved = prefs.getString('files_$account');
    if (saved != null) {
      localFiles.addAll(Map<String, String>.from(jsonDecode(saved) as Map));
    }
  }

  Future<void> _saveFiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('files_$account', jsonEncode(localFiles));
  }

  Uri _relayUri(String id, String role) {
    final base = Uri.parse(url);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/relay/$id/$role',
      queryParameters: {'token': token!, if (role == 'source') 'device': deviceId});
  }

  Future<void> _connectSource(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    final path = localFiles[id];
    if (path == null || !await File(path).exists() || _sources.containsKey(id)) return;
    try {
      final socket = await WebSocket.connect(_relayUri(id, 'source').toString());
      _sources[id] = socket;
      socket.listen((message) async {
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
      }, onDone: () { _sources.remove(id); }, onError: (_) { _sources.remove(id); });
    } catch (_) {
      // Retry on the next poll; no cooldown or permanent failure state.
    }
  }

  Future<void> _receive(Map<String, dynamic> track) async {
    final id = track['id'] as String;
    final directory = Directory('${(await getApplicationDocumentsDirectory()).path}/music');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$id.audio');
    final temp = File('${target.path}.part');
    WebSocket? socket;
    IOSink? sink;
    try {
      socket = await WebSocket.connect(_relayUri(id, 'receive').toString());
      sink = temp.openWrite();
      await for (final message in socket) {
        if (message is List<int>) {
          sink.add(message);
        } else if (message == 'done') {
          await sink.flush();
          await sink.close();
          sink = null;
          await temp.rename(target.path);
          localFiles[id] = target.path;
          await _saveFiles();
          transferStatus = 'Получено: ${track['title']}';
          notifyListeners();
          return;
        } else if (message == 'retry') {
          break;
        }
      }
    } catch (_) {
      // The source may be offline; leave the track pending for the next poll.
    } finally {
      await sink?.close();
      await socket?.close();
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> transferNow() async {
    if (_transferring || token == null) return;
    _transferring = true;
    try {
      await sync();
      for (final track in List<Map<String, dynamic>>.from(tracks.where((t) => t['provider'] == 'local'))) {
        if (localFiles.containsKey(track['id'])) {
          await _connectSource(track);
        } else {
          transferStatus = 'Ожидание устройства с файлом: ${track['title']}';
          notifyListeners();
          await _receive(track);
        }
      }
    } finally {
      _transferring = false;
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
      await for (final entry in Directory(selected).list(recursive: true, followLinks: false)) {
        if (entry is File && _isAudio(entry.path)) paths.add(entry.path);
      }
    } else {
      final selected = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
      if (selected == null) return;
      paths.addAll(selected.files.map((f) => f.path).whereType<String>());
    }
    final ids = <String>[];
    final directory = Directory('${(await getApplicationDocumentsDirectory()).path}/music');
    await directory.create(recursive: true);
    for (final path in paths) {
      final id = newId();
      final title = path.split(Platform.pathSeparator).last;
      final target = File('${directory.path}/$id.audio');
      await File(path).copy(target.path);
      localFiles[id] = target.path;
      await _saveFiles();
      ids.add(id);
      await mutate('track.upsert', {'id': id, 'provider': 'local',
        'source_id': deviceId, 'title': title, 'artist': null});
    }
    if (folder && ids.isNotEmpty) {
      final playlistId = newId();
      await mutate('playlist.upsert', {'id': playlistId, 'name': name!, 'sort_key': playlists.length});
      await mutate('playlist.set_tracks', {'playlist_id': playlistId, 'track_ids': ids});
    }
    await transferNow();
  }

  bool _isAudio(String path) => RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav|flac)$', caseSensitive: false).hasMatch(path);

  Future<void> playTrack(Map<String, dynamic> track, {String? folderId}) async {
    final path = localFiles[track['id']];
    if (path == null || !await File(path).exists()) {
      await transferNow();
      if (localFiles[track['id']] == null) return;
    }
    playingId = track['id'] as String;
    playingFolder = folderId;
    final ids = folderId == null
        ? tracks.map((t) => t['id']).toList()
        : (playlists.where((p) => p['id'] == folderId).firstOrNull?['track_ids'] as List? ?? []);
    final playable = ids.where((id) => localFiles.containsKey(id)).toList();
    final index = playable.indexOf(playingId);
    await player.setAudioSource(
      ConcatenatingAudioSource(children: playable.map((id) => AudioSource.file(localFiles[id]!)).toList()),
      initialIndex: index < 0 ? 0 : index,
    );
    await player.play();
    notifyListeners();
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
  final List<Map<String, dynamic>> pending = [];

  SyncApi get api => SyncApi(url, token);

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
          (data['tracks'], tracks), (data['playlists'], playlists),
          (data['queue'], queue), (data['pending'], pending),
        ]) {
          if (source is List) dest.addAll(source.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
    }
    _startPolling();
    if (token != null) unawaited(transferNow());
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (account != null) {
      await prefs.setString('account', account!);
      await prefs.setString('state_$account', jsonEncode({
        'cursor': cursor, 'tracks': tracks, 'playlists': playlists,
        'queue': queue, 'pending': pending,
      }));
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password, {bool register = false}) async {
    const base = backendUrl;
    final address = email.trim().toLowerCase();
    final previousToken = token;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final response = await SyncApi(base, null).request('POST',
          register ? '/auth/register' : '/auth/login', {'email': address, 'password': password});
      final identity = '$base|$address';
      if (identity != account) {
        tracks.clear(); playlists.clear(); queue.clear(); pending.clear(); cursor = 0;
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getString('state_$identity');
        if (saved != null) {
          final state = jsonDecode(saved) as Map<String, dynamic>;
          cursor = (state['cursor'] as num?)?.toInt() ?? 0;
          for (final (source, dest) in [
            (state['tracks'], tracks), (state['playlists'], playlists),
            (state['queue'], queue), (state['pending'], pending),
          ]) {
            if (source is List) dest.addAll(source.map((e) => Map<String, dynamic>.from(e as Map)));
          }
        }
      }
      url = base;
      account = identity;
      token = response['access_token'] as String;
      await _loadFiles();
      await _secure.write(key: 'session', value: token);
      await save();
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
    if (token != null && (token != previousToken || error == null)) await transferNow();
  }

  Future<void> signOut() async {
    await _secure.delete(key: 'session');
    token = null;
    account = null;
    cursor = 0;
    tracks.clear(); playlists.clear(); queue.clear(); pending.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('account');
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final socket in _sources.values) {
      socket.close();
    }
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
      playlists.sort((a, b) => (a['sort_key'] as int).compareTo(b['sort_key'] as int));
    } else if (kind == 'playlist.set_tracks') {
      final playlist = playlists.where((t) => t['id'] == p['playlist_id']).firstOrNull;
      if (playlist != null) playlist['track_ids'] = List.of(p['track_ids'] as List);
    } else if (kind == 'queue.set') {
      queue..clear()..addAll((p['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
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
        await api.request('POST', '/sync/operations', pending.first);
        pending.removeAt(0);
        await save();
      }
      while (true) {
        final result = await api.request('GET', '/sync/operations?after=$cursor&limit=100');
        final operations = result['operations'] as List;
        for (final raw in operations) {
          final op = raw as Map<String, dynamic>;
          apply(op['kind'] as String, Map<String, dynamic>.from(op['payload'] as Map));
          cursor = (op['version'] as num).toInt();
        }
        await save();
        if (operations.length < 100) break;
      }
      unawaited(transferNow());
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}