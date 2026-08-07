import 'package:flutter/foundation.dart';

/// What sits between Seekarr and a service, and what it costs.
///
/// The point of naming it: a failure is only actionable if the user knows *who*
/// gave up. "502" is not actionable; "your NPM proxy host, whose read timeout you
/// can raise" is.
enum SearchGateway {
  /// No intermediary identified itself — a direct LAN or Tailscale path.
  direct,

  /// nginx, which Nginx Proxy Manager is built on. 60 s by default, raisable per
  /// proxy host.
  nginx,

  /// Hard 100 s on a free plan, and not raisable there at all.
  cloudflare,

  /// Something identified itself but is not one we have advice for.
  other,
}

/// Measured, not guessed: what this instance's own searches have shown.
@immutable
class SearchHeadroom {
  const SearchHeadroom({
    this.gateway,
    this.gatewayName,
    this.longestSuccess,
    this.earliestCutoff,
    this.recentDurations = const [],
  });

  /// Null until the user runs the check.
  final SearchGateway? gateway;

  /// The raw `server` header, when there was one. Kept because a self-hoster
  /// recognises their own stack in it.
  final String? gatewayName;

  /// The longest search that came back with an answer.
  final Duration? longestSuccess;

  /// The shortest elapsed at which a search was cut off. Together with
  /// [longestSuccess] this brackets the real ceiling without ever guessing it.
  final Duration? earliestCutoff;

  /// The last few completed durations, newest first. Drives the adaptive reveal:
  /// an instance that is habitually slow should not make the user wait six
  /// seconds to be offered the way out.
  final List<Duration> recentDurations;

  static const maxRecent = 5;

  /// The threshold past which this instance is known to be slow.
  static const habituallySlow = Duration(seconds: 10);

  /// True when this instance's recent searches justify offering the handoff
  /// immediately rather than after six seconds.
  bool get isHabituallySlow {
    if (recentDurations.length < 3) return false;
    final total = recentDurations.fold(Duration.zero, (sum, d) => sum + d);
    return total ~/ recentDurations.length > habituallySlow;
  }

  /// The hard ceiling this gateway imposes, when it imposes one we know about.
  Duration? get knownCap => switch (gateway) {
    SearchGateway.cloudflare => const Duration(seconds: 100),
    SearchGateway.nginx => const Duration(seconds: 60),
    _ => null,
  };

  /// Whether the user can do anything about [knownCap].
  bool get capIsRaisable => gateway == SearchGateway.nginx;

  /// The likely ceiling, bracketed by evidence rather than asserted.
  ///
  /// Returns null when the two measurements do not actually bracket anything —
  /// a cut-off earlier than the longest success means the path is inconsistent,
  /// and naming a number from that would be worse than naming none.
  Duration? get likelyCeiling {
    final cutoff = earliestCutoff;
    if (cutoff == null) return null;
    final longest = longestSuccess;
    if (longest != null && longest >= cutoff) return null;
    return cutoff;
  }

  SearchHeadroom recordSuccess(Duration elapsed) {
    final longest = longestSuccess == null || elapsed > longestSuccess!
        ? elapsed
        : longestSuccess;
    return SearchHeadroom(
      gateway: gateway,
      gatewayName: gatewayName,
      longestSuccess: longest,
      earliestCutoff: earliestCutoff,
      recentDurations: [
        elapsed,
        ...recentDurations,
      ].take(maxRecent).toList(growable: false),
    );
  }

  /// Records a cut-off. Keeps the **earliest** one, because the ceiling is where
  /// the path first refuses, not where it happened to refuse last.
  SearchHeadroom recordCutoff(Duration elapsed) {
    final earliest = earliestCutoff == null || elapsed < earliestCutoff!
        ? elapsed
        : earliestCutoff;
    return SearchHeadroom(
      gateway: gateway,
      gatewayName: gatewayName,
      longestSuccess: longestSuccess,
      earliestCutoff: earliest,
      recentDurations: recentDurations,
    );
  }

  SearchHeadroom withGateway(SearchGateway gateway, {String? name}) {
    return SearchHeadroom(
      gateway: gateway,
      gatewayName: name,
      longestSuccess: longestSuccess,
      earliestCutoff: earliestCutoff,
      recentDurations: recentDurations,
    );
  }

  Map<String, dynamic> toJson() => {
    if (gateway != null) 'gateway': gateway!.name,
    if (gatewayName != null) 'gatewayName': gatewayName,
    if (longestSuccess != null) 'longestMs': longestSuccess!.inMilliseconds,
    if (earliestCutoff != null) 'cutoffMs': earliestCutoff!.inMilliseconds,
    'recentMs': recentDurations
        .map((d) => d.inMilliseconds)
        .toList(growable: false),
  };

  static SearchHeadroom fromJson(Map<String, dynamic> json) {
    SearchGateway? gateway;
    final raw = json['gateway'];
    if (raw is String) {
      for (final value in SearchGateway.values) {
        if (value.name == raw) gateway = value;
      }
    }
    return SearchHeadroom(
      gateway: gateway,
      gatewayName: json['gatewayName'] as String?,
      longestSuccess: json['longestMs'] is int
          ? Duration(milliseconds: json['longestMs'] as int)
          : null,
      earliestCutoff: json['cutoffMs'] is int
          ? Duration(milliseconds: json['cutoffMs'] as int)
          : null,
      recentDurations: (json['recentMs'] as List<dynamic>? ?? const [])
          .whereType<int>()
          .map((ms) => Duration(milliseconds: ms))
          .toList(growable: false),
    );
  }
}

/// Classifies an intermediary from what the response said about itself.
///
/// Header-based rather than probe-based: nothing here asks the server to be slow,
/// so the check costs one ordinary request and cannot be mistaken for load.
SearchGateway classifyGateway(String? serverHeader, {bool hasCfRay = false}) {
  if (hasCfRay) return SearchGateway.cloudflare;
  final server = serverHeader?.toLowerCase();
  if (server == null || server.isEmpty) return SearchGateway.direct;
  if (server.contains('cloudflare')) return SearchGateway.cloudflare;
  if (server.contains('nginx')) return SearchGateway.nginx;
  return SearchGateway.other;
}
