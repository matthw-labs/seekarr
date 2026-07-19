import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class ServicesOnlineSummary extends ConsumerWidget {
  const ServicesOnlineSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ServiceKey.values
        .map((service) => ref.watch(serviceSummaryProvider(service)))
        .toList(growable: false);
    final online = summaries
        .where((summary) => summary.asData?.value.isOnline ?? false)
        .length;
    final color = online > 0
        ? AppColors.success
        : Theme.of(context).colorScheme.error;

    return Tooltip(
      message: '$online online, ${ServiceKey.values.length - online} offline',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class ServiceStatusGrid extends ConsumerWidget {
  const ServiceStatusGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = ServiceKey.values
        .where((s) => settings.isServiceConfigured(s))
        .toList(growable: false);

    if (services.isEmpty) return const SizedBox.shrink();

    final cols = (services.length / 2).ceil();
    final rows = services.length > 1 ? 2 : 1;
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Show first column fully + ~80% of the second column to hint scrolling.
    final cardWidth = (screenWidth - AppSpacing.lg - AppSpacing.sm) / 1.8;
    const cardHeight = 76.0;
    final gridHeight = cardHeight * rows + (rows > 1 ? AppSpacing.sm : 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.md),
      child: SizedBox(
        height: gridHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: cols,
          separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, colIndex) {
            final top = services[colIndex * 2];
            final bottomIdx = colIndex * 2 + 1;
            final bottom = bottomIdx < services.length
                ? services[bottomIdx]
                : null;

            return SizedBox(
              width: cardWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: cardHeight,
                    child: _ServiceStatusCard(service: top),
                  ),
                  if (bottom != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: cardHeight,
                      child: _ServiceStatusCard(service: bottom),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ServiceStatusCard extends ConsumerWidget {
  final ServiceKey service;

  const _ServiceStatusCard({required this.service});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(serviceSummaryProvider(service));
    final settings = ref.watch(currentSettingsProvider);
    final fallbackHost = service.extractHost(settings.urlFor(service)) ?? '';

    return summary.when(
      data: (value) => _ServiceStatusCardBody(summary: value),
      loading: () => _ServiceStatusCardBody(
        summary: ServiceSummary(
          service: service,
          status: ServiceSummaryStatus.offline,
          host: fallbackHost,
          version: null,
          itemCount: null,
          itemLabel: service.itemLabel,
        ),
        isChecking: true,
      ),
      error: (_, __) => _ServiceStatusCardBody(
        summary: ServiceSummary(
          service: service,
          status: ServiceSummaryStatus.offline,
          host: fallbackHost,
          version: null,
          itemCount: null,
          itemLabel: service.itemLabel,
        ),
      ),
    );
  }
}

class _ServiceStatusCardBody extends StatelessWidget {
  final ServiceSummary summary;
  final bool isChecking;

  const _ServiceStatusCardBody({
    required this.summary,
    this.isChecking = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = summary.service;
    final isOnline = summary.isOnline && !isChecking;
    final statusText = isChecking ? 'Checking' : summary.statusLabel;
    final statusColor = isOnline
        ? AppColors.success
        : isChecking
        ? AppColors.warning
        : colorScheme.error;
    final borderColor = isOnline
        ? service.accent.withValues(alpha: 0.27)
        : colorScheme.error.withValues(alpha: 0.18);

    return AppCard.outlined(
      onTap: () => context.push('/services/${service.routeParam}'),
      backgroundColor: colorScheme.surfaceContainer,
      borderColor: borderColor,
      borderRadius: AppRadius.borderRadiusLg,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: service.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(service.icon, size: 15, color: service.accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  service.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    statusText.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  summary.host.isEmpty ? '—' : summary.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                summary.countLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
