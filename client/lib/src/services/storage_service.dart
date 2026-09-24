import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Information about a detected storage volume (SD card or internal storage).
class StorageVolumeInfo {
  final String path;
  final bool isRemovable;
  final int freeBytes;
  final int totalBytes;
  final String name;

  const StorageVolumeInfo({
    required this.path,
    required this.isRemovable,
    required this.freeBytes,
    required this.totalBytes,
    required this.name,
  });

  String get freeSpaceFormatted => formatBytes(freeBytes);
  String get totalSpaceFormatted => formatBytes(totalBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 Б';
    const suffixes = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  String toString() =>
      'StorageVolumeInfo(name: $name, removable: $isRemovable, free: $freeSpaceFormatted, total: $totalSpaceFormatted, path: $path)';
}

/// Service managing music file locations, SD-card detection, auto-fallback,
/// and storage preferences.
class StorageService {
  static const String prefPreferSdCard = 'prefer_sd_card';
  static const int minFreeSpaceBytes = 150 * 1024 * 1024; // 150 MB

  final MethodChannel _channel;
  final bool _isAndroid;
  SharedPreferences? _prefs;
  bool _preferSdCard = true;

  StorageService({
    MethodChannel? channel,
    SharedPreferences? prefs,
    bool? isAndroid,
  })  : _channel = channel ?? const MethodChannel('com.maboy.player/media'),
        _prefs = prefs,
        _isAndroid = isAndroid ?? Platform.isAndroid {
    if (_prefs != null) {
      _preferSdCard = _prefs!.getBool(prefPreferSdCard) ?? true;
    }
  }

  /// Initialize stored preferences.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _preferSdCard = _prefs!.getBool(prefPreferSdCard) ?? true;
  }

  /// Whether user prefers saving new downloads to an SD-card if available.
  bool get preferSdCard => _preferSdCard;

  /// Update user preference for saving to SD card.
  Future<void> setPreferSdCard(bool value) async {
    _preferSdCard = value;
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setBool(prefPreferSdCard, value);
  }

  /// Query available storage volumes. On Android, queries native MediaStore/StorageManager.
  Future<List<StorageVolumeInfo>> getStorageVolumes() async {
    if (!_isAndroid) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        return [
          StorageVolumeInfo(
            path: '${docDir.path}/music',
            isRemovable: false,
            freeBytes: 0,
            totalBytes: 0,
            name: 'Локальное хранилище',
          ),
        ];
      } catch (_) {
        return const [];
      }
    }

    try {
      final raw = await _channel.invokeMethod<List>('getStorageVolumes');
      if (raw == null) return const [];

      final list = <StorageVolumeInfo>[];
      for (final item in raw) {
        if (item is Map) {
          list.add(
            StorageVolumeInfo(
              path: item['path'] as String? ?? '',
              isRemovable: item['isRemovable'] as bool? ?? false,
              freeBytes: (item['freeBytes'] as num?)?.toInt() ?? 0,
              totalBytes: (item['totalBytes'] as num?)?.toInt() ?? 0,
              name: item['name'] as String? ?? 'Хранилище',
            ),
          );
        }
      }
      return list;
    } catch (e) {
      debugPrint('StorageService: failed to query storage volumes: $e');
      return const [];
    }
  }

  /// Returns the target directory for new music downloads or imported files.
  /// Selects removable SD card if enabled and space > threshold; otherwise falls back to internal storage.
  Future<Directory> getTargetMusicDirectory({
    String? subFolder,
    int? estimatedSizeBytes,
  }) async {
    final requiredSpace = estimatedSizeBytes ?? minFreeSpaceBytes;

    if (_isAndroid && _preferSdCard) {
      final volumes = await getStorageVolumes();
      final sdVolume = volumes.where((v) => v.isRemovable).firstOrNull;

      if (sdVolume != null && sdVolume.path.isNotEmpty) {
        if (sdVolume.freeBytes >= requiredSpace) {
          final targetPath = subFolder != null && subFolder.isNotEmpty
              ? '${sdVolume.path}/$subFolder'
              : sdVolume.path;
          final dir = Directory(targetPath);
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        } else {
          debugPrint(
            'StorageService: SD card has low free space (${sdVolume.freeSpaceFormatted} < ${StorageVolumeInfo.formatBytes(requiredSpace)}). Falling back to internal storage.',
          );
        }
      }
    }

    // Default internal storage directory
    final docDir = await getApplicationDocumentsDirectory();
    final internalPath = subFolder != null && subFolder.isNotEmpty
        ? '${docDir.path}/music/$subFolder'
        : '${docDir.path}/music';
    final internalDir = Directory(internalPath);
    if (!await internalDir.exists()) {
      await internalDir.create(recursive: true);
    }
    return internalDir;
  }

  /// Returns all music directories that should be scanned for tracks (both internal and SD card).
  Future<List<Directory>> getAllMusicDirectories() async {
    final dirs = <Directory>[];

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final internalMusic = Directory('${docDir.path}/music');
      dirs.add(internalMusic);
    } catch (e) {
      debugPrint('StorageService: error getting docDir: $e');
    }

    if (_isAndroid) {
      try {
        final volumes = await getStorageVolumes();
        for (final v in volumes) {
          if (v.path.isNotEmpty) {
            final volDir = Directory(v.path);
            if (!dirs.any((d) => d.path == volDir.path)) {
              dirs.add(volDir);
            }
          }
        }
      } catch (e) {
        debugPrint('StorageService: error querying volumes for scan: $e');
      }
    }

    return dirs;
  }

  /// Checks if a file path belongs to any app-managed music directories.
  Future<bool> isAppOwnedPath(String filePath) async {
    final dirs = await getAllMusicDirectories();
    final normalizedFile =
        Platform.isWindows ? filePath.toLowerCase() : filePath;

    for (final dir in dirs) {
      final prefix =
          '${dir.path}${Platform.pathSeparator}'.replaceAll(RegExp(r'[\\/]+'), Platform.pathSeparator);
      final normalizedPrefix =
          Platform.isWindows ? prefix.toLowerCase() : prefix;
      if (normalizedFile.startsWith(normalizedPrefix)) {
        return true;
      }
    }
    return false;
  }

  /// Finds an existing local file for a track by ID across all known music directories.
  Future<File?> findExistingTrackFile(String trackId) async {
    final dirs = await getAllMusicDirectories();
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            if (name.startsWith(trackId) || name.contains(trackId)) {
              if (await entity.length() > 5000) {
                return entity;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('StorageService: error listing ${dir.path}: $e');
      }
    }
    return null;
  }
}
