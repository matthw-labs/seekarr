import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:seekarr/core/app_animation.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/status/media_status.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/header_action_row.dart';
import 'package:seekarr/core/widgets/media_profile_selector.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// What a promoted primary action *does*.
///
/// Deliberately a small closed set rather than a callback with a label: the
/// promotion below has to be a pure, testable function of a resolved status, and
/// a `kind` is what a test can assert on.
enum MediaActionKind {
  openQueue,
  search,
  interactiveSearch,
  manualImport,
  monitor,
  request,
  add,
  refresh,

  /// Nothing follows from this status. The band renders no button at all.
  none,
}

/// Which writes the host screen actually supplied a path for.
///
/// Built from the callbacks, never asserted: a library detail screen has no add
/// path, so it passes `canAdd: false` and an untracked title yields a *sentence*
/// instead of a full-width accent CTA whose only behaviour is an info snackbar
/// reading "Add Movie is not available yet from this view." An action is
/// withheld, never disabled — a disabled full-width control teaches nothing.
@immutable
class MediaActionCapabilities {
  final bool canSearch;
  final bool canInteractiveSearch;
  final bool canImport;
  final bool canMonitor;
  final bool canRequest;
  final bool canAdd;
  final bool canOpenQueue;
  final bool canRefresh;

  const MediaActionCapabilities({
    this.canSearch = false,
    this.canInteractiveSearch = false,
    this.canImport = false,
    this.canMonitor = false,
    this.canRequest = false,
    this.canAdd = false,
    this.canOpenQueue = false,
    this.canRefresh = false,
  });
}

/// The one action a resolved status promotes, and why.
///
/// For [MediaActionKind.none] the [label] is empty and [icon] is not rendered;
/// only [consequence] is. The consequence lives here — beside the decision that
/// produced it — rather than being composed at the call site, so a state can
/// never ship a button without an explanation or an explanation that contradicts
/// its button.
@immutable
class MediaPrimaryAction {
  final MediaActionKind kind;
  final String label;
  final IconData icon;

  /// The sentence under the action: what is true right now, in the user's
  /// words. Never a raw exception, never a service enum name.
  final String consequence;

  const MediaPrimaryAction({
    required this.kind,
    required this.label,
    required this.icon,
    required this.consequence,
  });
}

/// Promotes exactly one action from an already-resolved [MediaStatusInfo].
///
/// Pure, and never called from anything but a `build` that already holds a
/// resolved status: this derives an *action*, not a status. Statuses arrive
/// fully resolved from the feature's `domain/` layer.
///
/// First match wins, and the order mirrors [MediaStatusInfo.label]'s own
/// precedence — pipeline beats unmonitored beats availability — so the promoted
/// verb and the status headline can never describe different situations.
///
/// Three of the outcomes are the point of the whole exercise:
///
/// * **`available` promotes nothing.** The loudest element on an available
///   monitored series used to read "Unmonitor", which is not what anyone opened
///   the page for. It is replaced with *nothing* rather than with another search
///   that can churn a library; "find a better release" stays reachable as
///   Interactive search in the overflow.
/// * **An action is withheld, never disabled.** [MediaActionKind.none] renders
///   no button, and the consequence carries the page instead.
/// * **Monitoring is not an action.** It is a persistent binary of the user's
///   copy, so it lives in the overflow — except at the one rung where *not*
///   monitoring is the reason nothing is happening.
MediaPrimaryAction resolveMediaAction(
  MediaStatusInfo status,
  MediaActionCapabilities caps, {
  required String serviceName,
  String? partialSummary,
  String? consequenceOverride,
}) {
  final pipeline = status.pipeline;

  if (pipeline != null) {
    switch (pipeline) {
      case MediaPipeline.clientUnavailable:
        return _queueOrNothing(caps, 'The download client is not answering.');
      case MediaPipeline.failed:
        return _findAnotherRelease(
          caps,
          status.detail ?? 'The transfer failed.',
        );
      case MediaPipeline.importBlocked:
        final consequence =
            'The download finished but $serviceName could not import it.';
        if (caps.canImport) {
          return MediaPrimaryAction(
            kind: MediaActionKind.manualImport,
            label: 'Finish import',
            icon: Icons.download_for_offline_outlined,
            consequence: consequence,
          );
        }
        return _queueOrNothing(caps, consequence);
      case MediaPipeline.stalled:
        final percent = status.progressPercent;
        return _findAnotherRelease(
          caps,
          percent == null ? 'Stalled.' : 'Stalled at $percent%.',
        );
      case MediaPipeline.queued:
      case MediaPipeline.downloading:
      case MediaPipeline.importPending:
      case MediaPipeline.importing:
      case MediaPipeline.paused:
        final base = status.detail ?? pipeline.label;
        final percent = status.progressPercent;
        return _queueOrNothing(
          caps,
          percent == null ? base : '$base · $percent%',
        );
    }
  }

  if (status.unmonitored && !status.isAvailable) {
    const consequence = 'Not monitored, so nothing is being hunted.';
    if (caps.canMonitor) {
      return const MediaPrimaryAction(
        kind: MediaActionKind.monitor,
        label: 'Monitor',
        icon: Icons.bookmark_add_outlined,
        consequence: consequence,
      );
    }
    return _nothing(consequence);
  }

  switch (status.availability) {
    case MediaAvailability.notTracked:
      final consequence = 'Not in $serviceName yet.';
      if (caps.canRequest) {
        return MediaPrimaryAction(
          kind: MediaActionKind.request,
          label: 'Request',
          icon: Icons.add_circle_outline_rounded,
          consequence: consequence,
        );
      }
      if (caps.canAdd) {
        return MediaPrimaryAction(
          kind: MediaActionKind.add,
          label: 'Add to $serviceName',
          icon: Icons.add_circle_outline_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.missing:
      const consequence = 'Expected on disk, nothing there.';
      if (caps.canSearch) {
        return const MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Find releases',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.partial:
      final consequence = partialSummary ?? 'Some of it is on disk.';
      if (caps.canSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Find missing',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.upgradable:
      const consequence = 'On disk, below the quality cutoff.';
      if (caps.canInteractiveSearch) {
        return const MediaPrimaryAction(
          kind: MediaActionKind.interactiveSearch,
          label: 'Find an upgrade',
          icon: Icons.search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.available:
      return _nothing('Everything expected is on disk.');

    case MediaAvailability.unavailable:
      return _nothing(consequenceOverride ?? 'Not released yet.');

    case MediaAvailability.deleted:
      return _nothing('Removed from $serviceName.');

    case MediaAvailability.unknown:
      return _nothing(status.detail ?? status.label);
  }
}

/// Every queue state routes to the queue — or, where the host gave no route
/// there, to a sentence.
///
/// The spec's ladder promotes `openQueue` unconditionally on these rungs; it is
/// guarded here for the same reason every other rung is. A full-width button
/// that cannot go anywhere is the dead end this whole ladder replaces.
MediaPrimaryAction _queueOrNothing(
  MediaActionCapabilities caps,
  String consequence,
) {
  if (!caps.canOpenQueue) return _nothing(consequence);
  return MediaPrimaryAction(
    kind: MediaActionKind.openQueue,
    label: 'Open queue',
    icon: Icons.monitor_heart_outlined,
    consequence: consequence,
  );
}

MediaPrimaryAction _findAnotherRelease(
  MediaActionCapabilities caps,
  String consequence,
) {
  if (!caps.canInteractiveSearch) return _nothing(consequence);
  return MediaPrimaryAction(
    kind: MediaActionKind.interactiveSearch,
    label: 'Find another release',
    icon: Icons.search_rounded,
    consequence: consequence,
  );
}

MediaPrimaryAction _nothing(String consequence) => MediaPrimaryAction(
  kind: MediaActionKind.none,
  label: '',
  icon: Icons.check_circle_outline_rounded,
  consequence: consequence,
);

/// One row of the actions overflow sheet.
///
/// [MediaOverflowAction.destructive] is a separate constructor rather than a
/// flag because it changes where the row *lands*: the sheet sorts every
/// destructive action below a divider, last, furthest from where the thumb
/// arrives. Delete used to sit roughly ten points from Manual Import in an
/// undifferentiated `spaceAround` row, told apart by hue alone.
@immutable
class MediaOverflowAction {
  final String label;
  final IconData icon;

  /// Null disables the row. Kept rather than omitted when a host wants the
  /// action visible but unavailable; most callers simply omit it instead.
  final VoidCallback? onInvoke;

  final bool isDestructive;

  const MediaOverflowAction({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = false;

  const MediaOverflowAction.destructive({
    required this.label,
    required this.icon,
    this.onInvoke,
  }) : isDestructive = true;
}

/// Shows the non-promoted actions for a media detail page.
///
/// [title] is the media title, shown as the sheet's subtitle. [actions] are
/// rendered in the order given, with one exception the sheet enforces itself:
/// every [MediaOverflowAction.destructive] is moved below a divider at the
/// bottom, so a caller cannot accidentally seat Delete beside Import.
///
/// **Haptics live here, once.** Each service screen used to fire its own, and
/// they had drifted: Radarr fired `selectionClick` on both searches and
/// `mediumImpact` before Delete while Sonarr and Lidarr fired nothing at all.
/// The row is the tap target now, so the row owns the feedback — a destructive
/// row gets `mediumImpact`, everything else `selectionClick`, and
/// [PressableScale]'s own light impact is suppressed so exactly one fires.
Future<void> showMediaDetailActions(
  BuildContext context, {
  required Color accent,
  required String title,
  required List<MediaOverflowAction> actions,
}) {
  final safe = actions.where((action) => action.label.isNotEmpty).toList();
  final ordinary = safe.where((action) => !action.isDestructive);
  final destructive = safe.where((action) => action.isDestructive);

  return AppBottomSheet.show<void>(
    context: context,
    title: 'Actions',
    subtitle: title,
    icon: Icons.more_horiz_rounded,
    accent: accent,
    builder: (sheetContext) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in ordinary) _MediaOverflowRow(action: action),
        if (destructive.isNotEmpty && ordinary.isNotEmpty)
          Divider(
            height: AppSpacing.xl,
            thickness: 1,
            color: Theme.of(sheetContext).colorScheme.outlineVariant,
          ),
        for (final action in destructive) _MediaOverflowRow(action: action),
      ],
    ),
  );
}

class _MediaOverflowRow extends StatelessWidget {
  final MediaOverflowAction action;

  const _MediaOverflowRow({required this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = action.onInvoke != null;
    final glyphColor = enabled
        ? (action.isDestructive
              ? colorScheme.error
              : colorScheme.onSurfaceVariant)
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.38);
    final labelColor = enabled
        ? (action.isDestructive ? colorScheme.error : colorScheme.onSurface)
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return PressableScale(
      // Exactly one haptic per row, fired below.
      haptic: false,
      semanticLabel: action.label,
      excludeChildSemantics: true,
      onTap: enabled ? () => _invoke(context) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: HeaderActionRow.buttonHeight,
        ),
        child: Row(
          children: [
            Icon(
              action.icon,
              size: ActionStateGlyph.glyphSize,
              color: glyphColor,
            ),
            const SizedBox(width: AppSpacing.md),
            // A full-width labelled row cannot truncate, which is what retires
            // the 58pt captions that ellipsised to "Inter…" / "Auto…".
            Expanded(
              child: Text(
                action.label,
                style: theme.textTheme.bodyLarge!
                    .weight(FontWeight.w600)
                    .copyWith(color: labelColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _invoke(BuildContext context) {
    if (action.isDestructive) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    Navigator.of(context).pop();
    action.onInvoke!();
  }
}

/// The status-led action band for the library detail screens (Radarr, Sonarr,
/// Lidarr).
///
/// **Never pad this widget.** The detail spine owns the gutter and every gap; a
/// caller that adds its own inset ships a visible mid-page jog.
///
/// One resolved status in, one promoted action out, everything else in an
/// overflow sheet. What this replaces was six controls of equal weight: a
/// full-width accent CTA reading "Unmonitor" on an *available* series, over five
/// 42pt circular buttons at `spaceAround` that mixed read-only actions
/// (Interactive, Auto Search, Profile) with a state change (Import) and a
/// destructive one (Delete) into one undifferentiated group — six simultaneous
/// choices at the top of the screen, in the least accurate part of the thumb's
/// reach, against a working-memory limit of about four.
class LibraryDetailActions extends StatelessWidget {
  /// The service that owns this page.
  ///
  /// One parameter rather than an accent plus a name, because the two must never
  /// disagree: the accent lights the promoted verb and the name appears in the
  /// consequence sentence.
  final ServiceKey service;

  /// The fully resolved status, from the feature's `domain/` layer.
  ///
  /// This widget derives no status. It promotes an action *from* one.
  final MediaStatusInfo status;

  /// The media title, used as the overflow sheet's subtitle.
  final String mediaTitle;

  /// Whether the user's copy is monitored. Wording of the overflow row only —
  /// monitoring is a persistent binary, not an action.
  final bool isMonitored;

  /// Human summary of a partial manifest, e.g. '41 of 48 episodes on disk.'
  final String? partialSummary;

  /// Replaces the consequence for a state the ladder cannot know on its own —
  /// a release date on a title that has not come out yet.
  final String? consequenceOverride;

  /// True while the promoted action is in flight: its glyph spins and the
  /// button stops accepting taps.
  ///
  /// One flag rather than one per action, because only one action is promoted.
  /// Map the host's own per-action flag onto it — `_isAutoSearching` on a search
  /// rung, `_isUpdatingMonitoredState` on the monitor rung.
  final bool isBusy;

  /// Momentarily true after the promoted action lands; holds a success check in
  /// place of the glyph for [AppAnimation.confirmationHold].
  final bool isConfirmed;

  /// Automatic search. Null withholds both the promotion and the overflow row.
  final VoidCallback? onSearch;

  /// Interactive (release picker) search.
  final VoidCallback? onInteractiveSearch;

  /// Manual import.
  final VoidCallback? onImport;

  /// Route to the download queue. Null makes every in-flight state explain
  /// itself in a sentence rather than promote a button that goes nowhere.
  final VoidCallback? onOpenQueue;

  /// Sets the monitored flag. Receives the *desired* value.
  final ValueChanged<bool>? onMonitoredChanged;

  /// Deletes the item from the service. Always lands last in the overflow.
  final VoidCallback? onDelete;

  /// Current quality profile name. Null hides the profile row.
  final String? currentProfileName;

  /// Current quality profile ID, for the picker's selected state.
  final int? currentProfileId;

  /// Available quality profiles for the picker.
  final List<Map<String, dynamic>> qualityProfiles;

  /// Called when a new quality profile is chosen.
  final Future<void> Function(int profileId)? onProfileSelected;

  const LibraryDetailActions({
    super.key,
    required this.service,
    required this.status,
    required this.mediaTitle,
    this.isMonitored = false,
    this.partialSummary,
    this.consequenceOverride,
    this.isBusy = false,
    this.isConfirmed = false,
    this.onSearch,
    this.onInteractiveSearch,
    this.onImport,
    this.onOpenQueue,
    this.onMonitoredChanged,
    this.onDelete,
    this.currentProfileName,
    this.currentProfileId,
    this.qualityProfiles = const [],
    this.onProfileSelected,
  });

  MediaActionCapabilities get _capabilities => MediaActionCapabilities(
    canSearch: onSearch != null,
    canInteractiveSearch: onInteractiveSearch != null,
    canImport: onImport != null,
    canMonitor: onMonitoredChanged != null,
    canOpenQueue: onOpenQueue != null,
  );

  /// The promoted action for this status. Exposed so a host (or a test) can read
  /// the same decision the band renders instead of re-deriving it.
  MediaPrimaryAction get promotedAction => resolveMediaAction(
    status,
    _capabilities,
    serviceName: service.title,
    partialSummary: partialSummary,
    consequenceOverride: consequenceOverride,
  );

  VoidCallback? _invokerFor(MediaActionKind kind) {
    switch (kind) {
      case MediaActionKind.openQueue:
        return onOpenQueue;
      case MediaActionKind.search:
        return onSearch;
      case MediaActionKind.interactiveSearch:
        return onInteractiveSearch;
      case MediaActionKind.manualImport:
        return onImport;
      case MediaActionKind.monitor:
        final setter = onMonitoredChanged;
        return setter == null ? null : () => setter(true);
      case MediaActionKind.request:
      case MediaActionKind.add:
      case MediaActionKind.refresh:
      case MediaActionKind.none:
        return null;
    }
  }

  /// Everything the promoted action did *not* take, in one fixed order.
  ///
  /// The promoted kind is skipped, so the sheet holds exactly the non-promoted
  /// actions and the same verb never appears twice.
  List<MediaOverflowAction> _overflowActions(
    BuildContext context,
    MediaActionKind promoted,
  ) {
    final profiles = qualityProfiles;
    final profileName = currentProfileName;
    final profileSetter = onProfileSelected;

    return <MediaOverflowAction>[
      if (onInteractiveSearch != null &&
          promoted != MediaActionKind.interactiveSearch)
        MediaOverflowAction(
          label: 'Interactive search',
          icon: Icons.search_rounded,
          onInvoke: onInteractiveSearch,
        ),
      if (onSearch != null && promoted != MediaActionKind.search)
        MediaOverflowAction(
          label: 'Auto search',
          icon: Icons.saved_search_rounded,
          onInvoke: onSearch,
        ),
      if (onMonitoredChanged != null && promoted != MediaActionKind.monitor)
        MediaOverflowAction(
          label: isMonitored ? 'Stop monitoring' : 'Monitor',
          icon: isMonitored
              ? Icons.bookmark_remove_outlined
              : Icons.bookmark_add_outlined,
          onInvoke: () => onMonitoredChanged!(!isMonitored),
        ),
      if (profileName != null && profileSetter != null && profiles.isNotEmpty)
        MediaOverflowAction(
          label: 'Quality profile: $profileName',
          icon: Icons.high_quality_rounded,
          onInvoke: () => showMediaProfileSelector(
            context,
            currentProfileName: profileName,
            currentProfileId: currentProfileId,
            qualityProfiles: profiles,
            onProfileSelected: profileSetter,
            accent: service.accent,
          ),
        ),
      if (onImport != null && promoted != MediaActionKind.manualImport)
        MediaOverflowAction(
          label: 'Manual import',
          icon: Icons.download_for_offline_outlined,
          onInvoke: onImport,
        ),
      if (onDelete != null)
        MediaOverflowAction.destructive(
          label: 'Delete',
          icon: Icons.delete_outline_rounded,
          onInvoke: onDelete,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final accent = service.accent;
    // Never a local luminance threshold: `> 0.55 ? black : white` put white on
    // Radarr's amber at roughly 2.1:1 — on the loudest control of the page.
    final onAccent = ServiceTheme.foregroundOn(accent);

    final action = promotedAction;
    final overflow = _overflowActions(context, action.kind);
    final invoker = _invokerFor(action.kind);
    final hasPrimary = action.kind != MediaActionKind.none && invoker != null;

    final consequence = Text(
      action.consequence,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall!.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );

    Widget? trailing;
    if (overflow.isNotEmpty) {
      trailing = SizedBox.square(
        dimension: HeaderActionRow.buttonHeight,
        child: OutlinedButton(
          onPressed: () => showMediaDetailActions(
            context,
            accent: accent,
            title: mediaTitle,
            actions: overflow,
          ),
          style: HeaderActionRow.tonalIconButtonStyle(
            foregroundColor: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
            borderColor: colorScheme.outlineVariant,
          ),
          child: const Icon(
            Icons.more_horiz_rounded,
            size: ActionStateGlyph.glyphSize,
            semanticLabel: 'More actions',
          ),
        ),
      );
    }

    if (!hasPrimary) {
      // Withheld, not disabled — and the sentence takes the wide slot so the
      // band is never a lone overflow button with nothing to explain it.
      return HeaderActionRow(expanded: consequence, trailing: trailing);
    }

    // The label is clamped at 1.6x for the reason the stacking section header
    // is: Flutter's answer to a single word too wide for its line is to break it
    // mid-word, which is how the request button came to read "Requeste / d".
    Widget label = MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
      child: Text(
        action.label,
        key: ValueKey(action.label),
        maxLines: 2,
        textAlign: TextAlign.center,
      ),
    );
    if (!reduceMotion) {
      label = AnimatedSwitcher(
        duration: AppAnimation.durationSm,
        switchInCurve: AppAnimation.emphasizedCurve,
        child: label,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeaderActionRow(
          expanded: FilledButton.icon(
            onPressed: isBusy ? null : invoker,
            icon: ActionStateGlyph(
              icon: action.icon,
              label: action.label,
              isBusy: isBusy,
              isConfirmed: isConfirmed,
              color: onAccent,
              fill: accent,
            ),
            label: label,
            style: HeaderActionRow.expandedButtonStyle(
              foregroundColor: onAccent,
              backgroundColor: accent,
            ),
          ),
          trailing: trailing,
        ),
        if (action.consequence.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          consequence,
        ],
      ],
    );
  }
}
