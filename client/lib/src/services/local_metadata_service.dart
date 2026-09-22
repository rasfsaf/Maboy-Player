import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';

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
    final fallbackTitle = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    try {
      final meta = readMetadata(file, getImage: artworkOutputPath != null);
      final rawTitle = meta.title?.trim();
      final title = (rawTitle != null && rawTitle.isNotEmpty)
          ? rawTitle
          : fallbackTitle;
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

      return ParsedTrackMetadata(
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        artworkPath: savedArtPath,
      );
    } catch (_) {
      return ParsedTrackMetadata(
        title: fallbackTitle,
        artist: null,
        album: null,
        durationMs: null,
        artworkPath: null,
      );
    }
  }
}
