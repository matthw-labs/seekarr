import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Which domain bands of the stack matrix the user has folded away.
///
/// Persisted rather than session-scoped. Folding Infrastructure shut is a
/// statement about how you use the hub, not about this visit, and a fold that
/// springs back on every cold open is a control you press once and never trust
/// again.
///
/// Stores the **collapsed** set, so the default — nothing stored — is a fully
/// expanded matrix. A hub that arrives folded shut hides the one thing the
/// screen exists to show; compaction is something the user opts into.
final collapsedServiceDomainsProvider =
    NotifierProvider<CollapsedServiceDomainsNotifier, Set<ServiceDomain>>(
      CollapsedServiceDomainsNotifier.new,
    );

class CollapsedServiceDomainsNotifier extends Notifier<Set<ServiceDomain>> {
  static const _key = 'services_collapsed_domains';

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
            // `ServiceDomain` would otherwise silently fold the wrong band.
            next.map((domain) => domain.name).toList(growable: false),
          );
    } catch (_) {
      // No persistence available — the in-memory fold still works.
    }
  }
}

ServiceDomain? _domainNamed(String name) {
  for (final domain in ServiceDomain.values) {
    if (domain.name == name) return domain;
  }
  return null;
}
