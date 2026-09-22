import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'audio_player.dart';

class MediaService {
  static bool _initialized = false;
  static const MethodChannel _mediaChannel = MethodChannel(
    'com.maboy.player/media',
  );

  static void listenToBecomingNoisy(void Function() onNoisy) {
    if (!Platform.isAndroid) return;
    _mediaChannel.setMethodCallHandler((call) async {
      if (call.method == 'onAudioBecomingNoisy') {
        onNoisy();
      }
    });
  }

  static Future<void> init() async {
    if (_initialized) return;
    try {
      MpvAudioKit.ensureInitialized();
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('Unable to initialize mpv audio backend: $error\n$stackTrace');
      rethrow;
    }
  }

  static MaboyAudioSource createAudioSource({
    required String trackId,
    required String title,
    String? artist,
    String? album,
    String? localFilePath,
    String? streamUrl,
    String? localArtworkPath,
    String? thumbnailNetworkUrl,
  }) {
    Uri? artUri;
    if (localArtworkPath != null && File(localArtworkPath).existsSync()) {
      artUri = Uri.file(localArtworkPath);
    } else if (thumbnailNetworkUrl != null && thumbnailNetworkUrl.isNotEmpty) {
      artUri = Uri.tryParse(thumbnailNetworkUrl);
    }

    if (localFilePath != null) {
      return MaboyAudioSource(
        trackId: trackId,
        uri: Uri.file(localFilePath),
        title: title,
        artist: artist ?? 'Неизвестный исполнитель',
        album: album ?? 'Maboy Library',
        artworkUri: artUri,
      );
    } else if (streamUrl != null) {
      return MaboyAudioSource(
        trackId: trackId,
        uri: Uri.parse(streamUrl),
        title: title,
        artist: artist ?? 'YouTube',
        album: album ?? 'YouTube',
        artworkUri: artUri,
        isNetwork: true,
      );
    } else {
      throw ArgumentError('Either localFilePath or streamUrl must be provided');
    }
  }
}
