import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';

/// `GET /api/` — the unauthenticated health document.
///
/// The only response that proves an Nginx Proxy Manager backend is at the other
/// end. A bare 200 does not: the admin port serves a single-page app through
/// `try_files … /index.html`, so almost any path returns 200 HTML — including
/// against a wrong port, a wrong host, or an entirely different web server.
class NpmServerInfo {
  const NpmServerInfo({
    required this.status,
    required this.version,
    required this.setupComplete,
    required this.major,
    required this.minor,
  });

  final String status;

  /// `major.minor.revision`, flattened for display.
  final String version;

  /// False while NPM is still showing its first-run wizard (no user exists
  /// yet). Absent before 2.13, where it reads as true rather than pretending to
  /// know.
  final bool setupComplete;

  final int major;
  final int minor;

  bool get isHealthy => status.toUpperCase() == 'OK';

  /// Whether this install predates the removal of the hard-coded default
  /// administrator (`admin@example.com` / `changeme`).
  ///
  /// Surfaced rather than ignored because on an untouched 2.12-or-older install
  /// that account still works, and it hands full control of every route on the
  /// box to anyone who can reach port 81.
  bool get hasDefaultAdminRisk => major < 2 || (major == 2 && minor <= 12);

  factory NpmServerInfo.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final versionMap = version is Map
        ? version.cast<String, dynamic>()
        : const <String, dynamic>{};
    final major = parseInt(versionMap['major']);
    final minor = parseInt(versionMap['minor']);
    return NpmServerInfo(
      status: json['status']?.toString() ?? '',
      version: '$major.$minor.${parseInt(versionMap['revision'])}',
      // Missing before 2.13. Defaulting to true keeps an older install from
      // being reported as "not set up" on the strength of an absent field.
      setupComplete: json.containsKey('setup')
          ? parseBool(json['setup'])
          : true,
      major: major,
      minor: minor,
    );
  }
}

/// A hostname Nginx Proxy Manager fronts, and where it sends the traffic.
class NpmProxyHost {
  const NpmProxyHost({
    required this.id,
    required this.domainNames,
    required this.forwardScheme,
    required this.forwardHost,
    required this.forwardPort,
    required this.enabled,
    required this.sslForced,
    required this.certificateId,
    required this.accessListId,
    required this.cachingEnabled,
    required this.blockExploits,
    required this.allowWebsocketUpgrade,
    required this.configLoaded,
    required this.errorText,
  });

  final int id;
  final List<String> domainNames;
  final String forwardScheme;
  final String forwardHost;
  final int forwardPort;
  final bool enabled;
  final bool sslForced;

  /// 0 when no certificate is attached.
  ///
  /// Never write this back as 0 to "clear" a certificate casually: NPM cascades
  /// a falsy `certificate_id` into `ssl_forced = false` and
  /// `http2_support = false`, and `ssl_forced = false` cascades again into
  /// `hsts_enabled = false` and then `hsts_subdomains = false`. One field
  /// silently wipes four.
  final int certificateId;

  final int accessListId;
  final bool cachingEnabled;
  final bool blockExploits;
  final bool allowWebsocketUpgrade;

  /// Whether the **last configuration attempt** for this host succeeded, from
  /// `meta.nginx_online`.
  ///
  /// **Not a live health signal, and must never be rendered as one.** NPM
  /// writes this only from `internalNginx.configure()` — on create, on updating
  /// an already-enabled host, and on enable. Nothing polls, nothing re-checks.
  /// A host whose backend died an hour ago still reads true here, and a host
  /// that failed to load stays false until someone edits it again.
  ///
  /// So the honest reading is "nginx refused this configuration the last time
  /// it was asked to load it", which is genuinely useful — it is invisible
  /// everywhere else and it means the hostname is not being served — but it is
  /// a config verdict, not an uptime probe. Calling it "Online" in the UI would
  /// promise monitoring this app does not do.
  final bool configLoaded;

  /// From `meta.nginx_err`, empty when the last configuration attempt was fine.
  final String errorText;

  /// The name to show. NPM allows several hostnames per host; the first is the
  /// canonical one in its own UI too.
  String get primaryDomain =>
      domainNames.isEmpty ? 'Unnamed host' : domainNames.first;

  String get target => '$forwardScheme://$forwardHost:$forwardPort';

  bool get hasCertificate => certificateId > 0;

  bool get hasAccessList => accessListId > 0;

  /// A host that is switched on but whose configuration nginx refused. The only
  /// state worth an alarm: a disabled host is *meant* not to be served, and a
  /// healthy-looking one is only as fresh as the last time it was configured
  /// (see [configLoaded]).
  bool get hasConfigError => enabled && !configLoaded;

  factory NpmProxyHost.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    final metaMap = meta is Map
        ? meta.cast<String, dynamic>()
        : const <String, dynamic>{};
    final domains = json['domain_names'];
    return NpmProxyHost(
      id: parseInt(json['id']),
      domainNames: domains is List
          ? domains.map((e) => e.toString()).toList(growable: false)
          : const [],
      forwardScheme: json['forward_scheme']?.toString() ?? 'http',
      forwardHost: json['forward_host']?.toString() ?? '',
      forwardPort: parseInt(json['forward_port']),
      enabled: parseBool(json['enabled']),
      sslForced: parseBool(json['ssl_forced']),
      certificateId: parseInt(json['certificate_id']),
      accessListId: parseInt(json['access_list_id']),
      cachingEnabled: parseBool(json['caching_enabled']),
      blockExploits: parseBool(json['block_exploits']),
      allowWebsocketUpgrade: parseBool(json['allow_websocket_upgrade']),
      // Absent means nginx has not complained, which is the healthy reading.
      configLoaded: metaMap.containsKey('nginx_online')
          ? parseBool(metaMap['nginx_online'])
          : true,
      errorText: metaMap['nginx_err']?.toString() ?? '',
    );
  }
}

/// A TLS certificate NPM holds.
///
/// Deliberately does **not** model `meta`. For an uploaded certificate that
/// object contains private key material, and for a Let's Encrypt one it holds
/// the DNS-provider credentials used for the challenge. None of it is needed to
/// show an expiry date, and a field that is never parsed is a field that cannot
/// end up in a cache, a log or a diagnostics export.
class NpmCertificate {
  const NpmCertificate({
    required this.id,
    required this.provider,
    required this.niceName,
    required this.domainNames,
    required this.expiresOn,
  });

  final int id;

  /// `letsencrypt` or `other` (an uploaded certificate).
  final String provider;

  final String niceName;
  final List<String> domainNames;
  final DateTime? expiresOn;

  bool get isLetsEncrypt => provider == 'letsencrypt';

  /// Whole days until expiry, or null when NPM did not give a date.
  int? daysUntilExpiry(DateTime now) {
    final expiry = expiresOn;
    if (expiry == null) return null;
    return expiry.difference(now).inDays;
  }

  /// Certificates worth surfacing. Let's Encrypt renews at 30 days out, so a
  /// shorter window than that would only ever fire on one that is already
  /// failing to renew — which is exactly the case this is for.
  bool isExpiringSoon(DateTime now) {
    final days = daysUntilExpiry(now);
    return days != null && days <= 21;
  }

  String get displayName =>
      niceName.isNotEmpty ? niceName : (domainNames.firstOrNull ?? 'Untitled');

  factory NpmCertificate.fromJson(Map<String, dynamic> json) {
    final domains = json['domain_names'];
    return NpmCertificate(
      id: parseInt(json['id']),
      provider: json['provider']?.toString() ?? '',
      niceName: json['nice_name']?.toString() ?? '',
      domainNames: domains is List
          ? domains.map((e) => e.toString()).toList(growable: false)
          : const [],
      expiresOn: DateTime.tryParse(json['expires_on']?.toString() ?? ''),
    );
  }
}

/// A `302`/`301` hostname, a `404` host, or a TCP/UDP stream — the three
/// smaller host kinds, which differ enough to name but not enough to model
/// separately for a dashboard.
class NpmSimpleHost {
  const NpmSimpleHost({
    required this.id,
    required this.label,
    required this.detail,
    required this.enabled,
    required this.configLoaded,
  });

  final int id;
  final String label;
  final String detail;
  final bool enabled;

  /// Same caveat as [NpmProxyHost.configLoaded]: the result of the last
  /// configuration attempt, not a live probe.
  final bool configLoaded;

  bool get hasConfigError => enabled && !configLoaded;

  static bool _configLoaded(Map<String, dynamic> json) {
    final meta = json['meta'];
    final metaMap = meta is Map
        ? meta.cast<String, dynamic>()
        : const <String, dynamic>{};
    return metaMap.containsKey('nginx_online')
        ? parseBool(metaMap['nginx_online'])
        : true;
  }

  static String _firstDomain(Map<String, dynamic> json) {
    final domains = json['domain_names'];
    if (domains is List && domains.isNotEmpty) return domains.first.toString();
    return 'Unnamed';
  }

  factory NpmSimpleHost.redirection(Map<String, dynamic> json) {
    final scheme = json['forward_scheme']?.toString() ?? 'auto';
    final target = json['forward_domain_name']?.toString() ?? '';
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: _firstDomain(json),
      detail: '→ $scheme://$target',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }

  factory NpmSimpleHost.dead(Map<String, dynamic> json) {
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: _firstDomain(json),
      detail: '404 host',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }

  factory NpmSimpleHost.stream(Map<String, dynamic> json) {
    final incoming = parseInt(json['incoming_port']);
    final host = json['forwarding_host']?.toString() ?? '';
    final port = parseInt(json['forwarding_port']);
    final protocols = <String>[
      if (parseBool(json['tcp_forwarding'])) 'TCP',
      if (parseBool(json['udp_forwarding'])) 'UDP',
    ];
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: ':$incoming',
      detail: '${protocols.join('/')} → $host:$port',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }

  /// An access list, named only. **Never fetched with `?expand=items`**: that
  /// returns the stored basic-auth usernames and passwords for the sites it
  /// protects, which this app has no reason to hold.
  factory NpmSimpleHost.accessList(Map<String, dynamic> json) {
    final satisfyAny = parseBool(json['satisfy_any']);
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: json['name']?.toString() ?? 'Access list',
      detail: satisfyAny ? 'Satisfy any' : 'Satisfy all',
      enabled: true,
      configLoaded: true,
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
