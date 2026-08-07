import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/network/pinned_image_cache.dart';
import 'package:seekarr/core/text_scale.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/features/discover/domain/models/discover_detail_model.dart';

/// Where a title can be streamed or bought, in the viewer's region.
///
/// Headless: the heading comes from the `MediaDetailSlot` that hosts it, so the
/// same list can never reach two differently-titled sections and the heading
/// cannot lose its accent or its `Semantics(header: true)`.
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

    if (providers == null) {
      return Text(
        'Watch provider info is not available in your region ($region).',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return _ProvidersContent(providers: providers!);
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

/// Height of a provider pill at the default reading size: an 18pt logo beside
/// one line of `labelSmall`, plus vertical breathing room.
const double _providerTileBaseHeight = 34;

/// The growing half of [_providerTileBaseHeight]: one line of `labelSmall`
/// (11pt at 1.22 leading).
const double _providerLabelHeight = 14;

/// The pill height for the current reading size. The logo is the fixed half,
/// the provider name the growing half, so the row and the pills inside it agree
/// on one number instead of two constants that drift.
double _providerTileHeight(BuildContext context) => TextScaleMetrics.boxHeight(
  context,
  base: _providerTileBaseHeight,
  textHeight: _providerLabelHeight,
);

class _WatchProviderRow extends StatelessWidget {
  final List<WatchProviderEntry> entries;

  const _WatchProviderRow({required this.entries});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _providerTileHeight(context),
      // The pills must lay their names out on the same clamp the row grew by,
      // or an accessibility reader gets an overflow stripe instead of the
      // ellipsis the clamp promises.
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: entries.length,
          separatorBuilder: (context, index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (context, index) =>
              _WatchProviderTile(entry: entries[index]),
        ),
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
      height: _providerTileHeight(context),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        // Non-interactive metadata, so the stadium is the right shape here —
        // and a token beats the hand-computed half-height it replaces, which
        // was wrong the moment the pill grew with the reading size.
        borderRadius: AppRadius.borderRadiusFull,
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
                      cacheManager: pinnedImageCacheFor(
                        'https://image.tmdb.org/t/p/w92$logoPath',
                      ),
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
            style: theme.textTheme.labelSmall
                ?.weight(FontWeight.w600)
                .copyWith(color: colorScheme.onSurface),
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
      // Uppercase, but there are two of these inside one section that already
      // has its own header, so they are sub-group labels rather than eyebrows —
      // they stay on the label ramp with the tracking it derives.
      style: Theme.of(context).textTheme.labelSmall
          ?.weight(FontWeight.w700)
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
