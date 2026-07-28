import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:seekarr/core/widgets/floating_bottom_nav_bar.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/service_theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/truenas/presentation/system/truenas_diagnostics_screen.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class _SystemEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String section;
  const _SystemEntry(this.title, this.subtitle, this.icon, this.section);
}

const _entries = <_SystemEntry>[
  _SystemEntry('General', 'Timezone & language', Icons.tune_rounded, 'general'),
  _SystemEntry(
    'Advanced',
    'Console & syslog',
    Icons.developer_mode_rounded,
    'advanced',
  ),
  _SystemEntry('Services', 'Start & stop', Icons.bolt_rounded, 'services'),
  _SystemEntry('Network', 'Interfaces & DNS', Icons.lan_rounded, 'network'),
  _SystemEntry(
    'Credentials',
    'Users & groups',
    Icons.group_rounded,
    'credentials',
  ),
  _SystemEntry(
    'Certificates',
    'TLS certificates',
    Icons.verified_user_rounded,
    'certificates',
  ),
  _SystemEntry('Email', 'Alerts delivery', Icons.email_rounded, 'email'),
  _SystemEntry(
    'Update',
    'System updates',
    Icons.system_update_rounded,
    'update',
  ),
  _SystemEntry('NTP Servers', 'Time sync', Icons.schedule_rounded, 'ntp'),
  _SystemEntry(
    'Alert Settings',
    'Notification services',
    Icons.notifications_rounded,
    'alert-settings',
  ),
];

class TrueNasSystemHubScreen extends StatelessWidget {
  const TrueNasSystemHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TrueNasSectionScaffold(
      title: 'System',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.4,
            children: [for (final entry in _entries) _SystemTile(entry: entry)],
          ),
          // Entry point for inspecting raw JSON-RPC responses. Debug builds
          // only: the screen dumps server payloads verbatim with a copy button,
          // which must never ship to release even while today's probes are
          // limited to non-sensitive methods.
          if (kDebugMode) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TrueNasDiagnosticsScreen(),
                ),
              ),
              icon: const Icon(Icons.bug_report_rounded, size: 18),
              label: const Text('Diagnostics (debug)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SystemTile extends StatelessWidget {
  final _SystemEntry entry;
  const _SystemTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serviceTheme = serviceThemeFor(ServiceKey.truenas);
    return PressableScale(
      onTap: () =>
          context.push(ServiceRoutes.truenasSystemSection(entry.section)),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: serviceTheme.softContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(entry.icon, size: 19, color: serviceTheme.accent),
            ),
            const Spacer(),
            Text(
              entry.title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
