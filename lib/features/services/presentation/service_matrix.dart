/// The stack matrix: the instrument at the top of `/services`.
///
/// One cell per configured service, answering three questions at once —
/// *is it reachable* (the pip and the state word), *what is it doing* (the live
/// line), and *take me there* (the whole cell is the button). That is why this
/// replaced a status grid and a separate feed: they were the same three
/// questions asked in three places.
///
/// Lives in the feature rather than in `lib/core/widgets/` because it is the
/// anatomy of exactly one screen. Project convention reserves `core/widgets` for
/// genuinely reusable components, and a matrix cell that hard-codes the
/// `/services/{key}` destination is not one.
///
/// ## Why there is no horizontal scroll here
///
/// The grid this replaced laid 13 services out in two rows scrolling sideways,
/// column-major, sized so the next card was clipped at 80% as a scroll hint.
/// Three things were wrong with that and all three are load-bearing for the
/// design: reading order ran top-left, bottom-left, top-right, so the grid had
/// to be decoded rather than scanned; the page scrolls vertically while the
/// primary readout scrolled horizontally, so the first two gestures fought; and
/// the single cell that matters — the one that is down — had an even chance of
/// being off-screen. A health readout you have to swipe to finish is not one.
///
/// ## Why the cell is quiet
///
/// The first version of this cell packed identity, a figure, a metric word and a
/// host into 168×96pt, and bought the hierarchy that space could not give it with
/// weight: an 800-weight `titleMedium` figure beside an uppercase eyebrow tracked
/// out to +1.4. One cell reads well. Thirteen of them are a wall of shouting,
/// and DESIGN.md's own Eyebrow Rule says why — the eyebrow "earns its emphasis
/// by being rare", and a grid is the definition of not rare.
///
/// So emphasis is now scarce and earned. A healthy service is plain body text on
/// a plain card; tone, weight and the metric's icon arrive only when
/// [ServiceSignal.needsAttention]. In a stack where nothing is wrong there is
/// nothing on this screen that shouts, which is what makes the one amber cell
/// findable at a glance.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/shimmer_placeholder.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/services/domain/service_signal.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/service_matrix_collapse_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Reachability of one service, as the matrix paints it.
///
/// `checking` is a state of its own rather than "offline with a different word".
/// The grid this replaced fabricated an offline summary while loading, which made
/// its border resolve to error red — so every service flashed as failed on cold
/// open, before a single request had come back.
enum ServiceReachability { online, checking, offline }

/// Layout constants for the matrix grid.
class ServiceMatrixMetrics {
  ServiceMatrixMetrics._();

  /// Preferred cell width. Columns are resolved against this, not declared.
  static const double preferredCellWidth = 168;

  /// Minimum columns, per the Column Floor Rule: the count is a floor, and a
  /// single-column matrix would read as a list of unrelated rows rather than as
  /// one instrument.
  static const int minColumns = 2;

  /// Gap between cells, both axes.
  static const double gap = AppSpacing.sm;

  /// The identity mark inside an expanded cell — the one place on `/services`
  /// where a service accent appears.
  static const double identityTileSize = 28;

  /// The identity mark inside a folded band's strip. Smaller because a dozen of
  /// them sit on one line, and it carries no text beside it.
  static const double collapsedIdentityTileSize = 24;

  /// Cell height before text growth: the identity tile, the live line, and the
  /// host row, plus padding.
  static const double cellBaseHeight = 92;

  /// How much of [cellBaseHeight] follows the reading size.
  ///
  /// All three lines now, not just the live line and the host: the service name
  /// moved up to `bodyMedium` — it is the cell's identity and was losing that
  /// argument to the figure — and at the 1.6x clamp a 14pt line no longer fits
  /// inside the identity tile's height the way a 12pt one did. Counting it here
  /// is what keeps the header row from pushing the host off the bottom.
  static const double cellTextHeight = 50;

  /// Columns that fit [availableWidth], never fewer than [minColumns].
  static int resolveColumns(double availableWidth) {
    final fit = ((availableWidth + gap) / (preferredCellWidth + gap)).floor();
    return fit < minColumns ? minColumns : fit;
  }
}

/// The whole matrix: domain bands of cells, then the unconfigured affordance.
class ServiceMatrix extends ConsumerWidget {
  const ServiceMatrix({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    if (configured.isEmpty) return const SizedBox.shrink();

    final collapsed = ref.watch(collapsedServiceDomainsProvider);

    final bands = <Widget>[];
    for (final domain in ServiceDomain.values) {
      final services = domain.services
          .where(settings.isServiceConfigured)
          .toList(growable: false);
      if (services.isEmpty) continue;

      bands.add(
        _DomainBand(
          domain: domain,
          services: services,
          collapsed: collapsed.contains(domain),
        ),
      );
    }

    final remaining = ServiceKey.values.length - configured.length;
    if (remaining > 0) {
      bands.add(
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.md,
          ),
          child: _UnconfiguredCell(count: remaining),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: bands,
    );
  }
}

/// One domain of the matrix: a foldable header over its grid of cells.
///
/// The fold exists because thirteen services is a lot of instrument to scroll
/// past on the way to Downloading, and which third of the stack you actually
/// watch is personal. Its state is persisted, not per-visit — see
/// [collapsedServiceDomainsProvider].
///
/// Collapsing genuinely removes the cells from the tree rather than hiding them.
/// That is the difference between this and `CollapsibleDomainSection`, whose
/// `AnimatedCrossFade` keeps both children built: a folded band there would still
/// watch [serviceSignalProvider] for every service in it, fanning out a library
/// fetch per hidden cell on every refresh to paint nothing. Hence the local
/// implementation instead of the shared widget.
class _DomainBand extends ConsumerWidget {
  const _DomainBand({
    required this.domain,
    required this.services,
    required this.collapsed,
  });

  final ServiceDomain domain;
  final List<ServiceKey> services;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion ? Duration.zero : AppAnimation.durationSm;

    // Read only while folded: expanded, every cell already watches its own
    // summary, and this would add a second subscription per service for a
    // sentence nobody hears.
    final offlineTitles = collapsed
        ? services
              .where(
                (service) =>
                    ref
                        .watch(serviceSummaryProvider(service))
                        .asData
                        ?.value
                        .isOnline ==
                    false,
              )
              .map((service) => service.title)
              .toList(growable: false)
        : const <String>[];

    void toggle() {
      HapticFeedback.selectionClick();
      ref.read(collapsedServiceDomainsProvider.notifier).toggle(domain);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `expanded:` rather than an announcement on toggle: the platform speaks
        // the change off the node update, it works on TalkBack where
        // announcements are dropped, and the state stays discoverable on
        // re-focus instead of only at the moment of the tap. Same contract as
        // `CollapsibleDomainSection`.
        Semantics(
          container: true,
          explicitChildNodes: true,
          header: true,
          button: true,
          expanded: !collapsed,
          // The un-uppercased label: `.toUpperCase()` is typography, and
          // VoiceOver spells out all-caps tokens it does not recognise.
          label: domain.label,
          value: collapsed
              ? serviceDomainBandValue(
                  serviceCount: services.length,
                  offlineServiceTitles: offlineTitles,
                )
              : null,
          hint: collapsed ? 'expands this group' : 'collapses this group',
          onTap: toggle,
          child: InkWell(
            onTap: toggle,
            excludeFromSemantics: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                collapsed ? AppSpacing.md : AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    // 48dp on Android also clears the 44pt iOS floor, and the
                    // header's own content is a 20pt glyph and a label — well
                    // under either on its own.
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        // The rotation is the visual expand cue; `expanded:`
                        // above is the audible one.
                        AnimatedRotation(
                          turns: collapsed ? 0.0 : 0.25,
                          duration: duration,
                          curve: AppAnimation.emphasizedCurve,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            domain.label.toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (collapsed) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Padding(
                      // Lines the strip up under the label rather than under the
                      // chevron.
                      padding: const EdgeInsets.only(left: 20 + AppSpacing.xs),
                      child: _CollapsedIdentityStrip(services: services),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        // Zero-height when folded, so the cells — and their KPI subscriptions —
        // are not in the tree at all.
        AnimatedSize(
          duration: duration,
          curve: AppAnimation.emphasizedCurve,
          alignment: Alignment.topCenter,
          child: collapsed
              ? const SizedBox(width: double.infinity)
              : _ServiceMatrixBand(services: services),
        ),
      ],
    );
  }
}

/// What a folded band shows in place of its cells: one identity mark per
/// service, unlit when that service is not answering.
///
/// It keeps the fold honest. A band that collapsed to a bare word would hide
/// exactly the fact the matrix exists to publish, so folding would trade the
/// instrument for the space — and the user would stop folding. This way the
/// strip still answers "is anything dark in here" without spending a row of
/// cells on it, and health stays a brightness step rather than a hue, the same
/// way an offline cell recedes instead of turning red.
class _CollapsedIdentityStrip extends ConsumerWidget {
  const _CollapsedIdentityStrip({required this.services});

  final List<ServiceKey> services;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExcludeSemantics(
      // Every tile here is a glyph with no text; the band's own spoken value
      // carries what they mean.
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final service in services)
            _IdentityTile(
              service: service,
              size: ServiceMatrixMetrics.collapsedIdentityTileSize,
              iconSize: 14,
              lit:
                  ref
                      .watch(serviceSummaryProvider(service))
                      .asData
                      ?.value
                      .isOnline ??
                  // Still checking: lit, because an unlit tile is a claim that
                  // the service is dark and no request has come back yet.
                  true,
            ),
        ],
      ),
    );
  }
}

/// The service accent's one appearance on `/services`, at two sizes.
///
/// Drained rather than recoloured when unlit: an offline service loses its
/// colour, it does not acquire a different one. Health has nowhere to hide in a
/// hue on a screen with thirteen of them — Radarr's amber, Prowlarr's orange,
/// Readarr's brick and the error red all sit in the same neighbourhood — and a
/// brightness step survives colour blindness, which a red border does not.
class _IdentityTile extends StatelessWidget {
  const _IdentityTile({
    required this.service,
    required this.size,
    required this.iconSize,
    required this.lit,
  });

  final ServiceKey service;
  final double size;
  final double iconSize;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: lit
            ? service.accent.withValues(alpha: 0.14)
            : colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Icon(
        service.icon,
        size: iconSize,
        color: lit ? service.accent : colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// One domain's services, wrapped into rows of equal-width cells.
///
/// Built as a `Column` of `Row`s rather than a `GridView` because the matrix
/// sits inside the page's own scroll view: a nested scrollable would need
/// shrink-wrapping and physics juggling to behave, for a grid that never
/// scrolls on its own.
class _ServiceMatrixBand extends StatelessWidget {
  const _ServiceMatrixBand({required this.services});

  final List<ServiceKey> services;

  @override
  Widget build(BuildContext context) {
    final cellHeight = TextScaleMetrics.boxHeight(
      context,
      base: ServiceMatrixMetrics.cellBaseHeight,
      textHeight: ServiceMatrixMetrics.cellTextHeight,
    );

    // The box grew by the clamped scale, so the text has to be laid out at the
    // same clamp or the two disagree: `boxHeight` stops growing at 1.6x by
    // design — "compact chrome ellipsises rather than clipping" — but a `Text`
    // reads the ambient scaler, so at 3x the cell would be sized for 1.6 and
    // painted at 3. That is the overflow stripe, not an ellipsis. Same
    // `MediaQuery` clamp the floating nav bar uses to stay a bar.
    final clamped = TextScaleMetrics.clampedScalerOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = ServiceMatrixMetrics.resolveColumns(
            constraints.maxWidth,
          );
          final rows = <Widget>[];

          for (var start = 0; start < services.length; start += columns) {
            final slice = services.skip(start).take(columns).toList();
            rows.add(
              Padding(
                padding: EdgeInsets.only(
                  bottom: start + columns < services.length
                      ? ServiceMatrixMetrics.gap
                      : 0,
                ),
                child: SizedBox(
                  height: cellHeight,
                  child: Row(
                    children: [
                      for (var index = 0; index < columns; index++) ...[
                        if (index > 0)
                          const SizedBox(width: ServiceMatrixMetrics.gap),
                        // The last row is padded with empty flex rather than
                        // letting three cells stretch across four columns: a
                        // matrix whose bottom row is wider than the rest reads
                        // as a different component.
                        Expanded(
                          child: index < slice.length
                              ? ServiceMatrixCell(service: slice[index])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }

          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: clamped),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          );
        },
      ),
    );
  }
}

/// One service: identity, reachability, live figure, host.
class ServiceMatrixCell extends ConsumerWidget {
  const ServiceMatrixCell({super.key, required this.service});

  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(serviceSummaryProvider(service));
    final settings = ref.watch(currentSettingsProvider);

    final reachability = switch (summary) {
      AsyncData(:final value) =>
        value.isOnline
            ? ServiceReachability.online
            : ServiceReachability.offline,
      AsyncError() => ServiceReachability.offline,
      _ => ServiceReachability.checking,
    };

    // Falls back to the configured URL's host so the cell can name which
    // instance it is talking about before the first response arrives.
    final host =
        summary.asData?.value.host ??
        service.extractHost(settings.urlFor(service)) ??
        '';

    // Only asked for once the service has answered. Watching it while offline
    // would fan out a library fetch per unreachable service on every rebuild,
    // and there is nothing to paint with the result.
    final signal = reachability == ServiceReachability.online
        ? ref.watch(serviceSignalProvider(service)).asData?.value
        : null;

    return _ServiceMatrixCellBody(
      service: service,
      reachability: reachability,
      signal: signal,
      host: host,
    );
  }
}

/// The painted cell, split from the provider reads so every state is reachable
/// by passing values in rather than by staging a container.
class _ServiceMatrixCellBody extends StatelessWidget {
  const _ServiceMatrixCellBody({
    required this.service,
    required this.reachability,
    required this.signal,
    required this.host,
  });

  final ServiceKey service;
  final ServiceReachability reachability;
  final ServiceSignal? signal;
  final String host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline = reachability == ServiceReachability.online;
    // An unreachable service recedes instead of changing colour: the surface
    // steps *down* the ladder so the cell reads as unlit. Health has nowhere to
    // hide in a hue — see the Room Light note in DESIGN.md — and a brightness
    // step survives colour blindness, which a red border does not.
    final surface = isOnline
        ? colorScheme.surfaceContainer
        : colorScheme.surfaceContainerLow;

    final statusLabel = switch (reachability) {
      ServiceReachability.online => 'Online',
      ServiceReachability.checking => 'Checking',
      ServiceReachability.offline => 'Offline',
    };

    return AppCard.surfaceOutlined(
      key: ValueKey('service-matrix-cell-${service.routeParam}'),
      onTap: () => context.push('/services/${service.routeParam}'),
      semanticLabel: service.title,
      semanticValue: serviceMatrixCellValue(
        statusLabel: statusLabel,
        signalSpoken: signal?.spoken,
        host: host,
      ),
      // Nothing inside is separately interactive, and every visible fragment is
      // already in the composed value above.
      excludeChildSemantics: true,
      backgroundColor: surface,
      borderRadius: AppRadius.borderRadiusLg,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _CellHeader(service: service, reachability: reachability),
          _CellLiveLine(
            reachability: reachability,
            signal: signal,
            statusLabel: statusLabel,
            surface: surface,
          ),
          if (host.isNotEmpty)
            Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                // A step dimmer than the metric word above it. The host is the
                // cell's least urgent line — it disambiguates two instances of
                // one service and is otherwise something you already know — so
                // it should be the first thing the eye skips.
                color:
                    theme.extension<SeekarrThemeColors>()?.dimText ??
                    colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

/// Identity tile, name, and the reachability pip.
class _CellHeader extends StatelessWidget {
  const _CellHeader({required this.service, required this.reachability});

  final ServiceKey service;
  final ServiceReachability reachability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isOnline = reachability == ServiceReachability.online;

    return Row(
      children: [
        // The one place a service accent appears on this screen. Thirteen
        // accents cannot light one room, so identity is confined to this mark
        // and health is not allowed to borrow it.
        _IdentityTile(
          service: service,
          size: ServiceMatrixMetrics.identityTileSize,
          iconSize: 16,
          lit: isOnline,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            service.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // The cell's primary. It was `bodySmall` at 700 — a size below the
            // figure and heavier than it needed to be, so the service's own name
            // lost the hierarchy argument to a number that changes hourly.
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isOnline
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (!isOnline) ...[
          const SizedBox(width: AppSpacing.xs),
          _ReachabilityPip(reachability: reachability),
        ],
      ],
    );
  }
}

/// A 6pt dot, on the cells that are not answering. Reinforcement only — never
/// the sole carrier of the state, which [_CellLiveLine] always spells out.
///
/// Deliberately absent when a service is online. A green pip on every healthy
/// cell is a mark that is present on almost every open, and a mark that is
/// always the same is one nobody reads on the day it changes — the same argument
/// `ServicesAlertBand` makes for rendering nothing when the stack is healthy.
/// Twelve green dots were also competing with the one amber figure that had
/// something to say.
class _ReachabilityPip extends StatelessWidget {
  const _ReachabilityPip({required this.reachability});

  final ServiceReachability reachability;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = switch (reachability) {
      ServiceReachability.online => AppColors.success,
      ServiceReachability.checking => AppColors.warning,
      ServiceReachability.offline => colorScheme.error,
    };

    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The row that carries the live figure when the service is up, and the state
/// word when it is not.
///
/// One slot for both is the point. The old card spent a row on `ONLINE` next to
/// a green dot saying the same thing, and spent the row below it on a library
/// total that does not change from one week to the next — so the only genuinely
/// live line on a control-room screen was chrome.
class _CellLiveLine extends StatelessWidget {
  const _CellLiveLine({
    required this.reachability,
    required this.signal,
    required this.statusLabel,
    required this.surface,
  });

  final ServiceReachability reachability;
  final ServiceSignal? signal;
  final String statusLabel;

  /// The cell's own background, which is what a tone-coloured word here is
  /// measured against. An offline cell sits a step lower on the surface ladder,
  /// so it is not the same composite as an online one.
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (reachability != ServiceReachability.online) {
      return Text(
        statusLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          // Through `onTint` even though there is no tint here: `tintAlpha: 0`
          // makes the composite the surface itself, and the same lightness walk
          // that saves a label over a tint is what keeps the saturated amber
          // legible on a light card. Painting `AppColors.warning` raw would
          // measure about 2:1 against `surface-light`.
          color: ServiceTheme.onTint(
            statusToneColor(
              colorScheme,
              reachability == ServiceReachability.checking
                  ? StatusTone.warning
                  : StatusTone.error,
            ),
            surface: surface,
            tintAlpha: 0,
          ),
        ),
      );
    }

    final current = signal;
    if (current == null) {
      // Reachable, metric still in flight. A shimmer says "coming"; blank space
      // would say "nothing to report", which is a different fact.
      return ShimmerPlaceholder.text(width: 64);
    }

    final needsAttention = current.needsAttention;
    final toneColor = needsAttention
        ? ServiceTheme.onTint(
            statusToneColor(colorScheme, current.tone),
            surface: surface,
            tintAlpha: 0,
          )
        : colorScheme.onSurface;

    return Row(
      children: [
        // Only when the figure is asking for something. On a healthy service the
        // glyph restates the metric word beside it, and thirteen of them turned
        // the grid into a sheet of pictograms.
        if (needsAttention) ...[
          Icon(current.icon, size: 13, color: toneColor),
          const SizedBox(width: AppSpacing.xs),
        ],
        // One text run, not two `Text`s in a `Row`. Two of them cannot both be
        // right: unflexed, a wide figure has no way to shrink — a transfer rate
        // is service-supplied and `1023.9 KB/s` at the band's 1.6x clamp is
        // wider on its own than the 143pt a two-column cell has on a 375pt
        // phone, which is an overflow stripe rather than an ellipsis. Made
        // flexible instead, Flutter splits the free space by flex factor and
        // never hands the remainder back, so `12 missing` elided to "12 missi…"
        // at the *default* reading size with room to spare.
        //
        // A single line with two spans has neither problem: the figure keeps its
        // own weight, colour and tabular figures, and the ellipsis lands where
        // it should — in the word, which is the recoverable half.
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: current.value,
                  // `bodyMedium`/700, down from `titleMedium`/800. It is still
                  // the only tabular, only bold thing on the cell, which is
                  // enough to find it — one weight step, not two sizes and a
                  // colour.
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: toneColor,
                    // The figure updates in place; proportional digits make it
                    // jitter.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // Absent when the value is already a state word — "Paused"
                // needs no "status" after it. See `ServiceSignal.label`.
                if (current.label.isNotEmpty)
                  TextSpan(
                    text: ' ${current.label}',
                    // Plain body, not `AppTheme.eyebrow`. The Eyebrow Rule stops
                    // at repetition: "the eyebrow earns its emphasis by being
                    // rare", and one per cell across a thirteen-cell grid is the
                    // "eyebrow everywhere" noise the style exists to avoid.
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// The tail of the matrix: how many services are still unconfigured.
///
/// Present so the hub can be a launcher for services you have not set up yet
/// without spending thirteen dimmed cells on the ones you never will.
class _UnconfiguredCell extends StatelessWidget {
  const _UnconfiguredCell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppCard.outlined(
      key: const ValueKey('services-unconfigured-cell'),
      onTap: () => context.go('/settings/services'),
      semanticLabel: servicesUnconfiguredCellLabel(count: count),
      excludeChildSemantics: true,
      borderColor: colorScheme.outlineVariant,
      borderRadius: AppRadius.borderRadiusLg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        // Clears the 44pt/48pt minimum target with the label at default size.
        vertical: AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          // Flexible and wrapping, not clamped and ellipsised: unlike a matrix
          // cell this affordance has no fixed height, so at an accessibility
          // reading size the right answer is to let it get taller. Truncating
          // "Set up 9 more services" is the one thing that would make it
          // useless.
          Flexible(
            child: Text(
              // The same string the screen reader gets: see
              // `servicesUnconfiguredCellLabel`.
              servicesUnconfiguredCellLabel(count: count),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
