import 'package:flutter/material.dart';

/// Sort options for releases in Interactive Search.
enum ReleaseSortType {
  score('CF Score', Icons.star_rounded),
  size('Size', Icons.storage_rounded),
  seeders('Seeders', Icons.arrow_upward_rounded),
  age('Age', Icons.schedule_rounded);

  final String label;
  final IconData icon;
  const ReleaseSortType(this.label, this.icon);
}

/// Download protocol of a release, used both as a facet and as a filter value.
enum ReleaseProtocol {
  usenet('Usenet', Icons.cloud_download_rounded),
  torrent('Torrent', Icons.swap_vert_rounded);

  final String label;
  final IconData icon;
  const ReleaseProtocol(this.label, this.icon);
}

/// Resolves the [ReleaseProtocol] of a release map, or null when unknown.
ReleaseProtocol? releaseProtocolOf(dynamic release) {
  final raw = (release['protocol'] as String?)?.toLowerCase();
  return switch (raw) {
    'usenet' => ReleaseProtocol.usenet,
    'torrent' => ReleaseProtocol.torrent,
    _ => null,
  };
}

/// Returns the protocols present in [releases], in enum order.
List<ReleaseProtocol> extractAvailableProtocols(List<dynamic> releases) {
  final found = releases.map(releaseProtocolOf).nonNulls.toSet();
  return ReleaseProtocol.values.where(found.contains).toList();
}

/// Whether a release was rejected by the *Arr quality/decision engine.
bool releaseIsRejected(dynamic release) {
  final rejections = release['rejections'] as List<dynamic>? ?? const [];
  return rejections.isNotEmpty;
}

/// Normalises the `rejections` payload (strings or `{reason: ...}` maps) into
/// a plain list of human-readable reasons.
List<String> releaseRejectionReasons(dynamic release) {
  final rejections = release['rejections'] as List<dynamic>? ?? const [];
  return rejections.map<String>((rejection) {
    if (rejection is String) return rejection;
    if (rejection is Map) {
      return rejection['reason'] as String? ?? rejection.toString();
    }
    return rejection.toString();
  }).toList();
}

/// Whether the *Arr decision engine approved this release.
///
/// The single definition of "approved" in the app. It used to be spelled three
/// different ways — the filter chip dropped only releases with rejections, the
/// summary counted the same, but the row's badge required `approved == true`.
/// A release with `approved: false` and no rejections therefore passed the
/// "Approved only" filter, was counted as approved, and still rendered an amber
/// "Not approved" badge.
///
/// A release is approved when it carries no rejections *and* the engine did not
/// mark it unapproved. When the payload omits `approved` entirely — not the case
/// for Radarr/Sonarr v3, but cheap to tolerate — the absence of rejections is
/// taken as approval so the filter cannot silently empty the list.
bool releaseIsApproved(dynamic release) {
  if (releaseIsRejected(release)) return false;
  final approved = release['approved'];
  if (approved is bool) return approved;
  return true;
}

/// Number of releases in [releases] the decision engine approved.
int countApprovedReleases(List<dynamic> releases) {
  return releases.where(releaseIsApproved).length;
}

/// Pure function that filters and sorts releases.
///
/// This function is extracted from InteractiveSearchSheet to enable
/// unit testing without widget context.
///
/// Parameters:
/// - [releases]: List of release maps from *Arr APIs
/// - [sortType]: The field to sort by
/// - [sortAscending]: Whether to reverse the default sort order
/// - [hideRejected]: Whether to keep only releases [releaseIsApproved] accepts
/// - [selectedIndexer]: Optional indexer name to filter by
/// - [selectedProtocol]: Optional download protocol to filter by
/// - [query]: Optional case-insensitive substring match on the release title
///
/// Returns a new filtered and sorted list (does not modify the original).
List<dynamic> filterAndSortReleases(
  List<dynamic> releases, {
  required ReleaseSortType sortType,
  required bool sortAscending,
  required bool hideRejected,
  String? selectedIndexer,
  ReleaseProtocol? selectedProtocol,
  String query = '',
}) {
  var result = List<dynamic>.from(releases);

  // Apply filters. Uses the same predicate as the count and the row badge, so
  // "Approved only" cannot show a row labelled "Not approved".
  if (hideRejected) {
    result = result.where(releaseIsApproved).toList();
  }

  if (selectedIndexer != null) {
    result = result.where((r) {
      return r['indexer'] == selectedIndexer;
    }).toList();
  }

  if (selectedProtocol != null) {
    result = result
        .where((r) => releaseProtocolOf(r) == selectedProtocol)
        .toList();
  }

  final trimmedQuery = query.trim().toLowerCase();
  if (trimmedQuery.isNotEmpty) {
    // Every whitespace-separated term must appear, so "1080 remux" narrows
    // the list the way users expect from a scene-name search.
    final terms = trimmedQuery.split(RegExp(r'\s+'));
    result = result.where((r) {
      final title = (r['title'] as String? ?? '').toLowerCase();
      return terms.every(title.contains);
    }).toList();
  }

  // Apply sorting
  result.sort((a, b) {
    int comparison;
    switch (sortType) {
      case ReleaseSortType.score:
        final aScore = (a['customFormatScore'] as num?)?.toInt() ?? 0;
        final bScore = (b['customFormatScore'] as num?)?.toInt() ?? 0;
        comparison = bScore.compareTo(aScore); // Default desc for score
      case ReleaseSortType.size:
        final aSize = (a['size'] as num?)?.toInt() ?? 0;
        final bSize = (b['size'] as num?)?.toInt() ?? 0;
        comparison = bSize.compareTo(aSize); // Default desc for size
      case ReleaseSortType.seeders:
        final aSeeders = (a['seeders'] as num?)?.toInt() ?? 0;
        final bSeeders = (b['seeders'] as num?)?.toInt() ?? 0;
        comparison = bSeeders.compareTo(aSeeders); // Default desc
      case ReleaseSortType.age:
        final aAge = (a['ageMinutes'] as num?)?.toInt() ?? 0;
        final bAge = (b['ageMinutes'] as num?)?.toInt() ?? 0;
        comparison = aAge.compareTo(bAge); // Default asc (newest first)
    }
    return sortAscending ? -comparison : comparison;
  });

  return result;
}

/// Extracts unique indexer names from a list of releases.
///
/// Returns a Set of indexer names. Null or missing indexers are
/// replaced with 'Unknown'.
Set<String> extractAvailableIndexers(List<dynamic> releases) {
  return releases.map((r) => r['indexer'] as String? ?? 'Unknown').toSet();
}

/// Formats a byte size into a human-readable string.
///
/// Examples:
/// - 512 -> "512 B"
/// - 1024 -> "1.0 KB"
/// - 1073741824 -> "1.00 GB"
String formatReleaseSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Formats age in minutes into a human-readable string.
///
/// Examples:
/// - 30 -> "30m"
/// - 120 -> "2h"
/// - 2880 -> "2d"
String formatReleaseAge(int minutes) {
  if (minutes < 60) return '${minutes}m';
  if (minutes < 1440) return '${(minutes / 60).round()}h';
  return '${(minutes / 1440).round()}d';
}
