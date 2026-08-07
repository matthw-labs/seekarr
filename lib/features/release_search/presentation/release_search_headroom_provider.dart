import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/domain/release_search_headroom.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Everything Seekarr has measured about how each instance is reached.
///
/// Persisted in `SharedPreferences` rather than secure storage: these are timings
/// and a server name, not credentials, and the card that shows them says out loud
/// that they never leave the device.
final searchHeadroomProvider =
    NotifierProvider<SearchHeadroomNotifier, Map<ServiceKey, SearchHeadroom>>(
      SearchHeadroomNotifier.new,
    );

/// The headroom for one service, or an empty record.
final serviceHeadroomProvider = Provider.family<SearchHeadroom, ServiceKey>((
  ref,
  service,
) {
  return ref.watch(searchHeadroomProvider)[service] ?? const SearchHeadroom();
});

class SearchHeadroomNotifier extends Notifier<Map<ServiceKey, SearchHeadroom>> {
  static const _key = 'release_search_headroom';

  @override
  Map<ServiceKey, SearchHeadroom> build() {
    try {
      final raw = ref.watch(sharedPreferencesProvider).getString(_key);
      if (raw == null) return const {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final result = <ServiceKey, SearchHeadroom>{};
      for (final entry in decoded.entries) {
        for (final service in ServiceKey.values) {
          if (service.name != entry.key) continue;
          result[service] = SearchHeadroom.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Records a search that came back with an answer.
  void recordSuccess(ServiceKey service, Duration elapsed) {
    _update(service, (current) => current.recordSuccess(elapsed));
  }

  /// Records a search that was cut off by something in the middle.
  ///
  /// Only gateway cut-offs and our own ceiling belong here. A lost connection or
  /// a server error says nothing about how long the path allows, and folding it
  /// in would report a ceiling that does not exist.
  void recordCutoff(ServiceKey service, Duration elapsed) {
    _update(service, (current) => current.recordCutoff(elapsed));
  }

  void recordGateway(ServiceKey service, SearchGateway gateway, String? name) {
    _update(service, (current) => current.withGateway(gateway, name: name));
  }

  void _update(
    ServiceKey service,
    SearchHeadroom Function(SearchHeadroom current) transform,
  ) {
    final next = Map<ServiceKey, SearchHeadroom>.of(state);
    next[service] = transform(next[service] ?? const SearchHeadroom());
    state = next;
    _persist(next);
  }

  void _persist(Map<ServiceKey, SearchHeadroom> value) {
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(
            _key,
            jsonEncode({
              for (final entry in value.entries)
                entry.key.name: entry.value.toJson(),
            }),
          );
    } catch (_) {
      // No prefs in this scope; the in-memory record still serves the session.
    }
  }
}

/// Asks the instance one ordinary question and reads who answered.
///
/// Deliberately **not** a timing probe: nothing here tries to make the server
/// slow, so it cannot be mistaken for load on the user's stack. All it does is
/// look at the response's own headers, which is enough to name the intermediary
/// and therefore enough to name its ceiling.
final headroomProbeProvider =
    Provider<Future<SearchGateway> Function(ServiceKey)>((ref) {
      return (service) async {
        Response<dynamic> response;
        switch (service) {
          case ServiceKey.sonarr:
            response = await ref.read(sonarrServiceProvider).probeHeaders();
          case ServiceKey.radarr:
            response = await ref.read(radarrServiceProvider).probeHeaders();
          case ServiceKey.lidarr:
            response = await ref.read(lidarrServiceProvider).probeHeaders();
          default:
            throw UnsupportedError(
              '${service.name} has no release search to measure',
            );
        }

        final headers = response.headers;
        final gateway = classifyGateway(
          headers.value('server'),
          hasCfRay: headers.value('cf-ray') != null,
        );
        ref
            .read(searchHeadroomProvider.notifier)
            .recordGateway(service, gateway, headers.value('server'));
        return gateway;
      };
    });
