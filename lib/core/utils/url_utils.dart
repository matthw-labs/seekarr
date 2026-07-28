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

  static const _invalidUrl =
      'Enter a valid URL (e.g. https://192.168.1.100:7878)';
  static const _credentialsInUrl =
      'Remove the username:password from the URL — enter credentials in their '
      'own fields';

  /// Validates a service URL that must carry an explicit scheme.
  ///
  /// Used by the settings form, where the stored value is shown back to the
  /// user verbatim. For the onboarding fields — whose clients default a
  /// scheme-less host to HTTPS — use [validateServiceHost] instead.
  static String? validateServiceUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Server URL is required';
    }

    final trimmed = value.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'URL must start with http:// or https://';
    }

    return _validateParsed(trimmed);
  }

  /// Validates a service URL that may omit the scheme.
  ///
  /// Every client normalises a scheme-less host to `https://`, so accepting it
  /// here matches what actually happens on connect. Anything that is not a
  /// plausible host — an unknown scheme, embedded whitespace, embedded
  /// credentials — is rejected up front so the user is told the address is
  /// malformed instead of being told the server is unreachable.
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

    return null;
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
    // IPv6 loopback / unique-local / link-local.
    if (h == '::1' || h.startsWith('fd') || h.startsWith('fe80')) return true;
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
}
