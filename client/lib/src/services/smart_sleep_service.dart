import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_player.dart';

/// Finite State Machine states for Smart Sleep Mode according to sleep.md.
enum SmartSleepState {
  /// Mode disabled or player is stopped. Sensor listeners and timers are inactive.
  idle,

  /// Track is playing. Inactivity timer is ticking.
  /// Telemetry / sensor micro-movements update last_movement_ts.
  /// Explicit user activity resets the inactivity timer.
  monitoring,

  /// Inactivity timeout elapsed or confident Sleep API signal received.
  /// Audio is fading out smoothly via non-linear quadratic curve.
  /// Accelerometer listens for Shake-to-Cancel.
  fading,

  /// Player is paused. Volume is restored to initial level V0 strictly after pause.
  /// Controller immediately transitions back to idle.
  stopped,
}

/// Configuration parameters for Smart Sleep Mode with defaults from sleep.md.
class SmartSleepConfig {
  const SmartSleepConfig({
    this.inactivityTimeoutMinutes = 30,
    this.bonusExtensionMinutes = 20,
    this.fadeDurationSeconds = 60,
    this.shakeThresholdG = 2.5,
    this.stillnessThresholdG = 0.4,
    this.sleepApiMinConfidence = 80,
    this.trackBoundaryGuardEnabled = true,
  });

  final int inactivityTimeoutMinutes;
  final int bonusExtensionMinutes;
  final int fadeDurationSeconds;
  final double shakeThresholdG;
  final double stillnessThresholdG;
  final int sleepApiMinConfidence;
  final bool trackBoundaryGuardEnabled;

  SmartSleepConfig copyWith({
    int? inactivityTimeoutMinutes,
    int? bonusExtensionMinutes,
    int? fadeDurationSeconds,
    double? shakeThresholdG,
    double? stillnessThresholdG,
    int? sleepApiMinConfidence,
    bool? trackBoundaryGuardEnabled,
  }) {
    return SmartSleepConfig(
      inactivityTimeoutMinutes:
          inactivityTimeoutMinutes ?? this.inactivityTimeoutMinutes,
      bonusExtensionMinutes:
          bonusExtensionMinutes ?? this.bonusExtensionMinutes,
      fadeDurationSeconds: fadeDurationSeconds ?? this.fadeDurationSeconds,
      shakeThresholdG: shakeThresholdG ?? this.shakeThresholdG,
      stillnessThresholdG: stillnessThresholdG ?? this.stillnessThresholdG,
      sleepApiMinConfidence:
          sleepApiMinConfidence ?? this.sleepApiMinConfidence,
      trackBoundaryGuardEnabled:
          trackBoundaryGuardEnabled ?? this.trackBoundaryGuardEnabled,
    );
  }
}

/// Service managing Smart Sleep Mode finite state machine, timers, fade-out curve,
/// volume restoration, track boundary protection, and native sensors binding.
class SmartSleepService extends ChangeNotifier {
  SmartSleepService({
    required this.player,
    EventChannel? eventChannel,
    DateTime Function()? clock,
  })  : _eventChannel =
            eventChannel ?? const EventChannel('jigit.studio/sleep_events'),
        _clock = clock ?? DateTime.now {
    _initPlayerSubscription();
  }

  final MaboyAudioPlayer player;
  final EventChannel _eventChannel;
  final DateTime Function() _clock;

  bool _enabled = false;
  bool get isEnabled => _enabled;

  SmartSleepConfig _config = const SmartSleepConfig();
  SmartSleepConfig get config => _config;

  SmartSleepState _state = SmartSleepState.idle;
  SmartSleepState get state => _state;

  /// Remaining seconds before entering fading mode while in [SmartSleepState.monitoring].
  int _remainingSeconds = 0;
  int get remainingSeconds => _remainingSeconds;

  /// Total inactivity window duration in seconds for progress calculation.
  int _totalWindowSeconds = 30 * 60;
  int get totalWindowSeconds => _totalWindowSeconds;

  /// Progress of current inactivity countdown (0.0 = just started/reset, 1.0 = expired).
  double get inactivityProgress {
    if (_totalWindowSeconds <= 0) return 0.0;
    final elapsed = _totalWindowSeconds - _remainingSeconds;
    return (elapsed / _totalWindowSeconds).clamp(0.0, 1.0);
  }

  /// Timestamp of the last detected physical or user movement.
  DateTime? _lastMovementTs;
  DateTime? get lastMovementTs => _lastMovementTs;

  /// Original volume level V0 before fading started.
  double _initialVolume = 1.0;
  double get initialVolume => _initialVolume;

  /// Current fading progress in seconds while in [SmartSleepState.fading].
  double _fadeElapsedSeconds = 0.0;
  double get fadeElapsedSeconds => _fadeElapsedSeconds;

  Timer? _countdownTimer;
  Timer? _fadeTicker;
  Timer? _restoreTicker;
  StreamSubscription<dynamic>? _playerStateSub;
  StreamSubscription<dynamic>? _nativeEventsSub;

  static const String _prefEnabledKey = 'smart_sleep_enabled';
  static const String _prefTimeoutKey = 'smart_sleep_timeout_minutes';
  static const String _prefFadeKey = 'smart_sleep_fade_seconds';
  static const String _prefBoundaryKey = 'smart_sleep_boundary_guard';

  void _initPlayerSubscription() {
    _playerStateSub = player.playerStateStream.listen((playerState) {
      if (!_enabled) return;
      if (playerState.playing) {
        if (_state == SmartSleepState.idle || _state == SmartSleepState.stopped) {
          _transitionToMonitoring();
        }
      } else {
        if (_state == SmartSleepState.monitoring) {
          _transitionToIdle();
        } else if (_state == SmartSleepState.fading) {
          // If paused by external event during fade, cancel fade and restore volume
          _cancelFade(restoreVolumeImmediately: true, addBonus: false);
          _transitionToIdle();
        }
      }
    });
  }

  /// Loads persisted configuration from SharedPreferences.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefEnabledKey) ?? false;
      final timeout = prefs.getInt(_prefTimeoutKey) ?? 30;
      final fade = prefs.getInt(_prefFadeKey) ?? 60;
      final boundary = prefs.getBool(_prefBoundaryKey) ?? true;

      _config = _config.copyWith(
        inactivityTimeoutMinutes: timeout,
        fadeDurationSeconds: fade,
        trackBoundaryGuardEnabled: boundary,
      );

      if (_enabled && player.playing) {
        _transitionToMonitoring();
      } else {
        _transitionToIdle();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading SmartSleepService settings: $e');
    }
  }

  /// Toggles Smart Sleep Mode on or off.
  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);

    if (_enabled) {
      if (player.playing) {
        _transitionToMonitoring();
      } else {
        _transitionToIdle();
      }
    } else {
      if (_state == SmartSleepState.fading) {
        _cancelFade(restoreVolumeImmediately: true, addBonus: false);
      }
      _transitionToIdle();
    }
    notifyListeners();
  }

  /// Updates inactivity timeout (15, 30, 45, 60 minutes).
  Future<void> setInactivityTimeoutMinutes(int minutes) async {
    if (minutes <= 0) return;
    _config = _config.copyWith(inactivityTimeoutMinutes: minutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefTimeoutKey, minutes);

    if (_state == SmartSleepState.monitoring) {
      _totalWindowSeconds = minutes * 60;
      _remainingSeconds = _totalWindowSeconds;
    }
    notifyListeners();
  }

  /// Updates fade-out duration (e.g. 60 or 90 seconds).
  Future<void> setFadeDurationSeconds(int seconds) async {
    if (seconds <= 0) return;
    _config = _config.copyWith(fadeDurationSeconds: seconds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefFadeKey, seconds);
    notifyListeners();
  }

  /// Toggles Track Boundary Guard policy.
  Future<void> setTrackBoundaryGuardEnabled(bool enabled) async {
    _config = _config.copyWith(trackBoundaryGuardEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBoundaryKey, enabled);
    notifyListeners();
  }

  /// Transitions FSM to [SmartSleepState.monitoring].
  void _transitionToMonitoring({int? customSeconds}) {
    _stopTimers();
    _state = SmartSleepState.monitoring;
    _totalWindowSeconds = customSeconds ?? (_config.inactivityTimeoutMinutes * 60);
    _remainingSeconds = _totalWindowSeconds;
    _lastMovementTs = _clock();
    _startNativeEventListener();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 1) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _remainingSeconds = 0;
        timer.cancel();
        _countdownTimer = null;
        _transitionToFading();
      }
    });

    notifyListeners();
  }

  /// Transitions FSM to [SmartSleepState.fading].
  void _transitionToFading() {
    _stopTimers();
    _state = SmartSleepState.fading;
    _fadeElapsedSeconds = 0.0;
    _initialVolume = player.volume;

    const intervalMs = 100;
    final totalFadeSeconds = _config.fadeDurationSeconds.toDouble();

    _fadeTicker = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      _fadeElapsedSeconds += intervalMs / 1000.0;

      if (_fadeElapsedSeconds >= totalFadeSeconds) {
        timer.cancel();
        _fadeTicker = null;
        unawaited(_completeFadeAndStop());
      } else {
        // Non-linear quadratic fade curve: V(t) = V0 * (1 - t/T)^2
        final factor = math.pow(1.0 - (_fadeElapsedSeconds / totalFadeSeconds), 2).toDouble();
        final targetVolume = (_initialVolume * factor).clamp(0.0, 1.0);
        player.setVolume(targetVolume);
        notifyListeners();
      }
    });

    notifyListeners();
  }

  /// Completes fading phase and stops playback as defined in sleep.md.
  Future<void> _completeFadeAndStop() async {
    _stopTimers();
    _state = SmartSleepState.stopped;
    notifyListeners();

    // 1. Pause playback
    await player.pause();

    // 2. Section 4.4: strictly restore volume to initial V0 AFTER pause
    await player.setVolume(_initialVolume);

    // 3. Transition to IDLE
    _transitionToIdle();
  }

  /// Transitions FSM to [SmartSleepState.idle].
  void _transitionToIdle() {
    _stopTimers();
    _stopNativeEventListener();
    _state = SmartSleepState.idle;
    _remainingSeconds = 0;
    notifyListeners();
  }

  /// Cancels fading phase, smoothly restores volume or immediately,
  /// and grants bonus time if requested.
  void _cancelFade({
    required bool restoreVolumeImmediately,
    required bool addBonus,
    bool smoothRamp = false,
  }) {
    _stopTimers();

    if (restoreVolumeImmediately) {
      player.setVolume(_initialVolume);
    } else if (smoothRamp) {
      _startSmoothVolumeRestore(targetVolume: _initialVolume, durationSeconds: 1.5);
    }

    if (addBonus && player.playing) {
      _transitionToMonitoring(
        customSeconds: _config.bonusExtensionMinutes * 60,
      );
    } else if (player.playing) {
      _transitionToMonitoring();
    } else {
      _transitionToIdle();
    }
  }

  /// Smoothly restores volume over [durationSeconds] (e.g. 1.5s for Shake-to-Cancel).
  void _startSmoothVolumeRestore({
    required double targetVolume,
    required double durationSeconds,
  }) {
    _restoreTicker?.cancel();
    final startVolume = player.volume;
    const intervalMs = 50;
    final totalSteps = (durationSeconds * 1000) / intervalMs;
    var step = 0;

    _restoreTicker = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      step++;
      if (step >= totalSteps) {
        timer.cancel();
        _restoreTicker = null;
        player.setVolume(targetVolume);
      } else {
        final progress = step / totalSteps;
        final current = startVolume + (targetVolume - startVolume) * progress;
        player.setVolume(current.clamp(0.0, 1.0));
      }
    });
  }

  /// Explicit user activity (UI tap, volume change, playback button, etc.).
  void recordUserActivity() {
    if (!_enabled) return;

    if (_state == SmartSleepState.monitoring) {
      // In MONITORING: reset inactivity timer to full duration
      _remainingSeconds = _totalWindowSeconds;
      _lastMovementTs = _clock();
      notifyListeners();
    } else if (_state == SmartSleepState.fading) {
      // In FADING: cancel fade, restore volume, +20 minutes bonus
      _cancelFade(
        restoreVolumeImmediately: true,
        addBonus: true,
      );
    }
  }

  /// Called when device screen turns ON (`SCREEN_ON`).
  void recordScreenOn() {
    if (!_enabled) return;

    if (_state == SmartSleepState.monitoring) {
      _remainingSeconds = _totalWindowSeconds;
      _lastMovementTs = _clock();
      notifyListeners();
    } else if (_state == SmartSleepState.fading) {
      // In FADING: cancel fade, restore volume, +20 minutes
      _cancelFade(
        restoreVolumeImmediately: true,
        addBonus: true,
      );
    }
  }

  /// Accelerometer micro-movement telemetry (Δg > 0.4 m/s²).
  void recordMovement(double deltaG) {
    if (!_enabled) return;
    if (deltaG >= _config.stillnessThresholdG) {
      _lastMovementTs = _clock();
      notifyListeners();
    }
  }

  /// Accelerometer shake gesture (Shake-to-Cancel, Δg > 2.5 m/s²).
  void recordShake(double deltaG) {
    if (!_enabled) return;

    if (_state == SmartSleepState.fading && deltaG >= _config.shakeThresholdG) {
      // Shake-to-Cancel: cancel fade, smoothly restore volume over 1.5s, +20 minutes bonus
      _cancelFade(
        restoreVolumeImmediately: false,
        addBonus: true,
        smoothRamp: true,
      );
    }
  }

  /// External Google Sleep API event with confidence rating (0..100).
  ///
  /// According to sleep.md section 3 & 4.1:
  /// Force transition to FADING if confidence >= 80% AND time since last_movement_ts >= 10 minutes.
  void recordSleepApiEvent(int confidence) {
    if (!_enabled) return;
    if (_state != SmartSleepState.monitoring) return;

    if (confidence >= _config.sleepApiMinConfidence) {
      final lastMove = _lastMovementTs;
      final now = _clock();
      final stillnessMinutes =
          lastMove == null ? 999 : now.difference(lastMove).inMinutes;

      if (stillnessMinutes >= 10) {
        _transitionToFading();
      }
    }
  }

  /// Track Boundary Guard policy check (section 4.3).
  ///
  /// Returns `true` if next track playback MUST BE BLOCKED.
  /// If current track ends during FADING, instantly pauses player, restores volume V0,
  /// and moves to STOPPED -> IDLE.
  bool onTrackCompleted() {
    if (!_enabled) return false;

    if (_state == SmartSleepState.fading && _config.trackBoundaryGuardEnabled) {
      unawaited(_completeFadeAndStop());
      return true; // Block next track!
    }
    return false;
  }

  /// Manually grants bonus +20 minutes or extends current timer.
  void addBonusExtension() {
    if (!_enabled) return;

    if (_state == SmartSleepState.fading) {
      _cancelFade(
        restoreVolumeImmediately: true,
        addBonus: true,
      );
    } else if (_state == SmartSleepState.monitoring) {
      _remainingSeconds += _config.bonusExtensionMinutes * 60;
      if (_remainingSeconds > _totalWindowSeconds) {
        _totalWindowSeconds = _remainingSeconds;
      }
      notifyListeners();
    }
  }

  /// Starts listening to native Android EventChannel for screen_on, movement, shake, sleep_api.
  void _startNativeEventListener() {
    if (_nativeEventsSub != null) return;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        _nativeEventsSub = _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is Map) {
              final type = event['type'] as String?;
              if (type == 'screen_on') {
                recordScreenOn();
              } else if (type == 'movement') {
                final delta = (event['delta'] as num?)?.toDouble() ?? 0.0;
                recordMovement(delta);
              } else if (type == 'shake') {
                final delta = (event['delta'] as num?)?.toDouble() ?? 0.0;
                recordShake(delta);
              } else if (type == 'sleep_segment') {
                final conf = (event['confidence'] as num?)?.toInt() ?? 0;
                recordSleepApiEvent(conf);
              }
            }
          },
          onError: (error) {
            debugPrint('SmartSleep native event error: $error');
          },
        );
      } catch (e) {
        debugPrint('Unable to subscribe to sleep_events EventChannel: $e');
      }
    }
  }

  void _stopNativeEventListener() {
    _nativeEventsSub?.cancel();
    _nativeEventsSub = null;
  }

  void _stopTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _fadeTicker?.cancel();
    _fadeTicker = null;
    _restoreTicker?.cancel();
    _restoreTicker = null;
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimers();
    _stopNativeEventListener();
    _playerStateSub?.cancel();
    super.dispose();
  }
}
