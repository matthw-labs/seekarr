/// Typed models for the Readarr API (v1).
///
/// Readarr shares the *arr contract with Radarr/Sonarr/Lidarr. The project is
/// archived upstream, but the v1 API remains functional; these models cover the
/// read-only dashboard (authors + recent history).
library;

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

/// An author (the primary library entity in Readarr, analogous to a Lidarr
/// artist). Books live under authors.
class ReadarrAuthor {
  const ReadarrAuthor({
    required this.id,
    required this.authorName,
    required this.monitored,
    required this.bookCount,
    required this.bookFileCount,
    this.overview,
    this.status,
  });

  final int id;
  final String authorName;
  final bool monitored;

  /// Total number of books tracked for this author.
  final int bookCount;

  /// Number of books that have a downloaded file on disk.
  final int bookFileCount;

  final String? overview;
  final String? status;

  /// Monitored books still missing a file.
  int get missingBookCount => (bookCount - bookFileCount).clamp(0, bookCount);

  factory ReadarrAuthor.fromJson(Map<String, dynamic> json) {
    final stats = json['statistics'];
    final statsMap = stats is Map<String, dynamic>
        ? stats
        : const <String, dynamic>{};
    return ReadarrAuthor(
      id: _asInt(json['id']),
      authorName:
          (json['authorName'] ??
                  json['authorNameLastFirst'] ??
                  'Unknown author')
              .toString(),
      monitored: json['monitored'] == true,
      bookCount: _asInt(statsMap['bookCount'] ?? statsMap['totalBookCount']),
      bookFileCount: _asInt(statsMap['bookFileCount']),
      overview: json['overview']?.toString(),
      status: json['status']?.toString(),
    );
  }
}

/// A single Readarr history record, used for the "Recent Activity" section.
///
/// The `data` payload varies per `eventType`; only the stable fields are typed.
class ReadarrHistoryItem {
  const ReadarrHistoryItem({
    required this.id,
    required this.eventType,
    this.sourceTitle,
    this.date,
    this.authorName,
  });

  final int id;
  final String eventType;
  final String? sourceTitle;
  final DateTime? date;
  final String? authorName;

  factory ReadarrHistoryItem.fromJson(Map<String, dynamic> json) {
    final author = json['author'];
    return ReadarrHistoryItem(
      id: _asInt(json['id']),
      eventType: (json['eventType'] ?? 'unknown').toString(),
      sourceTitle: json['sourceTitle']?.toString(),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      authorName: author is Map
          ? author['authorName']?.toString()
          : json['authorTitle']?.toString(),
    );
  }
}
