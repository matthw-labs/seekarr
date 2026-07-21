import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/snack_bar_helper.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/dockge/presentation/dockge_actions.dart';
import 'package:seekarr/features/dockge/presentation/dockge_provider.dart';

const _defaultCompose = '''services:
  app:
    image: nginx:latest
    restart: unless-stopped
    ports:
      - "8080:80"
''';

/// Compose editor for creating a new stack or editing an existing one.
class DockgeStackEditScreen extends ConsumerStatefulWidget {
  const DockgeStackEditScreen({super.key, this.name});

  /// The stack to edit. `null` creates a new stack.
  final String? name;

  bool get isNew => name == null;

  @override
  ConsumerState<DockgeStackEditScreen> createState() =>
      _DockgeStackEditScreenState();
}

class _DockgeStackEditScreenState extends ConsumerState<DockgeStackEditScreen> {
  final _nameCtrl = TextEditingController();
  final _yamlCtrl = TextEditingController();
  final _envCtrl = TextEditingController();
  bool _prefilled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _yamlCtrl.text = _defaultCompose;
      _prefilled = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _yamlCtrl.dispose();
    _envCtrl.dispose();
    super.dispose();
  }

  /// Allowed stack-name shape, matching Dockge's own frontend validation:
  /// lowercase alphanumerics plus `_`/`-`, and must start with an alphanumeric.
  static final RegExp _namePattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');

  String get _effectiveName =>
      widget.isNew ? _nameCtrl.text.trim() : widget.name!;

  Future<void> _submit({required bool deploy}) async {
    final name = _effectiveName;
    if (name.isEmpty) {
      SnackBarHelper.error(context, 'Stack name is required');
      return;
    }
    if (widget.isNew && !_namePattern.hasMatch(name)) {
      SnackBarHelper.error(
        context,
        'Stack name may only contain lowercase letters, numbers, '
        'dashes and underscores, and must start with a letter or number',
      );
      return;
    }
    setState(() => _busy = true);
    final yaml = _yamlCtrl.text;
    final env = _envCtrl.text;
    final ok = await runDockgeAction(
      context,
      ref,
      action: (client) => deploy
          ? client.deployStack(
              name: name,
              composeYAML: yaml,
              composeENV: env,
              isAdd: widget.isNew,
            )
          : client.saveStack(
              name: name,
              composeYAML: yaml,
              composeENV: env,
              isAdd: widget.isNew,
            ),
      successMessage: deploy ? 'Deployed $name' : 'Saved $name',
      failureMessage: deploy ? 'Deploy failed' : 'Save failed',
      invalidate: [dockgeStackListProvider, dockgeStackDetailProvider(name)],
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Prefill from the existing stack once.
    if (!_prefilled && !widget.isNew) {
      final detailAsync = ref.watch(dockgeStackDetailProvider(widget.name!));
      detailAsync.whenData((detail) {
        _yamlCtrl.text = detail.composeYAML;
        _envCtrl.text = detail.composeENV;
        _prefilled = true;
      });
    }

    return AmbientScaffold(
      accent: AppColors.dockge,
      appBar: GlassAppBar(
        title: Text(widget.isNew ? 'New stack' : 'Edit ${widget.name}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (widget.isNew) ...[
              _Label('Stack name'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                decoration: _inputDecoration(context, 'my-stack'),
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 16),
            ],
            _Label('compose.yaml'),
            const SizedBox(height: 6),
            _CodeField(controller: _yamlCtrl, minLines: 14),
            const SizedBox(height: 16),
            _Label('.env (optional)'),
            const SizedBox(height: 6),
            _CodeField(controller: _envCtrl, minLines: 4),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _submit(deploy: false),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _submit(deploy: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.dockge,
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.rocket_launch_rounded, size: 18),
                    label: const Text('Deploy'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusMd,
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, required this.minLines});

  final TextEditingController controller;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: null,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.multiline,
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        height: 1.4,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFF0A0B11),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusMd,
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
