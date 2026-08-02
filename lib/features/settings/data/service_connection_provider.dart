import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Represents the reachability state of a configured service.
///
/// *Why* a service is disconnected lives in `ServiceDiagnosis` alongside this,
/// in `service_verification.dart` — this enum answers only "is it up".
enum ServiceConnectionStatus {
  notConfigured,
  checking,
  connected,
  disconnected,
}

/// Only TrueNAS and Dockge use the WebSocket clients that support cert pinning.
///
/// Public so onboarding and settings can tailor their TLS-failure copy without
/// keeping a second copy of this rule.
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
