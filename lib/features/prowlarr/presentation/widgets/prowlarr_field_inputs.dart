import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/prowlarr/domain/models/prowlarr_models.dart';

/// Inputs generated from a Prowlarr provider's `fields` array.
///
/// Every field-driven resource — indexers, apps, download clients,
/// notifications, indexer proxies — describes its settings through the same
/// shape, so the whole form body is one widget ([ProwlarrFieldsSection]) shared
/// by the indexer form and the generic provider form — as is the outcome those
/// sheets report back ([ProwlarrFormOutcome]).

/// What the user did with a provider form sheet.
///
/// `deleteRequested` means the form asked its caller to delete: the
/// confirmation dialog, the snackbar and the provider invalidations all belong
/// to the flow that opened the sheet, not to the sheet itself.
enum ProwlarrFormOutcome { cancelled, saved, deleteRequested }

/// Normalises a field's incoming value to what its input will show.
///
/// Prowlarr sends a select's value as a bare number *or* as a string, and a
/// definition can carry a value that is no longer among its options — the
/// dropdown falls back to the first option there, so the seed has to agree with
/// it or the form would display one option and save another. Checkboxes get the
/// same treatment for string booleans.
dynamic prowlarrSeedFieldValue(ProwlarrField field) {
  if (field.isSelect) {
    final parsed = field.value is int
        ? field.value as int
        : int.tryParse('${field.value}');
    final options = field.selectOptions.map((o) => o.value).toSet();
    if (parsed != null && options.contains(parsed)) return parsed;
    return field.selectOptions.first.value;
  }
  if (field.isCheckbox) {
    return field.value == true || field.value?.toString() == 'true';
  }
  return field.value;
}

/// Seeds an edit map for every field of [fields], hidden ones included — a
/// hidden value (Cardigann's `definitionFile`) must survive the save.
Map<String, dynamic> prowlarrSeedFieldValues(List<ProwlarrField> fields) {
  return {
    for (final field in fields) field.name: prowlarrSeedFieldValue(field),
  };
}

/// The generated body of a provider form: every visible field, grouped by its
/// `section`, in Prowlarr's own order.
class ProwlarrFieldsSection extends StatelessWidget {
  const ProwlarrFieldsSection({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.showAdvanced = false,
  });

  final List<ProwlarrField> fields;
  final Map<String, dynamic> values;
  final void Function(String name, dynamic value) onChanged;
  final bool showAdvanced;

  /// True when [fields] holds anything the advanced toggle would reveal, so a
  /// form can hide the toggle entirely.
  static bool hasAdvanced(List<ProwlarrField> fields) =>
      fields.any((field) => field.advanced && !field.isHidden);

  @override
  Widget build(BuildContext context) {
    final visible = fields
        .where((field) => !field.isHidden)
        .where((field) => showAdvanced || !field.advanced)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in _group(visible)) ...[
          if (group.section != null) ProwlarrSectionLabel(text: group.section!),
          for (final field in group.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ProwlarrFieldInput(
                field: field,
                value: values[field.name],
                onChanged: (value) => onChanged(field.name, value),
              ),
            ),
        ],
      ],
    );
  }

  static List<_FieldGroup> _group(List<ProwlarrField> fields) {
    final groups = <_FieldGroup>[];
    for (final field in fields) {
      if (groups.isEmpty || groups.last.section != field.section) {
        groups.add(_FieldGroup(field.section, [field]));
      } else {
        groups.last.fields.add(field);
      }
    }
    return groups;
  }
}

class _FieldGroup {
  _FieldGroup(this.section, this.fields);

  final String? section;
  final List<ProwlarrField> fields;
}

/// One generated input for a provider field.
class ProwlarrFieldInput extends StatelessWidget {
  const ProwlarrFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final ProwlarrField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    if (field.isInfo) {
      return _FieldInfo(field: field);
    }
    if (field.isCheckbox) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(field.displayLabel),
        subtitle: field.helpText == null ? null : Text(field.helpText!),
        value: value == true,
        onChanged: onChanged,
      );
    }
    if (field.isSelect) {
      return DropdownButtonFormField<int>(
        // Seeded (and normalised) by the form state, so the value is always one
        // of the options below — a stray one would make the dropdown assert.
        initialValue: value is int ? value : field.selectOptions.first.value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: field.displayLabel,
          helperText: field.helpText,
          isDense: true,
        ),
        items: [
          for (final option in field.selectOptions)
            DropdownMenuItem(
              value: option.value,
              child: Text(
                option.name ?? '${option.value}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );
    }
    if (field.isPassword) {
      return _PasswordInput(field: field, value: value, onChanged: onChanged);
    }

    final isNumber = field.isNumber;
    return TextFormField(
      initialValue: value?.toString() ?? '',
      keyboardType: isNumber
          ? (field.isFloat
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number)
          : (field.isTextArea ? TextInputType.multiline : TextInputType.text),
      maxLines: field.isTextArea ? 4 : 1,
      decoration: InputDecoration(
        labelText: field.unit == null
            ? field.displayLabel
            : '${field.displayLabel} (${field.unit})',
        hintText: field.placeholder,
        helperText: field.helpText,
        helperMaxLines: 3,
        isDense: true,
      ),
      onChanged: (text) {
        if (!isNumber) {
          onChanged(text);
          return;
        }
        final trimmed = text.trim();
        if (trimmed.isEmpty) {
          onChanged(null);
        } else {
          onChanged(
            field.isFloat
                ? (double.tryParse(trimmed) ?? trimmed)
                : (int.tryParse(trimmed) ?? trimmed),
          );
        }
      },
    );
  }
}

class _PasswordInput extends StatefulWidget {
  const _PasswordInput({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final ProwlarrField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<_PasswordInput> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: widget.value?.toString() ?? '',
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.field.displayLabel,
        helperText: widget.field.helpText,
        helperMaxLines: 3,
        isDense: true,
        suffixIcon: IconButton(
          icon: Icon(
            _obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            size: 18,
          ),
          tooltip: _obscured ? 'Show' : 'Hide',
          onPressed: () => setState(() => _obscured = !_obscured),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// An `info` field: Prowlarr ships instructions (often HTML) as a field value.
class _FieldInfo extends StatelessWidget {
  const _FieldInfo({required this.field});

  final ProwlarrField field;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = prowlarrPlainText(field.value?.toString() ?? '');
    if (body.isEmpty && field.helpText == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.displayLabel,
            style: Theme.of(
              context,
            ).textTheme.labelLarge!.weight(FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body.isEmpty ? field.helpText! : body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label for a field `section`, and for the form's own groups of controls.
class ProwlarrSectionLabel extends StatelessWidget {
  const ProwlarrSectionLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall!.weight(FontWeight.w800),
      ),
    );
  }
}

/// The provider message Prowlarr shows above its own edit form (e.g. "this
/// indexer needs FlareSolverr"), tinted by its `info`/`warning`/`error` type.
class ProwlarrMessageBanner extends StatelessWidget {
  const ProwlarrMessageBanner({super.key, required this.message, this.type});

  final String message;
  final String? type;

  @override
  Widget build(BuildContext context) {
    final accent = switch ((type ?? '').toLowerCase()) {
      'error' => AppColors.error,
      'warning' => AppColors.warning,
      _ => AppColors.prowlarr,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              prowlarrPlainText(message),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prowlarr writes provider instructions as HTML (`<ol><li>…`), which would
/// otherwise be rendered as tag soup inside a Flutter `Text`.
String prowlarrPlainText(String html) {
  return html
      .replaceAll(RegExp(r'<li>'), '• ')
      .replaceAll(RegExp(r'</(li|p|ol|ul|div)>'), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}
