import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';

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
    case ServiceKey.truenas:
      // TrueNAS uses a WebSocket JSON-RPC ping instead of a REST endpoint.
      return '';
    case ServiceKey.dockge:
      // Dockge uses a Socket.IO connect/login instead of a REST endpoint.
      return '';
    case ServiceKey.prowlarr:
      return '/api/v1/system/status';
    case ServiceKey.readarr:
      return '/api/v1/system/status';
    case ServiceKey.sabnzbd:
      // SABnzbd authenticates with a query-string key, handled specially.
      return '';
    case ServiceKey.nzbget:
      // NZBGet uses a JSON-RPC call with Basic auth, handled specially.
      return '';
    case ServiceKey.unraid:
      // Unraid uses a GraphQL query with an x-api-key header, handled specially.
      return '';
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

  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: settings.truenasUrl,
      apiKey: settings.truenasApiKey,
      certFingerprint: settings.truenasCertFingerprint.isEmpty
          ? null
          : settings.truenasCertFingerprint,
    );
    try {
      await client.call('core.ping').timeout(const Duration(seconds: 6));
      return ServiceConnectionStatus.connected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      await client.close();
    }
  }

  if (service == ServiceKey.dockge) {
    final client = DockgeClient(
      baseUrl: settings.dockgeUrl,
      username: settings.dockgeUsername.isEmpty
          ? null
          : settings.dockgeUsername,
      password: settings.dockgePassword.isEmpty
          ? null
          : settings.dockgePassword,
      certFingerprint: settings.dockgeCertFingerprint.isEmpty
          ? null
          : settings.dockgeCertFingerprint,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 8));
      return ok
          ? ServiceConnectionStatus.connected
          : ServiceConnectionStatus.disconnected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      await client.close();
    }
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(
      url: settings.sabnzbdUrl,
      apiKey: settings.sabnzbdApiKey,
    );
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return ServiceConnectionStatus.connected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.nzbget) {
    final client = NzbgetClient(
      url: settings.nzbgetUrl,
      username: settings.nzbgetUsername.isEmpty
          ? null
          : settings.nzbgetUsername,
      password: settings.nzbgetPassword.isEmpty
          ? null
          : settings.nzbgetPassword,
    );
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return ServiceConnectionStatus.connected;
    } catch (_) {
      return ServiceConnectionStatus.disconnected;
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: settings.unraidUrl,
      apiKey: settings.unraidApiKey,
    );
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
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

/// Outcome of a connection check that can also surface an untrusted TLS
/// certificate, so the caller can offer to pin it (trust-on-first-use).
class ConnectionCheckResult {
  final ServiceConnectionStatus status;

  /// Non-null only when the connection failed specifically because the server
  /// presents a certificate not trusted by the platform and not yet pinned.
  final ServerCertificate? untrustedCertificate;

  const ConnectionCheckResult(this.status, {this.untrustedCertificate});
}

/// Only TrueNAS and Dockge use the WebSocket clients that support cert pinning.
///
/// Public so onboarding can tailor its TLS-failure copy without keeping a
/// second copy of this rule.
bool supportsCertPinning(ServiceKey service) =>
    service == ServiceKey.truenas || service == ServiceKey.dockge;

/// Parses [rawUrl] into `(host, port, isSecure)`, applying the same scheme and
/// default-port rules the TrueNAS/Dockge clients use.
({String host, int port, bool secure})? _tlsEndpoint(String rawUrl) {
  var raw = rawUrl.trim();
  if (raw.isEmpty) return null;
  if (!raw.contains('://')) raw = 'https://$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  final secure = UrlUtils.isSecureScheme(raw);
  return (
    host: uri.host,
    port: uri.hasPort ? uri.port : (secure ? 443 : 80),
    secure: secure,
  );
}

/// Probes [rawUrl] for a TLS certificate that is not trusted by the platform
/// and not already pinned as [pinnedFingerprint], returning it so the UI can
/// offer to trust it (trust-on-first-use). Returns null when the URL is not
/// TLS, the certificate already validates, it matches the current pin, or the
/// server is simply unreachable. Never trusts anything itself.
Future<ServerCertificate?> probeUntrustedCertificate(
  String rawUrl, {
  String pinnedFingerprint = '',
}) async {
  final endpoint = _tlsEndpoint(rawUrl);
  if (endpoint == null || !endpoint.secure) return null;
  try {
    final validates = await certificateValidatesByDefault(
      endpoint.host,
      endpoint.port,
    );
    // Certificate is fine; any failure is unrelated (auth, wrong URL, …).
    if (validates) return null;
    final cert = await probeServerCertificate(endpoint.host, endpoint.port);
    if (cert == null) return null;
    if (cert.fingerprint.toLowerCase() ==
        pinnedFingerprint.trim().toLowerCase()) {
      // Already pinned — the failure is something else.
      return null;
    }
    return cert;
  } catch (_) {
    // Server unreachable / DNS / refused — a genuine disconnect, not a cert
    // trust problem.
    return null;
  }
}

/// Checks [service] and, when it is a pinning-capable service reached over TLS
/// whose failure is caused by an untrusted certificate, probes and returns that
/// certificate so the UI can offer to trust it. Never trusts anything itself.
Future<ConnectionCheckResult> checkServiceWithCertProbe(
  ServiceKey service,
  SettingsModel settings,
) async {
  final status = await _checkService(service, settings);
  if (status != ServiceConnectionStatus.disconnected ||
      !supportsCertPinning(service)) {
    return ConnectionCheckResult(status);
  }
  final cert = await probeUntrustedCertificate(
    settings.urlFor(service),
    pinnedFingerprint: settings.certFingerprintFor(service),
  );
  return ConnectionCheckResult(status, untrustedCertificate: cert);
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
