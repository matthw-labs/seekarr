import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Which domain bands of the stack matrix the user has opened.
///
/// Persisted rather than session-scoped. Opening Infrastructure is a statement
/// about how you use the hub, not about this visit, and a fold that springs
/// back on every cold open is a control you press once and never trust again.
///
/// Stores the **expanded** set, so the default — nothing stored — is a fully
/// folded matrix. It used to store the collapsed set for the opposite default,
/// and the polarity is the whole point: with compact cards carrying a name and
/// a live figure, a folded band is no longer a hidden band, so the hub can open
/// on the short form and let the user pull open the third of the stack they
/// actually watch. The old `services_collapsed_domains` key is deliberately not
/// read — a stored collapse list means nothing once the sense is inverted, and
/// migrating it would fold open exactly the bands the user had shut.
final expandedServiceDomainsProvider =
    NotifierProvider<ExpandedServiceDomainsNotifier, Set<ServiceDomain>>(
      ExpandedServiceDomainsNotifier.new,
    );

class ExpandedServiceDomainsNotifier extends Notifier<Set<ServiceDomain>> {
  static const _key = 'services_expanded_domains';

  @override
  Set<ServiceDomain> build() {
    // Guarded so the screen still renders where SharedPreferences is not
    // provided — lightweight widget and router tests, per
    // `recentSearchesProvider`.
    try {
      final stored = ref.watch(sharedPreferencesProvider).getStringList(_key);
      if (stored == null) return const {};
      final domains = <ServiceDomain>{};
      for (final name in stored) {
        final domain = _domainNamed(name);
        if (domain != null) domains.add(domain);
      }
      return domains;
    } catch (_) {
      return const {};
    }
  }

  void toggle(ServiceDomain domain) {
    final next = state.toSet();
    // `remove` reports whether it was there, so one call decides the direction.
    if (!next.remove(domain)) next.add(domain);
    state = next;

    try {
      ref
          .read(sharedPreferencesProvider)
          .setStringList(
            _key,
            // Stored by `name` rather than by index: a reordered or extended
            // `ServiceDomain` would otherwise silently open the wrong band.
            next.map((domain) => domain.name).toList(growable: false),
          );
    } catch (_) {
      // No persistence available — the in-memory fold still works.
    }
  }
}

/// Whether the fold demo — the first band opening the screen expanded and
/// folding itself shut — has already played during this app launch.
///
/// In-memory on purpose, never persisted: the demo repeats **per launch**, not
/// per landing and not once ever. `/services` sits under a plain `ShellRoute`,
/// so entering the tab or popping out of a service dashboard remounts the
/// screen many times an hour — a per-mount demo is a page that keeps moving on
/// its own, and a persisted once-ever flag forgets that the affordance is
/// worth restating occasionally. One demonstration per process is the middle:
/// every cold open says "the bands do this", and the rest of the session
/// stays still.
final servicesFoldDemoPlayedProvider =
    NotifierProvider<ServicesFoldDemoPlayedNotifier, bool>(
      ServicesFoldDemoPlayedNotifier.new,
    );

class ServicesFoldDemoPlayedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markPlayed() => state = true;
}

/// The unconfigured-service count at which the user last dismissed the
/// "set up n more services" hint, or `-1` when they never have.
///
/// A count rather than a bool, because the hint has two different reasons to
/// appear and only one of them was dismissed. Configuring a service *lowers*
/// the remaining count, so the hint stays gone — which is what dismissing it
/// meant. A future release adding services to [ServiceKey] *raises* it above
/// the stored number, and the hint returns exactly once to say so. Settings is
/// the permanent route either way; this is only the nudge.
final dismissedMoreServicesCountProvider =
    NotifierProvider<DismissedMoreServicesCountNotifier, int>(
      DismissedMoreServicesCountNotifier.new,
    );

class DismissedMoreServicesCountNotifier extends Notifier<int> {
  static const _key = 'services_more_services_dismissed_at';

  @override
  int build() {
    try {
      return ref.watch(sharedPreferencesProvider).getInt(_key) ?? -1;
    } catch (_) {
      return -1;
    }
  }

  void dismiss(int remaining) {
    state = remaining;
    try {
      ref.read(sharedPreferencesProvider).setInt(_key, remaining);
    } catch (_) {}
  }
}

ServiceDomain? _domainNamed(String name) {
  for (final domain in ServiceDomain.values) {
    if (domain.name == name) return domain;
  }
  return null;
}
