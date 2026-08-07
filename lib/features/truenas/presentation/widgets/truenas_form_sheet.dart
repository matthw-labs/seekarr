import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A single field in a [showTrueNasFormSheet] form.
class TrueNasFormField {
  final String key;
  final String label;
  final String? initialValue;
  final bool boolField;
  final bool initialBool;
  final bool required;
  final bool obscure;
  final TextInputType keyboardType;
  final String? hint;
  final bool enabled;

  const TrueNasFormField({
    required this.key,
    required this.label,
    this.initialValue,
    this.boolField = false,
    this.initialBool = false,
    this.required = false,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.hint,
    this.enabled = true,
  });
}

/// Shows a scrollable form sheet and returns the entered values keyed by field
/// key (text fields as `String`, bool fields as `bool`), or null if cancelled.
/// Empty optional text fields are omitted from the result.
Future<Map<String, dynamic>?> showTrueNasFormSheet({
  required BuildContext context,
  required String title,
  required List<TrueNasFormField> fields,
  String submitLabel = 'Save',
  String? subtitle,
}) {
  return AppBottomSheet.showScrollable<Map<String, dynamic>>(
    context: context,
    title: title,
    subtitle: subtitle,
    accent: ServiceKey.truenas.accent,
    initialSize: 0.7,
    builder: (context, controller) => _FormBody(
      controller: controller,
      fields: fields,
      submitLabel: submitLabel,
    ),
  );
}

class _FormBody extends StatefulWidget {
  final ScrollController controller;
  final List<TrueNasFormField> fields;
  final String submitLabel;

  const _FormBody({
    required this.controller,
    required this.fields,
    required this.submitLabel,
  });

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, bool> _bools;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final f in widget.fields)
        if (!f.boolField)
          f.key: TextEditingController(text: f.initialValue ?? ''),
    };
    _bools = {
      for (final f in widget.fields)
        if (f.boolField) f.key: f.initialBool,
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final result = <String, dynamic>{};
    for (final f in widget.fields) {
      if (f.boolField) {
        result[f.key] = _bools[f.key];
      } else {
        final text = _controllers[f.key]!.text.trim();
        if (text.isNotEmpty) result[f.key] = text;
      }
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
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
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: f.boolField
                  ? SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(f.label),
                      value: _bools[f.key]!,
                      onChanged: f.enabled
                          ? (v) => setState(() => _bools[f.key] = v)
                          : null,
                    )
                  : TextFormField(
                      controller: _controllers[f.key],
                      enabled: f.enabled,
                      obscureText: f.obscure,
                      keyboardType: f.keyboardType,
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText: f.hint,
                      ),
                      validator: f.required
                          ? (v) => (v == null || v.trim().isEmpty)
                                ? '${f.label} is required'
                                : null
                          : null,
                    ),
            ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
        ],
      ),
    );
  }
}
