class UrlUtils {
  /// Constructs a URL for accessing images or other resources.
  /// Handles correct slash joining. API key authentication is handled via
  /// HTTP headers, not query parameters.
  static String buildUrl(String baseUrl, String path) {
    if (baseUrl.isEmpty || path.isEmpty) return '';

    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final cleanPath = path.startsWith('/') ? path : '/$path';

    return '$cleanBaseUrl$cleanPath';
  }

  /// The base URL every client feeds to Dio: trimmed, scheme-qualified, with no
  /// trailing slash.
  ///
  /// A scheme-less host defaults to HTTPS so an omitted scheme never downgrades
  /// an API key or a Basic-auth password to cleartext (security standard
  /// §10.2 #9); an explicit `http://` is honoured.
  ///
  /// Qualifying the scheme is not cosmetic: `BaseOptions(baseUrl: 'host:7878')`
  /// throws `ArgumentError` from Dio's own setter, and the onboarding and
  /// settings fields both accept a bare host — so without this a plausible
  /// address wedged the caller instead of failing as a connection error.
  static String normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized)) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return _withoutUserInfo(normalized);
  }

  /// Strips any `user:password@` from an address.
  ///
  /// [validateServiceHost] already rejects embedded credentials, and both UI
  /// entry points run it, so nothing reaches storage with them today. This is
  /// the belt to that braces, and it belongs here rather than only in the
  /// validator because *this* is the function whose output becomes
  /// `BaseOptions.baseUrl` — a credential that ever slipped past the form would
  /// be interpolated into every request URI, land in `HttpException`'s
  /// `uri = …` text on any transport failure, and be persisted in plain
  /// `SharedPreferences` rather than the Keychain.
  ///
  /// It is not hypothetical for Transmission specifically: `http://user:pass@
  /// host:9091/` is an idiomatic way to write that daemon's address, so anything
  /// that ever offers "paste your existing Transmission URL" walks straight
  /// into it.
  static String _withoutUserInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isEmpty) return url;
    return uri.replace(userInfo: '').toString();
  }

  static const _invalidUrl =
      'Enter a valid URL (e.g. https://192.168.1.100:7878)';
  static const _credentialsInUrl =
      'Remove the username:password from the URL — enter credentials in their '
      'own fields';

  /// Validates a service URL that may omit the scheme.
  ///
  /// The single rule for every address field in the app: onboarding and the
  /// settings form share it, so an address accepted during setup is still
  /// accepted when reopened for editing.
  ///
  /// [normalizeBaseUrl] turns a scheme-less host into `https://`, so accepting
  /// it here matches what actually happens on connect. Anything that is not a
  /// plausible host — an unknown scheme, embedded whitespace, embedded
  /// credentials, characters no hostname may contain — is rejected up front so
  /// the user is told the address is malformed instead of being told the server
  /// is unreachable.
  ///
  /// A bare single-label host (`nas`, a Docker Compose service name) is
  /// deliberately accepted: on a home network those resolve, and the previous
  /// "must look like a domain" rule turned working addresses into form errors.
  /// So is an internationalised name (`münchen.de`) — same class of input, and
  /// telling the user their address is malformed because it is not ASCII is the
  /// same false report the character rule exists to prevent.
  static String? validateServiceHost(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Server URL is required';
    }

    var trimmed = value.trim();
    final schemeMatch = RegExp(
      r'^([A-Za-z][A-Za-z0-9+.\-]*):\/\/',
    ).firstMatch(trimmed);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        return 'Only http:// and https:// addresses are supported';
      }
    } else {
      if (trimmed.contains('://')) return _invalidUrl;
      // Mirror the clients: a bare host means HTTPS.
      trimmed = 'https://$trimmed';
    }

    return _validateParsed(trimmed);
  }

  static String? _validateParsed(String url) {
    if (RegExp(r'\s').hasMatch(url)) return _invalidUrl;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return _invalidUrl;
    if (uri.userInfo.isNotEmpty) return _credentialsInUrl;
    if (!_isPlausibleHost(uri.host)) return _invalidUrl;

    return null;
  }

  /// One host label: letters, digits, hyphens and underscores, never starting
  /// or ending with a hyphen.
  ///
  /// Underscore is tolerated on purpose — it is illegal in a hostname per
  /// RFC 1123 but legal in a Docker/Compose service name, and reaching a
  /// container by its service name is a normal way to run this stack.
  ///
  /// "Letter" is `\p{L}`, not `A-Za-z`, so an internationalised name
  /// (`münchen.de`, a Cyrillic or CJK host) is a valid address rather than a
  /// malformed one. It is matched against the *decoded* label — see
  /// [_isPlausibleHost] — because `Uri.host` percent-encodes anything
  /// non-ASCII, and `%` is not a character any host may contain.
  static final _hostLabel = RegExp(
    r'^[\p{L}\p{N}_]([\p{L}\p{N}_\-]*[\p{L}\p{N}_])?$',
    unicode: true,
  );

  /// Whether [host] could be a host at all.
  ///
  /// `Uri.tryParse` is far more permissive than DNS: it happily reports
  /// `hello!world`, `a,b.com` or a percent-encoded blob as a "host", so free
  /// text typed into an address field parsed cleanly and the user learned it
  /// was wrong only when the connection test came back "couldn't reach it".
  /// This is the check that turns that into "that address is malformed".
  ///
  /// Deliberately *not* a "must contain a dot" rule: a single label is a
  /// legitimate address here.
  static bool _isPlausibleHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    // `Uri.host` strips the brackets from an IPv6 literal, and a DNS name can
    // never contain a colon — so this is an exact test, not a guess.
    if (host.contains(':')) return _parseIpv6(host) != null;

    // A single trailing dot is a legal fully-qualified name.
    final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    if (name.isEmpty) return false;

    // Split *before* decoding: a label is decoded only to be character-checked,
    // and decoding first would let `a%2Eb.com` present itself as two labels.
    return name.split('.').every((label) {
      if (label.isEmpty || label.length > 63) return false;
      final decoded = _percentDecoded(label);
      return decoded != null && _hostLabel.hasMatch(decoded);
    });
  }

  /// [label] with its percent-escapes resolved, or null when they are malformed.
  static String? _percentDecoded(String label) {
    if (!label.contains('%')) return label;
    try {
      return Uri.decodeFull(label);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The 16 bytes of [host] as an IPv6 literal, or null when it is not one.
  ///
  /// Strips a zone id (`fe80::1%eth0`, which `Uri.host` hands back percent-
  /// encoded as `%25eth0`) — `Uri.parseIPv6Address` rejects it, and the zone
  /// says nothing about which range the address is in.
  static List<int>? _parseIpv6(String host) {
    final zone = host.indexOf('%');
    final literal = zone == -1 ? host : host.substring(0, zone);
    try {
      return Uri.parseIPv6Address(literal);
    } on FormatException {
      return null;
    }
  }

  /// Hosts for which cleartext HTTP is a normal, supported home-lab setup.
  static bool _isPrivateHost(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h.endsWith('.lan')) {
      return true;
    }
    final v4 = RegExp(
      r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
    ).firstMatch(h);
    if (v4 != null) {
      final a = int.parse(v4.group(1)!);
      final b = int.parse(v4.group(2)!);
      // 127/8 loopback, 10/8, 192.168/16, 172.16/12, 169.254/16 link-local.
      if (a == 127 || a == 10) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 169 && b == 254) return true;
      return false;
    }
    // Only an actual IPv6 literal gets the IPv6 treatment, and a DNS name can
    // never contain a colon. Prefix-matching the text instead classified
    // `fdn.example.com` and `fe80s.example.com` as local, so the cleartext
    // warning stayed silent while the API key travelled unencrypted to a
    // public host.
    if (!h.contains(':')) return false;
    final v6 = _parseIpv6(h);
    if (v6 == null) return false;
    // ::1 loopback.
    if (v6.take(15).every((b) => b == 0) && v6[15] == 1) return true;
    // fc00::/7 unique-local.
    if ((v6[0] & 0xFE) == 0xFC) return true;
    // fe80::/10 link-local.
    if (v6[0] == 0xFE && (v6[1] & 0xC0) == 0x80) return true;
    return false;
  }

  /// Warns when [rawUrl] would send credentials in cleartext to a host outside
  /// the local network, and null when there is nothing to warn about.
  ///
  /// A plain `http://` LAN address is a supported setup, so it is not flagged.
  /// A public hostname over `http://` is: an on-path attacker there can read the
  /// API key or password and, before [SameOriginRedirectInterceptor], could also
  /// have redirected the request elsewhere.
  static String? cleartextWarning(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    if (!value.toLowerCase().startsWith('http://')) return null;

    final host = Uri.tryParse(value)?.host ?? '';
    if (host.isEmpty || _isPrivateHost(host)) return null;

    return 'This address is not on your local network and http:// sends your '
        'credentials unencrypted. Use https:// if the instance supports it.';
  }

  /// Whether [url] is an absolute http(s) address safe to hand to the platform
  /// via `launchUrl`.
  ///
  /// `Uri.tryParse` is a syntax check, not a scheme check: `javascript:alert(1)`,
  /// `data:text/html,…`, `intent://…` and `file:///…` all parse. Launching one
  /// of those externally hands whatever a remote service put in a field to the
  /// OS, so the scheme is allow-listed and a host is required.
  ///
  /// This lives here rather than in either feature because two of them need it
  /// for the same reason: TrueNAS renders app portal URLs the NAS supplies, and
  /// Seerr/TMDB supplies trailer URLs. Both are strings from a server the app
  /// does not control, and one allowlist is one place to fix.
  static bool isLaunchableWebUrl(String url) =>
      isLaunchableWebUri(Uri.tryParse(url.trim()));

  /// [isLaunchableWebUrl] for a caller that has already parsed the string —
  /// notably one using `Uri.tryParse` to keep a `FormatException` out of a tap
  /// handler, which then holds a nullable [Uri] rather than the raw text.
  static bool isLaunchableWebUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return uri.isScheme('http') || uri.isScheme('https');
  }

  /// Whether a service URL should be reached over TLS.
  ///
  /// Secure unless the user explicitly asked for cleartext with `http://`. The
  /// polarity matters: testing `== 'https'` instead would silently downgrade a
  /// typo (`htps://host`) or a well-meant `wss://host` to an unencrypted
  /// connection and send login credentials in the clear.
  static bool isSecureScheme(String rawUrl) {
    final scheme = Uri.tryParse(rawUrl.trim())?.scheme.toLowerCase();
    return scheme != 'http' && scheme != 'ws';
  }

  /// The canonical `https://host:port` origin [rawUrl] belongs to, or null
  /// when it cannot carry a TLS certificate at all (unparseable, or an
  /// explicit `http://`/`ws://`).
  ///
  /// A certificate is a property of the host that presents it, not of any one
  /// service reached through it — this is the single place that turns a
  /// service's saved URL into the key trusted-certificate pins are stored
  /// under, so two services behind the same reverse proxy resolve to the same
  /// key and share one trust decision. Every saved service URL is http(s) —
  /// the WebSocket-based clients (TrueNAS, Dockge) derive their own `wss://`
  /// internally — so only that pair needs handling here.
  static String? certOrigin(String rawUrl) {
    var raw = rawUrl.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';
    if (!isSecureScheme(raw)) return null;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;

    final port = uri.hasPort ? uri.port : 443;
    return 'https://${uri.host}:$port';
  }
}
