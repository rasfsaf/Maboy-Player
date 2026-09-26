import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/audio_player.dart';
import 'package:maboy/src/services/smart_sleep_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmartSleepService FSM & Algorithms', () {
    late MaboyAudioPlayer player;
    late SmartSleepService service;
    late DateTime simulatedNow;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      player = MaboyAudioPlayer();
      simulatedNow = DateTime(2026, 9, 26, 14, 0, 0);
      service = SmartSleepService(
        player: player,
        clock: () => simulatedNow,
      );
    });

    tearDown(() async {
      service.dispose();
      await player.dispose();
    });

    test('Initial defaults match sleep.md specification', () {
      expect(service.state, equals(SmartSleepState.idle));
      expect(service.isEnabled, isFalse);
      expect(service.config.inactivityTimeoutMinutes, equals(30));
      expect(service.config.bonusExtensionMinutes, equals(20));
      expect(service.config.fadeDurationSeconds, equals(60));
      expect(service.config.shakeThresholdG, equals(2.5));
      expect(service.config.stillnessThresholdG, equals(0.4));
      expect(service.config.sleepApiMinConfidence, equals(80));
      expect(service.config.trackBoundaryGuardEnabled, isTrue);
    });

    test('Enabling while playing enters MONITORING; pausing returns to IDLE', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      expect(player.playing, isTrue);

      await service.setEnabled(true);
      expect(service.isEnabled, isTrue);
      expect(service.state, equals(SmartSleepState.monitoring));
      expect(service.remainingSeconds, equals(30 * 60));

      await player.pause();
      expect(service.state, equals(SmartSleepState.idle));
    });

    test('User activity resets inactivity timer in MONITORING', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      expect(service.state, equals(SmartSleepState.monitoring));

      // Advance time slightly
      simulatedNow = simulatedNow.add(const Duration(minutes: 5));
      service.recordUserActivity();
      expect(service.remainingSeconds, equals(30 * 60));
      expect(service.lastMovementTs, equals(simulatedNow));
    });

    test('Screen ON resets inactivity timer in MONITORING', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      simulatedNow = simulatedNow.add(const Duration(minutes: 10));
      service.recordScreenOn();
      expect(service.remainingSeconds, equals(30 * 60));
      expect(service.lastMovementTs, equals(simulatedNow));
    });

    test('Telemetry micro-movement updates lastMovementTs', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      final moveTime = simulatedNow.add(const Duration(minutes: 7));
      simulatedNow = moveTime;

      // Below threshold (0.2 < 0.4) -> ignored
      service.recordMovement(0.2);
      expect(service.lastMovementTs, isNot(equals(moveTime)));

      // Above threshold (0.5 >= 0.4) -> updates timestamp
      service.recordMovement(0.5);
      expect(service.lastMovementTs, equals(moveTime));
    });

    test('Sleep API confidence >= 80% forces FADING if stillness >= 10 minutes', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);
      expect(service.state, equals(SmartSleepState.monitoring));

      // Stillness is only 5 minutes -> should NOT trigger fading
      simulatedNow = simulatedNow.add(const Duration(minutes: 5));
      service.recordSleepApiEvent(90);
      expect(service.state, equals(SmartSleepState.monitoring));

      // Stillness reaches 12 minutes -> triggers FADING
      simulatedNow = simulatedNow.add(const Duration(minutes: 7));
      service.recordSleepApiEvent(85);
      expect(service.state, equals(SmartSleepState.fading));
    });

    test('Shake-to-Cancel during FADING restores volume, adds bonus and returns to MONITORING', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      // Force transition to fading via Sleep API
      simulatedNow = simulatedNow.add(const Duration(minutes: 15));
      service.recordSleepApiEvent(95);
      expect(service.state, equals(SmartSleepState.fading));

      // Shake below threshold (1.5 < 2.5) -> ignored
      service.recordShake(1.5);
      expect(service.state, equals(SmartSleepState.fading));

      // Shake-to-Cancel (2.8 >= 2.5)
      service.recordShake(2.8);
      expect(service.state, equals(SmartSleepState.monitoring));
      // Bonus extension +20 minutes
      expect(service.remainingSeconds, equals(20 * 60));
    });

    test('Track Boundary Guard pauses and blocks next track when FADING', () async {
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      // Normal track completion in MONITORING does not block next track
      expect(service.onTrackCompleted(), isFalse);

      // Enter fading
      simulatedNow = simulatedNow.add(const Duration(minutes: 15));
      service.recordSleepApiEvent(90);
      expect(service.state, equals(SmartSleepState.fading));

      // Track completion in FADING blocks next track and stops
      final blocked = service.onTrackCompleted();
      expect(blocked, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.state, equals(SmartSleepState.idle));
    });

    test('Volume restoration: initial volume V0 is restored strictly after pause', () async {
      await player.setVolume(0.8);
      await player.setAudioSource(
        MaboyAudioSource(
          trackId: 'track-1',
          uri: Uri.parse('file:///dummy.mp3'),
          title: 'Track 1',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      await player.play();
      await service.setEnabled(true);

      simulatedNow = simulatedNow.add(const Duration(minutes: 15));
      service.recordSleepApiEvent(90);
      expect(service.state, equals(SmartSleepState.fading));
      expect(service.initialVolume, closeTo(0.8, 0.001));

      // Complete via boundary guard
      service.onTrackCompleted();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(player.playing, isFalse);
      expect(player.volume, closeTo(0.8, 0.001));
    });
  });
}
