import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/equalizer.dart';
import 'package:maboy/src/services/equalizer_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EqualizerConfig', () {
    test('default configuration is flat and disabled', () {
      const config = EqualizerConfig();
      expect(config.enabled, isFalse);
      expect(config.presetId, 'flat');
      expect(config.gains, [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]);
    });

    test('serializes and deserializes cleanly with JSON', () {
      const original = EqualizerConfig(
        enabled: true,
        presetId: 'rock',
        gains: [3.0, 5.0, 1.0, 3.0, 1.0, 2.0],
      );
      final json = original.toJson();
      final restored = EqualizerConfig.fromJson(json);

      expect(restored.enabled, isTrue);
      expect(restored.presetId, 'rock');
      expect(restored.gains, [3.0, 5.0, 1.0, 3.0, 1.0, 2.0]);
      expect(restored, equals(original));
    });

    test('copyWith updates specified fields only', () {
      const original = EqualizerConfig(
        enabled: false,
        presetId: 'flat',
        gains: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
      );
      final modified = original.copyWith(
        enabled: true,
        presetId: 'metal_plus',
        gains: [5.5, 2.5, -0.5, 0, 2, 3.5],
      );

      expect(modified.enabled, isTrue);
      expect(modified.presetId, 'metal_plus');
      expect(modified.gains, [5.5, 2.5, -0.5, 0, 2, 3.5]);
    });
  });

  group('EqualizerService', () {
    test('resolves global config by default for all folders', () async {
      final service = EqualizerService();
      await service.init('test-account');

      expect(service.globalConfig.enabled, isFalse);
      expect(service.hasFolderOverride('folder-1'), isFalse);

      final resolved = service.resolveEffectiveConfig('folder-1');
      expect(resolved.presetId, 'flat');
      expect(resolved.enabled, isFalse);
    });

    test('updates and persists global configuration', () async {
      final service = EqualizerService();
      await service.init('test-account');

      var notified = false;
      service.addListener(() => notified = true);

      await service.setGlobalConfig(
        const EqualizerConfig(
          enabled: true,
          presetId: 'jazz',
          gains: [1, 2, 3, 1, 0, 1],
        ),
      );

      expect(notified, isTrue);
      expect(service.globalConfig.enabled, isTrue);
      expect(service.globalConfig.presetId, 'jazz');

      // Re-init from storage and verify persistence
      final reloaded = EqualizerService();
      await reloaded.init('test-account');
      expect(reloaded.globalConfig.enabled, isTrue);
      expect(reloaded.globalConfig.presetId, 'jazz');
      expect(reloaded.globalConfig.gains, [1, 2, 3, 1, 0, 1]);
    });

    test('sets and resolves folder-specific preset override', () async {
      final service = EqualizerService();
      await service.init('test-account');

      // Set global preset to pop
      await service.setScopePreset(null, builtInPreset('pop'));

      // Set folder-1 preset to rock
      await service.setScopePreset('folder-1', builtInPreset('rock'));

      expect(service.hasFolderOverride('folder-1'), isTrue);
      expect(service.hasFolderOverride('folder-2'), isFalse);

      final folder1Config = service.resolveEffectiveConfig('folder-1');
      expect(folder1Config.presetId, 'rock');
      expect(folder1Config.gains, builtInPreset('rock').gains);

      // folder-2 should inherit global pop preset
      final folder2Config = service.resolveEffectiveConfig('folder-2');
      expect(folder2Config.presetId, 'pop');

      // Global should remain pop
      final globalConfig = service.resolveEffectiveConfig(null);
      expect(globalConfig.presetId, 'pop');
    });

    test('removes folder override and falls back to global', () async {
      final service = EqualizerService();
      await service.init('test-account');

      await service.setScopePreset(null, builtInPreset('flat'));
      await service.setScopePreset('folder-1', builtInPreset('classical'));

      expect(service.resolveEffectiveConfig('folder-1').presetId, 'classical');

      await service.removeFolderConfig('folder-1');
      expect(service.hasFolderOverride('folder-1'), isFalse);
      expect(service.resolveEffectiveConfig('folder-1').presetId, 'flat');
    });

    test('supports setting individual band in scope', () async {
      final service = EqualizerService();
      await service.init('test-account');

      await service.setScopePreset('folder-workout', builtInPreset('flat'));
      await service.setScopeBand('folder-workout', 0, 6.0); // 60Hz +6dB

      final config = service.resolveEffectiveConfig('folder-workout');
      expect(config.presetId, 'manual');
      expect(config.gains[0], 6.0);
      expect(config.gains[1], 0.0);

      // Global should still be flat
      expect(service.globalConfig.presetId, 'flat');
      expect(service.globalConfig.gains[0], 0.0);
    });

    test('resets cleanly on logout', () async {
      final service = EqualizerService();
      await service.init('test-account');
      await service.setScopePreset('folder-1', builtInPreset('metal_plus'));

      expect(service.hasFolderOverride('folder-1'), isTrue);

      await service.reset();
      expect(service.hasFolderOverride('folder-1'), isFalse);
      expect(service.globalConfig.presetId, 'flat');
    });
  });
}
