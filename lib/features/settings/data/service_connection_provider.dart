import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

/// Represents the reachability state of a configured service.
enum ServiceConnectionStatus {
  notConfigured,
  checking,
  connected,
  disconnected,
}

/// Returns the health-check endpoint path for [service].
String _healthEndpoint(ServiceKey service) {
  switch (service) {
    case ServiceKey.seerr:
      return '/api/v1/status';
    case ServiceKey.radarr:
    case ServiceKey.sonarr:
      return '/api/v3/system/status';
    case ServiceKey.lidarr:
      return '/api/v1/system/status';
    case ServiceKey.qbittorrent:
      return '/api/v2/app/version';
    case ServiceKey.bazarr:
      return '/api/system/status';
  }
}

/// Pings [service] using the currently configured URL and API key.
///
/// Returns [ServiceConnectionStatus.notConfigured] when URL or API key are
/// missing, [ServiceConnectionStatus.connected] on a 2xx response, otherwise
/// [ServiceConnectionStatus.disconnected]. A 5s timeout is applied to avoid
/// blocking the UI.
Future<ServiceConnectionStatus> _checkService(
  ServiceKey service,
  SettingsModel settings,
) async {
  if (!settings.isServiceConfigured(service)) {
    return ServiceConnectionStatus.notConfigured;
  }

  if (service == ServiceKey.qbittorrent) {
    final client = QbittorrentClient(
      url: settings.qbittorrentUrl,
      username: settings.qbittorrentUsername,
      password: settings.qbittorrentPassword,
    );
    try {
      await client.authenticate().timeout(const Duration(seconds: 5));
      await client.getVersion().timeout(const Duration(seconds: 5));
      return ServiceConnectionStatus.connected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      client.close();
    }
  }

  final url = settings.urlFor(service);
  final apiKey = settings.apiKeyFor(service);

  final client = ApiClient(baseUrl: url, apiKey: apiKey);
  try {
    final statusCode =
        (await client
                .get(_healthEndpoint(service))
                .timeout(const Duration(seconds: 5)))
            .statusCode ??
        0;
    return statusCode >= 200 && statusCode < 300
        ? ServiceConnectionStatus.connected
        : ServiceConnectionStatus.disconnected;
  } catch (_) {
    return ServiceConnectionStatus.disconnected;
  } finally {
    client.close();
  }
}

/// Provides the connection status for a specific [ServiceKey].
///
/// Auto-invalidates whenever the URL or API key for the service changes via
/// [currentSettingsProvider], ensuring the indicator refreshes after the user
/// edits service settings.
final serviceConnectionProvider =
    FutureProvider.family<ServiceConnectionStatus, ServiceKey>((
      ref,
      service,
    ) async {
      final settings = ref.watch(currentSettingsProvider);
      return _checkService(service, settings);
    });
