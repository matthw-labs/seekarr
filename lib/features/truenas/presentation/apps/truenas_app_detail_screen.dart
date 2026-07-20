import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/section_header.dart';
import 'package:seekarr/features/truenas/domain/models/app.dart';
import 'package:seekarr/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:seekarr/features/truenas/presentation/apps/truenas_apps_screen.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_info_row.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

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

class _AppDetailBody extends ConsumerWidget {
  final TrueNasApp app;
  const _AppDetailBody({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
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
              onTap: () => launchUrl(
                Uri.parse(entry.value),
                mode: LaunchMode.externalApplication,
              ),
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
