import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/dynamic_map_utils.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/truenas/presentation/system/truenas_config_edit.dart';
import 'package:seekarr/features/truenas/presentation/system/truenas_system_providers.dart';
import 'package:seekarr/features/truenas/presentation/truenas_actions.dart';
import 'package:seekarr/features/truenas/presentation/truenas_provider.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_form_sheet.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

/// Renders an async config map/list into a standard section scaffold.
class _AsyncSection<T> extends StatelessWidget {
  final String title;
  final AsyncValue<T> value;
  final VoidCallback onRefresh;
  final Widget Function(T data) builder;
  final List<Widget>? actions;

  const _AsyncSection({
    required this.title,
    required this.value,
    required this.onRefresh,
    required this.builder,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: title,
      actions: actions,
      body: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: value.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          error: (e, _) => ListView(
            children: [AppErrorState(error: e, onRetry: onRefresh)],
          ),
          data: (data) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
            ),
            children: [builder(data)],
          ),
        ),
      ),
    );
  }
}

Widget _infoCard(List<TrueNasInfoRow> rows) => AppCard.surfaceOutlined(
  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
);

// ── General ────────────────────────────────────────────────────────────────
class TrueNasGeneralScreen extends ConsumerWidget {
  const TrueNasGeneralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(truenasGeneralConfigProvider);
    return _AsyncSection<Map<String, dynamic>>(
      title: 'General',
      value: config,
      onRefresh: () => ref.invalidate(truenasGeneralConfigProvider),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: () {
            final data = config.asData?.value ?? const {};
            editTrueNasConfig(
              context: context,
              ref: ref,
              title: 'Edit general',
              current: data,
              labels: const {'timezone': 'Timezone', 'language': 'Language'},
              fields: [
                TrueNasFormField(
                  key: 'timezone',
                  label: 'Timezone',
                  initialValue: stringOrNull(data['timezone']),
                ),
                TrueNasFormField(
                  key: 'language',
                  label: 'Language',
                  initialValue: stringOrNull(data['language']),
                ),
              ],
              apply: (patch) =>
                  ref.read(truenasSystemApiProvider).updateGeneralConfig(patch),
              invalidate: [truenasGeneralConfigProvider],
            );
          },
        ),
      ],
      builder: (data) => _infoCard([
        TrueNasInfoRow(
          label: 'Timezone',
          value: stringOrNull(data['timezone']),
        ),
        TrueNasInfoRow(
          label: 'Language',
          value: stringOrNull(data['language']),
        ),
        TrueNasInfoRow(label: 'Keyboard', value: stringOrNull(data['kbdmap'])),
        TrueNasInfoRow(
          label: 'UI HTTP port',
          value: intOrNull(data['ui_port'])?.toString(),
        ),
        TrueNasInfoRow(
          label: 'UI HTTPS port',
          value: intOrNull(data['ui_httpsport'])?.toString(),
        ),
      ]),
    );
  }
}

// ── Advanced ─────────────────────────────────────────────────────────────
class TrueNasAdvancedScreen extends ConsumerWidget {
  const TrueNasAdvancedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(truenasAdvancedConfigProvider);
    return _AsyncSection<Map<String, dynamic>>(
      title: 'Advanced',
      value: config,
      onRefresh: () => ref.invalidate(truenasAdvancedConfigProvider),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: () {
            final data = config.asData?.value ?? const {};
            editTrueNasConfig(
              context: context,
              ref: ref,
              title: 'Edit advanced',
              current: data,
              labels: const {
                'consolemenu': 'Console menu',
                'serialconsole': 'Serial console',
                'sysloglevel': 'Syslog level',
                'syslogserver': 'Syslog server',
                'motd': 'Motd',
              },
              fields: [
                TrueNasFormField(
                  key: 'consolemenu',
                  label: 'Console menu',
                  boolField: true,
                  initialBool: data['consolemenu'] == true,
                ),
                TrueNasFormField(
                  key: 'serialconsole',
                  label: 'Serial console',
                  boolField: true,
                  initialBool: data['serialconsole'] == true,
                ),
                TrueNasFormField(
                  key: 'sysloglevel',
                  label: 'Syslog level',
                  initialValue: stringOrNull(data['sysloglevel']),
                  hint: 'e.g. F_INFO',
                ),
                TrueNasFormField(
                  key: 'syslogserver',
                  label: 'Syslog server',
                  initialValue: stringOrNull(data['syslogserver']),
                ),
                TrueNasFormField(
                  key: 'motd',
                  label: 'Motd',
                  initialValue: stringOrNull(data['motd']),
                ),
              ],
              apply: (patch) => ref
                  .read(truenasSystemApiProvider)
                  .updateAdvancedConfig(patch),
              invalidate: [truenasAdvancedConfigProvider],
            );
          },
        ),
      ],
      builder: (data) => _infoCard([
        TrueNasInfoRow(
          label: 'Console menu',
          value: data['consolemenu'] == true ? 'Enabled' : 'Disabled',
        ),
        TrueNasInfoRow(
          label: 'Serial console',
          value: data['serialconsole'] == true ? 'Enabled' : 'Disabled',
        ),
        TrueNasInfoRow(
          label: 'Syslog level',
          value: stringOrNull(data['sysloglevel']),
        ),
        TrueNasInfoRow(
          label: 'Syslog server',
          value: stringOrNull(data['syslogserver']),
        ),
        TrueNasInfoRow(label: 'Motd', value: stringOrNull(data['motd'])),
      ]),
    );
  }
}

// ── Network ────────────────────────────────────────────────────────────────
class TrueNasNetworkScreen extends ConsumerWidget {
  const TrueNasNetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(truenasNetworkConfigProvider);
    final interfaces = ref.watch(truenasInterfacesProvider);
    return _AsyncSection(
      title: 'Network',
      value: config,
      onRefresh: () {
        ref.invalidate(truenasNetworkConfigProvider);
        ref.invalidate(truenasInterfacesProvider);
      },
      builder: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard([
            TrueNasInfoRow(label: 'Hostname', value: data.hostname),
            TrueNasInfoRow(label: 'Domain', value: data.domain),
            TrueNasInfoRow(label: 'IPv4 gateway', value: data.ipv4Gateway),
            TrueNasInfoRow(
              label: 'Nameservers',
              value: data.nameservers.isEmpty
                  ? null
                  : data.nameservers.join(', '),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          const SectionHeader(title: 'Interfaces', showChevron: false),
          const SizedBox(height: AppSpacing.sm),
          interfaces.when(
            loading: () => AppSkeleton.listRows(count: 2),
            error: (e, _) => AppErrorState(
              error: e,
              onRetry: () => ref.invalidate(truenasInterfacesProvider),
            ),
            data: (list) => Column(
              children: [
                for (final iface in list)
                  AppCard.surfaceOutlined(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            iface.name,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.weight(FontWeight.w600),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            iface.addresses.isEmpty
                                ? (iface.linkState ?? '—')
                                : iface.addresses.join(', '),
                            style: Theme.of(context).textTheme.labelSmall,
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Email ────────────────────────────────────────────────────────────────
class TrueNasEmailScreen extends ConsumerWidget {
  const TrueNasEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(truenasMailConfigProvider);
    return _AsyncSection<Map<String, dynamic>>(
      title: 'Email',
      value: config,
      onRefresh: () => ref.invalidate(truenasMailConfigProvider),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit',
          onPressed: () {
            final data = config.asData?.value ?? const {};
            editTrueNasConfig(
              context: context,
              ref: ref,
              title: 'Edit email',
              current: data,
              intKeys: const {'port'},
              labels: const {
                'fromemail': 'From',
                'outgoingserver': 'Server',
                'port': 'Port',
                'security': 'Security',
                'user': 'Username',
              },
              fields: [
                TrueNasFormField(
                  key: 'fromemail',
                  label: 'From',
                  initialValue: stringOrNull(data['fromemail']),
                  keyboardType: TextInputType.emailAddress,
                ),
                TrueNasFormField(
                  key: 'outgoingserver',
                  label: 'Server',
                  initialValue: stringOrNull(data['outgoingserver']),
                ),
                TrueNasFormField(
                  key: 'port',
                  label: 'Port',
                  initialValue: intOrNull(data['port'])?.toString(),
                  keyboardType: TextInputType.number,
                ),
                TrueNasFormField(
                  key: 'security',
                  label: 'Security',
                  initialValue: stringOrNull(data['security']),
                  hint: 'PLAIN · SSL · TLS',
                ),
                TrueNasFormField(
                  key: 'user',
                  label: 'Username',
                  initialValue: stringOrNull(data['user']),
                ),
              ],
              apply: (patch) =>
                  ref.read(truenasSystemApiProvider).updateMailConfig(patch),
              invalidate: [truenasMailConfigProvider],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.send_rounded),
          tooltip: 'Send test email',
          onPressed: () => runTrueNasAction(
            context,
            ref,
            action: () => ref.read(truenasSystemApiProvider).sendTestMail(null),
            successMessage: 'Test email sent',
            failureMessage: 'Could not send test email',
          ),
        ),
      ],
      builder: (data) => _infoCard([
        TrueNasInfoRow(label: 'From', value: stringOrNull(data['fromemail'])),
        TrueNasInfoRow(
          label: 'Server',
          value: stringOrNull(data['outgoingserver']),
        ),
        TrueNasInfoRow(
          label: 'Port',
          value: intOrNull(data['port'])?.toString(),
        ),
        TrueNasInfoRow(
          label: 'Security',
          value: stringOrNull(data['security']),
        ),
        TrueNasInfoRow(label: 'Username', value: stringOrNull(data['user'])),
      ]),
    );
  }
}

// ── Update ───────────────────────────────────────────────────────────────
class TrueNasUpdateScreen extends ConsumerWidget {
  const TrueNasUpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(truenasUpdateStatusProvider);
    return _AsyncSection<Map<String, dynamic>>(
      title: 'Update',
      value: status,
      onRefresh: () => ref.invalidate(truenasUpdateStatusProvider),
      builder: (data) {
        final available =
            data['status'] == 'AVAILABLE' || data['available'] == true;
        final version =
            stringOrNull(data['version']) ??
            stringOrNull(mapOrNull(data['new_version'])?['version']);
        return _infoCard([
          TrueNasInfoRow(
            label: 'Status',
            value: available ? 'Update available' : 'Up to date',
          ),
          TrueNasInfoRow(label: 'Available version', value: version),
        ]);
      },
    );
  }
}

// ── Certificates ───────────────────────────────────────────────────────────
class TrueNasCertificatesScreen extends ConsumerWidget {
  const TrueNasCertificatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final certs = ref.watch(truenasCertificatesProvider);
    return _AsyncSection<List<Map<String, dynamic>>>(
      title: 'Certificates',
      value: certs,
      onRefresh: () => ref.invalidate(truenasCertificatesProvider),
      builder: (list) => list.isEmpty
          ? _infoCard([
              const TrueNasInfoRow(label: 'Certificates', value: 'None'),
            ])
          : Column(
              children: [
                for (final cert in list)
                  AppCard.surfaceOutlined(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stringOrNull(cert['name']) ?? '—',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          stringOrNull(cert['issuer']) ?? '',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── NTP ────────────────────────────────────────────────────────────────────
class TrueNasNtpScreen extends ConsumerWidget {
  const TrueNasNtpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(truenasNtpServersProvider);
    return _AsyncSection<List<Map<String, dynamic>>>(
      title: 'NTP Servers',
      value: servers,
      onRefresh: () => ref.invalidate(truenasNtpServersProvider),
      builder: (list) => Column(
        children: [
          for (final server in list)
            AppCard.surfaceOutlined(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      stringOrNull(server['address']) ?? '—',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Alert Settings ───────────────────────────────────────────────────────
class TrueNasAlertSettingsScreen extends ConsumerWidget {
  const TrueNasAlertSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(truenasAlertServicesProvider);
    return _AsyncSection<List<Map<String, dynamic>>>(
      title: 'Alert Settings',
      value: services,
      onRefresh: () => ref.invalidate(truenasAlertServicesProvider),
      builder: (list) => list.isEmpty
          ? _infoCard([
              const TrueNasInfoRow(
                label: 'Alert services',
                value: 'None configured',
              ),
            ])
          : Column(
              children: [
                for (final service in list)
                  AppCard.surfaceOutlined(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            stringOrNull(service['name']) ??
                                stringOrNull(service['type']) ??
                                '—',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          service['enabled'] == true ? 'On' : 'Off',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
