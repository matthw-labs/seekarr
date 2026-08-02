import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/ambient_scaffold.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/domain_section.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/presentation/widgets/service_connection_row.dart';

/// Every service Seekarr can talk to, and the state of each connection.
///
/// This is the one place a service's setup lives. The settings home used to
/// list configured services with their status while a second screen listed all
/// thirteen with a delete button and no status — two doors to the same room,
/// neither of them complete.
class SettingsConnectionsScreen extends ConsumerWidget {
  const SettingsConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    final available = ServiceKey.values
        .where((service) => !settings.isServiceConfigured(service))
        .toList(growable: false);

    return AmbientScaffold(
      appBar: const GlassAppBar(title: Text('Connections')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          // The nav bar floats over this content and grows with the reading
          // size, so the last row is only reachable if the list reserves for it.
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (configured.isNotEmpty) ...[
            SectionHeader(
              // Not "Connected": this section is what has an address saved,
              // and one of them being unreachable is exactly why you are here.
              title: 'Your services',
              showChevron: false,
              trailing: _CountChip(count: configured.length),
              semanticLabel:
                  '${configured.length} of ${ServiceKey.values.length} '
                  'services set up',
            ),
            for (final domain in ServiceDomain.values)
              ..._domainGroup(context, domain, configured),
            const SizedBox(height: AppSpacing.xl),
          ],
          SectionHeader(
            title: available.isEmpty ? 'Everything is set up' : 'Add a service',
            showChevron: false,
            subtitle: available.isEmpty
                ? 'All ${ServiceKey.values.length} services Seekarr supports '
                      'have an address saved.'
                : 'Seekarr talks straight to your instance. Nothing is stored '
                      'anywhere but this device.',
          ),
          if (available.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            SettingsGroupCard(
              children: [
                for (final service in available)
                  ServiceConnectionRow(
                    service: service,
                    onTap: () => _open(context, service),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Icon(
                Icons.check_circle_outline_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _domainGroup(
    BuildContext context,
    ServiceDomain domain,
    List<ServiceKey> configured,
  ) {
    final services = configured
        .where((service) => service.domain == domain)
        .toList(growable: false);
    if (services.isEmpty) return const [];

    return [
      DomainSectionHeader(
        label: domain.label,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
      ),
      SettingsGroupCard(
        children: [
          for (final service in services)
            ServiceConnectionRow(
              service: service,
              onTap: () => _open(context, service),
            ),
        ],
      ),
    ];
  }

  void _open(BuildContext context, ServiceKey service) {
    context.push('/settings/service/${service.routeParam}');
  }
}

/// The number of connected services, sized as a label rather than a figure —
/// it qualifies the heading, it is not a readout in its own right.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Text(
        '$count of ${ServiceKey.values.length}',
        style: AppTheme.eyebrow(colorScheme.onSurfaceVariant),
      ),
    );
  }
}
