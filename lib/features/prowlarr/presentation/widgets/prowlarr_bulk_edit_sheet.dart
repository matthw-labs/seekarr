import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_bottom_sheet.dart';
import 'package:seekarr/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:seekarr/features/prowlarr/presentation/widgets/prowlarr_tag_selector.dart';

/// The changes to apply to a selection of indexers.
///
/// Every property is nullable and only the non-null ones are sent, which is how
/// `PUT /api/v1/indexer/bulk` expresses the web UI's "No change" options.
class ProwlarrBulkEdit {
  final bool? enable;
  final int? priority;
  final int? appProfileId;
  final int? minimumSeeders;
  final double? seedRatio;
  final int? seedTime;
  final int? packSeedTime;
  final bool? preferMagnetUrl;

  const ProwlarrBulkEdit({
    this.enable,
    this.priority,
    this.appProfileId,
    this.minimumSeeders,
    this.seedRatio,
    this.seedTime,
    this.packSeedTime,
    this.preferMagnetUrl,
  });

  bool get isEmpty =>
      enable == null &&
      priority == null &&
      appProfileId == null &&
      minimumSeeders == null &&
      seedRatio == null &&
      seedTime == null &&
      packSeedTime == null &&
      preferMagnetUrl == null;
}

/// Tags to apply to a selection, with the apply mode Prowlarr expects.
class ProwlarrBulkTags {
  final List<int> tags;

  /// `add`, `remove` or `replace`.
  final String applyTags;

  const ProwlarrBulkTags({required this.tags, required this.applyTags});
}

/// Bulk editor for the selected indexers, mirroring the web UI's
/// "Edit selected indexers" modal.
Future<ProwlarrBulkEdit?> showProwlarrBulkEditSheet({
  required BuildContext context,
  required int count,
}) {
  return AppBottomSheet.showScrollable<ProwlarrBulkEdit>(
    context: context,
    title: 'Edit $count ${count == 1 ? 'indexer' : 'indexers'}',
    subtitle: 'Empty fields are left unchanged',
    icon: Icons.tune_rounded,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.8,
    minSize: 0.5,
    builder: (context, controller) => _BulkEditBody(controller: controller),
  );
}

/// Tag editor for the selected indexers ("Set tags" in the web UI).
Future<ProwlarrBulkTags?> showProwlarrBulkTagsSheet({
  required BuildContext context,
  required int count,
}) {
  return AppBottomSheet.showScrollable<ProwlarrBulkTags>(
    context: context,
    title: 'Tags for $count ${count == 1 ? 'indexer' : 'indexers'}',
    icon: Icons.sell_outlined,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.7,
    minSize: 0.4,
    builder: (context, controller) => _BulkTagsBody(controller: controller),
  );
}

class _BulkEditBody extends ConsumerStatefulWidget {
  const _BulkEditBody({required this.controller});

  final ScrollController controller;

  @override
  ConsumerState<_BulkEditBody> createState() => _BulkEditBodyState();
}

class _BulkEditBodyState extends ConsumerState<_BulkEditBody> {
  bool? _enable;
  bool? _preferMagnetUrl;
  int? _appProfileId;
  final _priority = TextEditingController();
  final _minimumSeeders = TextEditingController();
  final _seedRatio = TextEditingController();
  final _seedTime = TextEditingController();
  final _packSeedTime = TextEditingController();

  @override
  void dispose() {
    _priority.dispose();
    _minimumSeeders.dispose();
    _seedRatio.dispose();
    _seedTime.dispose();
    _packSeedTime.dispose();
    super.dispose();
  }

  void _apply() {
    final edit = ProwlarrBulkEdit(
      enable: _enable,
      preferMagnetUrl: _preferMagnetUrl,
      appProfileId: _appProfileId,
      priority: int.tryParse(_priority.text.trim()),
      minimumSeeders: int.tryParse(_minimumSeeders.text.trim()),
      seedRatio: double.tryParse(_seedRatio.text.trim().replaceAll(',', '.')),
      seedTime: int.tryParse(_seedTime.text.trim()),
      packSeedTime: int.tryParse(_packSeedTime.text.trim()),
    );
    Navigator.of(context).pop(edit);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(prowlarrAppProfilesProvider).asData?.value;

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        _TriStateField(
          label: 'Enable',
          value: _enable,
          trueLabel: 'Enabled',
          falseLabel: 'Disabled',
          onChanged: (value) => setState(() => _enable = value),
        ),
        const SizedBox(height: AppSpacing.md),
        if (profiles != null && profiles.isNotEmpty) ...[
          DropdownButtonFormField<int?>(
            initialValue: _appProfileId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sync profile',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<int?>(child: Text('No change')),
              for (final profile in profiles)
                DropdownMenuItem<int?>(
                  value: profile.id,
                  child: Text(profile.name ?? 'Profile ${profile.id}'),
                ),
            ],
            onChanged: (value) => setState(() => _appProfileId = value),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _NumberField(
          controller: _priority,
          label: 'Indexer priority',
          helper: '1 (highest) to 50 (lowest)',
        ),
        _NumberField(
          controller: _minimumSeeders,
          label: 'Minimum seeders',
          helper: 'Seeders an app requires before grabbing a release',
        ),
        _NumberField(
          controller: _seedRatio,
          label: 'Seed ratio',
          decimal: true,
        ),
        _NumberField(
          controller: _seedTime,
          label: 'Seed time',
          helper: 'Minutes',
        ),
        _NumberField(
          controller: _packSeedTime,
          label: 'Pack seed time',
          helper: 'Minutes, for season/discography packs',
        ),
        _TriStateField(
          label: 'Prefer magnet URL',
          value: _preferMagnetUrl,
          trueLabel: 'Yes',
          falseLabel: 'No',
          onChanged: (value) => setState(() => _preferMagnetUrl = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: _apply, child: const Text('Apply changes')),
      ],
    );
  }
}

class _BulkTagsBody extends ConsumerStatefulWidget {
  const _BulkTagsBody({required this.controller});

  final ScrollController controller;

  @override
  ConsumerState<_BulkTagsBody> createState() => _BulkTagsBodyState();
}

class _BulkTagsBodyState extends ConsumerState<_BulkTagsBody> {
  List<int> _tags = const [];
  String _applyTags = 'add';

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'add', label: Text('Add')),
            ButtonSegment(value: 'remove', label: Text('Remove')),
            ButtonSegment(value: 'replace', label: Text('Replace')),
          ],
          selected: {_applyTags},
          onSelectionChanged: (selection) =>
              setState(() => _applyTags = selection.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        ProwlarrTagSelector(
          selected: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _tags.isEmpty && _applyTags != 'replace'
              ? null
              : () => Navigator.of(
                  context,
                ).pop(ProwlarrBulkTags(tags: _tags, applyTags: _applyTags)),
          child: const Text('Apply tags'),
        ),
      ],
    );
  }
}

/// A "No change / on / off" selector, the shape the bulk endpoint needs for its
/// nullable booleans.
class _TriStateField extends StatelessWidget {
  const _TriStateField({
    required this.label,
    required this.value,
    required this.trueLabel,
    required this.falseLabel,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final String trueLabel;
  final String falseLabel;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge!.weight(FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<int>(
          segments: [
            const ButtonSegment(value: 0, label: Text('No change')),
            ButtonSegment(value: 1, label: Text(trueLabel)),
            ButtonSegment(value: 2, label: Text(falseLabel)),
          ],
          selected: {value == null ? 0 : (value! ? 1 : 2)},
          onSelectionChanged: (selection) =>
              onChanged(switch (selection.first) {
                1 => true,
                2 => false,
                _ => null,
              }),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.helper,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          hintText: 'No change',
          isDense: true,
        ),
      ),
    );
  }
}
