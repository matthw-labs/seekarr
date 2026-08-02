import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/features/import/domain/manual_import_models.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Container extensions the video \*arrs actually import.
///
/// Deliberately generous: this list only decides how a row is **presented**,
/// never what gets sent to the service, and a file classified as "other" is
/// still fully fixable and importable if the user opens it. So the cost of a
/// miss is one extra tap, while the win is large — a Sonarr scan of a mixed
/// downloads folder otherwise files playlists and music alongside genuine
/// unmatched episodes, and the "needs attention" count stops meaning anything.
const _videoExtensions = {
  'MKV',
  'MP4',
  'M4V',
  'AVI',
  'MPG',
  'MPEG',
  'WMV',
  'MOV',
  'FLV',
  'TS',
  'M2TS',
  'MTS',
  'WEBM',
  'OGV',
  'DIVX',
  'VOB',
  'ISO',
  'IFO',
  'RMVB',
  'ASF',
  'STRM',
};

/// Extensions Lidarr imports.
const _audioExtensions = {
  'MP3',
  'FLAC',
  'M4A',
  'M4B',
  'OGG',
  'OGA',
  'OPUS',
  'WAV',
  'WMA',
  'AAC',
  'ALAC',
  'APE',
  'AIFF',
  'AIF',
  'WV',
  'MKA',
};

/// Whether this file is the kind of media the service imports at all.
bool manualImportIsSupportedFile(ServiceKey service, ManualImportItem item) {
  final extension = item.extension.toUpperCase();
  return switch (service) {
    ServiceKey.radarr ||
    ServiceKey.sonarr => _videoExtensions.contains(extension),
    ServiceKey.lidarr => _audioExtensions.contains(extension),
    _ => true,
  };
}

/// Why a file is in the "other files" bucket, in the user's words.
String manualImportUnsupportedReason(
  ServiceKey service,
  ManualImportItem item,
) {
  final kind = switch (service) {
    ServiceKey.lidarr => 'an audio file',
    _ => 'a video file',
  };
  return 'Not $kind — ${service.title} cannot import ${item.extension} files.';
}

/// The title a file is grouped under: its matched media, or "Unmatched".
///
/// Grouping is what makes a 400-file scan workable — the user thinks in shows
/// and albums, not in filenames, so "select every Boruto file" has to be one
/// gesture rather than forty.
String manualImportGroupTitle(ServiceKey service, ManualImportItem item) {
  final title = switch (service) {
    ServiceKey.radarr => stringOrNull(item.movie?['title']),
    ServiceKey.sonarr => stringOrNull(item.series?['title']),
    ServiceKey.lidarr =>
      stringOrNull(item.artist?['artistName']) ??
          stringOrNull(item.artist?['title']),
    _ => null,
  };
  final trimmed = title?.trim();
  return trimmed == null || trimmed.isEmpty ? 'Unmatched' : trimmed;
}

/// What a matched file resolved to, split so the eye can verify it fast.
///
/// The verification question on the Review screen is always "did the service
/// guess right?", and answering it means comparing the parsed identity against
/// the filename. So the pieces are kept separate — a short [code] the eye can
/// match against the filename's `S02E01`, the [title] of the episode/album, and
/// the technical [quality] — instead of being mashed into one truncated line
/// where the episode code is the first thing to disappear.
class ManualImportIdentity {
  /// Short positional code: `S02E01`, a release year, a track number.
  final String? code;

  /// The name of the matched child: episode title, album title.
  final String? title;

  /// Quality, and language when it is not the default.
  final String? quality;

  const ManualImportIdentity({this.code, this.title, this.quality});
}

ManualImportIdentity manualImportIdentityFor(
  ServiceKey service,
  ManualImportItem item,
) {
  final quality = item.qualityLabel == 'Unknown' ? null : item.qualityLabel;

  return switch (service) {
    ServiceKey.radarr => ManualImportIdentity(
      code: stringOrNull(item.movie?['year']),
      quality: quality,
    ),
    ServiceKey.sonarr => ManualImportIdentity(
      code: _episodeCode(item.episodes),
      title: _episodeTitles(item.episodes),
      quality: quality,
    ),
    ServiceKey.lidarr => ManualImportIdentity(
      code: _trackCode(item.tracks),
      title: stringOrNull(item.album?['title']),
      quality: quality,
    ),
    _ => ManualImportIdentity(quality: quality),
  };
}

/// `S02E01`, or `S02E01-E02` for a multi-episode file.
String? _episodeCode(List<Map<String, dynamic>> episodes) {
  final codes = <String>[];
  int? season;
  for (final episode in episodes) {
    final seasonNumber = intOrNull(episode['seasonNumber']);
    final episodeNumber = intOrNull(episode['episodeNumber']);
    if (seasonNumber == null || episodeNumber == null) continue;
    season ??= seasonNumber;
    codes.add('E${episodeNumber.toString().padLeft(2, '0')}');
  }
  if (season == null || codes.isEmpty) return null;
  final seasonCode = 'S${season.toString().padLeft(2, '0')}';
  if (codes.length == 1) return '$seasonCode${codes.first}';
  return '$seasonCode${codes.first}-${codes.last}';
}

String? _episodeTitles(List<Map<String, dynamic>> episodes) {
  final titles = episodes
      .map((episode) => stringOrNull(episode['title']))
      .whereType<String>()
      .where((title) => title.trim().isNotEmpty)
      .toList(growable: false);
  if (titles.isEmpty) return null;
  if (titles.length <= 2) return titles.join(' + ');
  return '${titles.take(2).join(' + ')} +${titles.length - 2}';
}

String? _trackCode(List<Map<String, dynamic>> tracks) {
  final numbers = tracks
      .map(
        (track) =>
            intOrNull(track['trackNumber']) ??
            intOrNull(track['absoluteTrackNumber']),
      )
      .whereType<int>()
      .toList(growable: false);
  if (numbers.isEmpty) return tracks.isEmpty ? null : '${tracks.length} tracks';
  if (numbers.length == 1) return 'Track ${numbers.first}';
  return 'Tracks ${numbers.first}–${numbers.last}';
}

/// Does this file match the user's filter text?
///
/// Searches everything the row shows — matched title, positional code, episode
/// or album name, and the filename — so typing "boruto" finds the files
/// whether the service recognised them or not.
bool manualImportMatchesQuery(
  ServiceKey service,
  ManualImportItem item,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;

  final identity = manualImportIdentityFor(service, item);
  final haystack = [
    manualImportGroupTitle(service, item),
    identity.code,
    identity.title,
    identity.quality,
    // The name as rendered, not the service's `name` field: the \*arrs strip
    // the extension there, so filtering on `.mkv` would have found nothing.
    item.fileName,
    item.path,
  ].whereType<String>().join(' ').toLowerCase();

  return haystack.contains(normalized);
}
