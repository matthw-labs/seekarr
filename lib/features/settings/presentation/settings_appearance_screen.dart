import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';
import 'package:seekarr/features/settings/presentation/widgets/settings_choice_row.dart';

class SettingsAppearanceScreen extends ConsumerWidget {
  const SettingsAppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final theme = Theme.of(context);

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Appearance')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Text(
              'Both themes are first-class — light is not an inverted '
              'afterthought. Each service keeps its own colour either way.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SettingsGroupCard(
            children: [
              for (final mode in AppThemeMode.values)
                SettingsChoiceRow(
                  label: mode.label,
                  description: _describe(mode),
                  selected: settings.themeMode == mode,
                  onSelected: () => _updateThemeMode(ref, settings, mode),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _describe(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => 'Follows your device setting',
      AppThemeMode.light => 'Always light',
      AppThemeMode.dark => 'Always dark',
    };
  }

  Future<void> _updateThemeMode(
    WidgetRef ref,
    SettingsModel settings,
    AppThemeMode value,
  ) async {
    if (value == settings.themeMode) return;

    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(themeMode: value));
  }
}
