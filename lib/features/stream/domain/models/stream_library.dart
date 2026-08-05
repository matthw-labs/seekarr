/// One library ("section" in Plex, "virtual folder" in Jellyfin) on a media
/// server.
///
/// The Stream dashboard lists these as destinations rather than rendering their
/// contents inline: a library is a *room on the server*, and entering the
/// collection through a room is what keeps the Stream browse from reading as a
/// second copy of Radarr's global title list.
library;

import 'package:flutter/foundation.dart';

/// What a library holds. Drives the glyph and the item vocabulary.
enum StreamLibraryKind {
  movies(label: 'Movies'),
  shows(label: 'Shows'),
  music(label: 'Music'),
  photos(label: 'Photos'),
  other(label: 'Library');

  const StreamLibraryKind({required this.label});

  final String label;
}

@immutable
class StreamLibrary {
  /// Opaque server id.
  ///
  /// A Jellyfin `VirtualFolderInfo.ItemId` (a GUID) or a Plex section `key` (a
  /// numeric-looking string that the official schema explicitly declines to
  /// guarantee is numeric). Modelled as [String] for that reason — this is the
  /// value that forced `idExtractor` off `int`.
  final String id;

  final String name;
  final StreamLibraryKind kind;

  /// How many items the server reports, when it says.
  final int? itemCount;

  /// When this library was last scanned.
  ///
  /// **Asymmetric between the two servers, deliberately nullable.** Plex gives a
  /// per-section `scannedAt`; Jellyfin exposes only a global "Scan Media Library"
  /// scheduled task and a per-library `RefreshProgress`, with no per-library
  /// timestamp. A UI that assumes this is present would print an empty column on
  /// every Jellyfin install.
  final DateTime? lastScannedAt;

  /// Whether a scan is running for this library right now.
  final bool isRefreshing;

  const StreamLibrary({
    required this.id,
    required this.name,
    required this.kind,
    required this.itemCount,
    required this.lastScannedAt,
    required this.isRefreshing,
  });
}
