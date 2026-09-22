import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// In-memory cache for video metadata. Avoids hitting YouTube twice for the
/// same id in a single session.
final Map<String, YouTubeMetadata> _metadataCache = {};

/// Single shared HTTP client for thumbnail downloads.
HttpClient? _sharedClient;

HttpClient _getSharedClient() {
  final existing = _sharedClient;
  if (existing != null && !existing.idleTimeout.isNegative) return existing;
  final next = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30);
  _sharedClient = next;
  return next;
}

class YouTubeMetadata {
  YouTubeMetadata({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String? thumbnailUrl;
}

abstract class YouTubeProvider {
  Future<YouTubeMetadata?> getMetadata(String videoId);
  Future<String?> getStreamUrl(String videoId);
  Future<File?> downloadMp3({
    required String videoId,
    required String outputFilePath,
    void Function(double progress)? onProgress,
  });
}

class YouTubeDownloadService implements YouTubeProvider {
  YouTubeDownloadService() : _yt = YoutubeExplode();

  final YoutubeExplode _yt;
  bool? _hasYtDlp;

  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    if (uri.host.contains('youtube.com')) {
      if (uri.pathSegments.contains('watch')) {
        return uri.queryParameters['v'];
      }
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
    } else if (uri.host == 'youtu.be') {
      return uri.pathSegments.firstOrNull;
    }
    return null;
  }

  Future<bool> _isYtDlpAvailable() async {
    if (_hasYtDlp != null) return _hasYtDlp!;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      _hasYtDlp = false;
      return false;
    }
    try {
      final res = await Process.run('yt-dlp', [
        '--version',
      ]).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        _hasYtDlp = true;
        return true;
      }
    } catch (_) {}

    try {
      final res = await Process.run('python', [
        '-m',
        'yt_dlp',
        '--version',
      ]).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        _hasYtDlp = true;
        return true;
      }
    } catch (_) {}

    _hasYtDlp = false;
    return false;
  }

  @override
  Future<YouTubeMetadata?> getMetadata(String videoId) async {
    final cached = _metadataCache[videoId];
    if (cached != null) return cached;

    try {
      final video = await _yt.videos.get(videoId);
      final meta = YouTubeMetadata(
        id: videoId,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
      _metadataCache[videoId] = meta;
      return meta;
    } catch (_) {
      // Fallback: yt-dlp metadata if network/YouTubeExplode fails
      if (await _isYtDlpAvailable()) {
        try {
          final isNative =
              (await Process.run('yt-dlp', ['--version'])).exitCode == 0;
          final cmd = isNative ? 'yt-dlp' : 'python';
          final cookieCandidates = [
            File('cookies.txt'),
            File('data/cookies.txt'),
          ];
          final cookieFile = cookieCandidates
              .where((f) => f.existsSync())
              .firstOrNull;
          final args = [
            if (!isNative) ...['-m', 'yt_dlp'],
            if (cookieFile != null) ...['--cookies', cookieFile.path],
            '--js-runtimes',
            'node',
            '--remote-components',
            'ejs:github',
            '--dump-json',
            '--no-playlist',
            'https://www.youtube.com/watch?v=$videoId',
          ];
          final res = await Process.run(cmd, args);
          if (res.exitCode == 0) {
            final json =
                jsonDecode(res.stdout.toString()) as Map<String, dynamic>;
            final meta = YouTubeMetadata(
              id: videoId,
              title: json['title'] as String? ?? 'YouTube Audio',
              author: json['uploader'] as String? ?? 'YouTube',
              duration: json['duration'] != null
                  ? Duration(seconds: (json['duration'] as num).toInt())
                  : null,
              thumbnailUrl: json['thumbnail'] as String?,
            );
            _metadataCache[videoId] = meta;
            return meta;
          }
        } catch (_) {}
      }
      return null;
    }
  }

  @override
  Future<String?> getStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        final highest = audioStreams.withHighestBitrate();
        return highest.url.toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<File?> downloadMp3({
    required String videoId,
    required String outputFilePath,
    void Function(double progress)? onProgress,
  }) async {
    final target = File(outputFilePath);
    final targetDir = target.parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetBase = outputFilePath.endsWith('.mp3')
        ? outputFilePath.substring(0, outputFilePath.length - 4)
        : outputFilePath;
    final finalMp3 = File('$targetBase.mp3');

    // Check for YouTube cookies file to bypass 18+ age restrictions
    final cookieCandidates = [
      File('cookies.txt'),
      File('data/cookies.txt'),
      File('${targetDir.parent.path}/cookies.txt'),
    ];
    final cookieFile = cookieCandidates
        .where((f) => f.existsSync())
        .firstOrNull;

    // 1. If yt-dlp is available, download and convert directly to MP3 without saving video
    if (await _isYtDlpAvailable()) {
      try {
        final isNative =
            (await Process.run('yt-dlp', ['--version'])).exitCode == 0;
        final cmd = isNative ? 'yt-dlp' : 'python';
        final args = [
          if (!isNative) ...['-m', 'yt_dlp'],
          if (cookieFile != null) ...['--cookies', cookieFile.path],
          '--js-runtimes',
            'node',
            '--remote-components',
            'ejs:github',
            '-x',
            '--audio-format',
            'mp3',
            '--audio-quality',
            '0',
            '--no-playlist',
            '-o',
            '$targetBase.%(ext)s',
            'https://www.youtube.com/watch?v=$videoId',
        ];
        final process = await Process.start(cmd, args);
        process.stdout.transform(utf8.decoder).listen((data) {
          if (onProgress != null && data.contains('%')) {
            final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(data);
            if (match != null) {
              final pct = double.tryParse(match.group(1) ?? '0');
              if (pct != null) onProgress(pct / 100.0);
            }
          }
        });
        final exitCode = await process.exitCode;
        if (exitCode == 0 && await finalMp3.exists()) {
          return finalMp3;
        }
      } catch (_) {}
    }

    // 2. Pure Dart fallback: audio-only stream extraction (ZERO video saved/downloaded)
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      final stream = _yt.videos.streamsClient.get(audioStreamInfo);

      final tempFile = File('$targetBase.part');
      final output = tempFile.openWrite();
      var received = 0;
      final total = audioStreamInfo.size.totalBytes;

      await for (final chunk in stream) {
        output.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received / total);
        }
      }
      await output.flush();
      await output.close();

      // Check if ffmpeg is available to convert audio to true mp3
      var converted = false;
      try {
        final res = await Process.run('ffmpeg', [
          '-y',
          '-i',
          tempFile.path,
          '-vn',
          '-acodec',
          'libmp3lame',
          '-q:a',
          '2',
          finalMp3.path,
        ]).timeout(const Duration(seconds: 30));
        if (res.exitCode == 0 && await finalMp3.exists()) {
          converted = true;
          await tempFile.delete();
        }
      } catch (_) {}

      if (!converted) {
        if (await finalMp3.exists()) await finalMp3.delete();
        await tempFile.rename(finalMp3.path);
      }
      return finalMp3;
    } catch (_) {
      return null;
    }
  }

  /// Mid-roll screenshot. YouTube serves a "storyboard" mosaic for every
  /// video; this composes one frame at [seconds] into a JPEG by stitching
  /// the closest tiles from the low-res storyboard. Cheap, no ffmpeg.
  Future<File?> downloadScreenshot({
    required String videoId,
    required String outputImagePath,
    double seconds = 10.0,
  }) async {
    final client = _getSharedClient();
    try {
      // Request the lowest-res storyboard — quickest to compose.
      final uri = Uri.parse(
        'https://i.ytimg.com/sb/$videoId/storyboard3_L0/default.jpg',
      );
      final req = await client.getUrl(uri).timeout(
            const Duration(seconds: 6),
          );
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final bytes = await resp.fold<List<int>>(
        [],
        (prev, elem) => prev..addAll(elem),
      );
      if (bytes.isEmpty) return null;

      final file = File(outputImagePath);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      await file.writeAsBytes(bytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<File?> downloadThumbnail(String? url, String outputImagePath) async {
    if (url == null || url.isEmpty) return null;
    final client = _getSharedClient();
    try {
      final uri = Uri.parse(url);
      final req = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final file = File(outputImagePath);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        final bytes = await resp.fold<List<int>>(
          [],
          (prev, elem) => prev..addAll(elem),
        );
        if (bytes.isNotEmpty) {
          await file.writeAsBytes(bytes);
          return file;
        }
      }
    } catch (_) {}
    return null;
  }

  void dispose() {
    _yt.close();
    _sharedClient?.close(force: true);
    _sharedClient = null;
  }
}

/// Runs async tasks with a concurrency cap. Used by the parallel download
/// pool in AppController and the parallel metadata fetcher.
Future<List<T>> runWithConcurrency<T>(
  Iterable<T> items,
  Future<T> Function(T) worker, {
  int concurrency = 4,
}) async {
  final iterator = items.iterator;
  final results = <T>[];
  final pending = <Future<T>>[];

  Future<void> pump() async {
    while (iterator.moveNext() && pending.length < concurrency) {
      final item = iterator.current;
      pending.add(worker(item));
    }
    if (pending.isEmpty) return;
    final done = await Future.any(pending);
    pending.removeWhere((f) => f == done);
    results.add(done);
    await pump();
  }

  await pump();
  return results;
}