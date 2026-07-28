import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/utils/service_routes.dart';
import 'package:seekarr/core/widgets/media_detail_view.dart';
import 'package:seekarr/core/widgets/pressable_scale.dart';
import 'package:seekarr/features/discover/presentation/discover_detail_view_model.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class DiscoverCastList extends StatelessWidget {
  final List<DiscoverCastMember> cast;

  /// Accent for the section rule. Defaults to Seerr, which owns this data, but
  /// the host screen passes its own: the widget is reused inside the Radarr and
  /// Sonarr detail screens via `ArrMediaExtrasSection`, where a hard-coded
  /// indigo rule sat right below an amber one.
  final Color? accent;

  const DiscoverCastList({super.key, required this.cast, this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MediaDetailSectionHeader(
            title: 'Cast',
            accent: accent ?? ServiceKey.seerr.accent,
          ),
        ),
        SizedBox(
          height: 108,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: cast.length,
            itemBuilder: (context, index) => _CastTile(member: cast[index]),
          ),
        ),
      ],
    );
  }
}

class _CastTile extends StatelessWidget {
  final DiscoverCastMember member;

  const _CastTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final profilePath = member.profilePath;
    final imageUrl = profilePath != null && profilePath.isNotEmpty
        ? 'https://image.tmdb.org/t/p/w185$profilePath'
        : null;
    final tappable = member.id > 0;
    final heroTag = 'person_${member.id}';

    Widget avatar = CircleAvatar(
      radius: 32,
      backgroundColor: colorScheme.surfaceContainer,
      backgroundImage: imageUrl != null
          ? CachedNetworkImageProvider(imageUrl)
          : null,
      child: imageUrl == null
          ? Icon(Icons.person, size: 28, color: colorScheme.onSurfaceVariant)
          : null,
    );
    if (tappable) {
      avatar = Hero(tag: heroTag, child: avatar);
    }

    final tile = SizedBox(
      width: 64,
      child: Column(
        children: [
          avatar,
          const SizedBox(height: AppSpacing.xs),
          Text(
            member.name,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            member.character,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: tappable
          ? PressableScale(
              onTap: () => context.push(
                ServiceRoutes.seerrPerson(
                  member.id,
                  heroTag: heroTag,
                  posterUrl: imageUrl,
                ),
              ),
              child: tile,
            )
          : tile,
    );
  }
}
