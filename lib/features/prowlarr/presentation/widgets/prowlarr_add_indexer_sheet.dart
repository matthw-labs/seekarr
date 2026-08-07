import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_category_picker.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_list_shimmer.dart';

/// Lets the user pick one of Prowlarr's indexer definitions to add.
///
/// Returns the chosen definition (a schema `IndexerResource`) or null. The
/// filters match the web UI's Add Indexer modal: free text over name and
/// description, plus protocol, privacy and newznab categories.
Future<ProwlarrIndexer?> showProwlarrAddIndexerSheet({
  required BuildContext context,
}) {
  return AppBottomSheet.showScrollable<ProwlarrIndexer>(
    context: context,
    title: 'Add indexer',
    subtitle: 'Pick a definition from Prowlarr',
    icon: Icons.add_circle_outline_rounded,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.9,
    minSize: 0.5,
    builder: (context, controller) => _AddIndexerBody(controller: controller),
  );
}

class _AddIndexerBody extends ConsumerStatefulWidget {
  const _AddIndexerBody({required this.controller});

  final ScrollController controller;

  @override
  ConsumerState<_AddIndexerBody> createState() => _AddIndexerBodyState();
}

/// Privacy filter values as Prowlarr spells them, with display labels.
const _privacyLabels = <String, String>{
  'public': 'Public',
  'semiPrivate': 'Semi-private',
  'private': 'Private',
};

class _AddIndexerBodyState extends ConsumerState<_AddIndexerBody> {
  final _search = TextEditingController();
  String _query = '';
  String? _protocol;
  String? _privacy;
  Set<int> _categories = const {};

  /// The parent selection expanded to the ids definitions advertise; filled in
  /// `build` from the watched category tree.
  Set<int> _acceptedCategoryIds = const {};

  Future<void> _pickCategories() async {
    final picked = await showProwlarrCategoryPicker(
      context: context,
      selected: _categories,
    );
    if (picked == null || !mounted) return;
    setState(() => _categories = picked);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(ProwlarrIndexer definition) {
    if (_protocol != null &&
        (definition.protocol ?? '').toLowerCase() != _protocol) {
      return false;
    }
    if (_privacy != null &&
        (definition.privacy ?? '').toLowerCase() != _privacy!.toLowerCase()) {
      return false;
    }
    if (_categories.isNotEmpty &&
        !definition.categoryIds.any(_acceptedCategoryIds.contains)) {
      return false;
    }
    if (_query.isEmpty) return true;
    final haystack = [
      definition.name,
      definition.definitionName,
      definition.description,
    ].whereType<String>().join(' ').toLowerCase();
    return haystack.contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final schemaAsync = ref.watch(prowlarrIndexerSchemaProvider);
    _acceptedCategoryIds = prowlarrExpandCategories(
      _categories,
      ref.watch(prowlarrCategoriesProvider).asData?.value ?? const [],
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            controller: _search,
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search indexers',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              _ChoiceChip(
                label: 'Torrent',
                selected: _protocol == 'torrent',
                onTap: () => setState(
                  () => _protocol = _protocol == 'torrent' ? null : 'torrent',
                ),
              ),
              _ChoiceChip(
                label: 'Usenet',
                selected: _protocol == 'usenet',
                onTap: () => setState(
                  () => _protocol = _protocol == 'usenet' ? null : 'usenet',
                ),
              ),
              const _ChipDivider(),
              for (final privacy in _privacyLabels.entries)
                _ChoiceChip(
                  label: privacy.value,
                  selected: _privacy == privacy.key,
                  onTap: () => setState(
                    () =>
                        _privacy = _privacy == privacy.key ? null : privacy.key,
                  ),
                ),
              const _ChipDivider(),
              _ChoiceChip(
                label: _categories.isEmpty
                    ? 'Categories'
                    : 'Categories (${_categories.length})',
                selected: _categories.isNotEmpty,
                onTap: _pickCategories,
              ),
            ],
          ),
        ),
        Expanded(
          child: schemaAsync.when(
            data: (definitions) {
              final filtered = definitions.where(_matches).toList()
                ..sort(
                  (a, b) => (a.name ?? '').toLowerCase().compareTo(
                    (b.name ?? '').toLowerCase(),
                  ),
                );
              if (filtered.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text('No definition matches these filters.'),
                  ),
                );
              }
              return ListView.builder(
                controller: widget.controller,
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                itemCount: filtered.length,
                itemBuilder: (context, index) => _DefinitionRow(
                  definition: filtered[index],
                  onTap: () => Navigator.of(context).pop(filtered[index]),
                ),
              );
            },
            loading: () => ListView(
              controller: widget.controller,
              children: const [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'Loading every indexer definition — this one is a big '
                    'download.',
                  ),
                ),
                ProwlarrListShimmer(count: 6),
              ],
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load the indexer definitions'),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(prowlarrIndexerSchemaProvider),
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

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.definition, required this.onTap});

  final ProwlarrIndexer definition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isTorrent = (definition.protocol ?? '').toLowerCase() == 'torrent';
    final badges = <String>[
      if (definition.protocol != null) definition.protocol!.toUpperCase(),
      if (definition.privacy != null) definition.privacy!,
      if (definition.language != null) definition.language!,
    ];

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
                        definition.name ?? 'Unknown definition',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (definition.description != null)
                        Text(
                          definition.description!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (badges.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Text(
                            badges.join(' · '),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: isTorrent
                                      ? AppColors.prowlarr
                                      : AppColors.sonarr,
                                ),
                          ),
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

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected
            ? AppColors.prowlarr.withValues(alpha: 0.15)
            : colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusSm,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusSm,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium!
                  .weight(FontWeight.w700)
                  .copyWith(
                    color: selected
                        ? AppColors.prowlarr
                        : colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChipDivider extends StatelessWidget {
  const _ChipDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
