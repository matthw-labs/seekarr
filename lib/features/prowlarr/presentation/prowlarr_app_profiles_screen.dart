import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/utils/service_action.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';

/// Sync profiles (`appprofile`): the search and RSS settings Prowlarr pushes to
/// its apps, picked per indexer.
///
/// These are typed rather than field-driven — four properties, no `fields`
/// array — so they get a small hand-written form instead of the generated one.
class ProwlarrAppProfilesScreen extends ConsumerWidget {
  const ProwlarrAppProfilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(prowlarrAppProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.prowlarr.withValues(alpha: 0.12),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Back',
          onPressed: () =>
              RouteUtils.popOrGo(context, ServiceRoutes.prowlarrSettings),
        ),
        title: const Text('Sync profiles'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add sync profile',
            onPressed: () => _edit(context, ref, null),
          ),
        ],
      ),
      body: profilesAsync.when(
        data: (profiles) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(prowlarrAppProfilesProvider);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              for (final profile in profiles)
                _ProfileRow(
                  profile: profile,
                  onTap: () => _edit(context, ref, profile),
                  onDelete: () => _delete(context, ref, profile),
                ),
              if (profiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'No sync profiles yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Failed to load the sync profiles'),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: () => ref.invalidate(prowlarrAppProfilesProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    ProwlarrAppProfile? profile,
  ) async {
    final payload = await AppBottomSheet.show<Map<String, dynamic>>(
      context: context,
      title: profile == null ? 'New sync profile' : 'Edit sync profile',
      icon: Icons.tune_rounded,
      accent: AppColors.prowlarr,
      showClose: true,
      builder: (context) => _ProfileForm(profile: profile),
    );
    if (payload == null || !context.mounted) return;

    await runServiceAction(
      context,
      ref,
      action: () => ref.read(prowlarrServiceProvider).saveAppProfile(payload),
      successMessage: profile == null ? 'Profile created' : 'Profile saved',
      failureMessage: 'Could not save the profile',
      invalidate: [prowlarrAppProfilesProvider, prowlarrIndexersProvider],
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ProwlarrAppProfile profile,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Delete ${profile.name ?? 'this profile'}?',
      message:
          'Prowlarr refuses to delete a profile that indexers still use — '
          'move them to another profile first.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!result.confirmed || !context.mounted) return;

    await runServiceAction(
      context,
      ref,
      action: () =>
          ref.read(prowlarrServiceProvider).deleteAppProfile(profile.id),
      successMessage: 'Profile deleted',
      failureMessage: 'Could not delete the profile',
      invalidate: [prowlarrAppProfilesProvider],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.onTap,
    required this.onDelete,
  });

  final ProwlarrAppProfile profile;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = <String>[
      if (profile.enableRss) 'RSS',
      if (profile.enableAutomaticSearch) 'automatic search',
      if (profile.enableInteractiveSearch) 'interactive search',
    ];
    final summary = [
      enabled.isEmpty ? 'nothing enabled' : enabled.join(', '),
      'min ${profile.minimumSeeders} seeders',
    ].join(' · ');

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
                        profile.name ?? 'Profile ${profile.id}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall!.weight(FontWeight.w700),
                      ),
                      Text(
                        summary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  tooltip: 'Delete profile',
                  color: colorScheme.error,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.profile});

  final ProwlarrAppProfile? profile;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minimumSeeders;
  late bool _rss;
  late bool _automatic;
  late bool _interactive;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? '');
    _minimumSeeders = TextEditingController(
      text: '${profile?.minimumSeeders ?? 1}',
    );
    _rss = profile?.enableRss ?? true;
    _automatic = profile?.enableAutomaticSearch ?? true;
    _interactive = profile?.enableInteractiveSearch ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _minimumSeeders.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(<String, dynamic>{
      if (widget.profile != null) 'id': widget.profile!.id,
      'name': _name.text.trim(),
      'enableRss': _rss,
      'enableAutomaticSearch': _automatic,
      'enableInteractiveSearch': _interactive,
      'minimumSeeders': int.tryParse(_minimumSeeders.text.trim()) ?? 1,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Name is required'
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable RSS'),
            value: _rss,
            onChanged: (value) => setState(() => _rss = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable automatic search'),
            value: _automatic,
            onChanged: (value) => setState(() => _automatic = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable interactive search'),
            value: _interactive,
            onChanged: (value) => setState(() => _interactive = value),
          ),
          TextFormField(
            controller: _minimumSeeders,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Minimum seeders',
              helperText: 'Torrent seeders an app requires before grabbing',
              isDense: true,
            ),
            validator: (value) =>
                int.tryParse((value ?? '').trim()) == null ? 'Required' : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submit,
            child: Text(widget.profile == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }
}
