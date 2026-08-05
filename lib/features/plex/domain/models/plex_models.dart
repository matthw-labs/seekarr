/// Plex-specific DTOs that the shared `Stream*` contract has no room for.
///
/// Everything the dashboard renders arrives as [StreamSession] / [StreamItem] /
/// [StreamLibrary]; these types exist for the three things that are genuinely
/// Plex's and not a media server's in general — what `GET /identity` and `GET /`
/// say about the box, what a pasted `X-Plex-Token` turns out to be, and the
/// `MediaContainer` paging envelope that Plex insists must be read back rather
/// than assumed.
library;

import 'package:flutter/foundation.dart';

/// Reads an `int` that may legitimately be absent.
///
/// **Not** `parse_utils.parseInt`, and the difference is load-bearing on Plex:
/// that helper collapses a missing value to `0`, while Plex's own rule is
/// "missing means ABSENT, not zero" — an absent `viewCount` means unwatched, an
/// absent `viewOffset` means there is no resume point at all, and a `0` in
/// either slot would be a different claim. `leafCount` vs `viewedLeafCount`
/// depends on the same distinction to decide whether a show is fully watched or
/// simply unscanned.
int? plexInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? plexDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Reads a bool that Plex may send as `true`, `1` or `"1"`.
///
/// Returns null for an absent key so a caller can tell "the server said no"
/// from "the server did not say" — `myPlexSubscription` absent is not the same
/// claim as `myPlexSubscription: false`, and the difference decides whether the
/// UI blames Plex Pass for a refused terminate.
bool? plexBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
  }
  return null;
}

String? plexString(dynamic value) {
  if (value is String) return value.trim().isEmpty ? null : value;
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Converts a Plex epoch — **seconds**, not milliseconds — to a UTC [DateTime].
///
/// `addedAt`, `updatedAt`, `lastViewedAt`, `viewedAt` and `scannedAt` are all
/// epoch seconds while `duration` and `viewOffset` on the very same object are
/// milliseconds. Feeding a `scannedAt` to `fromMillisecondsSinceEpoch` unscaled
/// puts the last library scan in January 1970.
DateTime? plexEpochSeconds(dynamic value) {
  final seconds = plexInt(value);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// Whether a `Metadata` element came from the user's own server rather than
/// Plex's cloud catalogue.
///
/// `/hubs` and `/hubs/search` mix *provider* results into the same arrays as
/// local ones: rows whose `key`/`thumb` are absolute `https://plex.tv` or
/// metadata-provider URLs and whose `source` is `provider://tv.plex.provider.*`.
/// Rendering one would make the app fetch from plex.tv, which this client is
/// built never to touch — so a cloud row is dropped at the parse boundary
/// instead of being filtered later by whichever widget happens to remember.
///
/// The test is deliberately three-sided rather than trusting `source` alone:
/// `source` is absent on a plain library response, so its absence has to mean
/// "local", which in turn means a cloud row that omits it must still be caught
/// by its absolute `key` or `thumb`.
bool plexIsServerItem(Map<String, dynamic> metadata) {
  final source = plexString(metadata['source']);
  if (source != null && !source.startsWith('server://')) return false;

  // Only ever follow a relative key: an absolute one points off the server.
  final key = plexString(metadata['key']);
  if (key != null && !key.startsWith('/')) return false;

  final thumb = plexString(metadata['thumb']);
  if (thumb != null && !thumb.startsWith('/')) return false;

  return true;
}

/// A relative Plex artwork key, or null when the value is anything else.
///
/// The trailing integer on `thumb`/`art`/`parentThumb`/`grandparentThumb` is a
/// version stamp, so these keys are immutable and cacheable forever. An
/// absolute value means the image lives on plex.tv, and returning null is what
/// keeps [plexIsServerItem]'s guarantee from leaking one row later.
String? plexArtworkKey(dynamic value) {
  final key = plexString(value);
  if (key == null || !key.startsWith('/')) return null;
  return key;
}

/// What went wrong with a pasted `X-Plex-Token`, when the cause is knowable.
enum PlexTokenIssue {
  /// Nothing wrong that this client can see.
  none,

  /// The pasted value is a plex.tv JSON Web Token — they start `eyJ`, expire
  /// after seven days, and can only be refreshed by calling plex.tv. Since this
  /// client never contacts plex.tv, a JWT is a dead end rather than a delay, and
  /// saying so is more useful than letting it work for a week and then fail.
  jsonWebToken,

  /// The server itself refused the token (401, or Plex's non-standard 498).
  rejected,
}

/// Classifies a token before it is ever sent.
///
/// Cheap, offline and deliberately done up front: the alternative is a
/// connection that succeeds today, fails in seven days, and reports the failure
/// as "check your server".
PlexTokenIssue inspectPlexToken(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return PlexTokenIssue.none;
  // A compact JWS always begins with the base64url of `{"alg"` → `eyJ`.
  if (trimmed.startsWith('eyJ')) return PlexTokenIssue.jsonWebToken;
  return PlexTokenIssue.none;
}

/// `GET /identity` — the one Plex endpoint that needs no credential.
@immutable
class PlexServerIdentity {
  final String? machineIdentifier;
  final String? version;

  /// Whether the server has been claimed by a Plex account. An unclaimed server
  /// accepts any token, which is worth knowing before trusting a successful
  /// connection.
  final bool? claimed;

  const PlexServerIdentity({
    required this.machineIdentifier,
    required this.version,
    required this.claimed,
  });

  factory PlexServerIdentity.fromMediaContainer(Map<String, dynamic> json) {
    return PlexServerIdentity(
      machineIdentifier: plexString(json['machineIdentifier']),
      version: plexString(json['version']),
      claimed: plexBool(json['claimed']),
    );
  }
}

/// `GET /` — the authenticated capability sheet.
@immutable
class PlexServerCapabilities {
  final String? friendlyName;
  final String? machineIdentifier;
  final String? version;
  final String? myPlexUsername;

  /// **The Plex Pass gate.** Terminating someone else's stream is a Plex Pass
  /// feature, and a server without it answers the terminate call with a 401 that
  /// has nothing to do with the token. Reading this lets the UI say "this needs
  /// Plex Pass" instead of sending the user off to re-paste a token that was
  /// fine. Null when the server did not say.
  final bool? myPlexSubscription;

  /// Whether the server has Plex Home users beyond the owner. Informational
  /// only: their watch state is still unreadable — see
  /// `PlexClient.getViewers`.
  final bool? multiuser;

  final int? transcoderActiveVideoSessions;

  const PlexServerCapabilities({
    required this.friendlyName,
    required this.machineIdentifier,
    required this.version,
    required this.myPlexUsername,
    required this.myPlexSubscription,
    required this.multiuser,
    required this.transcoderActiveVideoSessions,
  });

  factory PlexServerCapabilities.fromMediaContainer(Map<String, dynamic> json) {
    return PlexServerCapabilities(
      friendlyName: plexString(json['friendlyName']),
      machineIdentifier: plexString(json['machineIdentifier']),
      version: plexString(json['version']),
      myPlexUsername: plexString(json['myPlexUsername']),
      myPlexSubscription: plexBool(json['myPlexSubscription']),
      multiuser: plexBool(json['multiuser']),
      transcoderActiveVideoSessions: plexInt(
        json['transcoderActiveVideoSessions'],
      ),
    );
  }

  /// The name to show for this server, preferring what the owner called it.
  String? get displayName => friendlyName ?? machineIdentifier;

  /// Whether stopping a stream is available at all on this server.
  ///
  /// Treated as available when the server did not say, so a missing attribute
  /// hides the button on nobody's server by mistake — the terminate call still
  /// explains itself if it comes back 401.
  bool get canTerminateSessions => myPlexSubscription ?? true;
}

/// One page of a `MediaContainer`, with the counters the server actually
/// returned.
///
/// Plex's own guidance is that "the response must be checked to see if the
/// response is in fact paginated… it might include a different number of items
/// than requested", so a pager that trusted the [PlexPage.size] it *asked* for
/// would either stop early or loop forever. [size] is therefore the server's
/// figure and never `items.length`: this client drops rows during parsing (cloud
/// results, on-deck lens filtering), and a page that filtered every row still
/// has to advance the offset rather than declaring the library finished.
@immutable
class PlexPage<T> {
  final List<T> items;

  /// `MediaContainer.offset`, echoed back by the server.
  final int offset;

  /// `MediaContainer.size` — how many rows the server put in this page.
  final int size;

  /// `MediaContainer.totalSize`, when the response is paginated at all. Null on
  /// an unpaginated endpoint (`/library/sections`, `onDeck` on older builds).
  final int? totalSize;

  const PlexPage({
    required this.items,
    required this.offset,
    required this.size,
    required this.totalSize,
  });

  const PlexPage.empty()
    : items = const [],
      offset = 0,
      size = 0,
      totalSize = null;

  /// Where the next request should start. Advances by what the server sent, not
  /// by what survived parsing.
  int get nextOffset => offset + size;

  /// Whether another request would return anything.
  ///
  /// With a [totalSize] this is arithmetic. Without one, the only honest signal
  /// is "the server sent rows", so an unpaginated endpoint reports more until it
  /// returns an empty page.
  bool get hasMore {
    final total = totalSize;
    if (total == null) return size > 0;
    return nextOffset < total;
  }

  PlexPage<T> copyWithItems(List<T> next) => PlexPage<T>(
    items: next,
    offset: offset,
    size: size,
    totalSize: totalSize,
  );
}
