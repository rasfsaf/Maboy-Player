import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maboy/src/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.documents);
  final String documents;

  @override
  Future<String?> getApplicationDocumentsPath() async => documents;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('storage_test_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths('${tempDir.path}/docs');
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StorageVolumeInfo', () {
    test('formatBytes formats properly', () {
      expect(StorageVolumeInfo.formatBytes(0), '0 Б');
      expect(StorageVolumeInfo.formatBytes(512), '512.0 Б');
      expect(StorageVolumeInfo.formatBytes(1024), '1.0 КБ');
      expect(StorageVolumeInfo.formatBytes(150 * 1024 * 1024), '150.0 МБ');
      expect(StorageVolumeInfo.formatBytes(32 * 1024 * 1024 * 1024), '32.0 ГБ');
    });
  });

  group('StorageService preferences', () {
    test('Defaults to preferSdCard = true and persists changes', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = StorageService(prefs: prefs);
      expect(service.preferSdCard, isTrue);

      await service.setPreferSdCard(false);
      expect(service.preferSdCard, isFalse);

      final service2 = StorageService(prefs: prefs);
      expect(service2.preferSdCard, isFalse);
    });
  });

  group('StorageService volumes and target selection', () {
    test('Selects SD card directory when available and has enough free space', () async {
      final prefs = await SharedPreferences.getInstance();
      final sdPath = '${tempDir.path}/sdcard/Android/data/com.maboy.player/files/Music';
      final internalPath = '${tempDir.path}/internal/music';

      const channel = MethodChannel('com.maboy.player/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getStorageVolumes') {
          return [
            {
              'path': internalPath,
              'isRemovable': false,
              'freeBytes': 5 * 1024 * 1024 * 1024,
              'totalBytes': 32 * 1024 * 1024 * 1024,
              'name': 'Внутренняя память',
            },
            {
              'path': sdPath,
              'isRemovable': true,
              'freeBytes': 16 * 1024 * 1024 * 1024, // 16 GB free
              'totalBytes': 64 * 1024 * 1024 * 1024,
              'name': 'SD-карта',
            },
          ];
        }
        return null;
      });

      final service = StorageService(channel: channel, prefs: prefs, isAndroid: true);
      final volumes = await service.getStorageVolumes();
      expect(volumes.length, 2);
      expect(volumes.any((v) => v.isRemovable), isTrue);

      final target = await service.getTargetMusicDirectory();
      expect(target.path, sdPath);
    });

    test('Falls back to internal storage when SD card has low free space (< 150 MB)', () async {
      final prefs = await SharedPreferences.getInstance();
      final sdPath = '${tempDir.path}/sdcard_full/files/Music';
      final internalPath = '${tempDir.path}/internal_fallback/music';

      const channel = MethodChannel('com.maboy.player/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getStorageVolumes') {
          return [
            {
              'path': internalPath,
              'isRemovable': false,
              'freeBytes': 5 * 1024 * 1024 * 1024,
              'totalBytes': 32 * 1024 * 1024 * 1024,
              'name': 'Внутренняя память',
            },
            {
              'path': sdPath,
              'isRemovable': true,
              'freeBytes': 50 * 1024 * 1024, // Only 50 MB free (< 150 MB threshold)
              'totalBytes': 64 * 1024 * 1024 * 1024,
              'name': 'SD-карта',
            },
          ];
        }
        return null;
      });

      final service = StorageService(channel: channel, prefs: prefs, isAndroid: true);
      final volumes = await service.getStorageVolumes();
      final sd = volumes.firstWhere((v) => v.isRemovable);
      expect(sd.freeBytes < StorageService.minFreeSpaceBytes, isTrue);

      final target = await service.getTargetMusicDirectory();
      // SD is full, so target should not be sdPath
      expect(target.path, isNot(equals(sdPath)));
    });

    test('Falls back to internal storage when preferSdCard is turned off by user', () async {
      final prefs = await SharedPreferences.getInstance();
      final sdPath = '${tempDir.path}/sdcard/files/Music';

      const channel = MethodChannel('com.maboy.player/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getStorageVolumes') {
          return [
            {
              'path': sdPath,
              'isRemovable': true,
              'freeBytes': 30 * 1024 * 1024 * 1024,
              'totalBytes': 64 * 1024 * 1024 * 1024,
              'name': 'SD-карта',
            },
          ];
        }
        return null;
      });

      final service = StorageService(channel: channel, prefs: prefs, isAndroid: true);
      await service.setPreferSdCard(false);

      final target = await service.getTargetMusicDirectory();
      expect(target.path, isNot(equals(sdPath)));
    });
  });
}
