import 'dart:io';

import '../api.dart';
import 'local_metadata_service.dart';
import 'track_formatter.dart';
import 'youtube_downloader.dart';

/// Dedicated service for inspecting, re-fetching and manually editing track metadata.
/// Keeps AppController lean and adheres to single-responsibility and anti-monolith guidelines.
class TrackMetadataService {
  const TrackMetadataService();

  /// Creates a clean copy of [track] with manually updated [title] and [artist].
  Map<String, dynamic> buildManualMetadataUpdate({
    required Map<String, dynamic> track,
    required String title,
    String? artist,
  }) {
    final cleanTitle = title.trim();
    final cleanArtist = artist?.trim();
    return {
      ...track,
      'title': cleanTitle,
      'artist': (cleanArtist != null && cleanArtist.isNotEmpty) ? cleanArtist : null,
    };
  }

  /// Attempts to re-fetch and re-assemble fresh metadata for [track].
  ///
  /// For YouTube tracks: executes the multi-tier resolver (YouTubeExplode, oEmbed,
  /// HTML scraping of ytInitialPlayerResponse, noembed, server proxy).
  ///
  /// For local tracks: re-reads ID3 / container tags from [localFilePath].
  Future<Map<String, dynamic>?> refreshTrackMetadata({
    required Map<String, dynamic> track,
    required YouTubeDownloadService ytService,
    SyncApi? api,
    String? localFilePath,
    String? artworkOutputPath,
  }) async {
    final provider = track['provider'] as String?;

    if (provider == 'youtube') {
      final videoId = track['source_id'] as String?;
      if (videoId == null || videoId.isEmpty) return null;

      // 1. Check if the local audio file already has embedded tags
      if (localFilePath != null) {
        final localFile = File(localFilePath);
        if (localFile.existsSync()) {
          final parsed = LocalMetadataService.parseFile(
            localFile,
            artworkOutputPath: artworkOutputPath,
          );
          final trackId = track['id'] as String? ?? '';
          if (parsed.title.isNotEmpty &&
              parsed.title != 'YouTube Audio' &&
              parsed.title != trackId &&
              parsed.title != 'Track') {
            return {
              ...track,
              'title': parsed.title,
              if (parsed.artist != null && parsed.artist!.isNotEmpty)
                'artist': parsed.artist,
              if (parsed.album != null && parsed.album!.isNotEmpty)
                'album': parsed.album,
              if (parsed.durationMs != null && parsed.durationMs! > 0)
                'duration_ms': parsed.durationMs,
            };
          }
        }
      }

      // 2. Multi-tier online resolution (Explode, oEmbed, HTML Scraper, Noembed, Server)
      final meta = await ytService.getMetadata(videoId, api: api);
      if (meta != null && meta.title.isNotEmpty && meta.title != 'YouTube Audio') {
        final formatted = TrackFormatter.split(
          rawTitle: meta.title,
          rawArtist: meta.author,
        );
        return {
          ...track,
          'title': formatted.title,
          'artist': formatted.artist.isNotEmpty ? formatted.artist : meta.author,
          if (meta.thumbnailUrl != null && meta.thumbnailUrl!.isNotEmpty)
            'thumbnail_url': meta.thumbnailUrl,
          if (meta.duration != null && meta.duration!.inMilliseconds > 0)
            'duration_ms': meta.duration!.inMilliseconds,
        };
      }
    } else if (provider == 'local') {
      if (localFilePath != null) {
        final localFile = File(localFilePath);
        if (localFile.existsSync()) {
          final parsed = LocalMetadataService.parseFile(
            localFile,
            artworkOutputPath: artworkOutputPath,
          );
          return {
            ...track,
            'title': parsed.title,
            if (parsed.artist != null && parsed.artist!.isNotEmpty)
              'artist': parsed.artist,
            if (parsed.album != null && parsed.album!.isNotEmpty)
              'album': parsed.album,
            if (parsed.durationMs != null && parsed.durationMs! > 0)
              'duration_ms': parsed.durationMs,
          };
        }
      }
    }

    return null;
  }
}
