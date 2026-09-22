import 'dart:async';
import 'package:flutter/foundation.dart';

import 'audio_player.dart';

enum RepeatMode {
  off,
  all,
  one;

  RepeatMode next() {
    switch (this) {
      case RepeatMode.off:
        return RepeatMode.all;
      case RepeatMode.all:
        return RepeatMode.one;
      case RepeatMode.one:
        return RepeatMode.off;
    }
  }

  String get label {
    switch (this) {
      case RepeatMode.off:
        return 'Повтор выкл';
      case RepeatMode.all:
        return 'Повторять все';
      case RepeatMode.one:
        return 'Повторять один';
    }
  }
}

class PlaybackManager extends ChangeNotifier {
  PlaybackManager({required this.player, required this.onStopPlayback}) {
    _initSubscriptions();
  }

  final MaboyAudioPlayer player;
  final Future<void> Function() onStopPlayback;

  RepeatMode _repeatMode = RepeatMode.off;
  RepeatMode get repeatMode => _repeatMode;

  double _speed = 1.0;
  double get speed => _speed;

  Timer? _countdownTimer;
  int? _sleepTimerRemainingSeconds;
  int? get sleepTimerRemainingSeconds => _sleepTimerRemainingSeconds;
  bool _sleepAfterCurrentTrack = false;
  bool get sleepAfterCurrentTrack => _sleepAfterCurrentTrack;

  bool get isSleepTimerActive =>
      _sleepTimerRemainingSeconds != null || _sleepAfterCurrentTrack;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  void _initSubscriptions() {
    _subscriptions.add(
      player.speedStream.listen((currentSpeed) {
        if (_speed != currentSpeed) {
          _speed = currentSpeed;
          notifyListeners();
        }
      }),
    );
  }

  Future<void> setRepeatMode(RepeatMode mode) async {
    _repeatMode = mode;
    if (mode == RepeatMode.one) {
      await player.setLoopMode(LoopMode.one);
    } else {
      await player.setLoopMode(LoopMode.off);
    }
    notifyListeners();
  }

  Future<void> toggleRepeatMode() => setRepeatMode(_repeatMode.next());

  Future<void> setSpeed(double newSpeed) async {
    final clamped = newSpeed.clamp(0.5, 2.5);
    _speed = clamped;
    await player.setSpeed(clamped);
    notifyListeners();
  }

  Future<void> seekRelative(Duration delta) async {
    final current = player.position;
    final total = player.duration ?? Duration.zero;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await player.seek(target);
  }

  void startSleepTimer(Duration duration, {bool afterCurrentTrack = false}) {
    cancelSleepTimer();
    _sleepAfterCurrentTrack = afterCurrentTrack;

    if (afterCurrentTrack) {
      notifyListeners();
      return;
    }

    _sleepTimerRemainingSeconds = duration.inSeconds;
    notifyListeners();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerRemainingSeconds == null ||
          _sleepTimerRemainingSeconds! <= 1) {
        cancelSleepTimer();
        _fireSleepTimer();
      } else {
        _sleepTimerRemainingSeconds = _sleepTimerRemainingSeconds! - 1;
        notifyListeners();
      }
    });
  }

  void cancelSleepTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _sleepTimerRemainingSeconds = null;
    _sleepAfterCurrentTrack = false;
    notifyListeners();
  }

  void onTrackCompleted() {
    if (_sleepAfterCurrentTrack) {
      cancelSleepTimer();
      _fireSleepTimer();
    }
  }

  void _fireSleepTimer() {
    unawaited(onStopPlayback());
  }

  static String formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '--:--';
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remMinutes = minutes % 60;
      return '$hours:${remMinutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
