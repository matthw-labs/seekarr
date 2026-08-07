import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// Bazarr-specific detail sections. Feature-local on purpose: no other
/// service has a subtitle-language axis, so these do not belong in
/// `core/widgets`.

/// A wrap of missing subtitle-language cards (code, full name, forced/HI).
class BazarrSubtitleLanguageWrap extends StatelessWidget {
  final List<BazarrSubtitleLanguage> languages;

  const BazarrSubtitleLanguageWrap({super.key, required this.languages});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The accent is not a legible label colour over its own tint in light
    // theme (Luminance Rule); onTint walks its lightness until it clears AA.
    final accentText = ServiceTheme.onTint(
      AppColors.bazarr,
      surface: colorScheme.surface,
      tintAlpha: 0.12,
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final lang in languages)
          Semantics(
            container: true,
            excludeSemantics: true,
            // Uppercase belongs in the eye, not in the ear — speak the full
            // name, and spell the flags out as words.
            label: [
              lang.name ?? lang.code2 ?? 'Unknown language',
              if (lang.forced) 'forced',
              if (lang.hi) 'hearing impaired',
            ].join(', '),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.bazarr.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusSm,
                border: Border.all(
                  color: AppColors.bazarr.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (lang.code2 ?? lang.name ?? '?').toUpperCase(),
                    style: Theme.of(context).textTheme.titleSmall!
                        .weight(FontWeight.w800)
                        .copyWith(color: accentText),
                  ),
                  if (lang.name != null && lang.code2 != null)
                    Text(
                      lang.name!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (lang.forced || lang.hi)
                    Text(
                      [
                        if (lang.forced) 'forced',
                        if (lang.hi) 'hi',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One wanted episode row, on the shared dense-row primitive.
///
/// Was the fourth hand-rolled dense row in the app — its own `Container` shell
/// instead of [AppCard], a fixed 36x36 leading box, a magic `vertical: 3`
/// padding, `maxLines: 1` on a service-supplied title, and no press feedback at
/// all. [MediaChildTile.numbered] is the same shape the Sonarr, Seerr and Lidarr
/// child regions already speak, so a wanted episode here now looks and sounds
/// like an episode everywhere else.
class BazarrWantedEpisodeTile extends StatelessWidget {
  final BazarrWantedItem item;

  const BazarrWantedEpisodeTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final langNames = item.missingLanguages
        .map((l) => l.name ?? l.code2)
        .whereType<String>()
        .join(', ');
    final ordinal = item.episodeNumber;

    return MediaChildTile.numbered(
      ordinal: ordinal,
      // `E04` reads as "E zero four" without this.
      ordinalLabel: ordinal == null ? '' : 'Episode $ordinal',
      title: item.episodeTitle ?? 'Episode ${ordinal ?? '?'}',
      // The languages in words, not a colour-only badge: this row's whole
      // subject is which subtitles are absent, so it has to say so.
      facts: [if (langNames.isNotEmpty) 'Missing $langNames' else 'Wanted'],
    );
  }
}
