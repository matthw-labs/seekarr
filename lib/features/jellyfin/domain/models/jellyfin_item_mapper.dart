/// `BaseItemDto` / `SessionInfoDto` → the shared Stream models.
///
/// Every function here is top-level and pure, which is a hard requirement rather
/// than a style: the client hands whole pages to `Isolate.run`, and a closure
/// that captured the client (and through it a `Dio`) could not be sent.
///
/// Jellyfin describes a film, a series, a season, an episode, an album and a
/// track with the *same* `BaseItemDto`, so one mapper covers every depth — the
/// difference from the arr side that `StreamItem` was designed around.
library;

import 'package:seekarr/features/jellyfin/domain/models/jellyfin_transcode_reason.dart';
import 'package:seekarr/features/jellyfin/domain/models/jellyfin_units.dart';
import 'package:seekarr/features/stream/domain/models/stream_item.dart';
import 'package:seekarr/features/stream/domain/models/stream_session.dart';

/// Above this many rows, mapping moves to an isolate.
///
/// Same threshold and same reasoning as the qBittorrent list parse: a page of 50
/// costs less to map inline than to ship across a port, while an unpaged
/// `/Shows/{id}/Episodes` on a 400-episode series is exactly the jank this rule
/// exists for.
const int kJellyfinIsolateMapThreshold = 200;

/// Item types Jellyfin can return that the Stream models have a shape for.
///
/// `Video`, `MusicVideo`, `Folder`, `CollectionFolder`, `BoxSet`, `Book`,
/// `Photo`, `TvChannel` and friends all land on `other`: they render, they just
/// do not claim a vocabulary they do not have.
StreamItemKind jellyfinItemKind(Object? rawType) {
  switch (rawType?.toString()) {
    case 'Movie':
      return StreamItemKind.movie;
    case 'Series':
      return StreamItemKind.series;
    case 'Season':
      return StreamItemKind.season;
    case 'Episode':
      return StreamItemKind.episode;
    case 'MusicAlbum':
      return StreamItemKind.album;
    case 'Audio':
      return StreamItemKind.track;
    default:
      return StreamItemKind.other;
  }
}

/// The server-relative artwork path for an item, or null when it has no image.
///
/// Deliberately a *path* and not a URL, per `StreamItem.posterPath`: resolving it
/// needs the credential, and the credential must stay in a header so it never
/// becomes part of `CachedNetworkImage`'s cache key.
///
/// `?tag=` is carried along because Jellyfin's image route is otherwise
/// indistinguishable across edits — replace a poster and every cache in the chain
/// keeps serving the old bytes from the identical URL. The tag is the server's own
/// content hash, so it is both the correct cache key and free.
///
/// **Order: the item's own art, then its parent's.** `Primary` first, then the
/// other types the item actually has — an episode is routinely `Thumb`-only, and
/// asking for a `Primary` that does not exist 404s. Only when the item has no art
/// at all does this fall back to `SeriesPrimaryImageTag` (or an album's parent),
/// which is what keeps an episode list from rendering as a grid of grey
/// rectangles. Trying the series *before* the item's own `Thumb` would be the
/// worse rule: it would show the series poster for a `Thumb`-only episode while
/// showing the episode's own wide still for one that has a `Primary`, so two rows
/// of the same list would disagree about what they are picturing.
String? jellyfinPosterPath(Map<String, dynamic> item) {
  final id = item['Id']?.toString();
  final imageTags = item['ImageTags'];
  if (id != null && id.isNotEmpty && imageTags is Map) {
    for (final type in const [
      'Primary',
      'Thumb',
      'Backdrop',
      'Banner',
      'Art',
      'Logo',
    ]) {
      final tag = imageTags[type]?.toString();
      if (tag != null && tag.isNotEmpty) {
        return '/Items/$id/Images/$type?tag=$tag';
      }
    }
  }

  final seriesId = item['SeriesId']?.toString();
  final seriesTag = item['SeriesPrimaryImageTag']?.toString();
  if (seriesId != null &&
      seriesId.isNotEmpty &&
      seriesTag != null &&
      seriesTag.isNotEmpty) {
    return '/Items/$seriesId/Images/Primary?tag=$seriesTag';
  }

  // An album inherits the artist's or the parent folder's image.
  final parentId = item['AlbumId']?.toString() ?? item['ParentId']?.toString();
  final parentTag = item['AlbumPrimaryImageTag']?.toString();
  if (parentId != null &&
      parentId.isNotEmpty &&
      parentTag != null &&
      parentTag.isNotEmpty) {
    return '/Items/$parentId/Images/Primary?tag=$parentTag';
  }

  return null;
}

/// `S2E4`, or `E4` / `S2` when only one of the two numbers is present.
///
/// Specials sit in season 0 and routinely arrive with a null `IndexNumber`, so
/// both halves have to be independently optional.
String? jellyfinEpisodeCode(Map<String, dynamic> item) {
  final season = jellyfinInt(item['ParentIndexNumber']);
  final episode = jellyfinInt(item['IndexNumber']);
  if (season == null && episode == null) return null;
  return [
    if (season != null) 'S$season',
    if (episode != null) 'E$episode',
  ].join();
}

/// The artist credit for a track or an album.
String? _artistLabel(Map<String, dynamic> item) {
  final albumArtist = item['AlbumArtist']?.toString();
  if (albumArtist != null && albumArtist.trim().isNotEmpty) return albumArtist;
  final artists = item['Artists'];
  if (artists is List && artists.isNotEmpty) {
    return artists.map((value) => value.toString()).join(', ');
  }
  return null;
}

/// One line that disambiguates the title, per `StreamItem.subtitle`: the series
/// for an episode, the artist for a track, the year for a film.
String? _itemSubtitle(Map<String, dynamic> item, StreamItemKind kind) {
  final year = jellyfinInt(item['ProductionYear']);
  switch (kind) {
    case StreamItemKind.episode:
      final series = item['SeriesName']?.toString();
      final code = jellyfinEpisodeCode(item);
      // The series name alone is what the contract asks for, but an episode list
      // is unreadable without the numbers and the season name is not always set.
      return [
        if (series != null && series.isNotEmpty) series,
        if (code != null) code,
      ].join(' · ').ifEmptyNull();
    case StreamItemKind.season:
      return item['SeriesName']?.toString().ifEmptyNull();
    case StreamItemKind.track:
      return _artistLabel(item) ?? item['Album']?.toString().ifEmptyNull();
    case StreamItemKind.album:
      return _artistLabel(item) ?? year?.toString();
    case StreamItemKind.movie:
    case StreamItemKind.series:
    case StreamItemKind.other:
      return year?.toString();
  }
}

/// Resume offset in milliseconds, or null when the item was never started.
///
/// `PlaybackPositionTicks` is authoritative. `PlayedPercentage` is the fallback
/// for the endpoints that summarise `UserData` without the tick field, and it is
/// a **0–100** double — the one place in this feature where a value that looks
/// like a fraction is not one.
int? _resumeOffsetMs(Map<String, dynamic> userData, Object? runtimeTicks) {
  final fromTicks = jellyfinMillisecondsFromTicks(
    userData['PlaybackPositionTicks'],
    zeroAsNull: true,
  );
  // Ticks are authoritative, so a present position ends the search either way.
  // Zero already arrives as null; a position under a millisecond *truncates* to
  // zero, which would slip past that guard and light up a resume bar pinned at
  // the left edge for something nobody has watched a frame of.
  if (fromTicks != null) return fromTicks > 0 ? fromTicks : null;

  final fraction = jellyfinFractionFromPercent(userData['PlayedPercentage']);
  final runtimeMs = jellyfinMillisecondsFromTicks(
    runtimeTicks,
    zeroAsNull: true,
  );
  if (fraction == null || fraction <= 0 || runtimeMs == null) return null;
  final offset = (runtimeMs * fraction).round();
  return offset > 0 ? offset : null;
}

/// One `BaseItemDto` → one [StreamItem].
StreamItem jellyfinStreamItemFromJson(Map<String, dynamic> item) {
  final kind = jellyfinItemKind(item['Type']);
  final rawUserData = item['UserData'];
  final userData = rawUserData is Map
      ? rawUserData.cast<String, dynamic>()
      : const <String, dynamic>{};
  final runtimeTicks = item['RunTimeTicks'];

  return StreamItem(
    id: item['Id']?.toString() ?? '',
    title: item['Name']?.toString() ?? '',
    subtitle: _itemSubtitle(item, kind),
    kind: kind,
    posterPath: jellyfinPosterPath(item),
    year: jellyfinInt(item['ProductionYear']),
    runtimeMs: jellyfinMillisecondsFromTicks(runtimeTicks, zeroAsNull: true),
    // `UserData` only exists on the response when the request passed
    // `enableUserData=true` *and* a userId; absent means "unknown", and false is
    // the honest reading of unknown for a watched flag.
    isPlayed: userData['Played'] == true,
    resumeOffsetMs: _resumeOffsetMs(userData, runtimeTicks),
    unplayedChildCount: jellyfinInt(userData['UnplayedItemCount']),
  );
}

/// A whole page of items. The `Isolate.run` entry point, hence top-level.
List<StreamItem> jellyfinStreamItemsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final items = <StreamItem>[];
  for (final element in raw) {
    if (element is Map) {
      items.add(jellyfinStreamItemFromJson(element.cast<String, dynamic>()));
    }
  }
  return items;
}

/// Jellyfin's `PlayMethod` → the shared decision enum.
///
/// A missing `PlayMethod` with a live `TranscodingInfo` is treated as a
/// transcode: the field is populated asynchronously as playback starts, and the
/// board must not spend those seconds claiming a stream is free.
StreamPlayMethod jellyfinPlayMethod(
  Object? rawPlayMethod, {
  required bool hasTranscodingInfo,
}) {
  switch (rawPlayMethod?.toString()) {
    case 'DirectPlay':
      return StreamPlayMethod.directPlay;
    case 'DirectStream':
      return StreamPlayMethod.directStream;
    case 'Transcode':
      return StreamPlayMethod.transcode;
    default:
      return hasTranscodingInfo
          ? StreamPlayMethod.transcode
          : StreamPlayMethod.directPlay;
  }
}

/// `Jellyfin Web · Chrome` — the client, then the device it runs on.
String _deviceLabel(Map<String, dynamic> session) {
  final client = session['Client']?.toString().trim() ?? '';
  final device = session['DeviceName']?.toString().trim() ?? '';
  if (client.isNotEmpty && device.isNotEmpty) return '$client · $device';
  if (client.isNotEmpty) return client;
  if (device.isNotEmpty) return device;
  // `DeviceType` is the last resort — it is often null on third-party clients.
  return session['DeviceType']?.toString() ?? '';
}

/// The `Bitrate` of the media source that is actually being played.
///
/// The fallback for a direct play, which has no rate of its own anywhere in the
/// payload. It describes the *file*, not the wire, which is exactly what
/// `StreamSession.bitrateIsNominal` exists to declare.
///
/// [mediaSourceId] is `PlayState.MediaSourceId` and is what makes this correct on
/// a library that keeps more than one version of a film: `MediaSources` then holds
/// both the 4K remux and the 1080p encode, and only one of them is on the wire.
/// Picking the largest — or the first — would report a 60 Mbps remux for somebody
/// watching the 1080p file, on the one row the board exists to make trustworthy.
/// The largest is still the fallback for the case where the id names no source we
/// can see (a version deleted mid-playback, or a proxy that trimmed the array).
int? _nominalBitrate(Map<String, dynamic> nowPlaying, Object? mediaSourceId) {
  final sources = nowPlaying['MediaSources'];
  if (sources is List) {
    final playing = mediaSourceId?.toString().trim() ?? '';
    int? best;
    for (final source in sources) {
      if (source is! Map) continue;
      final bitrate = jellyfinBitsPerSecond(source['Bitrate']);
      if (bitrate == null) continue;
      if (playing.isNotEmpty && source['Id']?.toString() == playing) {
        return bitrate;
      }
      if (best == null || bitrate > best) best = bitrate;
    }
    if (best != null) return best;
  }
  return jellyfinBitsPerSecond(nowPlaying['Bitrate']);
}

/// One `SessionInfoDto` → one [StreamSession], or null when nothing is playing.
///
/// `/Sessions` returns every *connected* client, not every playing one: an idle
/// browser tab sits in that array for as long as it holds the WebSocket, with
/// `NowPlayingItem: null`. Filtering on that field is the only thing separating
/// "nobody is watching" from "seven people are watching".
StreamSession? jellyfinStreamSessionFromJson(Map<String, dynamic> session) {
  final rawNowPlaying = session['NowPlayingItem'];
  if (rawNowPlaying is! Map) return null;
  final nowPlaying = rawNowPlaying.cast<String, dynamic>();

  final rawPlayState = session['PlayState'];
  final playState = rawPlayState is Map
      ? rawPlayState.cast<String, dynamic>()
      : const <String, dynamic>{};
  final rawTranscoding = session['TranscodingInfo'];
  final transcoding = rawTranscoding is Map
      ? rawTranscoding.cast<String, dynamic>()
      : null;

  final playMethod = jellyfinPlayMethod(
    playState['PlayMethod'],
    hasTranscodingInfo: transcoding != null,
  );

  // A transcode reports the encoder's actual target, so that figure is real. Any
  // other method has no rate field at all and falls back to the source file's
  // bitrate — nominal, and flagged as such so the board can never present it as
  // measured throughput it does not have.
  final transcodeBitrate = transcoding == null
      ? null
      : jellyfinBitsPerSecond(transcoding['Bitrate']);
  final bitrate =
      transcodeBitrate ??
      _nominalBitrate(nowPlaying, playState['MediaSourceId']);

  final kind = jellyfinItemKind(nowPlaying['Type']);
  final name = nowPlaying['Name']?.toString() ?? '';
  final seriesName = nowPlaying['SeriesName']?.toString() ?? '';

  // For an episode the *series* is the headline and the episode is the detail —
  // the opposite of `StreamItem`, and what makes a session row readable at a
  // glance. See `StreamSession.title`.
  final isEpisode = kind == StreamItemKind.episode && seriesName.isNotEmpty;
  final episodeCode = jellyfinEpisodeCode(nowPlaying);

  return StreamSession(
    // `Id`, never `DeviceId`: the stop command 404s on any other identifier.
    id: session['Id']?.toString() ?? '',
    userName: session['UserName']?.toString() ?? '',
    title: isEpisode ? seriesName : name,
    subtitle: isEpisode
        ? [if (episodeCode != null) episodeCode, name].join(' · ').ifEmptyNull()
        : _itemSubtitle(nowPlaying, kind),
    deviceLabel: _deviceLabel(session),
    posterPath: jellyfinPosterPath(nowPlaying),
    playMethod: playMethod,
    // A direct stream has reasons too, and dropping them was the bug: Jellyfin
    // remuxes *because of something* — an unsupported container, an external
    // subtitle track — and reports it in the same `TranscodeReasons` array. The
    // model says so at `StreamSession.transcodeReasons`, and Plex has always
    // passed its decisions through unconditionally, so the byte-identical
    // session explained itself on one server and not the other.
    //
    // Only a direct play is gated, and on the play method rather than on the
    // array being empty: nothing is being done to the file, so an array that
    // arrived anyway (a stale session row mid-transition) would explain
    // something that is not happening.
    transcodeReasons: playMethod == StreamPlayMethod.directPlay
        ? const []
        : jellyfinTranscodeReasonPhrases(transcoding?['TranscodeReasons']),
    bitrate: bitrate,
    bitrateIsNominal: transcodeBitrate == null,
    progress: jellyfinFractionFromTicks(
      position: playState['PositionTicks'],
      runtime: nowPlaying['RunTimeTicks'],
    ),
    isPaused: playState['IsPaused'] == true,
  );
}

/// Every playing session, most expensive first. The `Isolate.run` entry point.
///
/// "Most expensive" is the enum's own order (transcode → direct stream → direct
/// play), then bitrate, then the viewer's name so the list is stable between
/// polls — `List.sort` is not stable, and a board that reshuffled two identical
/// transcodes every three seconds would look broken.
List<StreamSession> jellyfinStreamSessionsFromJson(Object? raw) {
  if (raw is! List) return const [];
  final sessions = <StreamSession>[];
  for (final element in raw) {
    if (element is! Map) continue;
    final session = jellyfinStreamSessionFromJson(
      element.cast<String, dynamic>(),
    );
    if (session != null) sessions.add(session);
  }

  sessions.sort((a, b) {
    final byMethod = b.playMethod.index.compareTo(a.playMethod.index);
    if (byMethod != 0) return byMethod;
    final byBitrate = (b.bitrate ?? 0).compareTo(a.bitrate ?? 0);
    if (byBitrate != 0) return byBitrate;
    return a.userName.compareTo(b.userName);
  });
  return sessions;
}

extension _NullIfEmpty on String {
  /// `''` is never a useful subtitle; null lets the widget drop the line.
  String? ifEmptyNull() => trim().isEmpty ? null : this;
}
