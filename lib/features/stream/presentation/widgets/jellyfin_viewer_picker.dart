import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/stream/domain/stream_server_client.dart';

/// Picks whose watch state the Jellyfin library is read through.
///
/// **This is a required setting, not a preference, and the reason is structural.**
/// A Jellyfin API key authenticates as an administrator with **no user attached** —
/// the `UserId` claim is the empty GUID. It can therefore see every session and
/// every library, but it cannot answer "have I watched this": resume positions,
/// next-up and the unplayed filter are all user-scoped, and the endpoints that
/// serve them return 404 rather than a default when no `userId` is supplied.
///
/// So a household has to say which member the library speaks for. There is no
/// sensible default to fall back on: picking the first administrator would
/// silently report someone else's positions in a house of four, which is both a
/// wrong answer and a small privacy leak — and invisible in single-user testing.
///
/// **Plex has no counterpart, deliberately.** Its token *is* its user and
/// `/library/*` accepts no impersonation parameter, so a Plex library has exactly
/// one perspective. The control is absent there rather than showing a list of one.
class JellyfinViewerPicker extends ConsumerWidget {
  const JellyfinViewerPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(currentSettingsProvider).jellyfinUserId;
    final viewersAsync = ref.watch(jellyfinViewersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'WATCH STATE'.toUpperCase(),
          style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Continue watching, next up and unplayed are per person. Choose whose '
          'the library should show.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        viewersAsync.when(
          loading: () => const _PickerSkeleton(),
          // Not an error state: the viewer list needs a working connection, and
          // the user may simply not have saved one yet. Saying so is more useful
          // than an exception they cannot act on from here.
          error: (_, _) => Text(
            'Connect first, then come back to choose a viewer.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          data: (viewers) => viewers.isEmpty
              ? Text(
                  'This server reports no users.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : _ViewerList(
                  viewers: viewers,
                  selectedId: selectedId,
                  onSelected: (viewer) => _select(ref, viewer),
                ),
        ),
      ],
    );
  }

  Future<void> _select(WidgetRef ref, StreamViewer viewer) async {
    final settings = ref.read(currentSettingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(jellyfinUserId: viewer.id));
    // The client is rebuilt from the new id, which invalidates every per-viewer
    // lens with it — see `jellyfinClientProvider`, where the viewer is part of
    // *which client you are talking to* rather than part of a page's identity.
  }
}

class _ViewerList extends StatelessWidget {
  const _ViewerList({
    required this.viewers,
    required this.selectedId,
    required this.onSelected,
  });

  final List<StreamViewer> viewers;
  final String selectedId;
  final ValueChanged<StreamViewer> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final viewer in viewers)
          Semantics(
            label: viewer.name,
            selected: viewer.id == selectedId,
            button: true,
            excludeSemantics: true,
            child: ChoiceChip(
              label: Text(viewer.name),
              selected: viewer.id == selectedId,
              onSelected: (_) => onSelected(viewer),
            ),
          ),
      ],
    );
  }
}

class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading viewers',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          ShimmerPlaceholder.text(width: 84),
          ShimmerPlaceholder.text(width: 68),
        ],
      ),
    );
  }
}
