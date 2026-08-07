import 'package:cupola/features/settings/domain/service_key.dart';

enum ServiceSummaryStatus { online, offline }

/// Whether a configured service is answering, and what it says it is.
///
/// ## What this deliberately no longer carries
///
/// It used to hold an `itemCount` and an `itemLabel`, which composed into a
/// `countLabel` — the "76 movies" line on the old status card. Producing that one
/// string cost a **full library fetch per service**: `getMovies()`,
/// `getSeries()`, `getArtists()`, `getTorrents()`, `getAuthors()`, `getPools()`,
/// `fetchStacks()`, `getIndexers()`, one after another, none of them shared with
/// the providers the rest of the screen already used.
///
/// Two things made that indefensible. The figure was the *least* live thing on a
/// control-room screen — a library total does not change from one week to the
/// next — and the stack matrix that replaced the card shows a genuinely live
/// metric instead, resolved from `serviceKpiProvider`, which reads providers the
/// screen was loading anyway. So the counts became invisible while still being
/// paid for, thirteen times, on every open and every pull-to-refresh.
///
/// This object is now what its name says: reachability plus identity.
class ServiceSummary {
  final ServiceKey service;
  final ServiceSummaryStatus status;
  final String host;

  /// Reported version, when the service gave one.
  ///
  /// A by-product rather than a fetch of its own: the version endpoint *is* the
  /// reachability probe, so this value is already in hand by the time [status] is
  /// known.
  final String? version;

  const ServiceSummary({
    required this.service,
    required this.status,
    required this.host,
    required this.version,
  });

  bool get isOnline => status == ServiceSummaryStatus.online;

  String get statusLabel => isOnline ? 'Online' : 'Offline';

  String get versionLabel {
    final serviceVersion = version?.trim();
    if (serviceVersion != null && serviceVersion.isNotEmpty) {
      return serviceVersion.startsWith('v')
          ? serviceVersion
          : 'v$serviceVersion';
    }

    return '${service.apiVersion} API';
  }
}
