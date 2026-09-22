import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'youtube_downloader.dart';

class YouTubePlaylistService {
  YouTubePlaylistService({YouTubeDownloadService? downloader})
      : _yt = YoutubeExplode(),
        _downloader = downloader ?? YouTubeDownloadService();

  final YoutubeExplode _yt;
  final YouTubeDownloadService _downloader;

  /// Extract the playlist id (`list=…`) from a YouTube URL or raw id.
  /// Returns `null` if the URL has no playlist parameter.
  static String? extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^(PL|UU|LL|FL|RD|OL)[a-zA-Z0-9_-]{10,}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final list = uri.queryParameters['list'];
    if (list != null && list.isNotEmpty) return list;
    return null;
  }

  static bool isPlaylistUrl(String input) {
    final id = extractPlaylistId(input);
    return id != null && id.startsWith(RegExp(r'(PL|UU|LL|FL|RD|OL)'));
  }

  void dispose() {
    _yt.close();
    _downloader.dispose();
  }

  Future<YouTubePlaylistInfo?> getPlaylistInfo(String playlistId) async {
    try {
      final pl = await _yt.playlists.get(playlistId);
      final videos = await getPlaylistVideos(playlistId);
      return YouTubePlaylistInfo(
        id: pl.id.toString(),
        title: pl.title,
        thumbnailUrl: null,
        videoCount: pl.videoCount ?? videos.length,
        videos: videos,
      );
    } catch (_) {
      // Fallback: yt-dlp
      try {
        final res = await Process.run('yt-dlp', [
          '--js-runtimes',
          'node',
          '--remote-components',
          'ejs:github',
          '--flat-playlist',
          '-J',
          'https://www.youtube.com/playlist?list=$playlistId',
        ]).timeout(const Duration(seconds: 12));
        if (res.exitCode == 0) {
          final data = jsonDecode(res.stdout.toString());
          final entries = (data is Map ? data['entries'] : null) as List?;
          if (entries != null) {
            final videos = entries
                .whereType<Map>()
                .map(
                  (e) => YouTubeMetadata(
                    id: (e['id'] ?? '').toString(),
                    title: (e['title'] ?? 'YouTube Audio').toString(),
                    author: (e['uploader'] ?? 'YouTube').toString(),
                    duration: e['duration'] is num
                        ? Duration(seconds: (e['duration'] as num).toInt())
                        : null,
                    thumbnailUrl: null,
                  ),
                )
                .where((m) => m.id.isNotEmpty)
                .toList(growable: false);
            return YouTubePlaylistInfo(
              id: playlistId,
              title: (data is Map ? data['title'] as String? : null) ??
                  'YouTube Playlist',
              thumbnailUrl: null,
              videoCount: videos.length,
              videos: videos,
            );
          }
        }
      } catch (_) {}
      return null;
    }
  }

  Future<List<YouTubePlaylistInfo>> getUserPlaylists({String? authToken}) async {
    // Try yt-dlp first — youtube_explode dropped user-playlist listing in
    // recent versions. Keep the dart branch as a future hook.
    try {
      final res = await Process.run('yt-dlp', [
        '--js-runtimes',
        'node',
        '--remote-components',
        'ejs:github',
        if (authToken != null) ...[
          '--add-header',
          'Authorization: Bearer $authToken',
        ],
        '--flat-playlist',
        '-J',
        'https://www.youtube.com/playlist?list=LL',
      ]).timeout(const Duration(seconds: 10));
      if (res.exitCode == 0) {
        final data = jsonDecode(res.stdout.toString());
        if (data is Map && data['entries'] is List) {
          return ((data['entries'] as List).take(20))
              .whereType<Map>()
              .map(
                (e) => YouTubePlaylistInfo(
                  id: (e['id'] ?? '').toString(),
                  title: (e['title'] ?? 'YouTube Playlist').toString(),
                  thumbnailUrl: null,
                  videoCount: ((e['playlist_count'] ?? 0) as num).toInt(),
                ),
              )
              .where((p) => p.id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Fetch playlist items. The underlying stream is consumed sequentially
  /// (YouTube's pagination enforces it), but we keep the surface the same.
  Future<List<YouTubeMetadata>> getPlaylistVideos(
    String playlistId, {
    void Function(double progress)? onProgress,
  }) async {
    final List<YouTubeMetadata> out = [];
    final seen = <String>{};
    try {
      await for (final video in _yt.playlists.getVideos(playlistId).handleError(
            (Object _) {},
          )) {
        if (seen.contains(video.id.toString())) continue;
        seen.add(video.id.toString());
        out.add(YouTubeMetadata(
          id: video.id.toString(),
          title: video.title,
          author: video.author,
          duration: video.duration,
          thumbnailUrl: video.thumbnails.highResUrl,
        ));
        if (onProgress != null) onProgress(out.length / 30);
      }
    } catch (_) {}

    if (out.isEmpty) {
      try {
        final json = await Process.run('yt-dlp', [
          '--js-runtimes',
          'node',
          '--remote-components',
          'ejs:github',
          '--flat-playlist',
          '-J',
          'https://www.youtube.com/playlist?list=$playlistId',
        ]).timeout(const Duration(seconds: 12));
        if (json.exitCode == 0) {
          final data = jsonDecode(json.stdout.toString());
          if (data is Map && data['entries'] is List) {
            for (final entry in (data['entries'] as List).take(60)) {
              if (entry is! Map) continue;
              final id = (entry['id'] ?? '').toString();
              if (id.isEmpty || seen.contains(id)) continue;
              seen.add(id);
              out.add(YouTubeMetadata(
                id: id,
                title: (entry['title'] ?? 'YouTube Audio').toString(),
                author: (entry['uploader'] ?? 'YouTube').toString(),
                duration: entry['duration'] is num
                    ? Duration(seconds: (entry['duration'] as num).toInt())
                    : null,
                thumbnailUrl: entry['thumbnails'] is List
                    ? ((entry['thumbnails'] as List).firstOrNull is Map)
                        ? ((entry['thumbnails'] as List).firstOrNull
                                as Map)['url']
                            ?.toString()
                        : null
                    : null,
              ));
            }
          }
        }
      } catch (_) {}
    }
    return out;
  }

  /// Parallel-friendly: once we have ids, fan out and fetch full details with
  /// a concurrency cap. youtube_explode's per-id call is the slowest leg.
  Future<List<YouTubeMetadata>> hydrateDetails(
    Iterable<YouTubeMetadata> items, {
    int concurrency = 6,
  }) async {
    final list = items.toList(growable: false);
    if (list.isEmpty) return const [];
    return runWithConcurrency<YouTubeMetadata>(
      list,
      (seed) async {
        if (seed.duration != null) return seed;
        final full = await _downloader.getMetadata(seed.id);
        return full ?? seed;
      },
      concurrency: concurrency,
    );
  }
}

class YouTubePlaylistInfo {
  YouTubePlaylistInfo({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.videoCount,
    this.videos = const [],
  });

  final String id;
  final String title;
  final String? thumbnailUrl;
  final int videoCount;
  final List<YouTubeMetadata> videos;
}