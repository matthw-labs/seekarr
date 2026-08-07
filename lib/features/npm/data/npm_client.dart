import 'package:dio/dio.dart';

import 'package:seekarr/core/network/cert_trust.dart';
import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/network/redirect_guard.dart';
import 'package:seekarr/core/utils/url_utils.dart';
import 'package:seekarr/features/npm/domain/models/npm_models.dart';

/// Error thrown by [NpmClient].
///
/// [message] is always a static sentence written here or one of Nginx Proxy
/// Manager's own fixed error strings — **never** an interpolated response body.
/// That rule is load-bearing rather than stylistic: the login response carries
/// the bearer token, and `AppErrorState` renders `toString()` verbatim, so
/// `throw NpmException('Login failed: ${response.data}')` would put a working
/// credential on screen. [redactJwt] is the belt to that braces.
class NpmException implements Exception, HasFailureReason {
  const NpmException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });

  final String message;

  @override
  final ServiceFailureReason reason;

  @override
  String toString() => 'NpmException: $message';
}

/// Replaces anything shaped like a JWT with `***`.
///
/// Defence in depth for the one thing that must never be rendered. Nothing in
/// this client interpolates a response body today, but a server that echoes a
/// token in a 4xx — or a future edit that gets careless — is caught here rather
/// than on the user's screen. Modelled on `redactSabnzbdSecrets`.
String redactJwt(String input) {
  return input.replaceAll(
    RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
    '***',
  );
}

/// Client for the Nginx Proxy Manager admin API.
///
/// **NPM issues no API key.** The only credential it accepts is an account's
/// email and password, exchanged at `POST /api/tokens` for an RS256 JWT that
/// lives one day. That is a property of the server, and it is why this client
/// holds a password at all: it must be able to re-mint. The password lives in
/// the OS keychain like every other credential in this app; the token lives
/// **in memory only and is never persisted**, because a value that expires in a
/// day gains nothing from surviving a relaunch and would only add a secret with
/// no revocation story — NPM has no revocation list, so an issued token stays
/// valid until `exp` even after the password changes.
///
/// **NPM never returns 401.** Its whole auth ladder has to be learned:
///
/// | condition | status | body |
/// |---|---|---|
/// | wrong password | **400** | `Invalid email or password` |
/// | expired token | **400** | `Token has expired` |
/// | no token | 403 | `Permission Denied` |
/// | valid token, no permission | 403 | `Permission Denied` |
/// | malformed/garbage token | **500** | `Internal Error` |
///
/// A client written to the usual "401 means credentials" rule misdiagnoses
/// every one of those, and a stored garbage token looks like a server outage.
///
/// **There is also no rate limiting** — none, anywhere in NPM. Nothing on the
/// server protects the user's password from a retry storm, so the back-off is
/// this client's job: [_credentialsRejected] makes a refused login stick, and
/// [_authInFlight] collapses concurrent logins into one.
class NpmClient {
  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6).
  ///
  /// This matters more here than for most services: NPM is usually the thing
  /// *terminating* everyone else's TLS, so the hardened setup — proxying its
  /// own admin UI behind a certificate — is very often an internal CA or a
  /// self-signed certificate.
  NpmClient({
    required String url,
    this.identity,
    this.secret,
    Dio? dio,
    String? certFingerprint,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url) {
    _dio =
        dio ??
        Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            // Follow redirects by hand so the bearer token — which *is* the
            // account, with no scoping and no revocation — is never replayed to
            // a host the user did not configure. Required for a second reason
            // too: `GET /api` without the trailing slash is a 302 to `/api/`,
            // and that redirect has to reach the interceptor rather than be
            // rejected as a bad response.
            followRedirects: false,
            validateStatus: allowRedirectStatus,
          ),
        );
    if (dio == null) {
      // One Dio for login *and* data, deliberately. A second transport minted
      // just for the token exchange is the natural shape and the wrong one: it
      // would skip the pinned adapter, so against a self-signed NPM the login
      // would fail as "unreachable" while every data call would have worked,
      // and the user would never be offered the certificate prompt.
      _dio.interceptors.add(SameOriginRedirectInterceptor(_dio));
      final adapter = pinnedHttpClientAdapterFor(
        baseUrl,
        pinnedFingerprint: certFingerprint,
      );
      if (adapter != null) _dio.httpClientAdapter = adapter;
    }
  }

  final String baseUrl;
  final String? identity;
  final String? secret;
  late final Dio _dio;

  /// The transport, for tests that assert the pinned adapter and the redirect
  /// guard are actually installed.
  Dio get dio => _dio;

  /// Memory only. Never written to `SharedPreferences` or the Keychain.
  String? _token;
  DateTime? _tokenExpiry;

  /// Collapses concurrent logins into one. Five polls hitting an expired token
  /// at once must mint one token, not five — NPM has no rate limiting, and five
  /// parallel attempts on a wrong password is a retry storm against the user's
  /// own account.
  Future<void>? _authInFlight;

  /// Sticky once NPM has refused these credentials, so a polling screen stops
  /// asking. Also what lets [_ensureToken] fail fast: without it every call
  /// spends a full round trip to relearn the same answer, which on a slow link
  /// runs past the verification timeout and reports "check the address" for
  /// what is plainly a wrong password.
  bool _credentialsRejected = false;

  bool get _hasCredentials =>
      (identity?.trim().isNotEmpty ?? false) && (secret?.isNotEmpty ?? false);

  /// Whether the in-memory token is still usable.
  ///
  /// Refreshes at 80% of its life rather than waiting for a rejection, which
  /// turns the expiry path into a background detail instead of a user-visible
  /// failure once a day.
  bool get _tokenIsFresh {
    final token = _token;
    final expiry = _tokenExpiry;
    if (token == null || token.isEmpty || expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  /// `GET /api/` — the unauthenticated health document.
  ///
  /// The trailing slash is not optional: the admin nginx config answers
  /// `GET /api` with a 302 to `/api/`.
  Future<NpmServerInfo> serverInfo() async {
    final data = await _request<Map<String, dynamic>>(
      'GET',
      '/api/',
      authenticated: false,
    );
    final info = NpmServerInfo.fromJson(data);
    // A 200 alone proves nothing here — the admin port serves a single-page app
    // through `try_files … /index.html`, so a wrong port or an entirely
    // different web server also answers 200 with HTML. Only this JSON does.
    if (!info.isHealthy) {
      throw const NpmException(
        'That address answered, but it is not an Nginx Proxy Manager API. '
        'Check the port — the admin interface is on 81 by default, not the '
        'port the proxy itself serves.',
        reason: ServiceFailureReason.notFound,
      );
    }
    return info;
  }

  Future<String> version() async => (await serverInfo()).version;

  /// Proves the address *and* the credentials.
  ///
  /// Both halves are needed and they fail differently: [serverInfo] proves an
  /// NPM is there without any credential, and the login proves the credential
  /// without which every later call is a 403. Checking only the first is how a
  /// wrong password shows a green tile.
  Future<bool> testConnection() async {
    await serverInfo();
    if (_hasCredentials) await _authenticate();
    return true;
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// The proxy hosts, with their certificate and access-list bindings.
  ///
  /// `expand` deliberately omits `items`: expanding an access list's items
  /// returns the stored basic-auth usernames and passwords for the sites it
  /// protects, and this app has no reason to hold those.
  Future<List<NpmProxyHost>> proxyHosts() async {
    final data = await _request<List<dynamic>>(
      'GET',
      '/api/nginx/proxy-hosts',
      query: const {'expand': 'owner,access_list,certificate'},
    );
    return data
        .whereType<Map>()
        .map((e) => NpmProxyHost.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<NpmCertificate>> certificates() async {
    final data = await _request<List<dynamic>>(
      'GET',
      '/api/nginx/certificates',
    );
    return data
        .whereType<Map>()
        .map((e) => NpmCertificate.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<NpmSimpleHost>> redirectionHosts() async {
    return _simpleHosts(
      '/api/nginx/redirection-hosts',
      NpmSimpleHost.redirection,
    );
  }

  Future<List<NpmSimpleHost>> deadHosts() async {
    return _simpleHosts('/api/nginx/dead-hosts', NpmSimpleHost.dead);
  }

  Future<List<NpmSimpleHost>> streams() async {
    return _simpleHosts('/api/nginx/streams', NpmSimpleHost.stream);
  }

  Future<List<NpmSimpleHost>> accessLists() async {
    return _simpleHosts('/api/nginx/access-lists', NpmSimpleHost.accessList);
  }

  Future<List<NpmSimpleHost>> _simpleHosts(
    String path,
    NpmSimpleHost Function(Map<String, dynamic>) map,
  ) async {
    final data = await _request<List<dynamic>>('GET', path);
    return data
        .whereType<Map>()
        .map((e) => map(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Switches a proxy host on or off.
  ///
  /// Returns the host as it stands *after* the write, re-read rather than
  /// assumed. NPM answers a bare JSON `true` here — not an object — and that
  /// `true` only means the database row changed: `nginx -t` runs afterwards,
  /// and a configuration that fails to load merely sets `meta.nginx_online`
  /// false. Reporting success from the status code alone would tell the user a
  /// site is back up when nginx has refused it.
  ///
  /// Every write also reloads nginx globally, so this briefly affects every
  /// proxied site on the box. Do not call it in a loop.
  Future<NpmProxyHost?> setProxyHostEnabled(int id, bool enabled) async {
    await _request<dynamic>(
      'POST',
      '/api/nginx/proxy-hosts/$id/${enabled ? 'enable' : 'disable'}',
    );
    return _reloadProxyHost(id);
  }

  /// Repoints a proxy host at a different backend.
  ///
  /// Sends **only** the three fields being changed, and that is a contract
  /// rather than an economy: NPM's `PUT` body schema is
  /// `additionalProperties: false` over an allow-list, so handing back an
  /// object read from `GET` — with its `id`, `created_on`, `owner`,
  /// `certificate` — is rejected outright as a validation error. The patch is
  /// built from scratch.
  ///
  /// `certificate_id` is deliberately not writable through this method. A
  /// falsy value cascades: NPM clears `ssl_forced` and `http2_support`, which
  /// clears `hsts_enabled`, which clears `hsts_subdomains` — four settings
  /// wiped by one field. And the string `"new"` is a legal value that makes NPM
  /// go and request a real Let's Encrypt certificate. Neither belongs behind a
  /// port-number field on a phone.
  Future<NpmProxyHost?> updateProxyForward(
    int id, {
    required String scheme,
    required String host,
    required int port,
  }) async {
    final normalizedScheme = scheme.trim().toLowerCase();
    if (normalizedScheme != 'http' && normalizedScheme != 'https') {
      throw const NpmException('The forward scheme must be http or https.');
    }
    if (host.trim().isEmpty) {
      throw const NpmException('The forward host cannot be empty.');
    }
    if (port < 1 || port > 65535) {
      throw const NpmException('The forward port must be between 1 and 65535.');
    }

    await _request<dynamic>(
      'PUT',
      '/api/nginx/proxy-hosts/$id',
      body: {
        'forward_scheme': normalizedScheme,
        'forward_host': host.trim(),
        'forward_port': port,
      },
    );
    return _reloadProxyHost(id);
  }

  /// Asks NPM to renew a Let's Encrypt certificate.
  ///
  /// **Only ever from an explicit, confirmed user action.** This call talks to
  /// Let's Encrypt, so a retry loop, a pull-to-refresh binding or a background
  /// sync can burn the account's ACME rate limits and get the user's domain
  /// temporarily refused — a failure that outlasts the app session and that
  /// they cannot fix from here.
  Future<void> renewCertificate(int id) async {
    // NPM leaks a stack trace on any path containing `nginx/certificates`
    // (`payload.debug`), and certbot failures can carry DNS-provider
    // credentials in the surrounding context. `_request` never interpolates a
    // response body into an exception, which is what keeps that off the screen.
    await _request<dynamic>('POST', '/api/nginx/certificates/$id/renew');
  }

  Future<NpmProxyHost?> _reloadProxyHost(int id) async {
    try {
      final data = await _request<Map<String, dynamic>>(
        'GET',
        '/api/nginx/proxy-hosts/$id',
      );
      return NpmProxyHost.fromJson(data);
    } catch (_) {
      // The write itself succeeded; failing to re-read is not a reason to
      // report it as failed. The caller falls back to invalidating its list.
      return null;
    }
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  /// Mints a token, at most one at a time.
  Future<void> _authenticate() {
    final inFlight = _authInFlight;
    if (inFlight != null) return inFlight;
    final future = _login().whenComplete(() => _authInFlight = null);
    _authInFlight = future;
    return future;
  }

  Future<void> _login() async {
    if (!_hasCredentials) {
      throw const NpmException(
        'Nginx Proxy Manager needs the email and password of an account.',
        reason: ServiceFailureReason.unauthorized,
      );
    }
    if (_credentialsRejected) {
      throw const NpmException(
        'Nginx Proxy Manager rejected this email and password.',
        reason: ServiceFailureReason.unauthorized,
      );
    }

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '/api/tokens',
        // No `expiry` field: the login schema is `additionalProperties: false`
        // and rejects one outright. NPM's own default of one day is what this
        // gets, and one day is plenty for something re-minted from a stored
        // password.
        data: {'identity': identity!.trim(), 'secret': secret!},
        // The login must never be re-driven by the auth retry — that is how a
        // 400 on this very call would recurse.
        options: Options(extra: const {_skipAuthRetry: true}),
      );
    } on DioException catch (e) {
      throw _describe(e, isLogin: true);
    }

    final data = response.data;
    if (data is! Map) {
      throw const NpmException(
        'Nginx Proxy Manager did not return a token.',
        reason: ServiceFailureReason.unauthorized,
      );
    }
    final map = data.cast<String, dynamic>();

    // Two-factor changes the shape of a *successful* response rather than
    // failing: the same 200 comes back as `{requires_2fa, challenge_token}`
    // with no `token` at all. A client that reaches for `data['token']` gets
    // null and reports something incomprehensible. Completing the challenge
    // needs a rotating code this app has no way to ask for at poll time, so the
    // honest move is to say exactly that.
    if (map['requires_2fa'] == true) {
      throw const NpmException(
        'This Nginx Proxy Manager account has two-factor authentication '
        'enabled, which Seekarr cannot complete. Use a dedicated account '
        'without 2FA for the app.',
        reason: ServiceFailureReason.unauthorized,
      );
    }

    final token = map['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const NpmException(
        'Nginx Proxy Manager did not return a token.',
        reason: ServiceFailureReason.unauthorized,
      );
    }

    _token = token;
    final expires = DateTime.tryParse(map['expires']?.toString() ?? '');
    // Refresh at 80% of the lifetime. Falls back to a conservative hour when
    // NPM gives no parseable date, rather than treating the token as immortal.
    final now = DateTime.now();
    _tokenExpiry = expires == null
        ? now.add(const Duration(hours: 1))
        : now.add(expires.difference(now) * 0.8);
  }

  static const _skipAuthRetry = 'seekarr.npmSkipAuthRetry';

  /// One request, with the token minted or refreshed as needed and exactly one
  /// re-auth retry.
  Future<T> _request<T>(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool authenticated = true,
    bool retried = false,
  }) async {
    if (authenticated && !_tokenIsFresh) await _authenticate();

    final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          headers: {
            if (authenticated && _token != null)
              // Header only, never a query parameter — a token in a URL ends up
              // in `HttpException`'s `uri = …` text and in the server's access
              // log. NPM's own parser is a literal split on a space and accepts
              // nothing but `Bearer <token>`.
              'Authorization': 'Bearer $_token',
          },
          extra: retried ? const {_skipAuthRetry: true} : null,
        ),
      );
    } on DioException catch (e) {
      // An expired token is a 400 carrying a specific sentence — not a 401, and
      // indistinguishable by status code from a wrong password. Retry exactly
      // once, and only when this request has not already been retried.
      if (!retried && authenticated && _looksExpired(e)) {
        _token = null;
        _tokenExpiry = null;
        return _request<T>(
          method,
          path,
          query: query,
          body: body,
          authenticated: authenticated,
          retried: true,
        );
      }
      throw _describe(e);
    }

    final data = response.data;
    if (data is T) return data;
    throw const NpmException(
      'Nginx Proxy Manager returned something unexpected. Check that the '
      'address points at its admin interface.',
      reason: ServiceFailureReason.notFound,
    );
  }

  /// Whether this failure is specifically "the token has expired".
  ///
  /// Matched on the message because NPM gives a wrong password and an expired
  /// token the same 400. Reading the body is safe here — it is compared, never
  /// interpolated into anything user-visible.
  bool _looksExpired(DioException e) {
    if (e.response?.statusCode != 400) return false;
    final data = e.response?.data;
    if (data is! Map) return false;
    final error = data['error'];
    final message = error is Map ? error['message']?.toString() ?? '' : '';
    return message.toLowerCase().contains('expired');
  }

  /// Maps NPM's unusual status ladder onto a sentence and a reason.
  NpmException _describe(DioException e, {bool isLogin = false}) {
    final status = e.response?.statusCode;
    switch (status) {
      case 400:
        if (isLogin) {
          // Sticky: NPM has no rate limiting whatsoever, so nothing on the
          // server stops this client from hammering the user's own account.
          _credentialsRejected = true;
          return const NpmException(
            'Nginx Proxy Manager rejected this email and password.',
            reason: ServiceFailureReason.unauthorized,
          );
        }
        return const NpmException(
          'Nginx Proxy Manager refused the request.',
          reason: ServiceFailureReason.unknown,
        );
      case 403:
        // 403 means both "no token" and "this account may not do that", and
        // the two are indistinguishable from the status alone — so the message
        // names the likelier cause without asserting it.
        return const NpmException(
          'This Nginx Proxy Manager account is not allowed to do that. A '
          'view-only user can read hosts and certificates but cannot change '
          'them.',
          reason: ServiceFailureReason.unauthorized,
        );
      case 404:
        return const NpmException(
          'The Nginx Proxy Manager API is not at this address. Point Seekarr '
          'at the admin interface (port 81 by default).',
          reason: ServiceFailureReason.notFound,
        );
      case 500:
        // A malformed or bad-signature token is a 500, not a 401 — so a stored
        // token gone bad looks exactly like a server outage. Dropping it here
        // means the next call re-mints instead of failing forever.
        _token = null;
        _tokenExpiry = null;
        return const NpmException(
          'Nginx Proxy Manager answered with a server error.',
          reason: ServiceFailureReason.serverError,
        );
      default:
        return NpmException(
          redactJwt(e.message ?? 'Nginx Proxy Manager request failed'),
          reason: classifyConnectionFailure(e),
        );
    }
  }

  void close({bool force = false}) => _dio.close(force: force);
}
