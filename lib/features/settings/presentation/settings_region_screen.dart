import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';

const _regionScreenDescription =
    'Release dates, content ratings and watch providers are all reported for '
    'the region you pick here.';

class SettingsRegionScreen extends ConsumerStatefulWidget {
  const SettingsRegionScreen({super.key});

  @override
  ConsumerState<SettingsRegionScreen> createState() =>
      _SettingsRegionScreenState();
}

class _SettingsRegionScreenState extends ConsumerState<SettingsRegionScreen> {
  final _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final selected = SettingsModel.normalizeRegion(settings.region);
    final theme = Theme.of(context);

    // The current region is pinned above the list: on a thirty-entry picker,
    // finding what is already set should not mean scrolling for it.
    final matches = commonRegions.entries
        .where((entry) => entry.key != selected && _matches(entry))
        .toList(growable: false);

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Region')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          Text(
            _regionScreenDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _queryController,
            decoration: InputDecoration(
              hintText: 'Search regions',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      tooltip: 'Clear search',
                      onPressed: () {
                        _queryController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            textInputAction: TextInputAction.search,
            autocorrect: false,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_query.isEmpty) ...[
            SettingsGroupCard(
              children: [
                SettingsChoiceRow(
                  label: _label(selected),
                  description: 'Current region',
                  selected: true,
                  onSelected: () {},
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (matches.isEmpty)
            AppEmptyState.compact(
              icon: Icons.travel_explore_rounded,
              title: 'No matching region',
              message: 'Try the country name or its two-letter code.',
            )
          else
            SettingsGroupCard(
              children: [
                for (final entry in matches)
                  SettingsChoiceRow(
                    label: '${entry.value} (${entry.key})',
                    selected: entry.key == selected,
                    onSelected: () => _select(settings, entry.key),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  bool _matches(MapEntry<String, String> entry) {
    if (_query.trim().isEmpty) return true;
    final query = _query.trim().toLowerCase();
    return entry.value.toLowerCase().contains(query) ||
        entry.key.toLowerCase().contains(query);
  }

  String _label(String code) {
    final name = commonRegions[code] ?? code;
    return '$name ($code)';
  }

  Future<void> _select(SettingsModel settings, String code) async {
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(region: code));
  }
}
