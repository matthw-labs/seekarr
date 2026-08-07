import 'package:cupola/features/settings/domain/service_key.dart';

class GlobalSearchResult {
  final ServiceKey service;
  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final Map<String, String>? imageHeaders;
  final List<String> tags;
  final String route;
  final Object? routeExtra;

  /// Shared-element tag for this result's poster, already stamped into [route]
  /// so the flight has a matching destination on the detail page.
  ///
  /// Stored rather than derived from `service` + `id`: within one service a
  /// movie and a series can carry the same id, so the builder that knows which
  /// kind this is also owns making the tag unique.
  final String heroTag;

  const GlobalSearchResult({
    required this.service,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.imageHeaders,
    required this.tags,
    required this.route,
    required this.heroTag,
    this.routeExtra,
  });

  /// Whether this result has artwork worth flying.
  ///
  /// Bazarr's API carries no poster, so its rows would otherwise fly an empty
  /// grey box into the detail page's fallback glyph — motion with nothing to
  /// follow. Same rule the Recently Added rail applies.
  bool get canFlyPoster => imageUrl.isNotEmpty;
}

class GlobalSearchServiceResults {
  final ServiceKey service;
  final List<GlobalSearchResult> results;
  final Object? error;

  const GlobalSearchServiceResults({
    required this.service,
    required this.results,
    this.error,
  });

  bool get hasError => error != null;
}
