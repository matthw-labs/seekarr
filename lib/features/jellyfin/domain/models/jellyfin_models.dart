/// The three Jellyfin payloads that are *not* `BaseItemDto`, kept as their own
/// DTOs before they are reduced to the shared Stream models.
///
/// `PublicSystemInfo`, `UserDto` and `VirtualFolderInfo` each carry fields the
/// Stream contract has no room for but the app still reasons about — the server
/// name, whether a user is disabled, a library's physical locations — so they get
/// a thin typed layer instead of being read out of raw maps at the call site.
/// Everything else on the wire is a `BaseItemDto` and goes straight through
/// `jellyfin_item_mapper.dart`.
///
/// Constructors are pure and take a decoded map, so they remain safe to run
/// inside `Isolate.run` alongside the item mappers.
library;

import 'package:flutter/foundation.dart';

import 'package:seekarr/features/stream/domain/models/stream_library.dart';
import 'package:seekarr/features/stream/domain/stream_server_client.dart';

/// `GET /System/Info/Public` — the one endpoint that takes no credential.
///
/// Answering this proves the box is up and the base URL points at a Jellyfin,
/// which is what lets the app tell "server down" apart from "token rejected"
/// instead of surfacing both as one timeout.
@immutable
class JellyfinPublicSystemInfo {
  const JellyfinPublicSystemInfo({
    required this.version,
    required this.serverName,
    required this.id,
  });

  /// e.g. `10.11.11`. Null when the field is absent, which in practice means the
  /// address answered but is not a Jellyfin.
  final String? version;
  final String? serverName;
  final String? id;

  factory JellyfinPublicSystemInfo.fromJson(Map<String, dynamic> json) {
    return JellyfinPublicSystemInfo(
      version: _nonEmpty(json['Version']),
      serverName: _nonEmpty(json['ServerName']),
      id: _nonEmpty(json['Id']),
    );
  }

  /// Whether this response actually came from a Jellyfin server.
  ///
  /// A reverse proxy landing page happily returns 200 with a body that decodes
  /// to something; without this check the version probe would report success on
  /// an address that has no Jellyfin behind it at all.
  bool get isJellyfin => version != null;
}

/// `GET /Users` — one household member.
///
/// This endpoint is the *only* way to obtain a user id for this integration: an
/// API key authenticates as Administrator with an **empty** `UserId` claim, so
/// every user-scoped query (resume points, next-up, unplayed) has to be told
/// explicitly whose watch state to read.
@immutable
class JellyfinUserDto {
  const JellyfinUserDto({
    required this.id,
    required this.name,
    required this.isAdministrator,
    required this.isDisabled,
    required this.lastActivityAt,
  });

  final String id;
  final String name;
  final bool isAdministrator;
  final bool isDisabled;

  /// `LastActivityDate`, already parsed. Null when the user has never signed in.
  final DateTime? lastActivityAt;

  factory JellyfinUserDto.fromJson(Map<String, dynamic> json) {
    final policy = json['Policy'];
    final policyMap = policy is Map
        ? policy.cast<String, dynamic>()
        : const <String, dynamic>{};
    return JellyfinUserDto(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      isAdministrator: policyMap['IsAdministrator'] == true,
      isDisabled: policyMap['IsDisabled'] == true,
      lastActivityAt: _parseDate(json['LastActivityDate']),
    );
  }

  StreamViewer toStreamViewer() => StreamViewer(id: id, name: name);
}

/// `GET /Library/VirtualFolders` — one library.
@immutable
class JellyfinVirtualFolder {
  const JellyfinVirtualFolder({
    required this.itemId,
    required this.name,
    required this.collectionType,
    required this.locations,
    required this.refreshProgress,
    required this.refreshStatus,
  });

  /// `ItemId` — the `CollectionFolder`'s own id.
  ///
  /// Not `Id` and not the folder's name: this is the value `/Items?parentId=`
  /// scopes on and the `{itemId}` that `POST /Items/{itemId}/Refresh` rescans, so
  /// it is the only one of the three that is useful downstream.
  final String itemId;

  final String name;

  /// `movies`, `tvshows`, `music`, `musicvideos`, `boxsets`, `books`, `photos`,
  /// `homevideos`, `playlists`, `livetv` or `folders`. Absent on a mixed-content
  /// library, which is exactly why the kind falls back to `other`.
  final String? collectionType;

  /// Physical paths behind the library. Not shown anywhere yet, but it is the
  /// only field that distinguishes two libraries with the same name.
  final List<String> locations;

  /// 0–100 while a scan is running on this library. Absent when idle.
  final double? refreshProgress;

  /// e.g. `Idle`, `Queued`, `Active`. Absent on older servers, which is why
  /// [isRefreshing] can fall back to the progress figure.
  final String? refreshStatus;

  factory JellyfinVirtualFolder.fromJson(Map<String, dynamic> json) {
    final locations = json['Locations'];
    final progress = json['RefreshProgress'];
    return JellyfinVirtualFolder(
      itemId: json['ItemId']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      collectionType: _nonEmpty(json['CollectionType'])?.toLowerCase(),
      locations: locations is List
          ? locations.map((value) => value.toString()).toList(growable: false)
          : const [],
      refreshProgress: progress is num
          ? progress.toDouble()
          : double.tryParse(progress?.toString() ?? ''),
      refreshStatus: _nonEmpty(json['RefreshStatus']),
    );
  }

  /// Statuses that mean "no scan is running".
  ///
  /// Matched case-insensitively and by exclusion — the set of terminal statuses
  /// is small and stable, whereas the set of in-progress ones has grown across
  /// releases, so treating an unknown status as "refreshing" fails in the
  /// direction that merely shows a spinner one refresh too long.
  static const _idleStatuses = {
    'idle',
    'complete',
    'completed',
    'cancelled',
    'canceled',
    'failed',
  };

  bool get isRefreshing {
    final status = refreshStatus;
    if (status != null && status.isNotEmpty) {
      return !_idleStatuses.contains(status.toLowerCase());
    }
    // No status field: a progress figure only appears while a scan is live, but
    // a completed scan can leave 100 behind for a moment.
    final progress = refreshProgress;
    return progress != null && progress >= 0 && progress < 100;
  }

  StreamLibraryKind get kind {
    switch (collectionType) {
      case 'movies':
        return StreamLibraryKind.movies;
      case 'tvshows':
        return StreamLibraryKind.shows;
      case 'music':
        return StreamLibraryKind.music;
      case 'photos':
      case 'homevideos':
        return StreamLibraryKind.photos;
      // `musicvideos`, `boxsets`, `books`, `playlists`, `livetv`, `folders` and
      // mixed-content libraries (no CollectionType at all) have no glyph of
      // their own and no useful item vocabulary.
      default:
        return StreamLibraryKind.other;
    }
  }

  StreamLibrary toStreamLibrary() => StreamLibrary(
    id: itemId,
    name: name,
    kind: kind,
    // `VirtualFolderInfo` carries no item count, and deriving one would cost an
    // extra `/Items?limit=1` round trip per library on every dashboard refresh
    // just to read `TotalRecordCount`.
    itemCount: null,
    // **Always null on Jellyfin, and not an oversight.** There is no per-library
    // last-scan timestamp anywhere in the API: scanning is a single global
    // scheduled task ("Scan Media Library") and a library exposes only live
    // progress, never a completion time. `StreamLibrary.lastScannedAt` is
    // nullable precisely because Plex has this and Jellyfin does not.
    lastScannedAt: null,
    isRefreshing: isRefreshing,
  );
}

String? _nonEmpty(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

/// Jellyfin timestamps are ISO-8601 with a `Z` or an offset; anything else is
/// treated as absent rather than throwing inside a list mapper.
DateTime? _parseDate(Object? raw) {
  final value = _nonEmpty(raw);
  if (value == null) return null;
  return DateTime.tryParse(value);
}

/// Shared by both list endpoints: skip anything that is not a JSON object.
///
/// `jsonDecode` hands back `List<dynamic>`, and a single malformed element must
/// not take the whole page down — a browse that degrades to `[]` is the
/// convention, but a browse that drops one row and renders the other 49 is
/// better still.
List<T> jellyfinMapObjects<T>(
  Object? raw,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw is! List) return const [];
  final mapped = <T>[];
  for (final element in raw) {
    if (element is Map) {
      mapped.add(fromJson(element.cast<String, dynamic>()));
    }
  }
  return mapped;
}

/// Top-level entry points for `Isolate.run` — a closure would capture the
/// enclosing service and fail to send.
List<JellyfinUserDto> jellyfinUsersFromJson(Object? raw) =>
    jellyfinMapObjects(raw, JellyfinUserDto.fromJson);

List<JellyfinVirtualFolder> jellyfinVirtualFoldersFromJson(Object? raw) =>
    jellyfinMapObjects(raw, JellyfinVirtualFolder.fromJson);
