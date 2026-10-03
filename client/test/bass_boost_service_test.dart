import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/bass_boost_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BassBoostConfig', () {
    test('default values match expected Windows enhancement baseline', () {
      const config = BassBoostConfig();
      expect(config.enabled, isFalse);
      expect(config.frequency, 150.0);
      expect(config.gainDb, 0.0);
    });

    test('serializes and deserializes cleanly with JSON', () {
      const original = BassBoostConfig(
        enabled: true,
        frequency: 80.0,
        gainDb: 12.0,
      );
      final json = original.toJson();
      final restored = BassBoostConfig.fromJson(json);

      expect(restored.enabled, isTrue);
      expect(restored.frequency, 80.0);
      expect(restored.gainDb, 12.0);
      expect(restored, equals(original));
    });

    test('copyWith updates specified fields only', () {
      const original = BassBoostConfig(
        enabled: false,
        frequency: 100.0,
        gainDb: 6.0,
      );
      final modified = original.copyWith(enabled: true, gainDb: 18.0);

      expect(modified.enabled, isTrue);
      expect(modified.frequency, 100.0);
      expect(modified.gainDb, 18.0);
    });
  });

  group('BassBoostService', () {
    test('resolves global config by default for all scopes', () async {
      final service = BassBoostService();
      await service.init();

      expect(service.globalConfig.enabled, isFalse);
      expect(service.hasPlaylistOverride('playlist-1'), isFalse);

      final resolved = service.resolveEffectiveConfig('playlist-1');
      expect(resolved.frequency, 150.0);
      expect(resolved.gainDb, 0.0);
    });

    test('updates and persists global configuration', () async {
      final service = BassBoostService();
      await service.init();

      var notified = false;
      service.addListener(() => notified = true);

      await service.setGlobalConfig(
        const BassBoostConfig(enabled: true, frequency: 100.0, gainDb: 9.0),
      );

      expect(notified, isTrue);
      expect(service.globalConfig.enabled, isTrue);
      expect(service.globalConfig.frequency, 100.0);
      expect(service.globalConfig.gainDb, 9.0);

      // Verify fallback uses the updated global
      final fallback = service.resolveEffectiveConfig('any-playlist');
      expect(fallback.gainDb, 9.0);
    });

    test('per-playlist override takes precedence over global settings', () async {
      final service = BassBoostService();
      await service.init();

      await service.setGlobalConfig(
        const BassBoostConfig(enabled: true, frequency: 150.0, gainDb: 3.0),
      );

      const custom = BassBoostConfig(
        enabled: true,
        frequency: 75.0,
        gainDb: 15.0,
      );
      await service.setPlaylistConfig('folder-rock', custom);

      expect(service.hasPlaylistOverride('folder-rock'), isTrue);
      expect(service.hasPlaylistOverride('folder-jazz'), isFalse);

      // 'folder-rock' uses custom override
      final rockConfig = service.resolveEffectiveConfig('folder-rock');
      expect(rockConfig.frequency, 75.0);
      expect(rockConfig.gainDb, 15.0);

      // 'folder-jazz' falls back to global
      final jazzConfig = service.resolveEffectiveConfig('folder-jazz');
      expect(jazzConfig.frequency, 150.0);
      expect(jazzConfig.gainDb, 3.0);
    });

    test('removing playlist override smoothly falls back to global config', () async {
      final service = BassBoostService();
      await service.init();

      await service.setGlobalConfig(
        const BassBoostConfig(enabled: true, frequency: 200.0, gainDb: 6.0),
      );

      await service.setPlaylistConfig(
        'folder-edm',
        const BassBoostConfig(enabled: true, frequency: 50.0, gainDb: 21.0),
      );
      expect(service.hasPlaylistOverride('folder-edm'), isTrue);

      await service.removePlaylistConfig('folder-edm');
      expect(service.hasPlaylistOverride('folder-edm'), isFalse);

      final resolved = service.resolveEffectiveConfig('folder-edm');
      expect(resolved.frequency, 200.0);
      expect(resolved.gainDb, 6.0);
    });
  });
}
