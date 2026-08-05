import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/truenas/data/truenas_ws_client.dart';
import 'package:seekarr/features/unraid/data/unraid_client.dart';

/// Where a service's connection is checked, and how the result is described.
///
/// Onboarding grew a verifier that classifies *why* a connection failed while
/// settings kept a separate reachability-only check, so the same instance could
/// say "rejected the API key" during setup and a shrugging "could not reach it"
/// afterwards. Both now run through this file, and the health-endpoint table
/// exists once instead of twice.

/// The endpoint used to prove a service is answering.
///
/// Empty for the services that verify over something other than REST — TrueNAS
/// (WebSocket JSON-RPC), Dockge (Socket.IO), SABnzbd (query-string API), NZBGet
/// (JSON-RPC) and Unraid (GraphQL), each handled by its own branch below.
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
    case ServiceKey.prowlarr:
      return '/api/v1/system/status';
    case ServiceKey.readarr:
      return '/api/v1/system/status';
    case ServiceKey.jellyfin:
      return '/System/Info/Public';
    case ServiceKey.plex:
      return '/identity';
    case ServiceKey.truenas:
    case ServiceKey.dockge:
    case ServiceKey.sabnzbd:
    case ServiceKey.nzbget:
    case ServiceKey.unraid:
      return '';
  }
}

/// The outcome of a connection attempt: the status, why it failed, and the
/// certificate that explains the failure when one does.
///
/// Reachability alone leaves every failure looking identical, so the reason is
/// what lets the UI say "credentials rejected" instead of "check everything".
class ServiceDiagnosis {
  const ServiceDiagnosis(this.status, [this.reason, this.untrustedCertificate]);

  const ServiceDiagnosis.connected() : this(ServiceConnectionStatus.connected);

  const ServiceDiagnosis.notConfigured()
    : this(ServiceConnectionStatus.notConfigured);

  const ServiceDiagnosis.checking() : this(ServiceConnectionStatus.checking);

  /// The service answered, but could not be reached again to confirm.
  const ServiceDiagnosis.dropped()
    : this(
        ServiceConnectionStatus.disconnected,
        ServiceFailureReason.unreachable,
      );

  ServiceDiagnosis.failed(
    Object error, {
    ServiceFailureReason fallback = ServiceFailureReason.unknown,
  }) : this(
         ServiceConnectionStatus.disconnected,
         classifyConnectionFailure(error, fallback: fallback),
       );

  final ServiceConnectionStatus status;

  /// Null unless [status] is `disconnected`.
  final ServiceFailureReason? reason;

  /// Non-null only when the connection failed specifically because the server
  /// presents a certificate not trusted by the platform and not yet pinned.
  final ServerCertificate? untrustedCertificate;

  bool get isConnected => status == ServiceConnectionStatus.connected;

  bool get isDisconnected => status == ServiceConnectionStatus.disconnected;

  bool get isConfigured => status != ServiceConnectionStatus.notConfigured;

  ServiceDiagnosis withCertificate(ServerCertificate? certificate) =>
      ServiceDiagnosis(status, reason, certificate);
}

/// Verifies [service] against the credentials passed in, rather than the saved
/// ones, so a form can test what is typed before committing it.
Future<ServiceDiagnosis> diagnoseCredentials(
  ServiceKey service, {
  required String url,
  String apiKey = '',
  String username = '',
  String password = '',
  String certFingerprint = '',
}) async {
  final pin = certFingerprint.trim().isEmpty ? null : certFingerprint.trim();
  final urlTrimmed = url.trim();

  if (service == ServiceKey.dockge) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = DockgeClient(
      baseUrl: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
      certFingerprint: pin,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 8));
      // A rejected login throws with `unauthorized`, so `false` here means the
      // socket dropped after authenticating — a connection fault, not a wrong
      // password. Reporting it as "credentials rejected" sent users to re-type a
      // password that was fine.
      return ok
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis.dropped();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  if (service == ServiceKey.nzbget) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NzbgetClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
    );
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  if (!service.usesApiKey) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
    );
    try {
      // Two round trips (login + version), so allow more than a single hop.
      await client.getVersion().timeout(const Duration(seconds: 8));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  if (urlTrimmed.isEmpty || apiKey.trim().isEmpty) {
    return const ServiceDiagnosis.notConfigured();
  }

  if (service == ServiceKey.sabnzbd) {
    final client = SabnzbdClient(url: urlTrimmed, apiKey: apiKey.trim());
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(url: urlTrimmed, apiKey: apiKey.trim());
    try {
      await client.testConnection().timeout(const Duration(seconds: 6));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.truenas) {
    final client = TrueNasWsClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
    );
    try {
      await client.call('core.ping').timeout(const Duration(seconds: 6));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      await client.close();
    }
  }

  final client = ApiClient(baseUrl: urlTrimmed, apiKey: apiKey.trim());
  try {
    final code =
        (await client
                .get(_healthEndpoint(service))
                .timeout(const Duration(seconds: 5)))
            .statusCode ??
        0;
    if (code >= 200 && code < 300) return const ServiceDiagnosis.connected();
    return ServiceDiagnosis(
      ServiceConnectionStatus.disconnected,
      reasonForStatusCode(code),
    );
  } catch (e) {
    return ServiceDiagnosis.failed(e);
  } finally {
    client.close();
  }
}

/// Verifies [service] using the credentials already saved in [settings].
Future<ServiceDiagnosis> diagnoseService(
  ServiceKey service,
  SettingsModel settings,
) {
  if (!settings.isServiceConfigured(service)) {
    return Future.value(const ServiceDiagnosis.notConfigured());
  }
  return diagnoseCredentials(
    service,
    url: settings.urlFor(service),
    apiKey: settings.apiKeyFor(service),
    username: settings.usernameFor(service),
    password: settings.passwordFor(service),
    certFingerprint: settings.certFingerprintFor(service),
  );
}

/// Whether a certificate probe could still explain this failure.
///
/// An untrusted certificate surfaces as `tls`, and as `unreachable`/`unknown`
/// when the handshake fails before a reason can be attributed. Anything the
/// server answered — a rejected key, a 404, a 500 — rules the certificate out.
bool certProbeWorthwhile(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.serverError => false,
  _ => true,
};

/// Verifies [service] against [settings] and, when a pinning-capable service
/// fails in a way a certificate could explain, attaches the certificate so the
/// UI can offer to trust it. Never trusts anything itself.
Future<ServiceDiagnosis> diagnoseServiceWithCertProbe(
  ServiceKey service,
  SettingsModel settings,
) async {
  final diagnosis = await diagnoseService(service, settings);
  if (!diagnosis.isDisconnected ||
      !supportsCertPinning(service) ||
      !certProbeWorthwhile(diagnosis.reason)) {
    return diagnosis;
  }
  final certificate = await probeUntrustedCertificate(
    settings.urlFor(service),
    pinnedFingerprint: settings.certFingerprintFor(service),
  );
  return diagnosis.withCertificate(certificate);
}

/// A few words naming the cause, short enough to sit in a list row beside the
/// service name. [connectionFailureMessage] is the long form.
String connectionFailureHeadline(
  ServiceKey service,
  ServiceFailureReason? reason,
) {
  switch (reason) {
    case ServiceFailureReason.unreachable:
      return 'Unreachable';
    case ServiceFailureReason.timeout:
      return 'Timed out';
    case ServiceFailureReason.tls:
      return 'Certificate not trusted';
    case ServiceFailureReason.unauthorized:
      return service.usesApiKey ? 'API key rejected' : 'Sign-in rejected';
    case ServiceFailureReason.notFound:
      return 'API not at this address';
    case ServiceFailureReason.serverError:
      return 'Answered with an error';
    case ServiceFailureReason.unknown:
    case null:
      return 'Not reachable';
  }
}

/// User-facing copy for a failed verification. Each cause names the thing the
/// user can actually change.
String connectionFailureMessage(
  ServiceKey service,
  ServiceFailureReason? reason,
) {
  switch (reason) {
    case ServiceFailureReason.unreachable:
      return 'Could not reach the server. Check the address and port, and '
          'that ${service.title} is running and reachable from this device.';
    case ServiceFailureReason.timeout:
      return 'The server did not answer in time. Check the address, or try '
          'again if the instance is just slow to wake up.';
    case ServiceFailureReason.tls:
      // Never suggest downgrading to http:// here. A certificate that fails to
      // verify is the same signal an interception attack produces, and the
      // pinning-capable services already offer the right answer: verify again
      // and confirm the certificate when Seekarr offers to trust it.
      return supportsCertPinning(service)
          ? 'The HTTPS certificate could not be verified. If ${service.title} '
                'uses a self-signed certificate, test again and confirm the '
                'certificate when Seekarr offers to trust it.'
          : 'The HTTPS certificate could not be verified. Check the address, '
                'and that the certificate is valid for this hostname and not '
                'expired.';
    case ServiceFailureReason.unauthorized:
      return service.usesApiKey
          ? 'Reached ${service.title}, which rejected the API key.'
          : 'Reached ${service.title}, which rejected the username or '
                'password.';
    case ServiceFailureReason.notFound:
      return 'Reached the server, but the ${service.title} API is not at this '
          'address. Check for a missing or wrong base path.';
    case ServiceFailureReason.serverError:
      return '${service.title} answered with a server error. Check the '
          'instance and its logs.';
    case ServiceFailureReason.unknown:
    case null:
      return 'Could not verify the instance. Double-check the address and '
          'credentials.';
  }
}

/// The connection state of a single service, refreshed whenever its saved
/// address or credentials change.
final serviceDiagnosisProvider =
    FutureProvider.family<ServiceDiagnosis, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      return diagnoseService(service, settings);
    });
