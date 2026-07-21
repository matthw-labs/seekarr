import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_dialog.dart';
import 'package:seekarr/core/widgets/domain_section.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

class SettingsServicesScreen extends ConsumerWidget {
  const SettingsServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final theme = Theme.of(context);

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Services')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        children: [
          for (final domain in ServiceDomain.values) ...[
            DomainSectionHeader(label: domain.label),
            SettingsGroupCard(
              children: [
                for (final service in domain.services)
                  _serviceRow(context, ref, settings, theme, service),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _serviceRow(
    BuildContext context,
    WidgetRef ref,
    SettingsModel settings,
    ThemeData theme,
    ServiceKey service,
  ) {
    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      subtitle: _serviceSubtitle(settings, service),
      accentColor: service.accent,
      onTap: () => context.push('/settings/service/${service.routeParam}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isConfigured(settings, service))
            _DeleteButton(
              serviceName: service.title,
              onConfirm: () async {
                final cleared = service == ServiceKey.qbittorrent
                    ? settings.copyWithQbittorrent(
                        url: '',
                        username: '',
                        password: '',
                      )
                    : settings.copyWithService(service, url: '', apiKey: '');
                await ref
                    .read(settingsProvider.notifier)
                    .updateSettings(cleared);
              },
            ),
          Icon(
            Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  bool _isConfigured(SettingsModel settings, ServiceKey service) {
    return settings.isServiceConfigured(service);
  }

  String _serviceSubtitle(SettingsModel settings, ServiceKey service) {
    final url = settings.urlFor(service);
    return url.isEmpty ? 'Not configured' : service.extractHost(url) ?? url;
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.serviceName, required this.onConfirm});

  final String serviceName;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete_outline_rounded),
      color: Theme.of(context).colorScheme.error,
      iconSize: 20,
      tooltip: 'Remove credentials',
      visualDensity: VisualDensity.compact,
      onPressed: () => _showConfirmation(context),
    );
  }

  Future<void> _showConfirmation(BuildContext context) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Remove $serviceName',
      message:
          'This will delete all saved credentials and disconnect $serviceName.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (result.confirmed) {
      onConfirm();
    }
  }
}
