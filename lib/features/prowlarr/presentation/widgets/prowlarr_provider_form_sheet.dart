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
import 'package:cupola/features/prowlarr/presentation/widgets/prowlarr_tag_selector.dart';

/// Add/edit form for an app, download client, notification or indexer proxy.
///
/// The body is generated from the resource's `fields` (see
/// [ProwlarrFieldsSection]); on top of that each kind gets the few typed
/// controls its own modal has in the web UI — a sync level for apps, an
/// enable/priority pair for download clients, event toggles for notifications.
///
/// Deleting is *requested*, not performed: the confirmation and the
/// invalidations belong to the calling flow.
Future<ProwlarrFormOutcome> showProwlarrProviderFormSheet({
  required BuildContext context,
  required ProwlarrProviderKind kind,
  required ProwlarrProviderResource resource,
  bool isNew = false,
}) async {
  final outcome = await AppBottomSheet.showScrollable<ProwlarrFormOutcome>(
    context: context,
    title: isNew
        ? 'Add ${kind.singular}'
        : (resource.name ?? 'Edit ${kind.singular}'),
    subtitle: resource.displayImplementation.isEmpty
        ? null
        : resource.displayImplementation,
    icon: kind.icon,
    accent: AppColors.prowlarr,
    showClose: true,
    initialSize: 0.9,
    minSize: 0.5,
    builder: (context, controller) => _ProviderForm(
      controller: controller,
      kind: kind,
      resource: resource,
      isNew: isNew,
    ),
  );
  return outcome ?? ProwlarrFormOutcome.cancelled;
}

class _ProviderForm extends ConsumerStatefulWidget {
  const _ProviderForm({
    required this.controller,
    required this.kind,
    required this.resource,
    required this.isNew,
  });

  final ScrollController controller;
  final ProwlarrProviderKind kind;
  final ProwlarrProviderResource resource;
  final bool isNew;

  @override
  ConsumerState<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends ConsumerState<_ProviderForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _priority;
  late final Map<String, dynamic> _values;
  late List<int> _tags = [...widget.resource.tags];

  /// Typed, kind-specific properties (`syncLevel`, `enable`, `onGrab`…) sent
  /// alongside the generated fields.
  late final Map<String, dynamic> _extras;

  bool _showAdvanced = false;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    _name = TextEditingController(
      text: resource.name ?? resource.implementationName ?? '',
    );
    _priority = TextEditingController(text: '${resource.priority ?? 1}');
    _values = prowlarrSeedFieldValues(resource.fields);
    _extras = {
      for (final toggle in _toggles) toggle.key: resource.flag(toggle.key),
      if (widget.kind == ProwlarrProviderKind.application)
        'syncLevel': resource.syncLevel ?? 'fullSync',
      if (widget.kind == ProwlarrProviderKind.downloadClient)
        'enable': widget.isNew ? true : resource.enable,
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _priority.dispose();
    super.dispose();
  }

  /// Notification event toggles the implementation actually supports.
  ///
  /// Prowlarr advertises each one with a `supportsOnX` flag; showing a toggle it
  /// does not support would silently do nothing.
  List<_Toggle> get _toggles {
    if (widget.kind != ProwlarrProviderKind.notification) return const [];
    final resource = widget.resource;
    return [
      if (resource.flag('supportsOnGrab'))
        const _Toggle('onGrab', 'On grab', 'A release was grabbed'),
      if (resource.flag('supportsOnGrab'))
        const _Toggle(
          'includeManualGrabs',
          'Include manual grabs',
          'Also notify for grabs made from Prowlarr itself',
        ),
      if (resource.flag('supportsOnHealthIssue'))
        const _Toggle(
          'onHealthIssue',
          'On health issue',
          'Prowlarr reported a problem',
        ),
      if (resource.flag('supportsOnHealthIssue'))
        const _Toggle(
          'includeHealthWarnings',
          'Include health warnings',
          'Notify for warnings, not only errors',
        ),
      if (resource.flag('supportsOnHealthRestored'))
        const _Toggle(
          'onHealthRestored',
          'On health restored',
          'A previous problem cleared',
        ),
      if (resource.flag('supportsOnApplicationUpdate'))
        const _Toggle(
          'onApplicationUpdate',
          'On application update',
          'Prowlarr itself was updated',
        ),
    ];
  }

  Map<String, dynamic> _buildPayload() {
    return widget.resource.toPayload(
      id: widget.isNew ? 0 : widget.resource.id,
      name: _name.text.trim(),
      tags: _tags,
      fields: widget.resource.fields
          .map((field) => field.copyWithValue(_values[field.name]))
          .toList(growable: false),
      extras: {
        ..._extras,
        if (widget.kind == ProwlarrProviderKind.downloadClient)
          'priority': int.tryParse(_priority.text.trim()) ?? 1,
      },
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(prowlarrServiceProvider)
          .saveProvider(widget.kind, _buildPayload());
      if (mounted) Navigator.of(context).pop(ProwlarrFormOutcome.saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        SnackBarHelper.error(
          context,
          'Could not save this ${widget.kind.singular}',
          detail: e,
        );
      }
    }
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _testing = true);
    try {
      await ref
          .read(prowlarrServiceProvider)
          .testProvider(widget.kind, _buildPayload());
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
    final resource = widget.resource;
    final kind = widget.kind;

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
          if (resource.message != null)
            ProwlarrMessageBanner(
              message: resource.message!,
              type: resource.messageType,
            ),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name', isDense: true),
            validator: (value) => (value == null || value.trim().isEmpty)
                ? 'Name is required'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (kind == ProwlarrProviderKind.application) ...[
            const ProwlarrSectionLabel(text: 'Sync level'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fullSync', label: Text('Full')),
                ButtonSegment(value: 'addOnly', label: Text('Add only')),
                ButtonSegment(value: 'disabled', label: Text('Off')),
              ],
              selected: {(_extras['syncLevel'] as String?) ?? 'fullSync'},
              onSelectionChanged: (selection) =>
                  setState(() => _extras['syncLevel'] = selection.first),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Full sync keeps this app\'s indexers in step with Prowlarr; add '
              'only never removes or edits what it already has.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (kind == ProwlarrProviderKind.downloadClient) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable'),
              value: _extras['enable'] == true,
              onChanged: (value) => setState(() => _extras['enable'] = value),
            ),
            TextFormField(
              controller: _priority,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Client priority',
                helperText: '1 is the highest priority',
                isDense: true,
              ),
              validator: (value) => int.tryParse((value ?? '').trim()) == null
                  ? 'Required'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final toggle in _toggles)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(toggle.label),
              subtitle: Text(toggle.help),
              value: _extras[toggle.key] == true,
              onChanged: (value) => setState(() => _extras[toggle.key] = value),
            ),
          ProwlarrFieldsSection(
            fields: resource.fields,
            values: _values,
            showAdvanced: _showAdvanced,
            onChanged: (name, value) => setState(() => _values[name] = value),
          ),
          const ProwlarrSectionLabel(text: 'Tags'),
          ProwlarrTagSelector(
            selected: _tags,
            onChanged: (tags) => setState(() => _tags = tags),
          ),
          if (ProwlarrFieldsSection.hasAdvanced(resource.fields))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show advanced settings'),
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
              label: Text('Delete ${widget.kind.singular}'),
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

class _Toggle {
  const _Toggle(this.key, this.label, this.help);

  final String key;
  final String label;
  final String help;
}
