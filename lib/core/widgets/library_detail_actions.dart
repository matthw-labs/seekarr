import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/header_action_row.dart';
import 'package:cupola/core/widgets/media_profile_selector.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
///   Interactive search beside it.
/// * **An action is withheld, never disabled.** [MediaActionKind.none] renders
///   no button, and the consequence carries the page instead.
/// * **Monitoring is not an action.** It is a persistent binary of the user's
///   copy, so it lives in the overflow — except at the one rung where *not*
///   monitoring is the reason nothing is happening.
///
/// **A button names its MECHANISM; the consequence sentence names the SITUATION.**
/// There are exactly two search mechanisms and therefore exactly two labels:
/// `Auto search` for [MediaActionKind.search], which hands the decision to the
/// service, and `Interactive search` for [MediaActionKind.interactiveSearch],
/// which hands it to the user. Nothing else may name a search.
///
/// This replaced four names for the automatic search (`Find releases`,
/// `Find missing`, `Auto search`) and three for the interactive one
/// (`Find an upgrade`, `Find another release`, `Interactive search`) — seven
/// labels for two behaviours. Worse, the state-shaped names pointed the wrong
/// way: `Find releases` reads as *show me the releases*, which is the
/// interactive behaviour, while the button it sat on performed the automatic
/// grab. On a rung where both mechanisms are on screen at once — a missing title
/// promotes the automatic one and shows the interactive one beside it — the user
/// could not tell which was which, and the label was the reason.
///
/// The per-state nuance those names carried is not lost, it moved to where state
/// belongs: `partial` says "Part of this is on disk; Radarr is hunting the rest.",
/// `upgradable` says "The file is below your quality cutoff, so Radarr keeps
/// looking." The button says how, the sentence says why.
MediaPrimaryAction resolveMediaAction(
  MediaStatusInfo status,
  MediaActionCapabilities caps, {
  required String serviceName,

  /// A whole clause for the `partial` rung, count first: `41 of 48 episodes are
  /// on disk.` A host supplies it because only the host knows the child noun.
  String? partialSummary,

  /// A **tail** for the `unavailable` rung, not a whole sentence: it completes
  /// `There's nothing to search for until …`, so pass `Jul 17, 2026` and never
  /// `Out on Jul 17, 2026.`. A tail keeps the stem inside the ladder's voice and
  /// puts the date last, where changing it cannot reflow the prose before it.
  String? consequenceOverride,
}) {
  final pipeline = status.pipeline;

  if (pipeline != null) {
    switch (pipeline) {
      case MediaPipeline.clientUnavailable:
        // Names the component that is down and the consequence the badge
        // withholds: the whole queue is frozen, not just this title. "The
        // download client" and never a brand name — the app does not know which
        // client is configured.
        return _queueOrNothing(
          caps,
          'Nothing moves until the download client answers.',
        );
      case MediaPipeline.failed:
        // The attributed frame REPLACES the fallback clause; it is never
        // appended after it, or the sentence claims two different things.
        final reported = _reports(serviceName, status.detail);
        return _findAnotherRelease(
          caps,
          "This release won't finish. ${reported ?? 'Another one might.'}",
        );
      case MediaPipeline.importBlocked:
        // The fact the badge withholds leads: the bytes arrived safely and the
        // blockage is at the import step. Deliberately no detail frame here —
        // on this rung the service's message is usually a path-length wall of
        // text, and the promoted verb has already done the sentence's job.
        final consequence =
            'The download is done; $serviceName needs a hand importing it.';
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
          percent == null
              ? 'No bytes are moving on this transfer right now.'
              // The figure is the last thing in the sentence, so 5% -> 43% ->
              // 100% never reflows a word beside it.
              : 'No bytes are moving right now; it sits at $percent%.',
        );
      // These five shared one branch that printed `detail ?? pipeline.label`
      // plus an appended percentage — the badge's own word with a diagnostic
      // stapled to it, which is the worst restatement on the ladder. Each rung
      // now says what follows from itself instead.
      case MediaPipeline.queued:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            // Deliberately silent about *whose* turn: true of both a client
            // queue and a service-side release delay.
            "This title is waiting its turn; no bytes have moved yet.",
          ),
        );
      case MediaPipeline.downloading:
        final downloadedPercent = status.progressPercent;
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            downloadedPercent == null
                ? 'The download client has it.'
                : 'The download client has it, $downloadedPercent% through.',
          ),
        );
      case MediaPipeline.importPending:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            'The download is done; $serviceName imports it on its next pass.',
          ),
        );
      case MediaPipeline.importing:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            '$serviceName is moving the files into your library.',
          ),
        );
      case MediaPipeline.paused:
        return _queueOrNothing(
          caps,
          _withWarning(
            status,
            serviceName,
            'Nothing moves until the download client resumes it.',
          ),
        );
    }
  }

  if (status.unmonitored && !status.isAvailable) {
    // The badge already says Unmonitored, so it carries the reason and the
    // sentence carries the consequence. The promoted Monitor verb carries the
    // fix; the sentence must not restate it.
    final consequence = "$serviceName isn't searching for this title.";
    if (caps.canMonitor) {
      return MediaPrimaryAction(
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
      // True of both the Seerr Request path and the *arr Add path, because
      // "tracking" is what both of them start.
      final consequence =
          'Nothing happens until $serviceName is tracking this title.';
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
      // Provable rather than hopeful: the unmonitored rung above is checked
      // first, so anything reaching here IS monitored, and therefore genuinely
      // in Wanted and in RSS. Naming the ongoing process instead of the absence
      // is the whole mechanism — it is what replaced "Expected on disk, nothing
      // there.", which had no actor and so read as a monitoring alert.
      final consequence = '$serviceName is hunting a release for this title.';
      if (caps.canSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Auto search',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.partial:
      final consequence =
          partialSummary ??
          'Part of this is on disk; $serviceName is hunting the rest.';
      if (caps.canSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.search,
          label: 'Auto search',
          icon: Icons.saved_search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.upgradable:
      // Names the reason the badge omits — the cutoff, which is the real
      // Radarr/Sonarr noun — and the consequence: the search is still live.
      final consequence =
          'The file is below your quality cutoff, so $serviceName keeps '
          'looking.';
      if (caps.canInteractiveSearch) {
        return MediaPrimaryAction(
          kind: MediaActionKind.interactiveSearch,
          label: 'Interactive search',
          icon: Icons.search_rounded,
          consequence: consequence,
        );
      }
      return _nothing(consequence);

    case MediaAvailability.available:
      // This sentence pays for the withheld primary: it tells the operator the
      // absence of a button is a *result*, not a gap. It is half the answer to
      // "the action row feels too empty" — the visible secondaries beside the
      // overflow are the other half.
      //
      // "everything it expects" and not "nothing is outstanding": the first
      // draft used the latter, which is bookish and ambiguous enough to be read
      // as "nothing is excellent". What this rung is actually about is the count
      // the page already shows — 89 of 89, 1 file — which is what the service
      // expected and got.
      return _nothing(
        "$serviceName has everything it expects, so it isn't searching.",
      );

    case MediaAvailability.unavailable:
      // The override is a tail substitution, so the stem stays inside the
      // ladder's voice and a date change never reflows the prose before it.
      return _nothing(
        "There's nothing to search for until ${consequenceOverride ?? "it's released"}.",
      );

    case MediaAvailability.deleted:
      return _nothing(
        'Nothing changes here until this title is back in $serviceName.',
      );

    case MediaAvailability.unknown:
      // On this rung the service's words ARE the only fact available, so the
      // frame stands alone. The bare label "Unknown" is never a sentence again.
      return _nothing(
        _reports(serviceName, status.detail) ??
            "$serviceName didn't report a state for this title.",
      );
  }
}

/// Normalises a service-supplied `detail` into an attributed sentence.
///
/// The service's words arrive after a colon, never inside our own grammar, so a
/// screen reader is handed a whole clause instead of the bare fragment the old
/// ladder passed through — `status.detail` *was* the entire sentence on two
/// rungs. Returns null when nothing legible survives, which is what lets a
/// caller fall back to its own clause instead of rendering a colon and nothing.
String? _reports(String serviceName, String? detail) {
  var text = detail?.trim() ?? '';
  const exceptionPrefix = 'Exception: ';
  if (text.startsWith(exceptionPrefix)) {
    text = text.substring(exceptionPrefix.length).trim();
  }
  if (text.isEmpty) return null;
  if (!text.endsWith('.') && !text.endsWith('!') && !text.endsWith('?')) {
    text = '$text.';
  }

  return '$serviceName reports: $text';
}

/// Appends the attributed detail as a second sentence on a warning-toned queue
/// rung.
///
/// Without it the badge turns warning-toned with nothing on the page saying why:
/// that reason rode in `detail`, which the five-way split of the queue branch
/// would otherwise drop on the floor.
String _withWarning(MediaStatusInfo status, String serviceName, String base) {
  if (!status.hasWarning) return base;
  final reported = _reports(serviceName, status.detail);

  return reported == null ? base : '$base $reported';
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
    label: 'Interactive search',
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

/// A non-promoted action plus the rank at which it may claim a visible slot.
///
/// Two orders, one list. The sheet renders in list order; the row fills its
/// slots by [visibleRank]. Keeping both on one object is what makes it
/// impossible for an action to be shown twice or to disappear from both places.
@immutable
class _SecondaryCandidate {
  final MediaOverflowAction action;

  /// Lower wins a slot first. Null can never be visible.
  final int? visibleRank;

  /// Shorter label for the visible button, where a sheet row's width is not
  /// available. Falls back to the sheet's own label.
  final String? visibleLabel;

  const _SecondaryCandidate({
    required this.action,
    required this.visibleRank,
    this.visibleLabel,
  });

  String get visibleName => visibleLabel ?? action.label;
}

/// The candidates that earn the row's visible slots, in rank order.
///
/// Anything without a rank, or without an invoker, is filtered out first: a
/// visible control that does nothing is worse than one that was never offered,
/// and this band's whole rule is that an action is withheld rather than
/// disabled.
List<_SecondaryCandidate> _visibleSecondaries(
  List<_SecondaryCandidate> candidates, {
  required int slots,
}) {
  if (slots <= 0) return const [];
  final ranked =
      candidates
          .where(
            (candidate) =>
                candidate.visibleRank != null &&
                candidate.action.onInvoke != null,
          )
          .toList()
        ..sort((a, b) => a.visibleRank!.compareTo(b.visibleRank!));

  return ranked.take(slots).toList(growable: false);
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
/// The sheet is the tap target now, so the sheet owns the feedback — a
/// destructive row gets `mediumImpact`, everything else `selectionClick`, and
/// [PressableScale]'s own light impact is suppressed so exactly one fires.
Future<void> showMediaDetailActions(
  BuildContext context, {
  required Color accent,
  required String title,
  required List<MediaOverflowAction> actions,
}) {
  final safe = actions.where((action) => action.label.isNotEmpty).toList();

  return AppBottomSheet.show<void>(
    context: context,
    title: 'Actions',
    subtitle: title,
    icon: Icons.more_horiz_rounded,
    accent: accent,
    builder: (sheetContext) => _MediaOverflowRows(actions: safe),
  );
}

/// The sheet's rows, and the one thing they share: a sheet spends itself on a
/// single action.
///
/// The rows sit on a route that pops *before* the action runs, and a
/// [MediaOverflowAction] is a bare [VoidCallback] — so the host learns about a
/// tap only once it has already started the work, and cannot refuse a second
/// one. Two fingers landing on Manual import and Delete in the same frame is
/// enough: both rows fire, both pop, and the second pop takes the detail page
/// with it while a delete is already in flight. The guard belongs here, where
/// the sheet knows it has been used.
class _MediaOverflowRows extends StatefulWidget {
  final List<MediaOverflowAction> actions;

  const _MediaOverflowRows({required this.actions});

  @override
  State<_MediaOverflowRows> createState() => _MediaOverflowRowsState();
}

class _MediaOverflowRowsState extends State<_MediaOverflowRows> {
  bool _spent = false;

  void _invoke(MediaOverflowAction action) {
    if (_spent) return;
    setState(() => _spent = true);
    if (action.isDestructive) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    Navigator.of(context).pop();
    action.onInvoke!();
  }

  @override
  Widget build(BuildContext context) {
    final ordinary = widget.actions.where((action) => !action.isDestructive);
    final destructive = widget.actions.where((action) => action.isDestructive);

    Widget row(MediaOverflowAction action) => _MediaOverflowRow(
      action: action,
      onInvoke: action.onInvoke == null || _spent
          ? null
          : () => _invoke(action),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in ordinary) row(action),
        if (destructive.isNotEmpty && ordinary.isNotEmpty)
          Divider(
            height: AppSpacing.xl,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        for (final action in destructive) row(action),
      ],
    );
  }
}

class _MediaOverflowRow extends StatelessWidget {
  final MediaOverflowAction action;

  /// Null disables the row — either the action carries no invoker, or the sheet
  /// has already been spent on another one.
  final VoidCallback? onInvoke;

  const _MediaOverflowRow({required this.action, required this.onInvoke});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onInvoke != null;
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
      onTap: onInvoke,
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

  /// True while a write started from this band is in flight: the promoted
  /// action's glyph spins and **nothing in the band accepts a tap** — not the
  /// promoted button, not the visible secondaries, not the overflow trigger.
  ///
  /// One flag rather than one per action, because the band is one console for
  /// one item: whatever is in flight, a second command against the same title is
  /// never what the user meant. Map the host's own in-flight flags onto it —
  /// `_isAutoSearching || _isUpdatingMonitoredState || _isDeleting`.
  ///
  /// It is the *only* re-entrancy guard on this path. Hosts hand over bare
  /// [VoidCallback]s that fire a service command directly, so before this reached
  /// past the promoted button, triple-tapping the auto-search secondary sent
  /// three searches and the overflow could start a second Delete on top of a
  /// running one.
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

  /// Every tap target in the band goes through here, so [isBusy] can never be
  /// honoured by one rung and forgotten by the next.
  VoidCallback? _whenIdle(VoidCallback? invoke) => isBusy ? null : invoke;

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
  /// Every non-promoted action, in *sheet* order, each carrying the rank at
  /// which it may claim one of the row's visible slots.
  ///
  /// The two orders are deliberately different. The sheet reads best grouped by
  /// kind — both searches together, then state, then the destructive one last.
  /// The row must never spend both of its slots on two searches, so
  /// `visibleRank` promotes Interactive search and then the quality profile,
  /// which are the two an operator actually reaches for on a title that is
  /// already complete. A null rank can only ever appear in the sheet, which is
  /// how Delete is kept from becoming a visible peer of Import on any rung.
  List<_SecondaryCandidate> _candidates(
    BuildContext context,
    MediaActionKind promoted,
  ) {
    final profiles = qualityProfiles;
    final profileName = currentProfileName;
    final profileSetter = onProfileSelected;

    return <_SecondaryCandidate>[
      if (onInteractiveSearch != null &&
          promoted != MediaActionKind.interactiveSearch)
        _SecondaryCandidate(
          visibleRank: 0,
          action: MediaOverflowAction(
            label: 'Interactive search',
            icon: Icons.search_rounded,
            onInvoke: onInteractiveSearch,
          ),
        ),
      if (onSearch != null && promoted != MediaActionKind.search)
        _SecondaryCandidate(
          visibleRank: 2,
          action: MediaOverflowAction(
            label: 'Auto search',
            icon: Icons.saved_search_rounded,
            onInvoke: onSearch,
          ),
        ),
      if (onMonitoredChanged != null && promoted != MediaActionKind.monitor)
        _SecondaryCandidate(
          visibleRank: 4,
          action: MediaOverflowAction(
            label: isMonitored ? 'Stop monitoring' : 'Monitor',
            icon: isMonitored
                ? Icons.bookmark_remove_outlined
                : Icons.bookmark_add_outlined,
            onInvoke: () => onMonitoredChanged!(!isMonitored),
          ),
        ),
      if (profileName != null && profileSetter != null && profiles.isNotEmpty)
        _SecondaryCandidate(
          visibleRank: 1,
          // The sheet names the current profile because it has the width for it;
          // the visible button cannot, so it carries the bare noun and the
          // current value stays one tap away. Same action, two densities.
          visibleLabel: 'Quality profile',
          action: MediaOverflowAction(
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
        ),
      if (onImport != null && promoted != MediaActionKind.manualImport)
        _SecondaryCandidate(
          visibleRank: 3,
          action: MediaOverflowAction(
            label: 'Manual import',
            icon: Icons.download_for_offline_outlined,
            onInvoke: onImport,
          ),
        ),
      if (onDelete != null)
        _SecondaryCandidate(
          // Never visible. A destructive action is not a peer of Import in a
          // row of identical discs, which is what the previous band shipped.
          visibleRank: null,
          action: MediaOverflowAction.destructive(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            onInvoke: onDelete,
          ),
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
    final invoker = _invokerFor(action.kind);
    final hasPrimary = action.kind != MediaActionKind.none && invoker != null;

    // A withheld primary frees both slots. That is the whole answer to a row
    // that read as an empty shelf on an available title: the promotion rule is
    // unchanged — promoting a search on a complete title is what the previous
    // pass deliberately killed — but the space it leaves is now spent on the two
    // actions an operator does reach for, instead of on nothing.
    final candidates = _candidates(context, action.kind);
    final visible = _visibleSecondaries(candidates, slots: hasPrimary ? 1 : 2);
    final overflow = candidates
        .where((candidate) => !visible.contains(candidate))
        .map((candidate) => candidate.action)
        .toList(growable: false);

    final consequence = Text(
      action.consequence,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall!.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );

    final tonalStyle = HeaderActionRow.tonalIconButtonStyle(
      foregroundColor: colorScheme.onSurfaceVariant,
      backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
      borderColor: colorScheme.outlineVariant,
    );

    Widget? overflowDisc;
    if (overflow.isNotEmpty) {
      overflowDisc = SizedBox.square(
        dimension: HeaderActionRow.buttonHeight,
        child: OutlinedButton(
          onPressed: _whenIdle(
            () => showMediaDetailActions(
              context,
              accent: accent,
              title: mediaTitle,
              actions: overflow,
            ),
          ),
          style: tonalStyle,
          child: const Icon(
            Icons.more_horiz_rounded,
            size: ActionStateGlyph.glyphSize,
            semanticLabel: 'More actions',
          ),
        ),
      );
    }

    // Icon-only, for the rungs where a primary already holds the wide slot.
    // The glyph carries the accessible name because there is no visible caption
    // to read: a 9pt caption in a fixed box is exactly what ellipsised to
    // "Inter…" and "Auto…" in the band this replaced.
    Widget secondaryDisc(_SecondaryCandidate candidate) => SizedBox.square(
      dimension: HeaderActionRow.buttonHeight,
      child: OutlinedButton(
        // Disabled rather than withheld while the band is busy: a control that
        // vanishes mid-write reflows the row under the thumb, which is how the
        // next tap lands on whatever slid into its place.
        onPressed: _whenIdle(candidate.action.onInvoke),
        style: tonalStyle,
        child: Icon(
          candidate.action.icon,
          size: ActionStateGlyph.glyphSize,
          semanticLabel: candidate.visibleName,
        ),
      ),
    );

    // Labelled, for the rungs with no primary. Two bare discs beside a wide
    // empty gap read as leftovers; a labelled pair reads as a console. The label
    // is clamped and wraps to two lines rather than eliding, for the same reason
    // the primary's is.
    // **No glyph on this variant, and that is arithmetic rather than taste.**
    // Two buttons plus the overflow disc leave roughly 150pt each on a 402pt
    // phone, and an 18pt glyph, its 8pt gap and 12pt of padding either side eat
    // about 50 of that — leaving ~100pt for a label that wants 118. So
    // "Interactive search" wrapped to two centred lines beside a left-hanging
    // icon, which is exactly what it looked like: an accident. With only two
    // controls on a wide row the words *are* the affordance, so the glyph gives
    // its width back to them and stays on the icon-only variant, where it is the
    // whole control. The label still wraps rather than elides once a reading
    // size genuinely needs a second line.
    Widget secondaryButton(_SecondaryCandidate candidate) => OutlinedButton(
      onPressed: _whenIdle(candidate.action.onInvoke),
      style:
          HeaderActionRow.tonalExpandedButtonStyle(
            foregroundColor: colorScheme.onSurfaceVariant,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
            borderColor: colorScheme.outlineVariant,
          ).copyWith(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: Text(
          candidate.visibleName,
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
      ),
    );

    final trailingChildren = <Widget>[
      if (hasPrimary) ...visible.map(secondaryDisc),
      if (overflowDisc != null) overflowDisc,
    ];
    final trailing = trailingChildren.isEmpty
        ? null
        : trailingChildren.length == 1
        ? trailingChildren.single
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < trailingChildren.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                trailingChildren[i],
              ],
            ],
          );

    if (!hasPrimary) {
      if (visible.isEmpty) {
        // Nothing promoted and no capability to surface: the sentence takes the
        // wide slot so the band is never a lone overflow button with nothing to
        // explain it.
        return HeaderActionRow(expanded: consequence, trailing: trailing);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeaderActionRow(
            expanded: Row(
              children: <Widget>[
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: secondaryButton(visible[i])),
                ],
              ],
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
            onPressed: _whenIdle(invoker),
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
