/// Result of formatting track title and artist.
class FormattedTrackInfo {
  final String title;
  final String artist;

  const FormattedTrackInfo({
    required this.title,
    required this.artist,
  });
}

/// Utility for cleaning and separating track title and artist.
///
/// Detects formats like "Artist - Title", "Artist – Title", "Artist — Title",
/// extracts the artist into the artist field and leaves the clean song title.
///
/// Rules:
/// 1. If there is no dash, do not touch anything.
/// 2. If the dash is at the very beginning before any text (e.g. "- Title"), do not touch anything.
/// 3. Only split when there is non-empty text before the dash (artist) AND after the dash (title).
class TrackFormatter {
  static final RegExp _dashPattern = RegExp(r'[-–—]');

  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Checks if a string resembles a UUID (standard 8-4-4-4-12 hex format)
  /// or a trailing UUID fragment from downloaded file paths.
  static bool isUuidLike(String input) {
    final trimmed = input.trim();
    if (_uuidPattern.hasMatch(trimmed)) return true;
    // Also catch chopped UUID chunks like 41c8-abff-9415f3dfdacc or 2ce5...
    final parts = trimmed.split('-');
    if (parts.length >= 2 && parts.every((p) => RegExp(r'^[0-9a-fA-F]+$').hasMatch(p))) {
      final totalHexLen = parts.fold<int>(0, (sum, p) => sum + p.length);
      if (totalHexLen >= 16 && trimmed.length <= 40) {
        return true;
      }
    }
    return false;
  }

  /// Splits "Artist - Title" into separate artist and title strings.
  static FormattedTrackInfo split({
    required String rawTitle,
    String? rawArtist,
  }) {
    final trimmed = rawTitle.trim();
    final defaultArtist = (rawArtist != null && rawArtist.trim().isNotEmpty)
        ? rawArtist.trim()
        : '';

    // If the title looks like a UUID (e.g. filename fallback $id), DO NOT split it!
    if (isUuidLike(trimmed)) {
      return FormattedTrackInfo(
        title: rawTitle,
        artist: defaultArtist,
      );
    }

    // 1. If there is no dash at all, do not touch.
    final firstDashMatch = _dashPattern.firstMatch(trimmed);
    if (firstDashMatch == null) {
      return FormattedTrackInfo(
        title: rawTitle,
        artist: defaultArtist,
      );
    }

    // 2. If dash is at the very beginning before text (e.g. "- Track", "-- Track"),
    // do not count it and do not touch.
    if (firstDashMatch.start == 0) {
      return FormattedTrackInfo(
        title: rawTitle,
        artist: defaultArtist,
      );
    }

    // 3. Extract text before and after the first dash
    final dashIndex = firstDashMatch.start;
    final leftPart = trimmed.substring(0, dashIndex).trim();
    final rightPart = trimmed.substring(dashIndex + 1).trim();

    // Must have meaningful content on both sides
    if (leftPart.isEmpty || rightPart.isEmpty) {
      return FormattedTrackInfo(
        title: rawTitle,
        artist: defaultArtist,
      );
    }

    var cleanTitle = rightPart;
    // Strip wrapping quotes around title: "Song" -> Song, «Song» -> Song, 'Song' -> Song
    if ((cleanTitle.startsWith('"') && cleanTitle.endsWith('"')) ||
        (cleanTitle.startsWith('«') && cleanTitle.endsWith('»')) ||
        (cleanTitle.startsWith("'") && cleanTitle.endsWith("'"))) {
      if (cleanTitle.length > 2) {
        cleanTitle = cleanTitle.substring(1, cleanTitle.length - 1).trim();
      }
    }

    return FormattedTrackInfo(
      title: cleanTitle.isNotEmpty ? cleanTitle : rightPart,
      artist: leftPart,
    );
  }
}
