import 'package:flutter/material.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/features/truenas/domain/models/app.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_screen.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasAppDetailScreen extends ConsumerWidget {
  final String name;
  const TrueNasAppDetailScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(truenasAppProvider(name));

    return TrueNasSectionScaffold(
      title: name,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasAppProvider(name)),
        child: app.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.detailBody()],
          ),
          error: (e, _) => ListView(
            children: [
              AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(truenasAppProvider(name)),
              ),
            ],
          ),
          data: (data) => data == null
              ? ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('App not found.'),
                    ),
                  ],
                )
              : _AppDetailBody(app: data),
        ),
      ),
    );
  }
}

/// Opens an app portal, refusing anything that is not a web address.
///
/// App portals are strings the *server* chose — a compromised TrueNAS, or just
/// a hostile chart in a third-party catalog, controls both the label and the
/// target. Handing them straight to `launchUrl` let a tile reading "Web UI"
/// fire `intent://`, `file://` or `tel:` from Cupola's context. A portal is a
/// web address; anything that isn't http/https is refused.
///
/// The allowlist itself is [UrlUtils.isLaunchableWebUri], shared with the
/// Seerr-supplied trailer URLs that need the identical guard for the identical
/// reason.
Future<void> _openPortal(BuildContext context, String rawUrl) async {
  // `Uri.tryParse` rather than `Uri.parse`: a portal string that isn't a URI at
  // all threw FormatException straight out of the tap handler.
  final uri = Uri.tryParse(rawUrl.trim());
  if (!UrlUtils.isLaunchableWebUri(uri)) {
    SnackBarHelper.error(context, 'Portal link is not a web address');
    return;
  }
  try {
    final launched = await launchUrl(
      uri!,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      SnackBarHelper.error(context, 'Nothing on this device can open $rawUrl');
    }
  } catch (e) {
    // launchUrl throws PlatformException when no handler is installed.
    if (context.mounted) {
      SnackBarHelper.error(
        context,
        'Could not open the portal link.',
        detail: e,
      );
    }
  }
}

class _AppDetailBody extends ConsumerWidget {
  final TrueNasApp app;
  const _AppDetailBody({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      children: [
        AppCard.surfaceOutlined(
          child: Row(
            children: [
              AppIcon(iconUrl: app.iconUrl, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium!.weight(FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    AppStateLabel(state: app.state, version: app.humanVersion),
                  ],
                ),
              ),
              AppLifecycleControl(app: app),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard.surfaceOutlined(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TrueNasInfoRow(label: 'Name', value: app.name),
              TrueNasInfoRow(label: 'Catalog train', value: app.train),
              TrueNasInfoRow(label: 'Version', value: app.humanVersion),
              TrueNasInfoRow(
                label: 'Update',
                value: app.upgradeAvailable ? 'Available' : 'Up to date',
              ),
            ],
          ),
        ),
        if (app.portals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const SectionHeader(title: 'Portals', showChevron: false),
          const SizedBox(height: AppSpacing.sm),
          for (final entry in app.portals.entries)
            AppCard.surfaceOutlined(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              onTap: () => _openPortal(context, entry.value),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new_rounded, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    entry.value,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
