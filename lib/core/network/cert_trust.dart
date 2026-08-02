import 'dart:io';

import 'package:crypto/crypto.dart';

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
HttpClient buildPinnedHttpClient({
  String? pinnedFingerprint,
  Duration connectionTimeout = const Duration(seconds: 10),
}) {
  final pin = pinnedFingerprint?.trim().toLowerCase();
  final client = HttpClient()..connectionTimeout = connectionTimeout;
  if (pin != null && pin.isNotEmpty) {
    client.badCertificateCallback = (cert, host, port) =>
        certificateFingerprint(cert).toLowerCase() == pin;
  }
  return client;
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
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (cert) {
        captured = cert;
        return true;
      },
    ).timeout(timeout);
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
  try {
    socket = await SecureSocket.connect(host, port).timeout(timeout);
    return true;
  } on HandshakeException {
    return false;
  } on CertificateException {
    return false;
  } finally {
    socket?.destroy();
  }
}
