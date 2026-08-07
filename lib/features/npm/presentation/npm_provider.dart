import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// Nginx Proxy Manager client bound to the current settings.
///
/// Throws if NPM is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.nginxProxyManager)` first.
///
/// One long-lived client per configuration, and here that is not just an
/// optimisation: the bearer token lives on the instance and nowhere else, so a
/// fresh client per call would mean a fresh login per call — against a server
/// with no rate limiting, on an account whose password is the key to every
/// route on the box.
final npmClientProvider = Provider<NpmClient>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (settings.npmUrl.isEmpty) {
    throw Exception('Nginx Proxy Manager not configured');
  }
  final client = NpmClient(
    url: settings.npmUrl,
    identity: settings.npmUsername.isEmpty ? null : settings.npmUsername,
    secret: settings.npmPassword.isEmpty ? null : settings.npmPassword,
    certFingerprint: settings.pinForUrl(settings.npmUrl),
  );
  ref.onDispose(() => client.close());
  return client;
});

/// The hostnames NPM fronts.
final npmProxyHostsProvider = FutureProvider<List<NpmProxyHost>>((ref) async {
  return ref.watch(npmClientProvider).proxyHosts();
});

/// Certificates, for expiry watching.
final npmCertificatesProvider = FutureProvider<List<NpmCertificate>>((
  ref,
) async {
  return ref.watch(npmClientProvider).certificates();
});

/// Redirections, 404 hosts and streams, fetched together because the dashboard
/// shows them as one "other hosts" band and none of them is worth a round trip
/// of its own.
final npmOtherHostsProvider = FutureProvider<List<NpmSimpleHost>>((ref) async {
  final client = ref.watch(npmClientProvider);
  final results = await Future.wait([
    client.redirectionHosts(),
    client.deadHosts(),
    client.streams(),
  ]);
  return results.expand((hosts) => hosts).toList(growable: false);
});

/// Access lists, by name only — never with `?expand=items`, which would return
/// the basic-auth credentials of the sites they protect.
final npmAccessListsProvider = FutureProvider<List<NpmSimpleHost>>((ref) async {
  return ref.watch(npmClientProvider).accessLists();
});

/// The unauthenticated health document — version, and whether this install is
/// old enough to still carry NPM's hard-coded default administrator.
final npmServerInfoProvider = FutureProvider<NpmServerInfo>((ref) async {
  return ref.watch(npmClientProvider).serverInfo();
});
