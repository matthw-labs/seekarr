import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/release_search/domain/release_search_headroom.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_headroom_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// How much room this instance's path leaves for a long search.
///
/// The ceiling is a property of **one instance's path**, not of the app: a stack
/// can easily have Sonarr behind a proxy and Radarr direct over Tailscale. So the
/// card lives beside that service's connection, and everything on it is either
/// read from the response's own headers or measured from the user's real searches
/// — never guessed, and never sent anywhere.
class SearchHeadroomCard extends ConsumerStatefulWidget {
  const SearchHeadroomCard({super.key, required this.service});

  final ServiceKey service;

  /// Only the services that actually have interactive release search.
  static bool appliesTo(ServiceKey service) =>
      service == ServiceKey.sonarr ||
      service == ServiceKey.radarr ||
      service == ServiceKey.lidarr;

  @override
  ConsumerState<SearchHeadroomCard> createState() => _SearchHeadroomCardState();
}

class _SearchHeadroomCardState extends ConsumerState<SearchHeadroomCard> {
  bool _checking = false;

  Future<void> _runCheck() async {
    HapticFeedback.selectionClick();
    setState(() => _checking = true);
    try {
      await ref.read(headroomProbeProvider)(widget.service);
    } catch (e) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          "Couldn't reach ${widget.service.title} to check the path.",
          detail: e,
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headroom = ref.watch(serviceHeadroomProvider(widget.service));

    return AppCard.surfaceOutlined(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Neutral, not `warning`: on Radarr's screen the room is lit by an
              // accent byte-identical to the warning tone, and a status colour
              // indistinguishable from the room's own light carries nothing.
              Icon(
                Icons.speed_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Search headroom',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: _checking ? null : _runCheck,
                child: Text(_checking ? 'Checking…' : 'Run check'),
              ),
            ],
          ),
          Text(
            _verdict(headroom),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurface,
              height: 1.5,
            ),
          ),
          if (_advice(headroom) != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _advice(headroom)!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
          if (_reachLimitText != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _reachLimitText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
          if (_hasEvidence(headroom)) ...[
            const SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.6,
                ),
                children: [
                  const TextSpan(text: 'From your own searches: '),
                  ..._evidence(context, headroom),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Measured on this device. Nothing is sent anywhere.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant.withValues(alpha: 0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The path's timeout is one property of *this instance's path* (the
  /// class's own thesis, above); why the search cannot leave the app is
  /// another, and it belongs on the same card for the same reason.
  ///
  /// Derived from the reach rather than from either fact directly, so the two
  /// instance-specific reasons — a certificate trusted only inside Seekarr, and
  /// a cleartext origin the background path must not carry an API key over —
  /// cannot drift apart from the transport actually chosen.
  ///
  /// Names what removes as well as what limits: on Android the 9-minute
  /// WorkManager ceiling stops applying at all, since it only governs the
  /// background path this instance cannot use.
  String? get _reachLimitText {
    final reach = ref.watch(releaseSearchReachProvider(widget.service));
    final title = widget.service.title;
    final noCeiling = defaultTargetPlatform == TargetPlatform.android
        ? " — there's no minute ceiling either way, since that only applies to "
              'the background path this instance cannot use'
        : '';

    return switch (reach) {
      ReleaseSearchReach.beyondTheApp || ReleaseSearchReach.whileOpen => null,
      ReleaseSearchReach.whileOpenTrustedCert =>
        '$title uses a certificate trusted only inside Seekarr, so this '
            'search runs while Seekarr stays open instead of in the '
            'background$noCeiling. Installing the certificate on this device '
            'restores it.',
      ReleaseSearchReach.whileOpenCleartext =>
        '$title is reached over plain http, so this search runs while Seekarr '
            'stays open instead of in the background$noCeiling. A background '
            'search cannot refuse a redirect, and over http anyone on the '
            "network can inject one to collect $title's API key. Switching "
            'this instance to https restores it.',
    };
  }

  bool _hasEvidence(SearchHeadroom h) =>
      h.longestSuccess != null || h.earliestCutoff != null;

  String _verdict(SearchHeadroom h) {
    return switch (h.gateway) {
      null =>
        'Run the check to see what sits between Seekarr and '
            '${widget.service.title}, and what it allows.',
      SearchGateway.direct =>
        'Direct connection — nothing between you and '
            '${widget.service.title}, so no gateway timeout applies.',
      SearchGateway.cloudflare =>
        'This path goes through Cloudflare, which cuts a request off at 100 '
            'seconds.',
      SearchGateway.nginx =>
        'This path goes through nginx — Nginx Proxy Manager is built on it — '
            'which allows 60 seconds by default.',
      SearchGateway.other =>
        'Something answers in front of ${widget.service.title}'
            '${h.gatewayName == null ? '' : ' (${h.gatewayName})'}. Its timeout '
            'is whatever it is configured with.',
    };
  }

  String? _advice(SearchHeadroom h) {
    return switch (h.gateway) {
      SearchGateway.cloudflare =>
        'That limit cannot be raised on a free plan. Reach this instance over '
            'Tailscale or your LAN for long searches.',
      SearchGateway.nginx =>
        'You can raise it per proxy host, in that host\'s advanced settings.',
      SearchGateway.other =>
        'If long searches keep getting cut off, raise its read timeout — or '
            'reach the instance directly.',
      _ => null,
    };
  }

  List<InlineSpan> _evidence(BuildContext context, SearchHeadroom h) {
    final theme = Theme.of(context);
    final figure = theme.textTheme.bodySmall?.tabular.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final spans = <InlineSpan>[];

    if (h.longestSuccess != null) {
      spans
        ..add(const TextSpan(text: 'longest that completed '))
        ..add(TextSpan(text: _short(h.longestSuccess!), style: figure));
    }
    if (h.earliestCutoff != null) {
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' · '));
      spans
        ..add(const TextSpan(text: 'earliest cut-off seen '))
        ..add(TextSpan(text: _short(h.earliestCutoff!), style: figure));
    }
    final ceiling = h.likelyCeiling;
    if (ceiling != null) {
      spans
        ..add(const TextSpan(text: ' → likely ceiling around '))
        ..add(TextSpan(text: _short(ceiling), style: figure));
    }
    return spans;
  }

  String _short(Duration d) {
    if (d.inMinutes == 0) return '${d.inSeconds}s';
    final seconds = d.inSeconds % 60;
    return seconds == 0
        ? '${d.inMinutes}m'
        : '${d.inMinutes}:${seconds.toString().padLeft(2, '0')}';
  }
}
