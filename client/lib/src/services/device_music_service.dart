import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DiscoveredAudioFile {
  DiscoveredAudioFile({
    required this.path,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  final String path;
  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;
}

class DeviceMusicService {
  static const MethodChannel _channel = MethodChannel('com.maboy.maboy/media');

  static final RegExp _audioExtRegex = RegExp(
    r'\.(mp3|m4a|aac|ogg|opus|wav|flac)$',
    caseSensitive: false,
  );

  /// Requests or verifies permission to read audio files from device storage.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('Error requesting media permission: $e');
      return false;
    }
  }

  /// Checks if permission is already granted without prompting the user.
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted = await _channel.invokeMethod<bool>('checkPermission');
      return granted ?? false;
    } catch (e) {
      debugPrint('Error checking media permission: $e');
      return false;
    }
  }

  /// Discovers audio tracks from Android MediaStore and default music folders.
  static Future<List<DiscoveredAudioFile>> scanDefaultFolders() async {
    final results = <String, DiscoveredAudioFile>{};

    if (Platform.isAndroid) {
      final hasPerm = await requestPermission();
      if (!hasPerm) {
        debugPrint('Media permission denied on Android');
        return [];
      }

      // 1. Query Android MediaStore
      try {
        final rawTracks = await _channel.invokeMethod<List<dynamic>>(
          'queryMediaStore',
        );
        if (rawTracks != null) {
          for (final raw in rawTracks) {
            if (raw is Map) {
              final path = raw['path'] as String?;
              if (path != null && path.isNotEmpty && File(path).existsSync()) {
                final duration = raw['duration_ms'];
                results[path] = DiscoveredAudioFile(
                  path: path,
                  title: raw['title'] as String?,
                  artist: raw['artist'] as String?,
                  album: raw['album'] as String?,
                  durationMs: duration is num ? duration.toInt() : null,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error querying MediaStore: $e');
      }

      // 2. Query default directories directly to catch any files not yet indexed by MediaStore
      try {
        final dirs = await _channel.invokeMethod<List<dynamic>>(
          'getDefaultAudioDirs',
        );
        final folderList = <String>[
          if (dirs != null) ...dirs.cast<String>(),
          '/storage/emulated/0/Music',
          '/storage/emulated/0/Download',
          '/storage/emulated/0/Audio',
          '/storage/emulated/0/Podcasts',
        ];

        for (final folderPath in folderList.toSet()) {
          final dir = Directory(folderPath);
          if (await dir.exists()) {
            await for (final entry in dir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entry is File && _audioExtRegex.hasMatch(entry.path)) {
                if (!results.containsKey(entry.path)) {
                  results[entry.path] = DiscoveredAudioFile(path: entry.path);
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning default Android directories: $e');
      }
    } else if (Platform.isWindows) {
      // Graceful fallback for Windows desktop
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final candidateDirs = [
          '$userProfile\\Music',
          '$userProfile\\Downloads',
        ];
        for (final folderPath in candidateDirs) {
          final dir = Directory(folderPath);
          if (await dir.exists()) {
            await for (final entry in dir.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entry is File && _audioExtRegex.hasMatch(entry.path)) {
                if (!results.containsKey(entry.path)) {
                  results[entry.path] = DiscoveredAudioFile(path: entry.path);
                }
              }
            }
          }
        }
      }
    }

    return results.values.toList();
  }
}
