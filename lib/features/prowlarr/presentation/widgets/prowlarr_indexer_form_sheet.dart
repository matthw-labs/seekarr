import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_field_inputs.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_provider_pickers.dart';
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_tag_selector.dart';

/// Shows the add/edit indexer form and returns what the user chose to do.
///
/// [indexer] is either an existing indexer (edit) or a definition coming from
/// `indexer/schema` (add, [isNew] true). The form itself is generated from the
/// indexer's `fields`, exactly like the web UI's edit modal, so a Cardigann
/// tracker asking for a cookie and a Newznab server asking for an API key both
/// render without indexer-specific code.
///
/// Deleting is *requested* rather than performed here: the confirmation dialog
/// belongs to the caller's flow, which owns the snackbar and the invalidations.
Future<ProwlarrFormOutcome> showProwlarrIndexerFormSheet({
  required BuildContext context,
  required ProwlarrIndexer indexer,
  bool isNew = false,
}) async {
  final outcome = await AppBottomSheet.showScrollable<ProwlarrFormOutcome>(
    context: context,
    title: isNew ? 'Add indexer' : (indexer.name ?? 'Edit indexer'),
    subtitle: indexer.displayImplementation.isEmpty
        ? null
        : indexer.displayImplementation,
    icon: Icons.travel_explore_rounded,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.9,
    minSize: 0.5,
    builder: (context, controller) =>
        _IndexerForm(controller: controller, indexer: indexer, isNew: isNew),
  );
  return outcome ?? ProwlarrFormOutcome.cancelled;
}

class _IndexerForm extends ConsumerStatefulWidget {
  const _IndexerForm({
    required this.controller,
    required this.indexer,
    required this.isNew,
  });

  final ScrollController controller;
  final ProwlarrIndexer indexer;
  final bool isNew;

  @override
  ConsumerState<_IndexerForm> createState() => _IndexerFormState();
}

class _IndexerFormState extends ConsumerState<_IndexerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _priority;
  late bool _enable;
  late bool _redirect;
  late int _appProfileId;
  late int _downloadClientId;
  late List<int> _tags;

  /// Edited field values by field name, seeded from every field — including the
  /// hidden ones (Cardigann's `definitionFile`), which must survive the save.
  late final Map<String, dynamic> _values;

  bool _showAdvanced = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final indexer = widget.indexer;
    _name = TextEditingController(text: indexer.name ?? '');
    _priority = TextEditingController(text: '${indexer.priority ?? 25}');
    _enable = widget.isNew ? true : indexer.enable;
    _redirect = indexer.redirect;
    _appProfileId = indexer.appProfileId;
    _downloadClientId = indexer.downloadClientId;
    _tags = [...indexer.tags];
    _values = prowlarrSeedFieldValues(indexer.fields);
  }

  @override
  void dispose() {
    _name.dispose();
    _priority.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPayload() {
    return widget.indexer.toPayload(
      id: widget.isNew ? 0 : widget.indexer.id,
      name: _name.text.trim(),
      enable: _enable,
      redirect: _redirect,
      priority: int.tryParse(_priority.text.trim()) ?? 25,
      appProfileId: _appProfileId,
      downloadClientId: _downloadClientId,
      tags: _tags,
      fields: widget.indexer.fields
          .map((field) => field.copyWithValue(_values[field.name]))
          .toList(growable: false),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(prowlarrServiceProvider).saveIndexer(_buildPayload());
      if (mounted) Navigator.of(context).pop(ProwlarrFormOutcome.saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SnackBarHelper.error(
          context,
          widget.isNew
              ? 'Could not add this indexer'
              : 'Could not save this indexer',
          detail: e,
        );
      }
    }
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    try {
      await ref.read(prowlarrServiceProvider).testIndexer(_buildPayload());
      if (mounted) SnackBarHelper.success(context, 'Test passed');
    } catch (e) {
      if (mounted) SnackBarHelper.error(context, 'Test failed', detail: e);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indexer = widget.indexer;

    return Form(
      key: _formKey,
      child: ListView(
        controller: widget.controller,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          if (indexer.message != null)
            ProwlarrMessageBanner(
              message: indexer.message!,
              type: indexer.messageType,
            ),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Name is required'
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable'),
            subtitle: indexer.supportsRss
                ? null
                : const Text('RSS is not supported by this indexer'),
            value: _enable,
            onChanged: (value) => setState(() => _enable = value),
          ),
          if (indexer.supportsRedirect)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Redirect'),
              subtitle: const Text(
                'Send the download to the client via Prowlarr instead of the app',
              ),
              value: _redirect,
              onChanged: (value) => setState(() => _redirect = value),
            ),
          const SizedBox(height: AppSpacing.sm),
          ProwlarrSyncProfileField(
            value: _appProfileId,
            onChanged: (value) => setState(() => _appProfileId = value),
          ),
          if (_showAdvanced) ...[
            const SizedBox(height: AppSpacing.md),
            ProwlarrDownloadClientField(
              value: _downloadClientId,
              protocol: indexer.protocol,
              onChanged: (value) => setState(() => _downloadClientId = value),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ProwlarrFieldsSection(
            fields: indexer.fields,
            values: _values,
            showAdvanced: _showAdvanced,
            onChanged: (name, value) => setState(() => _values[name] = value),
          ),
          TextFormField(
            controller: _priority,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Indexer priority',
              helperText: '1 is the highest priority, 50 the lowest',
              isDense: true,
            ),
            validator: (value) {
              final parsed = int.tryParse((value ?? '').trim());
              if (parsed == null || parsed < 1 || parsed > 50) {
                return 'Enter a priority between 1 and 50';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Tags',
            style: Theme.of(
              context,
            ).textTheme.titleSmall!.weight(FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Only apps with a matching tag receive this indexer. No tag means '
            'every app receives it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ProwlarrTagSelector(
            selected: _tags,
            onChanged: (tags) => setState(() => _tags = tags),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show advanced settings'),
            subtitle: const Text('Download client and per-indexer extras'),
            value: _showAdvanced,
            onChanged: (value) => setState(() => _showAdvanced = value),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing || _saving ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_rounded, size: 18),
                  label: const Text('Test'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving || _testing ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(widget.isNew ? 'Add' : 'Save'),
                ),
              ),
            ],
          ),
          if (!widget.isNew) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _saving || _testing
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pop(ProwlarrFormOutcome.deleteRequested),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete indexer'),
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
