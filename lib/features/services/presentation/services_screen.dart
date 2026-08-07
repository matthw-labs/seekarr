import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_alert_band.dart';
import 'package:cupola/features/services/presentation/services_dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    ref.listen<int>(navigationRefreshProvider(NavigationSection.services), (
      previous,
      next,
    ) {
      _invalidateServicesDashboard(ref);
    });

    final settings = ref.watch(currentSettingsProvider);
    final allUnconfigured = ServiceKey.values.every(
      (s) => !settings.isServiceConfigured(s),
    );

    return AmbientScaffold(
      // No accent passed: the room on this screen is lit by the brand primary.
      // Thirteen service accents cannot light one room, so identity is confined
      // to each matrix cell's icon tile — see the Room Light Rule's one
      // documented exception in DESIGN.md.
      appBar: const GlassAppBar(title: Text('Services')),
      body: allUnconfigured
          // The page owns the viewport, not the empty state — see the contract
          // on `AppEmptyState`. Its height is entirely text, and at an
          // accessibility reading size a 72pt icon well, a wrapped title, a
          // two-line message and a button clear a short phone, taking the only
          // button on the screen with them. The `minHeight` keeps it centred
          // while it fits, so nothing moves at the default reading size.
          //
          // Default physics deliberately: there is no `RefreshIndicator` on this
          // branch, because with nothing configured there is nothing to re-fetch
          // — the screen rebuilds off settings.
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  // The nav bar floats *over* this branch, so centring in the
                  // full viewport puts the optical centre behind it and the
                  // block reads low. Reserving the clearance inside the centring
                  // box is what lifts it back onto the visible middle.
                  child: Padding(
                    padding: EdgeInsets.only(bottom: bottomPadding),
                    child: _ServicesEmptyState(
                      onSetUpServices: () => context.go('/settings/services'),
                    ),
                  ),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () => _refreshServicesDashboard(ref),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: bottomPadding),
                // Static in every state. What needs your hand comes before what
                // is happening on its own, which comes before browsing:
                //
                //  * the band is absent unless something stopped answering
                //  * the matrix is the instrument — health, launcher and live
                //    metrics in one object
                //  * In Flight is time-sensitive, so it is second rather than
                //    last, where it used to sit under three browse rails
                //  * Requests never filters and never renders empty by design;
                //    pending sorts to the top with its actions attached
                //  * Recently Added is the only browsing region left
                children: const [
                  ServicesAlertBand(),
                  ServiceMatrix(),
                  ServicesInFlightSection(),
                  ServicesRequestsSection(),
                  ServicesRecentlyAddedSection(),
                ],
              ),
            ),
    );
  }
}

/// The ring at rest, and the claim it makes.
///
/// This is the same object onboarding opens with, which is what makes "Skip for
/// now" cost nothing: the promise persists as the empty state instead of
/// evaporating into a grey placeholder, and the button leads back into the same
/// pick step. Deliberately *not* [AppEmptyState] — that widget is for a region
/// that came up empty, and this screen is the product's front door on a first
/// run.
class _ServicesEmptyState extends StatelessWidget {
  const _ServicesEmptyState({required this.onSetUpServices});
  final VoidCallback onSetUpServices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ServiceRing(
            states: const {},
            diameter: serviceRingDiameter(context, preferred: 268),
            spin: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Nothing answers yet.',
            style: theme.textTheme.titleLarge!
                .weight(FontWeight.w700)
                .copyWith(color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${ServiceKey.values.length} services are waiting for an address. '
            'Light one up and this screen fills in.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            onPressed: onSetUpServices,
            child: const Text('Pick your services'),
          ),
        ],
      ),
    );
  }
}

/// Pull-to-refresh: drop everything the screen shows, then hold the spinner
/// until the slowest of it has actually come back.
///
/// `onRefresh` used to be `() async => _invalidateServicesDashboard(ref)`, whose
/// future completes on the same microtask — so the indicator retracted while
/// thirteen summaries and three merged lists were still in flight. A control-room
/// screen that says "done" before it has re-read anything is worse than one with
/// no refresh: the user reads the stale figure as the fresh one.
///
/// Failures are swallowed rather than propagated. Every source here already
/// degrades to `[]`/offline and paints its own state; letting one rejection out
/// would abort `Future.wait` and retract the spinner early — the exact bug being
/// fixed, restored by the unhappy path.
Future<void> _refreshServicesDashboard(WidgetRef ref) async {
  _invalidateServicesDashboard(ref);

  Future<void> settle(Future<Object?> pending) async {
    try {
      await pending;
    } catch (_) {}
  }

  await Future.wait([
    for (final service in ServiceKey.values)
      settle(ref.read(serviceSummaryProvider(service).future)),
    settle(ref.read(servicesQueueProvider.future)),
    settle(ref.read(servicesRequestsProvider.future)),
    settle(ref.read(servicesRecentlyAddedProvider.future)),
  ]);
}

void _invalidateServicesDashboard(WidgetRef ref) {
  for (final service in ServiceKey.values) {
    ref.invalidate(serviceSummaryProvider(service));
    // The matrix's live line is the reason to pull-to-refresh this screen, and
    // it was the one thing refresh did not touch: the KPI providers were only
    // ever invalidated from the individual service pages.
    ref.invalidate(serviceKpiProvider(service));
    ref.invalidate(serviceSignalProvider(service));
  }
  ref.invalidate(servicesRequestsProvider);
  ref.invalidate(servicesRecentlyAddedProvider);
  ref.invalidate(servicesQueueProvider);
  // The library providers the merged rail and the KPIs read through. Invalidated
  // by name rather than relying on the aliases above, which no longer have a
  // section of their own since the two per-service rails merged.
  ref.invalidate(servicesMoviesProvider);
  ref.invalidate(servicesSeriesProvider);
  ref.invalidate(servicesMusicProvider);
}
