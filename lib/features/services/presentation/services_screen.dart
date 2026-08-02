import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/providers/navigation_refresh_provider.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/service_matrix.dart';
import 'package:seekarr/features/services/presentation/services_alert_band.dart';
import 'package:seekarr/features/services/presentation/services_dashboard_sections.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

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
                  child: _ServicesEmptyState(
                    onSetUpServices: () => context.go('/settings/services'),
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

class _ServicesEmptyState extends StatelessWidget {
  const _ServicesEmptyState({required this.onSetUpServices});
  final VoidCallback onSetUpServices;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.dns_outlined,
      // "Connected" rather than "configured", because that is the word the rest
      // of this screen uses for the same state: a service that stops answering
      // "isn't answering", and the fix is a connection, not a config file.
      title: 'No services connected',
      // Says what a connection actually needs, which the title and the button do
      // not. It used to say "to start managing them from one place" — a benefit
      // pitched to someone who has already installed the app, in place of the
      // one fact that gets them past this screen.
      message:
          "Add a service's address and credentials in Settings. "
          'Seekarr talks to your instances directly.',
      action: FilledButton.icon(
        onPressed: onSetUpServices,
        icon: const Icon(Icons.settings_outlined, size: 18),
        // Same verb as the matrix's trailing cell, which goes to the same place.
        label: const Text('Set up a service'),
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
