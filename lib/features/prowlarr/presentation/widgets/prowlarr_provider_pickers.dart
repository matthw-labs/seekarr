import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_field_inputs.dart';

/// Per-indexer download client, the advanced setting of the web UI's edit
/// modal.
///
/// Renders nothing when Prowlarr has no client of the indexer's protocol —
/// there would be nothing to choose but "Any", which is already the default.
class ProwlarrDownloadClientField extends ConsumerWidget {
  const ProwlarrDownloadClientField({
    super.key,
    required this.value,
    required this.protocol,
    required this.onChanged,
  });

  /// `0` means "Any", i.e. let Prowlarr pick.
  final int value;
  final String? protocol;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(prowlarrDownloadClientsProvider).asData?.value;
    if (clients == null) return const SizedBox.shrink();

    final matching = clients
        .where(
          (client) =>
              protocol == null ||
              client.protocol == null ||
              client.protocol == protocol,
        )
        .toList(growable: false);
    if (matching.isEmpty) return const SizedBox.shrink();

    final ids = matching.map((client) => client.id).toSet();
    return DropdownButtonFormField<int>(
      initialValue: ids.contains(value) ? value : 0,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Download client',
        helperText: 'Used for grabs redirected through Prowlarr',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('Any')),
        for (final client in matching)
          DropdownMenuItem(
            value: client.id,
            child: Text(client.name ?? client.displayImplementation),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

/// Sync profile (`appProfileId`) for one indexer — the search/RSS settings
/// Prowlarr pushes to its apps.
///
/// Renders nothing until the profiles have loaded, so the form never shows a
/// dropdown with a single stale value in it.
class ProwlarrSyncProfileField extends ConsumerWidget {
  const ProwlarrSyncProfileField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(prowlarrAppProfilesProvider).asData?.value;
    if (profiles == null || profiles.isEmpty) return const SizedBox.shrink();
    final ids = profiles.map((profile) => profile.id).toSet();

    return DropdownButtonFormField<int>(
      initialValue: ids.contains(value) ? value : profiles.first.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Sync profile',
        helperText: 'Search and RSS settings pushed to the apps',
        isDense: true,
      ),
      items: [
        for (final profile in profiles)
          DropdownMenuItem(
            value: profile.id,
            child: Text(profile.name ?? 'Profile ${profile.id}'),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

/// Picks an implementation to add for [kind], from `<kind>/schema`.
///
/// Returns the chosen schema resource, or null. These lists are short (tens of
/// entries) so a search field is enough — unlike the indexer schema, which has
/// its own dedicated sheet with protocol/privacy/category filters.
Future<ProwlarrProviderResource?> showProwlarrImplementationPicker({
  required BuildContext context,
  required ProwlarrProviderKind kind,
}) {
  return AppBottomSheet.showScrollable<ProwlarrProviderResource>(
    context: context,
    title: 'Add ${kind.singular}',
    subtitle: 'Pick an implementation',
    icon: kind.icon,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.8,
    minSize: 0.4,
    builder: (context, controller) =>
        _ImplementationList(kind: kind, controller: controller),
  );
}

class _ImplementationList extends ConsumerStatefulWidget {
  const _ImplementationList({required this.kind, required this.controller});

  final ProwlarrProviderKind kind;
  final ScrollController controller;

  @override
  ConsumerState<_ImplementationList> createState() =>
      _ImplementationListState();
}

class _ImplementationListState extends ConsumerState<_ImplementationList> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(prowlarrProviderSchemaProvider(widget.kind));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            controller: _search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Search',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: schemaAsync.when(
            data: (implementations) {
              final filtered =
                  implementations
                      .where(
                        (item) =>
                            _query.isEmpty ||
                            (item.implementationName ?? item.name ?? '')
                                .toLowerCase()
                                .contains(_query),
                      )
                      .toList()
                    ..sort(
                      (a, b) => (a.implementationName ?? a.name ?? '')
                          .toLowerCase()
                          .compareTo(
                            (b.implementationName ?? b.name ?? '')
                                .toLowerCase(),
                          ),
                    );
              if (filtered.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text('Nothing matches that search.'),
                  ),
                );
              }
              return ListView.builder(
                controller: widget.controller,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  return _ImplementationRow(
                    item: item,
                    onTap: () => Navigator.of(context).pop(item),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load the ${widget.kind.title}'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => ref.invalidate(
                        prowlarrProviderSchemaProvider(widget.kind),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImplementationRow extends StatelessWidget {
  const _ImplementationRow({required this.item, required this.onTap});

  final ProwlarrProviderResource item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Some implementations describe themselves in an `info` field rather than a
    // description property.
    final blurb = item.fields
        .where((field) => field.isInfo)
        .map((field) => prowlarrPlainText(field.value?.toString() ?? ''))
        .where((text) => text.isNotEmpty)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.implementationName ?? item.name ?? 'Unknown',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (blurb != null)
                        Text(
                          blurb,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
