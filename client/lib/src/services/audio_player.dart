import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' as mpv;

// Re-export so callers can reference Channels without depending on mpv_audio_kit
// directly. They use MaboyAudioPlayer.setAudioChannels(mpv.Channels.stereo), etc.
export 'package:mpv_audio_kit/mpv_audio_kit.dart' show Channels;

enum ProcessingState { idle, loading, ready, completed }

enum LoopMode { off, one }

class MaboyPlayerState {
  const MaboyPlayerState({
    required this.playing,
    required this.processingState,
  });

  final bool playing;
  final ProcessingState processingState;
}

class MaboyAudioSource {
  const MaboyAudioSource({
    required this.trackId,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    this.artworkUri,
    this.isNetwork = false,
  });

  final String trackId;
  final Uri uri;
  final String title;
  final String artist;
  final String album;
  final Uri? artworkUri;
  final bool isNetwork;
}

/// Compatibility boundary between the application and mpv_audio_kit.
///
/// Native resources are intentionally created only when media is opened. This
/// keeps controller and widget tests deterministic while still using the exact
/// production engine for Windows and Android playback.
class MaboyAudioPlayer {
  bool get _isTestEnv => Platform.environment.containsKey('FLUTTER_TEST');
  mpv.Player? _native;
  MaboyAudioSource? _audioSource;
  final List<StreamSubscription<dynamic>> _nativeSubscriptions = [];

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration? _duration;
  double _volume = 1;
  double _speed = 1;
  LoopMode _loopMode = LoopMode.off;
  ProcessingState _processingState = ProcessingState.idle;
  bool _equalizerEnabled = false;
  List<double> _equalizerGains = List<double>.filled(6, 0);
  bool _unsolicitedPlayBlocked = false;
  bool _disposed = false;

  /// Output channel layout. Defaults to stereo so mono source files are
  /// always upscaled to L+R instead of staying single-channel.
  mpv.Channels _audioChannels = mpv.Channels.stereo;

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _speedController = StreamController<double>.broadcast();
  final _stateController = StreamController<MaboyPlayerState>.broadcast();

  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;
  Future<void> Function(dynamic error)? onError;

  bool get playing => _playing;
  Duration get position => _position;
  Duration? get duration => _duration;
  double get speed => _speed;
  MaboyAudioSource? get audioSource => _audioSource;
  bool get unsolicitedPlayBlocked => _unsolicitedPlayBlocked;

  Stream<bool> get playingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<double> get speedStream => _speedController.stream;
  Stream<MaboyPlayerState> get playerStateStream => _stateController.stream;

  void _emitState() {
    if (_disposed) return;
    _stateController.add(
      MaboyPlayerState(playing: _playing, processingState: _processingState),
    );
  }

  Future<mpv.Player> _ensureNative() async {
    if (_disposed) throw StateError('Audio player is disposed');
    final existing = _native;
    if (existing != null) return existing;

    mpv.MpvAudioKit.ensureInitialized();
    final player = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        initialVolume: _volume * 100,
        autoPlay: false,
        forceSeekable: true,
      ),
    );
    _native = player;

    _nativeSubscriptions.addAll([
      player.stream.playWhenReady.listen((value) {
        _playing = value;
        _playingController.add(value);
        _emitState();
      }),
      player.stream.position.listen((value) {
        _position = value;
        _positionController.add(value);
      }),
      player.stream.duration.listen((value) {
        _duration = value;
        _durationController.add(value);
      }),
      player.stream.rate.listen((value) {
        _speed = value;
        _speedController.add(value);
      }),
      player.stream.completed.listen((completed) {
        if (!completed) return;
        _playing = false;
        _processingState = ProcessingState.completed;
        _playingController.add(false);
        _emitState();
      }),
      player.stream.error.listen((error) {
        debugPrint('mpv playback error: $error');
        final callback = onError;
        if (callback != null) unawaited(callback(error));
      }),
      player.stream.mediaSessionCommands.listen((command) {
        if (command is mpv.MediaSessionCommandNext) {
          final callback = onNext;
          if (callback != null) unawaited(callback());
        } else if (command is mpv.MediaSessionCommandPrevious) {
          final callback = onPrevious;
          if (callback != null) unawaited(callback());
        } else if (command is mpv.MediaSessionCommandPlay ||
            command is mpv.MediaSessionCommandPlayPause) {
          if (_unsolicitedPlayBlocked) {
            debugPrint(
              'Suppressing unsolicited remote play command while blocked after disconnect',
            );
            unawaited(player.pause());
          }
        }
      }),
    ]);

    await player.setLoop(
      _loopMode == LoopMode.one ? mpv.Loop.file : mpv.Loop.off,
    );
    await player.setRate(_speed);
    await _applyEqualizer(player);
    await _applyChannels(player);
    return player;
  }

  Future<void> setAudioSource(MaboyAudioSource source) async {
    _audioSource = source;
    _position = Duration.zero;
    _duration = null;
    _processingState = ProcessingState.loading;
    _positionController.add(_position);
    _durationController.add(_duration);
    _emitState();

    if (_isTestEnv) {
      _processingState = ProcessingState.ready;
      _emitState();
      return;
    }
    final player = await _ensureNative();
    final artwork = source.artworkUri == null
        ? mpv.MediaSessionArtwork.embedded
        : mpv.MediaSessionArtwork.uri(source.artworkUri!);
    await player.setMediaSession(
      mpv.MediaSession(
        title: source.title,
        artist: source.artist,
        album: source.album,
        artwork: artwork,
        appName: 'maboy',
        autoApplyPlaylistNavigation: false,
        // pauseOnly: a Telegram voice note, a call or any other app can pause
        // us by taking audio focus, but must never resume Maboy when it lets
        // the focus go. The plugin default is pauseAndResume, and every
        // setMediaSession resets to that default unless told otherwise.
        interruptionPolicy: mpv.InterruptionPolicy.pauseOnly,
      ),
    );
    await player.open(
      mpv.Media(
        source.uri.toString(),
        extras: {
          'trackId': source.trackId,
          'title': source.title,
          'artist': source.artist,
          'album': source.album,
        },
        httpChunkSize: source.isNetwork ? 8 * 1024 * 1024 : null,
      ),
      play: false,
    );
    _processingState = ProcessingState.ready;
    _emitState();
  }

  Future<void> play() async {
    _unsolicitedPlayBlocked = false;
    if (_audioSource == null) return;
    if (_isTestEnv) {
      _playing = true;
      _playingController.add(true);
      _emitState();
      return;
    }
    final player = await _ensureNative();
    await player.play();
  }

  void clearUnsolicitedPlayBlock() {
    _unsolicitedPlayBlocked = false;
  }

  Future<void> pauseDueToBecomingNoisy() async {
    _unsolicitedPlayBlocked = true;
    _playing = false;
    _playingController.add(false);
    _emitState();
    final player = _native;
    if (player != null) {
      await player.pause();
    }
  }

  Future<void> pause() async {
    if (_isTestEnv) {
      _playing = false;
      _playingController.add(false);
      _emitState();
      return;
    }
    final player = _native;
    if (player == null) return;
    await player.pause();
  }

  Future<void> stop() async {
    if (!_isTestEnv) {
      final player = _native;
      if (player != null) await player.stop();
    }
    _playing = false;
    _position = Duration.zero;
    _processingState = ProcessingState.idle;
    _playingController.add(false);
    _positionController.add(_position);
    _emitState();
  }

  Future<void> seek(Duration target) async {
    _position = target;
    _positionController.add(target);
    if (_isTestEnv) return;
    final player = _native;
    if (player == null) return;
    await player.seek(target, exact: true);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0, 1);
    final player = _native;
    if (player != null) await player.setVolume(_volume * 100);
  }

  Future<void> setSpeed(double value) async {
    _speed = value.clamp(0.5, 2.5);
    final player = _native;
    if (player != null) await player.setRate(_speed);
    _speedController.add(_speed);
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
    final player = _native;
    if (player != null) {
      await player.setLoop(mode == LoopMode.one ? mpv.Loop.file : mpv.Loop.off);
    }
  }

  Future<void> setEqualizer({
    required bool enabled,
    required List<double> gains,
  }) async {
    if (gains.length != 6 || gains.any((gain) => gain < -12 || gain > 12)) {
      throw ArgumentError('Equalizer requires six gains from -12 to +12 dB');
    }
    _equalizerEnabled = enabled;
    _equalizerGains = List<double>.from(gains, growable: false);
    final player = _native;
    if (player != null) await _applyEqualizer(player);
  }

  Future<void> _applyEqualizer(mpv.Player player) async {
    if (!_equalizerEnabled) {
      await player.setAudioEffects(const mpv.AudioEffects());
      await player.setVolumeGain(0);
      return;
    }
    const frequencies = [60, 150, 400, 1000, 2400, 15000];
    final entries = List.generate(
      frequencies.length,
      (index) => 'entry(${frequencies[index]},${_equalizerGains[index]})',
    ).join(';');
    await player.setAudioEffects(
      mpv.AudioEffects(
        firequalizer: mpv.FirequalizerSettings(
          enabled: true,
          gain: 'gain_interpolate(f)',
          gain_entry: entries,
          zero_phase: true,
        ),
      ),
    );
    final maximumBoost = _equalizerGains.fold<double>(
      0,
      (a, b) => a > b ? a : b,
    );
    await player.setVolumeGain(-maximumBoost.clamp(0, 12).toDouble());
  }

  /// Changes the output channel layout. Defaults to [mpv.Channels.stereo] so
  /// mono source files are always upscaled to L+R.
  ///
  /// Pass [mpv.Channels.mono] to fold both channels into one (useful for
  /// hearing-aid / single-earbud scenarios). Pass [mpv.Channels.auto] to
  /// restore mpv's automatic detection.
  Future<void> setAudioChannels(mpv.Channels channels) async {
    _audioChannels = channels;
    final player = _native;
    if (player != null) await _applyChannels(player);
  }

  Future<void> _applyChannels(mpv.Player player) async {
    await player.setAudioChannels(_audioChannels);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _nativeSubscriptions) {
      await subscription.cancel();
    }
    await _native?.dispose();
    await Future.wait([
      _playingController.close(),
      _positionController.close(),
      _durationController.close(),
      _speedController.close(),
      _stateController.close(),
    ]);
  }
}
