import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'track_formatter.dart';

class ParsedTrackMetadata {
  ParsedTrackMetadata({
    required this.title,
    this.artist,
    this.album,
    this.durationMs,
    this.artworkPath,
  });

  final String title;
  final String? artist;
  final String? album;
  final int? durationMs;
  final String? artworkPath;
}

class LocalMetadataService {
  static ParsedTrackMetadata parseFile(File file, {String? artworkOutputPath}) {
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path.split(Platform.pathSeparator).last;
    // Derive a human-readable fallback from the file name (strip extension).
    final rawFallback = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final safeFallbackTitle = rawFallback.trim().isNotEmpty ? rawFallback.trim() : 'Track';

    try {
      final meta = readMetadata(file, getImage: artworkOutputPath != null);
      final rawTitle = meta.title?.trim();
      final title = (rawTitle != null && rawTitle.isNotEmpty)
          ? rawTitle
          : safeFallbackTitle;
      final rawArtist = meta.artist?.trim() ?? meta.albumArtist?.trim();
      final artist = (rawArtist != null && rawArtist.isNotEmpty)
          ? rawArtist
          : null;
      final rawAlbum = meta.album?.trim();
      final album = (rawAlbum != null && rawAlbum.isNotEmpty) ? rawAlbum : null;
      final durationMs = meta.duration?.inMilliseconds;

      String? savedArtPath;
      if (artworkOutputPath != null && meta.pictures.isNotEmpty) {
        try {
          final pic = meta.pictures.first;
          final artFile = File(artworkOutputPath);
          if (!artFile.parent.existsSync()) {
            artFile.parent.createSync(recursive: true);
          }
          artFile.writeAsBytesSync(pic.bytes);
          savedArtPath = artFile.path;
        } catch (_) {}
      }

      final formatted = TrackFormatter.split(
        rawTitle: title,
        rawArtist: artist,
      );

      return ParsedTrackMetadata(
        title: formatted.title,
        artist: formatted.artist,
        album: album,
        durationMs: durationMs,
        artworkPath: savedArtPath,
      );
    } catch (_) {
      final fallbackFormatted = TrackFormatter.split(rawTitle: safeFallbackTitle);
      return ParsedTrackMetadata(
        title: fallbackFormatted.title,
        artist: fallbackFormatted.artist,
        album: null,
        durationMs: null,
        artworkPath: null,
      );
    }
  }
}
