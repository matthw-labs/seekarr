import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/api/api_client.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/features/dockge/data/dockge_client.dart';
import 'package:seekarr/features/jellyfin/data/jellyfin_client.dart';
import 'package:seekarr/features/npm/data/npm_client.dart';
import 'package:seekarr/features/nzbget/data/nzbget_client.dart';
import 'package:seekarr/features/plex/data/plex_client.dart';
import 'package:seekarr/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:seekarr/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/transmission/data/transmission_client.dart';
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
///
/// Jellyfin's and Plex's entries are **reachability probes, not credential
/// checks**: both are anonymous endpoints, and neither server reads the
/// `X-Api-Key` header the shared [ApiClient] sends, so a 2xx here says nothing
/// at all about the pasted credential. That is why those two verify through
/// their own clients first and only fall back to this table to explain a
/// refusal — see [diagnoseCredentials].
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
    // Transmission (RPC envelope + session-id handshake) and Nginx Proxy
    // Manager (token exchange) join this group for the same reason: no plain
    // GET can separate "reachable" from "authenticated" for either.
    case ServiceKey.transmission:
    case ServiceKey.nginxProxyManager:
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
  const ServiceDiagnosis(
    this.status, [
    this.reason,
    this.certificateProbe,
    this.detail,
  ]);

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
         null,
         connectionFailureDetail(error),
       );

  final ServiceConnectionStatus status;

  /// Null unless [status] is `disconnected`.
  final ServiceFailureReason? reason;

  /// Non-null only when the connection failed specifically because the server
  /// presents a certificate not trusted by the platform and not yet pinned —
  /// [UntrustedCertificateProbe.rotated] is what tells the UI whether this is
  /// a first-time trust or this origin's pin no longer matches (ADR-6).
  final UntrustedCertificateProbe? certificateProbe;

  /// The verbatim sentence the failure carried, when it carried one.
  ///
  /// Almost always null: a [ServiceFailureReason] plus the service's name is
  /// enough to write a better sentence than a client library would. The
  /// exception is a component that knows something the closed vocabulary cannot
  /// hold — `SameOriginRedirectInterceptor` refusing a cross-origin redirect
  /// knows *which* origin it was sent to, and `redirected` alone can only say
  /// "a redirect Seekarr will not follow". Rendered in place of
  /// [connectionFailureMessage] when present, never alongside it.
  final String? detail;

  /// What the UI should actually say about this outcome.
  ///
  /// One accessor rather than `detail ?? connectionFailureMessage(...)` repeated
  /// at each surface — the settings screen and the onboarding walk both report
  /// the same test, and them disagreeing is exactly the drift this codebase
  /// keeps paying for elsewhere.
  String messageFor(ServiceKey service) =>
      detail ?? connectionFailureMessage(service, reason);

  bool get isConnected => status == ServiceConnectionStatus.connected;

  bool get isDisconnected => status == ServiceConnectionStatus.disconnected;

  bool get isConfigured => status != ServiceConnectionStatus.notConfigured;

  ServiceDiagnosis withCertificateProbe(UntrustedCertificateProbe? probe) =>
      ServiceDiagnosis(status, reason, probe, detail);
}

/// Verifies [service] against the credentials passed in, rather than the saved
/// ones, so a form can test what is typed before committing it.
///
/// [clientIdentifier] is Plex's persisted `X-Plex-Client-Identifier` and is
/// ignored by every other service. It is read from settings rather than minted
/// here because Plex registers a new device row against the user's server for
/// each distinct value it sees.
Future<ServiceDiagnosis> diagnoseCredentials(
  ServiceKey service, {
  required String url,
  String apiKey = '',
  String username = '',
  String password = '',
  String certFingerprint = '',
  String clientIdentifier = '',
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
      certFingerprint: pin,
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

  if (service == ServiceKey.nginxProxyManager) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = NpmClient(
      url: urlTrimmed,
      identity: username.trim().isEmpty ? null : username.trim(),
      secret: password.isEmpty ? null : password,
      certFingerprint: pin,
    );
    try {
      // Checks both halves: `GET /api/` proves an NPM is there, and the login
      // proves the credential. Only the first would go green for a wrong
      // password, since the admin port answers 200 with its SPA for almost any
      // request.
      await client.testConnection().timeout(const Duration(seconds: 10));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  if (service == ServiceKey.transmission) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = TransmissionClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
      certFingerprint: pin,
    );
    try {
      // `session-get` in one round trip forces the CSRF handshake, validates
      // the Basic credentials, and proves the rpc/host whitelists admit this
      // device — the three ways a reachable Transmission still refuses to talk.
      await client.testConnection().timeout(const Duration(seconds: 8));
      return const ServiceDiagnosis.connected();
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  // Named, not inferred. This used to read `if (!service.usesApiKey)`, which is
  // a *negative capability* rather than an identity — so every future
  // credential-authenticated service was silently routed here, and Transmission
  // would have had its password POSTed as form data to
  // `/api/v2/auth/login` on the Transmission host. It 404s, so the failure
  // would have looked like a broken client rather than a broken dispatcher.
  // `_diagnoseOverApiClient` now fails closed for anything that reaches it
  // unrouted, which is the other half of that guard.
  if (service == ServiceKey.qbittorrent) {
    if (urlTrimmed.isEmpty) return const ServiceDiagnosis.notConfigured();
    final client = QbittorrentClient(
      url: urlTrimmed,
      username: username.trim().isEmpty ? null : username.trim(),
      password: password.isEmpty ? null : password,
      certFingerprint: pin,
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
    final client = SabnzbdClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
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

  if (service == ServiceKey.unraid) {
    final client = UnraidClient(
      url: urlTrimmed,
      apiKey: apiKey.trim(),
      certFingerprint: pin,
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

  // The two media servers authenticate with a header the shared `ApiClient`
  // does not send — `Authorization: MediaBrowser Token=` for Jellyfin,
  // `X-Plex-Token` for Plex — and both health endpoints in the table above are
  // anonymous. Verified through the generic branch, *any* non-empty string
  // therefore came back 2xx and the tile went green while every real call 401ed.
  // Their own clients are what actually present the credential.
  if (service == ServiceKey.jellyfin) {
    final client = JellyfinClient(
      baseUrl: urlTrimmed,
      apiKey: apiKey.trim(),
      pinnedCertFingerprint: pin,
    );
    bool accepted;
    try {
      // `/System/Info` — the authenticated twin of the public probe. Swallows
      // its own errors and answers false for all of them, which is why the
      // refusal still has to be explained below rather than reported as-is.
      accepted = await client.verifyCredential().timeout(
        const Duration(seconds: 6),
      );
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
    if (accepted) return const ServiceDiagnosis.connected();
    return _explainCredentialRefusal(service, url: urlTrimmed, pin: pin);
  }

  if (service == ServiceKey.plex) {
    final client = PlexClient(
      url: urlTrimmed,
      token: apiKey.trim(),
      clientIdentifier: clientIdentifier.trim(),
      pinnedCertFingerprint: pin,
    );
    try {
      // Unlike Jellyfin's, this one already separates the two questions: it
      // answers false only for an actual refusal and rethrows a `PlexException`
      // carrying its own `ServiceFailureReason` for anything else — including
      // the JWT it refuses to send at all, which is an unauthorized the user has
      // to fix by pasting a different *kind* of token. So no second probe.
      final accepted = await client.verifyCredential().timeout(
        const Duration(seconds: 6),
      );
      return accepted
          ? const ServiceDiagnosis.connected()
          : const ServiceDiagnosis(
              ServiceConnectionStatus.disconnected,
              ServiceFailureReason.unauthorized,
            );
    } catch (e) {
      return ServiceDiagnosis.failed(e);
    } finally {
      client.close();
    }
  }

  return _diagnoseOverApiClient(
    service,
    url: urlTrimmed,
    apiKey: apiKey,
    pin: pin,
  );
}

/// Reachability and status classification over the shared [ApiClient], which
/// has been pin-aware since ADR-6 — this is the branch the pinning scope used
/// to carve out. [pin] threads straight through; when it is null this is
/// byte-identical to the pre-ADR-6 unpinned client.
Future<ServiceDiagnosis> _diagnoseOverApiClient(
  ServiceKey service, {
  required String url,
  required String apiKey,
  required String? pin,
}) async {
  // Fails closed on a routing bug. An empty entry in [_healthEndpoint] means
  // "this service is verified through its own client", and every one of those
  // has a branch above. If a new service reaches here without one, the request
  // below would be `GET ''` — a plain fetch of the base URL — which most of
  // these servers answer 200 for with their own web UI, *whatever* credential
  // was supplied. That is a green "Connected" tile for a wrong password: the
  // exact bug that shipped once for Jellyfin and Plex. Reporting the service as
  // unreachable is wrong too, but it is wrong in the direction that gets
  // noticed and cannot mislead anyone into thinking a bad credential works.
  final endpoint = _healthEndpoint(service);
  if (endpoint.isEmpty) {
    return const ServiceDiagnosis(
      ServiceConnectionStatus.disconnected,
      ServiceFailureReason.unknown,
    );
  }

  final client = ApiClient(
    baseUrl: url,
    apiKey: apiKey.trim(),
    pinnedCertFingerprint: pin,
  );
  try {
    final code =
        (await client.get(endpoint).timeout(const Duration(seconds: 5)))
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

/// Turns "the credential was not accepted" into a verdict, for a service whose
/// own client cannot say *why* it said no.
///
/// Asks the credential-free endpoint whether the box is even there. If it
/// answers, the address is right and the credential is the thing that was
/// refused; if it does not, the original failure was never about the key and
/// the reachability verdict — unreachable, TLS, wrong base path — is the honest
/// one to report. Costs a second round trip only on the failure path.
Future<ServiceDiagnosis> _explainCredentialRefusal(
  ServiceKey service, {
  required String url,
  required String? pin,
}) async {
  final reachability = await _diagnoseOverApiClient(
    service,
    url: url,
    apiKey: '',
    pin: pin,
  );
  if (!reachability.isConnected) return reachability;
  return const ServiceDiagnosis(
    ServiceConnectionStatus.disconnected,
    ServiceFailureReason.unauthorized,
  );
}

/// Verifies [service] using the credentials already saved in [settings].
Future<ServiceDiagnosis> diagnoseService(
  ServiceKey service,
  SettingsModel settings,
) {
  if (!settings.isServiceConfigured(service)) {
    return Future.value(const ServiceDiagnosis.notConfigured());
  }
  final url = settings.urlFor(service);
  return diagnoseCredentials(
    service,
    url: url,
    apiKey: settings.apiKeyFor(service),
    username: settings.usernameFor(service),
    password: settings.passwordFor(service),
    certFingerprint: settings.pinForUrl(url) ?? '',
    clientIdentifier: settings.plexClientId,
  );
}

/// Whether a certificate probe could still explain this failure.
///
/// An untrusted certificate surfaces as `tls`, and as `unreachable`/`unknown`
/// when the handshake fails before a reason can be attributed. Anything the
/// server answered — a rejected key, a 404, a 500, a redirect nobody could
/// follow — rules the certificate out: the response proves the handshake
/// already completed, so probing for an untrusted certificate costs a round
/// trip to learn nothing.
bool certProbeWorthwhile(ServiceFailureReason? reason) => switch (reason) {
  ServiceFailureReason.unauthorized ||
  ServiceFailureReason.notFound ||
  ServiceFailureReason.redirected ||
  ServiceFailureReason.serverError => false,
  _ => true,
};

/// Verifies [service] against [settings] and, when it fails in a way a
/// certificate could explain, attaches the probe so the UI can offer to trust
/// it. Every service can reach this since ADR-6 — there is no
/// pinning-capability gate left to check. Never trusts anything itself.
Future<ServiceDiagnosis> diagnoseServiceWithCertProbe(
  ServiceKey service,
  SettingsModel settings, {
  CertificateProber probe = probeUntrustedCertificate,
}) async {
  final diagnosis = await diagnoseService(service, settings);
  if (!diagnosis.isDisconnected || !certProbeWorthwhile(diagnosis.reason)) {
    return diagnosis;
  }
  final url = settings.urlFor(service);
  final certProbe = await probe(
    url,
    pinnedFingerprint: settings.pinForUrl(url) ?? '',
  );
  return diagnosis.withCertificateProbe(certProbe);
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
      // Never suggest downgrading to http:// here. A certificate that fails
      // to verify is the same signal an interception attack produces, and
      // every service can now offer the right answer (ADR-6): verify again
      // and confirm the certificate when Seekarr offers to trust it.
      return 'The HTTPS certificate could not be verified. If '
          '${service.title} uses a self-signed certificate, test again and '
          'confirm the certificate when Seekarr offers to trust it.';
    case ServiceFailureReason.unauthorized:
      return service.usesApiKey
          ? 'Reached ${service.title}, which rejected the API key.'
          : 'Reached ${service.title}, which rejected the username or '
                'password.';
    case ServiceFailureReason.notFound:
      return 'Reached the server, but the ${service.title} API is not at this '
          'address. Check for a missing or wrong base path.';
    case ServiceFailureReason.redirected:
      // The generic form. A refusal from `SameOriginRedirectInterceptor`
      // carries its own sentence naming the origin it was sent to, and
      // `messageFor` shows that instead; this is what is left when only the
      // reason survived — an unfollowable 3xx from a client that does not
      // explain itself.
      return 'Reached the server, but it answered with a redirect Seekarr '
          'will not follow. A reverse proxy in front of ${service.title} is '
          'the usual cause — point Seekarr at the address the proxy sends '
          'the request to, or stop it redirecting the API.';
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
