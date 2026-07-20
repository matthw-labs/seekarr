import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/app_empty_state.dart';
import 'package:seekarr/core/widgets/app_error_state.dart';
import 'package:seekarr/core/widgets/app_skeleton.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/truenas/domain/models/app.dart';
import 'package:seekarr/features/truenas/presentation/apps/truenas_app_actions.dart';
import 'package:seekarr/features/truenas/presentation/apps/truenas_apps_providers.dart';
import 'package:seekarr/features/truenas/presentation/widgets/truenas_section_scaffold.dart';

class TrueNasAppsScreen extends ConsumerWidget {
  const TrueNasAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(truenasAppsProvider);

    return TrueNasSectionScaffold(
      title: 'Apps',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(truenasAppsProvider),
        child: apps.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [AppSkeleton.listRows()],
          ),
          error: (e, _) => ListView(
            children: [
              AppErrorState(
                error: e,
                onRetry: () => ref.invalidate(truenasAppsProvider),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? const AppEmptyState(
                  icon: Icons.apps_rounded,
                  title: 'No apps installed',
                  message: 'Install apps from the TrueNAS catalog.',
                  accentColor: AppColors.truenas,
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: [
                    for (final app in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _AppCard(app: app),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AppCard extends ConsumerWidget {
  final TrueNasApp app;
  const _AppCard({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PressableScale(
      onTap: () => context.push(ServiceRoutes.truenasApp(app.name)),
      child: AppCard.surfaceOutlined(
        child: Row(
          children: [
            AppIcon(iconUrl: app.iconUrl),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          app.title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (app.upgradeAvailable) ...[
                        const SizedBox(width: 6),
                        const _UpgradeBadge(),
                      ],
                    ],
                  ),
                  AppStateLabel(state: app.state, version: app.humanVersion),
                ],
              ),
            ),
            AppLifecycleControl(app: app),
          ],
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  final String? iconUrl;
  const AppIcon({super.key, this.iconUrl, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.truenas.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.apps_rounded, size: 20, color: AppColors.truenas),
    );
    final url = iconUrl;
    if (url == null || url.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => placeholder,
        placeholder: (_, __) => placeholder,
      ),
    );
  }
}

class AppStateLabel extends StatelessWidget {
  final String state;
  final String? version;
  const AppStateLabel({super.key, required this.state, this.version});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upper = state.toUpperCase();
    final color = upper == 'RUNNING'
        ? AppColors.success
        : upper == 'CRASHED'
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          version != null ? '$upper · $version' : upper,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _UpgradeBadge extends StatelessWidget {
  const _UpgradeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'UPDATE',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.info,
          fontWeight: FontWeight.w700,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// Start/stop + overflow (upgrade/delete) control shared with the detail view.
class AppLifecycleControl extends ConsumerWidget {
  final TrueNasApp app;
  const AppLifecycleControl({super.key, required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            app.isRunning
                ? Icons.stop_circle_outlined
                : Icons.play_circle_outline,
            color: app.isRunning ? null : AppColors.success,
          ),
          tooltip: app.isRunning ? 'Stop' : 'Start',
          onPressed: () => appLifecycleAction(
            context,
            ref,
            app: app,
            action: app.isRunning ? AppAction.stop : AppAction.start,
          ),
        ),
        PopupMenuButton<AppAction>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) =>
              appLifecycleAction(context, ref, app: app, action: action),
          itemBuilder: (context) => [
            if (app.upgradeAvailable)
              const PopupMenuItem(
                value: AppAction.upgrade,
                child: Text('Upgrade'),
              ),
            const PopupMenuItem(value: AppAction.delete, child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}
