import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_downloader.dart';

class YouTubePlaylistInfo {
  YouTubePlaylistInfo({
    required this.id,
    required this.title,
    required this.author,
    required this.videos,
  });

  final String id;
  final String title;
  final String author;
  final List<YouTubeMetadata> videos;
}

class YouTubePlaylistService {
  YouTubePlaylistService({YoutubeExplode? yt})
    : _yt = yt ?? YoutubeExplode(),
      _ownsYt = yt == null;

  final YoutubeExplode _yt;
  final bool _ownsYt;

  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (RegExp(
      r'^(PL|RD|OLAK5uy_|UU|LL|FL)[a-zA-Z0-9_-]+$',
    ).hasMatch(trimmed)) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final listParam = uri.queryParameters['list'];
      if (listParam != null && listParam.isNotEmpty) {
        return listParam;
      }
    }
    return null;
  }

  static bool isPlaylistUrl(String input) {
    return extractPlaylistId(input) != null;
  }

  Future<YouTubePlaylistInfo?> getPlaylistInfo(
    String playlistId, {
    int maxVideos = 200,
    void Function(int count)? onVideoDiscovered,
  }) async {
    try {
      final playlist = await _yt.playlists.get(playlistId);
      final videos = <YouTubeMetadata>[];

      await for (final video in _yt.playlists.getVideos(playlistId)) {
        videos.add(
          YouTubeMetadata(
            id: video.id.value,
            title: video.title,
            author: video.author,
            duration: video.duration,
            thumbnailUrl: video.thumbnails.highResUrl,
          ),
        );
        onVideoDiscovered?.call(videos.length);
        if (videos.length >= maxVideos) break;
      }

      return YouTubePlaylistInfo(
        id: playlistId,
        title: playlist.title,
        author: playlist.author,
        videos: videos,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    if (_ownsYt) {
      _yt.close();
    }
  }
}
