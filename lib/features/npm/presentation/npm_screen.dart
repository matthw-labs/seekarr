import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_actions.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Nginx Proxy Manager dashboard: what the box is fronting, what is broken, and
/// which certificates are about to lapse.
class NpmScreen extends ConsumerWidget {
  const NpmScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  final bool showAppBar;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final isConfigured = settings.isServiceConfigured(
      ServiceKey.nginxProxyManager,
    );

    return AmbientScaffold(
      accent: AppColors.nginxProxyManager,
      appBar: showAppBar
          ? const GlassAppBar(title: Text('Nginx Proxy Manager'))
          : null,
      body: SafeArea(
        child: isConfigured
            ? _NpmDashboard(topPadding: topPadding)
            : _NpmNotConfigured(
                onOpenSettings: () => context.go(
                  '/settings/service/'
                  '${ServiceKey.nginxProxyManager.routeParam}',
                ),
              ),
      ),
    );
  }
}

class _NpmNotConfigured extends StatelessWidget {
  const _NpmNotConfigured({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.alt_route_rounded,
              size: 48,
              color: AppColors.nginxProxyManager,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nginx Proxy Manager is not configured yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    );
  }
}

final _invalidateAfterAction = <ProviderOrFamily>[
  npmProxyHostsProvider,
  npmCertificatesProvider,
];

void _invalidateAll(WidgetRef ref) {
  ref.invalidate(npmProxyHostsProvider);
  ref.invalidate(npmCertificatesProvider);
  ref.invalidate(npmOtherHostsProvider);
  ref.invalidate(npmServerInfoProvider);
  ref.invalidate(serviceKpiProvider(ServiceKey.nginxProxyManager));
  ref.invalidate(serviceSummaryProvider(ServiceKey.nginxProxyManager));
}

class _NpmDashboard extends ConsumerWidget {
  const _NpmDashboard({required this.topPadding});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hostsAsync = ref.watch(npmProxyHostsProvider);
    final certsAsync = ref.watch(npmCertificatesProvider);
    final otherAsync = ref.watch(npmOtherHostsProvider);
    final summaryAsync = ref.watch(
      serviceSummaryProvider(ServiceKey.nginxProxyManager),
    );
    final isOffline = summaryAsync.maybeWhen(
      data: (summary) => !summary.isOnline,
      orElse: () => false,
    );

    if (isOffline) {
      return ServiceOfflineState(
        serviceName: ServiceKey.nginxProxyManager.title,
        accent: AppColors.nginxProxyManager,
        onRetry: () => _invalidateAll(ref),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _invalidateAll(ref);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          ServiceKpiPeek(
            kpis: ref.watch(serviceKpiProvider(ServiceKey.nginxProxyManager)),
            accent: AppColors.nginxProxyManager,
          ),
          const _DefaultAdminWarning(),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Proxy hosts', showChevron: false),
          const SizedBox(height: 2),
          _ProxyHostList(hostsAsync: hostsAsync),
          const SizedBox(height: 8),
          const SectionHeader(title: 'Certificates', showChevron: false),
          const SizedBox(height: 2),
          _CertificateList(certsAsync: certsAsync),
          const SizedBox(height: 8),
          const SectionHeader(
            title: 'Redirections, 404s and streams',
            showChevron: false,
          ),
          const SizedBox(height: 2),
          _SimpleHostList(hostsAsync: otherAsync),
        ],
      ),
    );
  }
}

/// Warns when the install is old enough to still ship NPM's hard-coded default
/// administrator.
///
/// Not scaremongering: `admin@example.com` / `changeme` existed as a real
/// working login up to 2.12, and on this service that account can rewrite every
/// route on the box. If the user has one of those versions, saying so is worth
/// more than anything else on this screen.
class _DefaultAdminWarning extends ConsumerWidget {
  const _DefaultAdminWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(npmServerInfoProvider).asData?.value;
    if (info == null || !info.hasDefaultAdminRisk) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: AppRadius.borderRadiusMd,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.gpp_maybe_rounded,
              color: AppColors.warning,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Version ${info.version} still ships the default '
                'admin@example.com / changeme login. If it has not been '
                'changed, anyone who can reach this box has full control of '
                'every route on it.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProxyHostList extends ConsumerWidget {
  const _ProxyHostList({required this.hostsAsync});

  final AsyncValue<List<NpmProxyHost>> hostsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return hostsAsync.when(
      data: (hosts) {
        if (hosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No proxy hosts configured.'),
          );
        }
        // Broken first, then disabled, then the rest. A control-room screen
        // should not make you scroll to find the thing that is down.
        final ordered = [...hosts]
          ..sort((a, b) {
            int rank(NpmProxyHost h) =>
                h.hasConfigError ? 0 : (h.enabled ? 2 : 1);
            final byRank = rank(a).compareTo(rank(b));
            return byRank != 0
                ? byRank
                : a.primaryDomain.compareTo(b.primaryDomain);
          });
        return Column(
          children: ordered
              .map((host) => _ProxyHostTile(host: host))
              .toList(growable: false),
        );
      },
      loading: () => const _NpmShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load proxy hosts',
        onRetry: () => ref.invalidate(npmProxyHostsProvider),
      ),
    );
  }
}

class _ProxyHostTile extends ConsumerWidget {
  const _ProxyHostTile({required this.host});

  final NpmProxyHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final (Color tone, IconData glyph, String state) = host.hasConfigError
        ? (AppColors.error, Icons.error_outline_rounded, 'nginx error')
        : host.enabled
        ? (AppColors.success, Icons.check_circle_rounded, 'Online')
        : (
            colorScheme.onSurfaceVariant,
            Icons.pause_circle_rounded,
            'Disabled',
          );

    final detail = [
      state,
      host.target,
      if (host.hasCertificate) 'TLS',
      if (host.hasAccessList) 'Access list',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(glyph, size: 16, color: tone),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.primaryDomain,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      host.errorText.isNotEmpty ? host.errorText : detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: host.errorText.isNotEmpty
                            ? AppColors.error
                            : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _ProxyHostMenu(host: host),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProxyHostMenu extends ConsumerWidget {
  const _ProxyHostMenu({required this.host});

  final NpmProxyHost host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 18),
      tooltip: 'Host actions',
      onSelected: (value) {
        switch (value) {
          case 'enable':
            // Switching a host back **on** is the recoverable direction: it can
            // only restore service, and nginx refusing the config is reported
            // rather than hidden. No typed confirmation for that.
            runNpmAction(
              context,
              ref,
              action: (c) => c.setProxyHostEnabled(host.id, true),
              successMessage: '${host.primaryDomain} enabled',
              failureMessage: 'Failed to enable ${host.primaryDomain}',
              invalidate: _invalidateAfterAction,
            );
          case 'disable':
            _confirmDisable(context, ref, host);
        }
      },
      itemBuilder: (context) => [
        if (host.enabled)
          const PopupMenuItem(value: 'disable', child: Text('Disable…'))
        else
          const PopupMenuItem(value: 'enable', child: Text('Enable')),
      ],
    );
  }
}

Future<void> _confirmDisable(
  BuildContext context,
  WidgetRef ref,
  NpmProxyHost host,
) async {
  final confirmed = await confirmByTyping(
    context,
    title: 'Take ${host.primaryDomain} offline?',
    message:
        'Disabling this proxy host stops Nginx Proxy Manager serving that '
        'hostname. Anyone using it — not just this device — gets a connection '
        'error immediately, and nothing on the server warns them.',
    phrase: host.primaryDomain,
    confirmLabel: 'Disable',
  );
  if (!confirmed || !context.mounted) return;

  await runNpmAction(
    context,
    ref,
    action: (c) => c.setProxyHostEnabled(host.id, false),
    successMessage: '${host.primaryDomain} is now offline',
    failureMessage: 'Failed to disable ${host.primaryDomain}',
    invalidate: _invalidateAfterAction,
  );
}

class _CertificateList extends ConsumerWidget {
  const _CertificateList({required this.certsAsync});

  final AsyncValue<List<NpmCertificate>> certsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return certsAsync.when(
      data: (certs) {
        if (certs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('No certificates.'),
          );
        }
        final now = DateTime.now();
        final ordered = [...certs]
          ..sort((a, b) {
            final aDays = a.daysUntilExpiry(now) ?? 1 << 30;
            final bDays = b.daysUntilExpiry(now) ?? 1 << 30;
            return aDays.compareTo(bDays);
          });
        return Column(
          children: ordered
              .take(8)
              .map((cert) => _CertificateTile(cert: cert, now: now))
              .toList(growable: false),
        );
      },
      loading: () => const _NpmShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load certificates',
        onRetry: () => ref.invalidate(npmCertificatesProvider),
      ),
    );
  }
}

class _CertificateTile extends ConsumerWidget {
  const _CertificateTile({required this.cert, required this.now});

  final NpmCertificate cert;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final days = cert.daysUntilExpiry(now);
    final expiring = cert.isExpiringSoon(now);
    final expired = days != null && days < 0;
    final tone = expired
        ? AppColors.error
        : expiring
        ? AppColors.warning
        : AppColors.success;
    final detail = days == null
        ? cert.provider
        : expired
        ? 'Expired ${-days} days ago'
        : 'Expires in $days days';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: tone),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cert.displayName,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: expiring || expired
                            ? tone
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Renewal is offered only for Let's Encrypt certificates, and
              // only as a deliberate tap. The call reaches Let's Encrypt, so
              // binding it to anything automatic — a retry, a pull-to-refresh —
              // would burn the account's ACME rate limits and get the user's
              // domain refused for hours in a way they cannot fix from here.
              if (cert.isLetsEncrypt)
                TextButton(
                  onPressed: () => runNpmAction(
                    context,
                    ref,
                    action: (c) => c.renewCertificate(cert.id),
                    successMessage: 'Renewal requested',
                    failureMessage: 'Failed to request renewal',
                    invalidate: _invalidateAfterAction,
                  ),
                  child: const Text('Renew'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleHostList extends ConsumerWidget {
  const _SimpleHostList({required this.hostsAsync});

  final AsyncValue<List<NpmSimpleHost>> hostsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return hostsAsync.when(
      data: (hosts) {
        if (hosts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Nothing else configured.'),
          );
        }
        return Column(
          children: hosts
              .take(10)
              .map((host) => _SimpleHostTile(host: host))
              .toList(growable: false),
        );
      },
      loading: () => const _NpmShimmer(),
      error: (error, _) => _ErrorRetry(
        message: 'Failed to load the other hosts',
        onRetry: () => ref.invalidate(npmOtherHostsProvider),
      ),
    );
  }
}

class _SimpleHostTile extends StatelessWidget {
  const _SimpleHostTile({required this.host});

  final NpmSimpleHost host;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Icon(
                host.hasConfigError
                    ? Icons.error_outline_rounded
                    : Icons.subdirectory_arrow_right_rounded,
                size: 18,
                color: host.hasConfigError
                    ? AppColors.error
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  host.label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.weight(FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  host.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NpmShimmer extends StatelessWidget {
  const _NpmShimmer();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: AppRadius.borderRadiusMd,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
