import 'package:flutter/material.dart';

import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

/// Badge style (label, colour, icon) for a Prowlarr history [item].
///
/// Shared by the dashboard activity feed and the indexer detail history so
/// event styling stays consistent across both screens.
({String label, Color color, IconData icon}) prowlarrEventStyle(
  ProwlarrHistoryItem item,
) {
  if (!item.successful) {
    return (label: 'FAILED', color: AppColors.error, icon: Icons.close_rounded);
  }
  return switch (item.eventType) {
    'releaseGrabbed' => (
      label: 'GRAB',
      color: AppColors.success,
      icon: Icons.download_rounded,
    ),
    'indexerQuery' => (
      label: 'QUERY',
      color: AppColors.prowlarr,
      icon: Icons.search_rounded,
    ),
    'indexerRss' => (
      label: 'RSS',
      color: AppColors.sonarr,
      icon: Icons.rss_feed_rounded,
    ),
    'indexerAuth' => (
      label: 'AUTH',
      color: AppColors.warning,
      icon: Icons.key_rounded,
    ),
    _ => (
      label: (item.eventType ?? 'EVENT').toUpperCase(),
      color: AppColors.prowlarr,
      icon: Icons.bolt_rounded,
    ),
  };
}

/// The `source` field from a history [item]'s heterogeneous data map, or null
/// when it is missing or empty.
String? prowlarrHistorySource(ProwlarrHistoryItem item) {
  final source = item.data['source'];
  return (source is String && source.isNotEmpty) ? source : null;
}

/// A human-readable title for a history [item]: the search query when present,
/// otherwise a source-derived label, otherwise the raw event type.
String prowlarrHistoryTitle(ProwlarrHistoryItem item) {
  final query = item.data['query'];
  if (query is String && query.trim().isNotEmpty) return query;
  final source = prowlarrHistorySource(item);
  if (source != null) return '$source request';
  return item.eventType ?? 'Activity';
}

/// Formats an ISO-8601 timestamp as a coarse relative string (e.g. "5m ago").
///
/// Uses a UTC wall clock (`DateTime.now()`); precision beyond minutes is not
/// needed for the activity feed.
String prowlarrRelativeTime(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return iso;
  final diff = DateTime.now().toUtc().difference(parsed.toUtc());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
