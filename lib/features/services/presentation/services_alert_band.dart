/// The conditional outage notice above the stack matrix on `/services`.
///
/// Renders **nothing** while every configured service is answering, which is
/// the whole design: its presence is the signal, so a healthy stack has no
/// alert chrome to learn to ignore. A persistent "13 of 13 online" instrument
/// would be green on almost every open, and a badge that is always green is a
/// badge nobody reads on the day it turns red.
///
/// It replaces an 8pt dot in the app bar whose only affordance was a `Tooltip` —
/// useless on the phone this app is mostly used on — and which counted against
/// all thirteen `ServiceKey.values` rather than the configured ones, so a healthy
/// five-service stack reported "5 online, 8 offline".
///
/// ## Why it is a line and not a card
///
/// It used to be a full-width card filled with `error` at 10%, bordered in
/// `error` at 28%, with an error-red glyph, an error-red sentence and an
/// error-red Retry. That is the chrome of something that has just gone wrong —
/// and for a self-hosted stack it mostly has not. A box on a home server is
/// down for an afternoon while you rebuild it, or permanently because you
/// stopped running it and have not removed it from Settings yet; either way the
/// screen shouted the same alarm on every single open.
///
/// So the notice keeps its *presence* as the signal and gives up its volume:
/// no fill, no border, a sentence in `onSurfaceVariant`, and the error tone
/// spent on exactly one 16pt glyph. That glyph is the whole of the alarm now,
/// which is enough — the sentence names the service, and the cards below it
/// have already drained to unlit.
///
/// ## Why it can be dismissed, and why the dismissal is not persisted
///
/// A notice you cannot silence about a service you knowingly left down is just
/// a permanent banner. So it takes an acknowledgement — but scoped to the
/// outage, not to the notice: dismissing names the services currently dark, and
/// anything that goes down *afterwards* raises the band again with only the new
/// names in it.
///
/// The acknowledgement is session-scoped on purpose. Persisting it would mean a
/// service that is still unreachable tomorrow never says so again, which is the
/// failure mode the band exists to prevent. And it self-clears on recovery: a
/// service that comes back drops out of the dismissed set, so the *next* time
/// it fails it is news again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/services/domain/services_semantics.dart';
import 'package:seekarr/features/services/presentation/service_kpi_provider.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// The configured services that have answered, and said no.
///
/// Split out of the band so the dismissal can be pruned against it from a
/// listener: deriving it inline would leave nothing for `ref.listen` to watch,
/// and mutating the dismissed set during `build` is the kind of thing that
/// works until the first rebuild in the same frame.
final servicesOfflineProvider = Provider<List<ServiceKey>>((ref) {
  final settings = ref.watch(currentSettingsProvider);

  // Only configured services can be "not answering". An unconfigured one is not
  // a fault, and treating it as one is what made the old aggregate lie.
  return ServiceKey.values
      .where(settings.isServiceConfigured)
      .where((service) {
        // Strictly `false`, not `!= true`: a summary still loading is neither
        // online nor a fault, and a band that appears during the first second of
        // every cold open is a band that cried wolf.
        return ref
                .watch(serviceSummaryProvider(service))
                .asData
                ?.value
                .isOnline ==
            false;
      })
      .toList(growable: false);
});

/// Outages the user has acknowledged this session. See the library docs for why
/// this is deliberately not persisted.
final dismissedOutagesProvider =
    NotifierProvider<DismissedOutagesNotifier, Set<ServiceKey>>(
      DismissedOutagesNotifier.new,
    );

class DismissedOutagesNotifier extends Notifier<Set<ServiceKey>> {
  @override
  Set<ServiceKey> build() => const {};

  void dismiss(Iterable<ServiceKey> services) {
    state = {...state, ...services};
  }

  /// Drops acknowledgements for services that are no longer down.
  ///
  /// This is what makes a dismissal cover *an outage* rather than *a service*:
  /// once Readarr answers again its acknowledgement is spent, and the next time
  /// it stops answering the band has something new to say.
  void retainOnly(Set<ServiceKey> stillOffline) {
    final next = state.intersection(stillOffline);
    if (next.length == state.length) return;
    state = next;
  }
}

class ServicesAlertBand extends ConsumerWidget {
  const ServicesAlertBand({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(servicesOfflineProvider);
    final dismissed = ref.watch(dismissedOutagesProvider);

    // In a listener rather than in `build`: pruning is a write, and a provider
    // written to while it is being read is a loop waiting to happen.
    ref.listen<List<ServiceKey>>(servicesOfflineProvider, (_, next) {
      ref.read(dismissedOutagesProvider.notifier).retainOnly(next.toSet());
    });

    final unacknowledged = offline
        .where((service) => !dismissed.contains(service))
        .toList(growable: false);
    if (unacknowledged.isEmpty) return const SizedBox.shrink();

    return _AlertBandBody(
      services: unacknowledged,
      onRetry: () {
        // Only the offenders. Re-checking the whole stack would throw away
        // twelve good summaries to re-fetch one bad one.
        for (final service in unacknowledged) {
          ref.invalidate(serviceSummaryProvider(service));
          ref.invalidate(serviceKpiProvider(service));
          ref.invalidate(serviceSignalProvider(service));
        }
      },
      onDismiss: () =>
          ref.read(dismissedOutagesProvider.notifier).dismiss(unacknowledged),
    );
  }
}

class _AlertBandBody extends StatelessWidget {
  const _AlertBandBody({
    required this.services,
    required this.onRetry,
    required this.onDismiss,
  });

  final List<ServiceKey> services;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titles = services.map((s) => s.title).toList(growable: false);
    final message = servicesAlertBandMessage(titles);

    // The one place the error tone is still spent. Through `onTint` with no
    // tint — the composite is the scaffold surface itself — because the raw
    // error red measures around 3:1 on the light background and this is a 16pt
    // glyph, which owes 3:1 as a graphical object and has no text beside it in
    // the same colour to lean on.
    final alarm = ServiceTheme.onTint(
      colorScheme.error,
      surface: colorScheme.surface,
      tintAlpha: 0,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Semantics(
        key: const ValueKey('services-alert-band'),
        container: true,
        // The retry and the dismiss stay reachable as their own controls; this
        // node only owns the sentence.
        explicitChildNodes: true,
        // Announced when it appears, which is the moment it matters. It is not
        // routed through `announce()` as well: that double-reads on iOS and is a
        // no-op on Android.
        liveRegion: true,
        // The same string the band paints: see `servicesAlertBandMessage`.
        label: message,
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.cloud_off_rounded, size: 16, color: alarm),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                // Brand primary, never the error tone. A "try again" is an
                // ordinary action; painting it red makes the recovery look as
                // alarming as the fault.
                foregroundColor: colorScheme.primary,
                // 44pt on iOS / 48dp on Android is the floor, and this button
                // shares its row with body text that would otherwise size it.
                minimumSize: const Size(56, 44),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(
                'Retry',
                style: theme.textTheme.labelLarge
                    ?.weight(FontWeight.w700)
                    .copyWith(color: colorScheme.primary),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 16),
              color: colorScheme.onSurfaceVariant,
              tooltip: servicesDismissAlertLabel(titles),
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.borderRadiusSm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
