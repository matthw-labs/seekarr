import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/io.dart';

/// Details of a TLS certificate presented by a server, surfaced to the user
/// when it is not trusted by the platform (e.g. self-signed home installs).
class ServerCertificate {
  /// Lowercase hex SHA-256 fingerprint of the certificate's DER encoding.
  final String fingerprint;
  final String subject;
  final String issuer;
  final DateTime? validFrom;
  final DateTime? validTo;

  const ServerCertificate({
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    this.validFrom,
    this.validTo,
  });

  /// Fingerprint grouped into colon-separated byte pairs for display
  /// (e.g. `AB:CD:EF:...`), matching how browsers show fingerprints.
  String get displayFingerprint {
    final upper = fingerprint.toUpperCase();
    final pairs = <String>[
      for (var i = 0; i + 2 <= upper.length; i += 2) upper.substring(i, i + 2),
    ];
    return pairs.join(':');
  }
}

/// SHA-256 fingerprint of [cert]'s DER encoding, as lowercase hex.
String certificateFingerprint(X509Certificate cert) {
  return sha256.convert(cert.der).toString();
}

/// Builds an [HttpClient] that performs standard TLS verification, but also
/// trusts a certificate whose SHA-256 fingerprint equals [pinnedFingerprint]
/// (trust-on-first-use for self-signed servers).
///
/// When [pinnedFingerprint] is null or empty, no exception is made: the
/// platform trust store is the sole authority, exactly like a browser with no
/// stored exception. This is deliberately the secure default — blindly
/// accepting every certificate would let any on-path attacker present their
/// own and capture the credentials sent over the connection.
///
/// [pinnedHost] and [pinnedPort], when given, must also match before the
/// fingerprint is even checked. This client was a singleton per pinned
/// connection when only TrueNAS and Dockge could pin (ADR-5); under ADR-6 one
/// process can hold a dozen pinned clients across services that share an
/// origin, so the fingerprint alone is no longer enough to keep a pin scoped
/// to the host it was granted for. `SameOriginRedirectInterceptor` already
/// refuses a cross-origin redirect on `ApiClient`; this is defence in depth
/// behind it, and the only guard for a client built directly on this
/// `HttpClient` (the raw-`Dio` and WebSocket clients), which the interceptor
/// never sees.
HttpClient buildPinnedHttpClient({
  String? pinnedFingerprint,
  String? pinnedHost,
  int? pinnedPort,
  Duration connectionTimeout = const Duration(seconds: 10),
}) {
  final pin = pinnedFingerprint?.trim().toLowerCase();
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  if (pin != null && pin.isNotEmpty) {
    client.badCertificateCallback = (cert, host, port) =>
        pinnedCertificateIsTrusted(
          cert,
          host: host,
          port: port,
          pinnedFingerprint: pin,
          pinnedHost: pinnedHost,
          pinnedPort: pinnedPort,
        );
  }
  return client;
}

/// The decision [buildPinnedHttpClient] installs: may this certificate, from
/// this host and port, be accepted despite failing platform verification?
///
/// Lifted out of the closure so it can be tested directly. `HttpClient`
/// exposes `badCertificateCallback` as a **setter only**, so a test cannot read
/// the installed closure back — which left the single most security-critical
/// predicate in the app with no coverage at all, in either direction. Everything
/// it guards (ADR-6's host and port binding, the fingerprint comparison) is
/// invisible to CI unless it lives somewhere a test can call.
///
/// Returns false unless *all three* match. A fingerprint-only check would let a
/// pin granted for one origin accept the same certificate presented by any other
/// host this process talks to.
bool pinnedCertificateIsTrusted(
  X509Certificate cert, {
  required String host,
  required int port,
  required String pinnedFingerprint,
  String? pinnedHost,
  int? pinnedPort,
}) {
  final pin = pinnedFingerprint.trim().toLowerCase();
  if (pin.isEmpty) return false;
  if (pinnedHost != null && host != pinnedHost) return false;
  if (pinnedPort != null && port != pinnedPort) return false;
  return certificateFingerprint(cert).toLowerCase() == pin;
}

/// Connects to [host]:[port] over TLS accepting any certificate, purely to read
/// the certificate the server presents so it can be shown in a trust prompt.
///
/// The socket is never used to transfer data — it is closed immediately. Used
/// only on the connection-test failure path to power the self-signed exception
/// flow. Returns null if no certificate could be read.
Future<ServerCertificate?> probeServerCertificate(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  X509Certificate? captured;
  SecureSocket? socket;

  // Held separately from `socket` so the timeout path can still close it.
  // `.timeout()` completes the *outer* future and abandons the inner one, which
  // keeps connecting: `socket` is therefore still null in the `finally`, the
  // `destroy()` there is a no-op, and the connection that lands a moment later
  // is never closed. Under ADR-6 this probe runs on *every* disconnected,
  // probe-worthy failure rather than the rare TrueNAS/Dockge case ADR-5
  // confined it to, so repeated taps on "Test connection" against a flaky host
  // leaked one descriptor and one half-open TLS connection each.
  final pending = SecureSocket.connect(
    host,
    port,
    onBadCertificate: (cert) {
      captured = cert;
      return true;
    },
  );
  unawaited(
    pending
        .then((arrived) {
          if (!identical(arrived, socket)) arrived.destroy();
        })
        .catchError((_) {}),
  );

  try {
    socket = await pending.timeout(timeout);
    // A valid certificate never triggers onBadCertificate; read it directly.
    captured ??= socket.peerCertificate;
  } finally {
    socket?.destroy();
  }
  final cert = captured;
  if (cert == null) return null;
  return ServerCertificate(
    fingerprint: certificateFingerprint(cert),
    subject: cert.subject,
    issuer: cert.issuer,
    validFrom: cert.startValidity,
    validTo: cert.endValidity,
  );
}

/// Builds a Dio [IOHttpClientAdapter] pinned to [pinnedFingerprint] for
/// [baseUrl]'s own origin, or null when [pinnedFingerprint] is null/empty.
///
/// The one place every Dio-based client threads a stored fingerprint (ADR-6)
/// through to [buildPinnedHttpClient] — `ApiClient` and the four per-service
/// clients that build their own `Dio` (qBittorrent, SABnzbd, NZBGet, Unraid)
/// all call this rather than deriving the origin's host/port themselves, so
/// there is exactly one place that rule can drift. A null return means "leave
/// this Dio's adapter at its default", which is what keeps every unpinned
/// connection — the overwhelming majority, including every service reached
/// over a certificate the OS already trusts — byte-identical to how it
/// behaved before ADR-6.
IOHttpClientAdapter? pinnedHttpClientAdapterFor(
  String baseUrl, {
  String? pinnedFingerprint,
}) {
  final pin = pinnedFingerprint?.trim() ?? '';
  if (pin.isEmpty) return null;

  final origin = Uri.parse(baseUrl);
  return IOHttpClientAdapter(
    createHttpClient: () => buildPinnedHttpClient(
      pinnedFingerprint: pin,
      pinnedHost: origin.host,
      pinnedPort: origin.hasPort
          ? origin.port
          : (origin.scheme == 'https' ? 443 : 80),
    ),
  );
}

/// Returns true if [host]:[port] presents a certificate the platform already
/// trusts (standard verification succeeds). Returns false when the handshake
/// fails specifically because the certificate is untrusted; rethrows other
/// errors (connection refused, timeout, DNS) so the caller can distinguish a
/// certificate-trust problem from an unreachable server.
Future<bool> certificateValidatesByDefault(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  SecureSocket? socket;
  // Same abandoned-future leak as [probeServerCertificate], and it matters here
  // for the same reason: this runs first on every probe-worthy failure, so a
  // user retrying against an unreachable host leaks a descriptor per attempt.
  final pending = SecureSocket.connect(host, port);
  unawaited(
    pending
        .then((arrived) {
          if (!identical(arrived, socket)) arrived.destroy();
        })
        .catchError((_) {}),
  );
  try {
    socket = await pending.timeout(timeout);
    return true;
  } on HandshakeException {
    return false;
  } on CertificateException {
    return false;
  } finally {
    socket?.destroy();
  }
}
