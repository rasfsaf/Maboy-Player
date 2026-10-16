import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'captcha_solver_service.dart';
import '../api.dart';
import 'local_metadata_service.dart';
import 'track_formatter.dart';

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

class YouTubeDownloadResult {
  YouTubeDownloadResult({
    this.file,
    this.errorMessage,
    this.isAgeRestricted = false,
    this.isUnavailable = false,
  });

  final File? file;
  final String? errorMessage;
  final bool isAgeRestricted;
  final bool isUnavailable;

  bool get isSuccess => file != null;
}

class YouTubeStreamResult {
  YouTubeStreamResult({
    this.url,
    this.errorMessage,
    this.isAgeRestricted = false,
  });

  final String? url;
  final String? errorMessage;
  final bool isAgeRestricted;

  bool get isSuccess => url != null;
}

abstract class YouTubeProvider {
  Future<YouTubeMetadata?> getMetadata(String videoId, {SyncApi? api});
  Future<String?> getStreamUrl(String videoId);
  Future<YouTubeStreamResult> getStreamResult(String videoId);
  Future<File?> downloadMp3({
    required String videoId,
    required String outputFilePath,
    void Function(double progress)? onProgress,
  });
  Future<YouTubeDownloadResult> downloadMp3Result({
    required String videoId,
    required String outputFilePath,
    void Function(double progress)? onProgress,
  });
}

class YouTubeDownloadService implements YouTubeProvider {
  YouTubeDownloadService({YoutubeExplode? youtube, CaptchaSolverService? captcha})
    : _yt = youtube ?? YoutubeExplode(),
      _captcha = captcha ?? CaptchaSolverService();

  final YoutubeExplode _yt;
  final CaptchaSolverService _captcha;

  bool _needsCaptcha(String output) {
    final text = output.toLowerCase();
    return text.contains('captcha') || text.contains('not a bot') || text.contains('sign in to confirm');
  }

  Future<List<String>?> captchaRetryArgs(String diagnostics, List<String> args) async {
    if (!_needsCaptcha(diagnostics)) return null;
    final token = await _captcha.solve(
      const CaptchaTask(
        type: 'RecaptchaV2TaskProxyless',
        websiteUrl: 'https://www.youtube.com',
        websiteKey: 'youtube',
      ),
      timeout: const Duration(seconds: 30),
    );
    if (token == null || token.isEmpty) return null;
    final poToken = base64Encode(utf8.encode(token));
    return [...args, '--extractor-args', 'youtube:po_token=web.gvs+$poToken'];
  }

  Future<YouTubeDownloadResult?> _retryYtDlpWithCaptcha(
    String cmd,
    List<String> args,
    void Function(double)? onProgress,
    File finalMp3,
    String diagnostics,
  ) async {
    final retryArgs = await captchaRetryArgs(diagnostics, args);
    if (retryArgs == null) return null;
    final retry = await Process.start(cmd, retryArgs);
    retry.stdout.transform(utf8.decoder).listen((text) {
      final match = RegExp(r'\[download\]\s+(\d+\.?\d*)%').firstMatch(text);
      final pct = double.tryParse(match?.group(1) ?? '');
      if (pct != null) onProgress?.call(pct / 100.0);
    });
    final code = await retry.exitCode.timeout(const Duration(minutes: 3));
    if (code == 0 && await finalMp3.exists()) {
      return YouTubeDownloadResult(file: finalMp3);
    }
    return null;
  }
  String? _ytDlpCommand;

  List<File> _cookieCandidates([Directory? outputDirectory]) {
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = <File>[
      File('cookies.txt'),
      File('data/cookies.txt'),
      File('${executableDirectory.path}${Platform.pathSeparator}cookies.txt'),
      File(
        '${executableDirectory.path}${Platform.pathSeparator}data'
        '${Platform.pathSeparator}cookies.txt',
      ),
      if (outputDirectory != null)
        File(
          '${outputDirectory.parent.path}${Platform.pathSeparator}cookies.txt',
        ),
    ];
    final seen = <String>{};
    return candidates.where((file) => seen.add(file.absolute.path)).toList();
  }

  File? _findCookieFile([Directory? outputDirectory]) => _cookieCandidates(
    outputDirectory,
  ).where((file) => file.existsSync()).firstOrNull;

  List<String> _ytDlpPrefix(String command) =>
      command == 'yt-dlp' ? const [] : const ['-m', 'yt_dlp'];

  /// Converts yt-dlp diagnostics into a stable user-facing error. Keep this
  /// independent from process execution so all YouTube paths classify errors
  /// identically and the behavior can be tested without network access.
  static YouTubeStreamResult classifyYtDlpError(String diagnostics) {
    final message = diagnostics.toLowerCase();
    final invalidCookies =
        message.contains('cookies are no longer valid') ||
        message.contains('cookies have likely been rotated');
    final ageRestricted =
        message.contains('confirm your age') ||
        message.contains('age-restricted') ||
        message.contains('may be inappropriate for some users');
    final authRequired =
        ageRestricted ||
        message.contains('sign in to confirm') ||
        message.contains('authentication');

    if (invalidCookies) {
      return YouTubeStreamResult(
        isAgeRestricted: ageRestricted,
        errorMessage:
            'Файл cookies.txt устарел. Экспортируй cookies YouTube заново '
            'из авторизованного приватного окна браузера.',
      );
    }
    if (authRequired) {
      return YouTubeStreamResult(
        isAgeRestricted: ageRestricted,
        errorMessage: ageRestricted
            ? 'Видео 18+: нужен актуальный cookies.txt от аккаунта YouTube '
                  'с подтвержденным возрастом.'
            : 'YouTube требует авторизацию: обнови cookies.txt.',
      );
    }
    if (message.contains('video unavailable') ||
        message.contains('this video is unavailable')) {
      return YouTubeStreamResult(errorMessage: 'Видео недоступно на YouTube.');
    }
    if (message.contains('timed out') || message.contains('timeout')) {
      return YouTubeStreamResult(
        errorMessage: 'YouTube не ответил вовремя. Повтори попытку.',
      );
    }
    return YouTubeStreamResult(
      errorMessage: 'Не удалось получить аудиопоток YouTube.',
    );
  }

  static final RegExp _videoIdRegex = RegExp(
    r'(?:https?:\/\/)?(?:www\.|m\.|music\.)?(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:[^\s]*&)?v=|shorts\/|live\/|embed\/|v\/))([a-zA-Z0-9_-]{11})',
    caseSensitive: false,
  );

  static String? extractVideoId(String input) {
    final trimmed = input.trim();
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final match = _videoIdRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
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

  static String? extractTitleCandidate(String input) {
    var text = input.trim();
    final urlRegex = RegExp(r'https?:\/\/[^\s]+', caseSensitive: false);
    text = text.replaceAll(urlRegex, '').trim();
    if (text.isEmpty) return null;

    text = text.replaceAll(RegExp(r'[:\s]+$'), '').trim();
    text = text.replaceAll(RegExp(r'\s+on\s+YouTube\.?$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\s+(?:на|в)\s+YouTube\.?$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'^(?:Watch|Смотрите|Посмотрите)\s+(?:видео\s+|video\s+)?', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'^[\s"“«»\-_:]+|[\s"”«»\-_:]+$'), '').trim();

    return text.isNotEmpty && text.length >= 2 ? text : null;
  }

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
  }

  static Future<YouTubeMetadata?> fetchOEmbed(String videoId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final uri = Uri.parse(
        'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = await utf8.decoder.bind(response).join();
        final json = jsonDecode(body);
        if (json is Map<String, dynamic>) {
          final title = json['title'] as String?;
          final author = json['author_name'] as String?;
          final thumbnail = json['thumbnail_url'] as String?;
          if (title != null && title.trim().isNotEmpty) {
            return YouTubeMetadata(
              id: videoId,
              title: _decodeHtmlEntities(title.trim()),
              author: (author != null && author.trim().isNotEmpty)
                  ? _decodeHtmlEntities(author.trim())
                  : 'YouTube',
              duration: null,
              thumbnailUrl: thumbnail,
            );
          }
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Direct HTML scrape of the YouTube watch page. Always works without yt-dlp or scraper tokens.
  static Future<YouTubeMetadata?> fetchHtmlMetadata(String videoId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      request.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final html = await utf8.decoder.bind(response).join();

        // 1. Try extracting player response JSON
        final playerMatch = RegExp(
          r'ytInitialPlayerResponse\s*=\s*(\{.+?\});(?:var\s|const\s|</script>)',
        ).firstMatch(html);
        if (playerMatch != null) {
          try {
            final json =
                jsonDecode(playerMatch.group(1)!) as Map<String, dynamic>;
            final details = json['videoDetails'] as Map<String, dynamic>?;
            if (details != null) {
              final title = (details['title'] as String?)?.trim();
              final author = (details['author'] as String?)?.trim();
              final lengthSec = int.tryParse('${details['lengthSeconds']}');
              final thumbs = details['thumbnail']?['thumbnails'] as List?;
              final thumbUrl = (thumbs != null && thumbs.isNotEmpty)
                  ? thumbs.last['url'] as String?
                  : null;
              if (title != null && title.isNotEmpty) {
                return YouTubeMetadata(
                  id: videoId,
                  title: _decodeHtmlEntities(title),
                  author: (author != null && author.isNotEmpty)
                      ? _decodeHtmlEntities(author)
                      : 'YouTube',
                  duration: lengthSec != null && lengthSec > 0
                      ? Duration(seconds: lengthSec)
                      : null,
                  thumbnailUrl: thumbUrl,
                );
              }
            }
          } catch (_) {}
        }

        // 2. Fallback: OpenGraph / Twitter meta tags
        final metaTitleMatch = RegExp(
          r"""<meta\s+(?:name|property)=["'](?:title|og:title|twitter:title)["']\s+content=["']([^"']+)["']""",
          caseSensitive: false,
        ).firstMatch(html) ?? RegExp(
          r"""<meta\s+content=["']([^"']+)["']\s+(?:name|property)=["'](?:title|og:title|twitter:title)["']""",
          caseSensitive: false,
        ).firstMatch(html);
        var title = metaTitleMatch?.group(1)?.trim();

        // 3. Fallback: <title> tag
        if (title == null || title.isEmpty) {
          final titleTagMatch = RegExp(
            r'<title>(.*?)<\/title>',
            caseSensitive: false,
          ).firstMatch(html);
          if (titleTagMatch != null) {
            title = titleTagMatch
                .group(1)
                ?.replaceAll(RegExp(r'\s*-\s*YouTube$', caseSensitive: false), '')
                .trim();
          }
        }

        if (title != null && title.isNotEmpty && title != 'YouTube') {
          title = _decodeHtmlEntities(title);

          final authorMatch = RegExp(
            r"""<link\s+itemprop=["']name["']\s+content=["']([^"']+)["']""",
            caseSensitive: false,
          ).firstMatch(html);
          final author = authorMatch != null
              ? _decodeHtmlEntities(authorMatch.group(1)!.trim())
              : 'YouTube';

          final thumbMatch = RegExp(
            r"""<meta\s+(?:name|property)=["']og:image["']\s+content=["']([^"']+)["']""",
            caseSensitive: false,
          ).firstMatch(html);
          final thumbUrl = thumbMatch?.group(1);

          return YouTubeMetadata(
            id: videoId,
            title: title,
            author: author,
            duration: null,
            thumbnailUrl: thumbUrl,
          );
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Fallback to noembed.com public proxy for oEmbed
  static Future<YouTubeMetadata?> fetchNoembed(String videoId) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..findProxy = HttpClient.findProxyFromEnvironment;
    try {
      final uri = Uri.parse(
        'https://noembed.com/embed?url=https://www.youtube.com/watch?v=$videoId',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _browserUserAgent);
      final response = await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final body = await utf8.decoder.bind(response).join();
        final json = jsonDecode(body);
        if (json is Map<String, dynamic>) {
          final title = json['title'] as String?;
          final author = json['author_name'] as String?;
          if (title != null && title.trim().isNotEmpty) {
            return YouTubeMetadata(
              id: videoId,
              title: _decodeHtmlEntities(title.trim()),
              author: (author != null && author.trim().isNotEmpty)
                  ? _decodeHtmlEntities(author.trim())
                  : 'YouTube',
              duration: null,
              thumbnailUrl: json['thumbnail_url'] as String?,
            );
          }
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<String?> _getYtDlpCommand() async {
    if (_ytDlpCommand != null) {
      return _ytDlpCommand!.isEmpty ? null : _ytDlpCommand;
    }
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      _ytDlpCommand = '';
      return null;
    }
    try {
      final res = await Process.run('yt-dlp', [
        '--version',
      ]).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        _ytDlpCommand = 'yt-dlp';
        return 'yt-dlp';
      }
    } catch (_) {}

    try {
      final res = await Process.run('python', [
        '-m',
        'yt_dlp',
        '--version',
      ]).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        _ytDlpCommand = 'python';
        return 'python';
      }
    } catch (_) {}

    _ytDlpCommand = '';
    return null;
  }

  @override
  Future<YouTubeMetadata?> getMetadata(String videoId, {SyncApi? api}) async {
    // 1. Fast YouTubeExplode
    try {
      final video = await _yt.videos
          .get(videoId)
          .timeout(const Duration(seconds: 6));
      return YouTubeMetadata(
        id: videoId,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
      );
    } catch (_) {}

    // 2. Fast lightweight oEmbed (works on mobile without scraper blocks)
    try {
      final oembed = await fetchOEmbed(videoId);
      if (oembed != null) return oembed;
    } catch (_) {}

    // 3. Direct HTML scraping (extracts ytInitialPlayerResponse, og:title, <title>)
    try {
      final htmlMeta = await fetchHtmlMetadata(videoId);
      if (htmlMeta != null) return htmlMeta;
    } catch (_) {}

    // 4. Public noembed proxy
    try {
      final noembedMeta = await fetchNoembed(videoId);
      if (noembedMeta != null) return noembedMeta;
    } catch (_) {}

    // 5. Fallback: Query Maboy server metadata proxy if available
    if (api != null) {
      try {
        final res = await api.request('GET', '/youtube/metadata?video_id=$videoId');
        final title = res['title'] as String?;
        if (title != null && title.trim().isNotEmpty) {
          final durationMs = (res['duration_ms'] as num?)?.toInt();
          return YouTubeMetadata(
            id: videoId,
            title: title.trim(),
            author: res['author'] as String? ?? 'YouTube',
            duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
            thumbnailUrl: res['thumbnail_url'] as String?,
          );
        }
      } catch (_) {}
    }

    // 6. Fallback: yt-dlp metadata if network/YouTubeExplode fails (desktop)
    final ytCmd = await _getYtDlpCommand();
    if (ytCmd != null) {
      try {
        final isNative = ytCmd == 'yt-dlp';
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
        final res = await Process.run(
          cmd,
          args,
        ).timeout(const Duration(seconds: 15));
        if (res.exitCode == 0) {
          final json =
              jsonDecode(res.stdout.toString()) as Map<String, dynamic>;
          return YouTubeMetadata(
            id: videoId,
            title: json['title'] as String? ?? 'YouTube Audio',
            author: json['uploader'] as String? ?? 'YouTube',
            duration: json['duration'] != null
                ? Duration(seconds: (json['duration'] as num).toInt())
                : null,
            thumbnailUrl: json['thumbnail'] as String?,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Future<Map<String, dynamic>?> healMetadata(
    Map<String, dynamic> track, {
    File? audioFile,
    SyncApi? api,
  }) async {
    final currentTitle = track['title'] as String? ?? '';
    final currentArtist = track['artist'] as String? ?? '';
    final isFallback = currentTitle.trim().isEmpty ||
        currentTitle == 'YouTube Audio' ||
        TrackFormatter.isUuidLike(currentTitle) ||
        TrackFormatter.isUuidLike(currentArtist);
    if (!isFallback) return null;

    final videoId = track['source_id'] as String?;
    if (videoId == null || videoId.isEmpty) return null;

    // 1. Fetch fresh metadata from YouTube (Explode, oEmbed, HTML, noembed, server proxy)
    final fresh = await getMetadata(videoId, api: api);
    if (fresh != null &&
        fresh.title.isNotEmpty &&
        fresh.title != 'YouTube Audio' &&
        !TrackFormatter.isUuidLike(fresh.title)) {
      final formatted = TrackFormatter.split(
        rawTitle: fresh.title,
        rawArtist: fresh.author,
      );
      return {
        ...track,
        'title': formatted.title,
        'artist': formatted.artist.isNotEmpty ? formatted.artist : fresh.author,
        if (fresh.thumbnailUrl != null) 'thumbnail_url': fresh.thumbnailUrl,
        if (fresh.duration != null) 'duration_ms': fresh.duration!.inMilliseconds,
      };
    }

    // 2. Fallback: Check if local audio file has REAL embedded tags (not filename fallback)
    if (audioFile != null && audioFile.existsSync()) {
      try {
        final parsed = LocalMetadataService.parseFile(audioFile);
        final trackId = track['id'] as String? ?? '';
        if (parsed.hasEmbeddedTags &&
            parsed.title.isNotEmpty &&
            parsed.title != 'YouTube Audio' &&
            parsed.title != trackId &&
            parsed.title != 'Track' &&
            !TrackFormatter.isUuidLike(parsed.title)) {
          return {
            ...track,
            'title': parsed.title,
            if (parsed.artist != null &&
                parsed.artist!.isNotEmpty &&
                !TrackFormatter.isUuidLike(parsed.artist!))
              'artist': parsed.artist,
            if (parsed.album != null && parsed.album!.isNotEmpty) 'album': parsed.album,
            if (parsed.durationMs != null) 'duration_ms': parsed.durationMs,
          };
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<String?> getStreamUrl(String videoId) async {
    return (await getStreamResult(videoId)).url;
  }

  @override
  Future<YouTubeStreamResult> getStreamResult(String videoId) async {
    // 1. Try yt-dlp first if available (fast and extracts direct stream url)
    final ytCmd = await _getYtDlpCommand();
    YouTubeStreamResult? ytDlpFailure;
    if (ytCmd != null) {
      try {
        final cmd = ytCmd == 'yt-dlp' ? 'yt-dlp' : 'python';
        final cookieFile = _findCookieFile();
        final args = [
          ..._ytDlpPrefix(ytCmd),
          if (cookieFile != null) ...['--cookies', cookieFile.path],
          '--js-runtimes',
          'node',
          '--remote-components',
          'ejs:github',
          '-g',
          '-f',
          'bestaudio',
          '--no-playlist',
          'https://www.youtube.com/watch?v=$videoId',
        ];
        final res = await Process.run(
          cmd,
          args,
        ).timeout(const Duration(seconds: 20));
        if (res.exitCode == 0) {
          final out = res.stdout.toString().trim();
          final lines = out
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.startsWith('http'));
          if (lines.isNotEmpty) {
            return YouTubeStreamResult(url: lines.first);
          }
        }
        ytDlpFailure = classifyYtDlpError('${res.stderr}\n${res.stdout}');
      } on TimeoutException {
        ytDlpFailure = classifyYtDlpError('timeout');
      } catch (error) {
        ytDlpFailure = YouTubeStreamResult(
          errorMessage: 'Не удалось запустить yt-dlp: $error',
        );
      }
    }

    // 2. Pure Dart fallback: YouTubeExplode with client rotation
    final fallbackClients = [
      null,
      [YoutubeApiClient.androidMusic],
      [YoutubeApiClient.ios],
      [YoutubeApiClient.tv],
      [YoutubeApiClient.mweb],
    ];
    for (final clients in fallbackClients) {
      try {
        final manifest = clients == null
            ? await _yt.videos.streamsClient
                  .getManifest(videoId)
                  .timeout(const Duration(seconds: 8))
            : await _yt.videos.streamsClient
                  .getManifest(videoId, ytClients: clients)
                  .timeout(const Duration(seconds: 8));
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          final highest = audioStreams.withHighestBitrate();
          return YouTubeStreamResult(url: highest.url.toString());
        }
      } on VideoUnplayableException catch (error) {
        ytDlpFailure ??= classifyYtDlpError(error.message);
      } catch (_) {}
    }
    return ytDlpFailure ??
        YouTubeStreamResult(
          errorMessage: 'Не удалось получить аудиопоток YouTube.',
        );
  }

  @override
  Future<File?> downloadMp3({
    required String videoId,
    required String outputFilePath,
    void Function(double progress)? onProgress,
  }) async {
    final result = await downloadMp3Result(
      videoId: videoId,
      outputFilePath: outputFilePath,
      onProgress: onProgress,
    );
    return result.file;
  }

  @override
  Future<YouTubeDownloadResult> downloadMp3Result({
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
    final tempFile = File('$targetBase.part');

    // Check for YouTube cookies file to bypass 18+ age restrictions
    final cookieFile = _findCookieFile(targetDir);

    // 1. If yt-dlp is available, download and convert directly to MP3 without saving video
    final ytCmd = await _getYtDlpCommand();
    YouTubeStreamResult? ytDlpFailure;
    if (ytCmd != null) {
      try {
        final cmd = ytCmd == 'yt-dlp' ? 'yt-dlp' : 'python';
        final args = [
          ..._ytDlpPrefix(ytCmd),
          if (cookieFile != null) ...['--cookies', cookieFile.path],
          '--js-runtimes',
          'node',
          '--remote-components',
          'ejs:github',
          '-x',
          '--embed-metadata',
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
        final diagnostics = StringBuffer();
        process.stdout.transform(utf8.decoder).listen((data) {
          if (onProgress != null && data.contains('%')) {
            final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(data);
            if (match != null) {
              final pct = double.tryParse(match.group(1) ?? '0');
      if (pct != null) onProgress?.call(pct / 100.0);
            }
          }
        });
        process.stderr.transform(utf8.decoder).listen(diagnostics.write);
        final exitCode = await process.exitCode.timeout(
          const Duration(minutes: 3),
        );
        if (exitCode == 0 && await finalMp3.exists()) {
          return YouTubeDownloadResult(file: finalMp3);
        }
        final firstError = diagnostics.toString();
        if (_needsCaptcha(firstError)) {
          final retried = await _retryYtDlpWithCaptcha(cmd, args, onProgress, finalMp3, firstError);
          if (retried != null) return retried;
        }
        ytDlpFailure = classifyYtDlpError(firstError);
      } on TimeoutException {
        ytDlpFailure = classifyYtDlpError('timeout');
      } catch (error) {
        ytDlpFailure = YouTubeStreamResult(
          errorMessage: 'Не удалось запустить yt-dlp: $error',
        );
      }
    }

    // 2. Pure Dart fallback: audio-only stream extraction (ZERO video saved/downloaded)
    IOSink? output;
    try {
      StreamManifest? manifest;
      final fallbackClients = [
        null,
        [YoutubeApiClient.androidMusic],
        [YoutubeApiClient.ios],
        [YoutubeApiClient.tv],
        [YoutubeApiClient.mweb],
      ];
      for (final clients in fallbackClients) {
        try {
          manifest = clients == null
              ? await _yt.videos.streamsClient
                    .getManifest(videoId)
                    .timeout(const Duration(seconds: 10))
              : await _yt.videos.streamsClient
                    .getManifest(videoId, ytClients: clients)
                    .timeout(const Duration(seconds: 10));
          if (manifest.audioOnly.isNotEmpty) break;
        } on VideoUnplayableException catch (e) {
          final msg = e.message.toLowerCase();
          final isAge =
              msg.contains('age') ||
              msg.contains('inappropriate') ||
              msg.contains('sign in') ||
              msg.contains('confirm');
          return YouTubeDownloadResult(
            isAgeRestricted: isAge,
            isUnavailable: true,
            errorMessage:
                ytDlpFailure?.errorMessage ??
                (isAge
                    ? 'Видео 18+: нужен актуальный cookies.txt от аккаунта '
                          'YouTube с подтвержденным возрастом.'
                    : (e.message.isNotEmpty ? e.message : 'Видео недоступно')),
          );
        } catch (_) {}
      }

      if (manifest == null || manifest.audioOnly.isEmpty) {
        return YouTubeDownloadResult(
          isUnavailable: true,
          isAgeRestricted: ytDlpFailure?.isAgeRestricted ?? false,
          errorMessage:
              ytDlpFailure?.errorMessage ?? 'Аудиопоток недоступен на YouTube',
        );
      }

      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      final stream = _yt.videos.streamsClient.get(audioStreamInfo);

      output = tempFile.openWrite();
      var received = 0;
      final total = audioStreamInfo.size.totalBytes;

      await for (final chunk in stream.timeout(
        const Duration(seconds: 15),
        onTimeout: (sink) =>
            sink.addError(TimeoutException('Таймаут передачи аудиопотока')),
      )) {
        output.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received / total);
        }
      }
      await output.flush();
      await output.close();
      output = null;

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
      return YouTubeDownloadResult(file: finalMp3);
    } on TimeoutException {
      return YouTubeDownloadResult(
        errorMessage: 'Таймаут скачивания аудиопотока YouTube',
      );
    } catch (e) {
      final str = e.toString();
      if (str.contains('confirm your age') || str.contains('inappropriate')) {
        return YouTubeDownloadResult(
          isAgeRestricted: true,
          isUnavailable: true,
          errorMessage: 'Возрастное ограничение (18+)',
        );
      }
      return YouTubeDownloadResult(errorMessage: 'Ошибка загрузки: $e');
    } finally {
      if (output != null) {
        try {
          await output.close();
        } catch (_) {}
      }
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<File?> downloadThumbnail(String? url, String outputImagePath) async {
    if (url == null || url.isEmpty) return null;
    HttpClient? client;
    try {
      final uri = Uri.parse(url);
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 10));
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
    } catch (_) {
    } finally {
      client?.close();
    }
    return null;
  }

  void dispose() {
    _yt.close();
  }
}
