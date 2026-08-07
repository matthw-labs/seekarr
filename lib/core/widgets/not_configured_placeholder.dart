import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// Shown where a service has no address or credentials stored yet.
///
/// Built on [AppEmptyState] rather than as its own layout, because a service you
/// have not set up is a normal daily condition, not a fault: the app is meant to
/// have thirteen integrations and nobody runs all of them. It used to paint a
/// 64pt settings glyph in `colorScheme.error` — alarm chrome for a state the user
/// created on purpose by not filling in a form — and `AppEmptyState`'s own doc
/// already named this placeholder as one of the states it exists to unify.
class NotConfiguredPlaceholder extends StatelessWidget {
  /// The generic form, for callers that know only the service's display name —
  /// notably [AsyncValueWidget] and [MediaDetailPlaceholderView], which reach
  /// this state by string-matching a `<Service> not configured` throw and so
  /// never hold a [ServiceKey]. Its button lands on the Settings root.
  const NotConfiguredPlaceholder({super.key, required this.serviceName})
    : service = null;

  /// The form a service dashboard should use: the button deep-links to that
  /// service's own settings page instead of the Settings root.
  ///
  /// This is not cosmetic. The private per-dashboard copies this widget
  /// replaced all navigated to `/settings/service/<routeParam>`, and collapsing
  /// them onto the generic constructor silently downgraded four screens to
  /// "here is Settings, go find it yourself". The per-service page is also where
  /// [ServiceKey.setupNote] is rendered, so the guidance those copies printed
  /// inline (Unraid's GraphQL sandbox, Plex's token flavour) is one tap away and
  /// stated once rather than duplicated per surface.
  NotConfiguredPlaceholder.forService(ServiceKey service, {super.key})
    : service = service,
      serviceName = service.title;

  final String serviceName;

  /// Null for the generic form; set by [NotConfiguredPlaceholder.forService].
  final ServiceKey? service;

  @override
  Widget build(BuildContext context) {
    final key = service;
    return AppEmptyState(
      icon: Icons.settings_outlined,
      // The same voice as the rest of the app's connection states, which say a
      // service "isn't answering" rather than reporting a config condition.
      title: "$serviceName isn't set up",
      // "Credentials" rather than "the URL and API Key": four of the thirteen
      // services authenticate with a WebUI login and have no API key to paste, so
      // naming one told a third of the roster to look for a field that is not
      // there. The "Please" went with it — the UI is not asking a favour.
      message: "Add its address and credentials in Settings.",
      action: FilledButton.icon(
        onPressed: () => context.go(
          key == null ? '/settings' : '/settings/service/${key.routeParam}',
        ),
        icon: const Icon(Icons.settings_outlined, size: 18),
        label: const Text('Open Settings'),
      ),
    );
  }
}
