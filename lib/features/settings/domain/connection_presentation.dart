import 'package:flutter/material.dart';

import 'package:seekarr/core/network/connection_failure.dart';
import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// A connection state resolved into everything the UI needs to render it: a
/// tone from the closed vocabulary, a glyph, and words.
///
/// Resolved here rather than inside the rows and banners that draw it, so the
/// settings home, the connections list and the service form cannot describe the
/// same failure three different ways.
class ConnectionPresentation {
  const ConnectionPresentation({
    required this.tone,
    required this.icon,
    required this.label,
    required this.needsAttention,
  });

  /// From the shared [StatusTone] vocabulary; resolve to a colour with
  /// `statusToneColor`.
  final StatusTone tone;

  final IconData icon;

  /// A few words naming the state, short enough for a list row.
  final String label;

  /// Whether this state is worth promoting to the user. False for healthy and
  /// for never-configured services — the settings home stays quiet unless
  /// something is actually wrong.
  final bool needsAttention;
}

/// Describes a connection state for [service].
///
/// The split between `warning` and `error` is triage, not decoration: amber
/// means the server answered and the credentials or the path are wrong — fixable
/// in the form — while red means nothing answered at all.
ConnectionPresentation describeConnection(
  ServiceKey service, {
  required ServiceConnectionStatus status,
  ServiceFailureReason? reason,
}) {
  switch (status) {
    case ServiceConnectionStatus.notConfigured:
      return const ConnectionPresentation(
        tone: StatusTone.neutral,
        icon: Icons.add_link_rounded,
        label: 'Not set up',
        needsAttention: false,
      );
    case ServiceConnectionStatus.checking:
      return const ConnectionPresentation(
        tone: StatusTone.neutral,
        icon: Icons.cloud_sync_rounded,
        label: 'Checking',
        needsAttention: false,
      );
    case ServiceConnectionStatus.connected:
      return const ConnectionPresentation(
        tone: StatusTone.success,
        icon: Icons.cloud_done_rounded,
        label: 'Connected',
        needsAttention: false,
      );
    case ServiceConnectionStatus.disconnected:
      return switch (reason) {
        ServiceFailureReason.unauthorized => ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.key_off_rounded,
          label: service.usesApiKey ? 'API key rejected' : 'Sign-in rejected',
          needsAttention: true,
        ),
        ServiceFailureReason.notFound => const ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.wrong_location_rounded,
          label: 'API not at this address',
          needsAttention: true,
        ),
        ServiceFailureReason.tls => const ConnectionPresentation(
          tone: StatusTone.warning,
          icon: Icons.gpp_bad_rounded,
          label: 'Certificate not trusted',
          needsAttention: true,
        ),
        ServiceFailureReason.timeout => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.timer_off_rounded,
          label: 'Timed out',
          needsAttention: true,
        ),
        ServiceFailureReason.serverError => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.report_gmailerrorred_rounded,
          label: 'Answered with an error',
          needsAttention: true,
        ),
        ServiceFailureReason.unreachable ||
        ServiceFailureReason.unknown ||
        null => const ConnectionPresentation(
          tone: StatusTone.error,
          icon: Icons.cloud_off_rounded,
          label: 'Unreachable',
          needsAttention: true,
        ),
      };
  }
}
