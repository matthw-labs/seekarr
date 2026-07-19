import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/widgets/widgets.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DiscoverWatchProviders extends StatelessWidget {
  final WatchProviderRegion? providers;
  final String region;

  const DiscoverWatchProviders({
    super.key,
    required this.providers,
    required this.region,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaDetailSectionHeader(
          title: 'Where to Watch',
          accent: ServiceKey.seerr.accent,
        ),
        if (providers == null)
          Text(
            'Watch provider info is not available in your region ($region).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          )
        else
          _ProvidersContent(providers: providers!),
      ],
    );
  }
}

class _ProvidersContent extends StatelessWidget {
  final WatchProviderRegion providers;

  const _ProvidersContent({required this.providers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedTextStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    if (providers.flatrate.isEmpty && providers.buy.isEmpty) {
      return Text(
        'No streaming or purchase options available.',
        style: mutedTextStyle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (providers.flatrate.isNotEmpty) ...[
          _ProviderGroupLabel(label: 'Stream'),
          const SizedBox(height: AppSpacing.xs),
          _WatchProviderRow(entries: providers.flatrate),
        ],
        if (providers.flatrate.isNotEmpty && providers.buy.isNotEmpty)
          const SizedBox(height: AppSpacing.sm),
        if (providers.buy.isNotEmpty) ...[
          _ProviderGroupLabel(label: 'Buy / Rent'),
          const SizedBox(height: AppSpacing.xs),
          _WatchProviderRow(entries: providers.buy),
        ],
      ],
    );
  }
}

class _WatchProviderRow extends StatelessWidget {
  final List<WatchProviderEntry> entries;

  const _WatchProviderRow({required this.entries});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _WatchProviderTile(entry: entries[index]),
      ),
    );
  }
}

class _WatchProviderTile extends StatelessWidget {
  final WatchProviderEntry entry;

  const _WatchProviderTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logoPath = entry.logoPath;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: ClipOval(
              child: logoPath != null && logoPath.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w92$logoPath',
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Icon(
                        Icons.play_circle_outline,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Icon(
                      Icons.play_circle_outline,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderGroupLabel extends StatelessWidget {
  final String label;

  const _ProviderGroupLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}
