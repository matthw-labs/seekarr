import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/reel_motion.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/reel_command_button.dart';
import 'package:cupola/core/widgets/reel_line.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';

/// Screen padding for every beat. Wider than the app's 16dp because a beat is a
/// single centred column with nothing beside it.
const onboardingPadding = EdgeInsets.fromLTRB(
  AppSpacing.xl,
  AppSpacing.xl,
  AppSpacing.xl,
  AppSpacing.xxl,
);

/// Widest the column is allowed to get. Past this a field's label and its
/// control drift too far apart to read as a pair.
const onboardingMaxWidth = 560.0;

/// A beat whose content is centred while it fits and scrolls once it does not.
///
/// The page owns the viewport, not the content. A ring, a display headline, a
/// paragraph and two buttons fit comfortably at the default reading size and
/// overflow a short phone by four figures at an accessibility one — so the
/// scrollable is the default and the `minHeight` is what keeps the composition
/// centred, rather than the other way round. The actions stay pinned below it,
/// because an action you have to scroll to find is worse than a scroll.
class OnboardingBeat extends StatelessWidget {
  const OnboardingBeat({
    super.key,
    required this.children,
    this.actions,
    this.alignment = MainAxisAlignment.start,
  });

  final List<Widget> children;
  final Widget? actions;

  /// Where the content sits in the space the ring leaves it.
  ///
  /// `start` for the beats that continue straight out of the instrument — a
  /// form or a list reads as attached to it. `end` for the two that are a claim
  /// plus an action, where the copy belongs with the buttons it argues for.
  /// Centring is what both used to do, and with the ring hoisted above the pager
  /// it opened a hole under it on every beat.
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Padding(
    padding: onboardingPadding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: alignment,
                  children: children,
                ),
              ),
            ),
          ),
        ),
        if (actions != null) ...[
          const SizedBox(height: AppSpacing.lg),
          actions!,
        ],
      ],
    ),
  );
}

/// Two actions side by side, stacking once the reading size stops letting them
/// share a line. Past roughly 1.4x the labels overlap rather than elide.
class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({super.key, this.secondary, required this.primary});

  final Widget? secondary;
  final Widget primary;

  @override
  Widget build(BuildContext context) {
    if (secondary == null) {
      return SizedBox(width: double.infinity, child: primary);
    }
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          const SizedBox(height: AppSpacing.sm),
          secondary!,
        ],
      );
    }
    return Row(
      children: [
        secondary!,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: primary),
      ],
    );
  }
}

// ── Beat 1: the door ────────────────────────────────────────────────────────

/// The claim, the ring, and one way in.
class OnboardingDoor extends StatelessWidget {
  const OnboardingDoor({
    super.key,
    required this.onStart,
    required this.onSkip,
  });

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      children: [
        const OnePunchline.assembling(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '${ServiceKey.values.length} self-hosted services — media, '
          'downloads, storage — on one screen, talking straight to your own '
          'boxes. No cloud in the middle.',
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      actions: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              child: const Text('Set up my stack'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onSkip, child: const Text('Skip for now')),
        ],
      ),
    );
  }
}

/// One word of a headline in an accent, resolved against the surface it sits
/// on — the same move as [OnePunchline]'s "One" and "them all", carried to the
/// two headlines either side of it so the claim's colour vocabulary threads
/// through the whole flow rather than living on the door alone.
class _AccentedHeadline extends StatelessWidget {
  const _AccentedHeadline({
    required this.before,
    required this.accent,
    required this.after,
    required this.accentColor,
    required this.style,
  });

  final String before;
  final String accent;
  final String after;
  final Color accentColor;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = ServiceTheme.onTint(
      accentColor,
      surface: scheme.surface,
      tintAlpha: 0,
    );
    return Text.rich(
      TextSpan(
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: accent,
            style: TextStyle(color: ink),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
      style: style,
    );
  }
}

// ── Beat 2: the pick ────────────────────────────────────────────────────────

/// Fifteen services as accent chips in four labelled sectors, and the ring above
/// as a live readout of the choice.
class OnboardingPick extends StatelessWidget {
  const OnboardingPick({
    super.key,
    required this.picked,
    required this.onToggle,
    required this.onContinue,
    required this.onBack,
  });

  final Set<ServiceKey> picked;
  final void Function(ServiceKey) onToggle;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OnboardingBeat(
      children: [
        _AccentedHeadline(
          before: '',
          accent: 'Bring',
          after: ' them all.',
          accentColor: AppColors.primary,
          style: theme.textTheme.headlineMedium!
              .weight(FontWeight.w800)
              .copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Pick what you actually run. Nothing here is permanent — services '
          'can be added or dropped any time in Settings.',
          style: theme.textTheme.bodyMedium!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final domain in ServiceDomain.values) ...[
          Text(
            domain.label.toUpperCase(),
            style: AppTheme.eyebrow(theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final service in domain.services)
                _PickChip(
                  service: service,
                  selected: picked.contains(service),
                  onTap: () => onToggle(service),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ],
      actions: OnboardingFooter(
        secondary: OutlinedButton(onPressed: onBack, child: const Text('Back')),
        // The count is the only thing on this beat that reports the choice back,
        // and it changes on every chip tap — so it rolls. The slot is reserved
        // for the longest label the button can ever hold, which is why tapping
        // the fifteenth service moves a digit rather than the whole word.
        primary: ReelCommandButton(
          label: picked.isEmpty ? 'Continue' : 'Continue with ${picked.length}',
          slotLabels: ['Continue with ${ServiceKey.values.length}'],
          onPressed: () async => onContinue(),
        ),
      ),
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  final ServiceKey service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The chip's own label sits on a tint of the accent, so it resolves through
    // `onTint` — the raw accent fails AA over its own 14% wash in light theme.
    final labelColor = selected
        ? ServiceTheme.onTint(
            service.accent,
            surface: scheme.surface,
            tintAlpha: 0.14,
          )
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: service.title,
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: AppRadius.borderRadiusMd,
        child: AnimatedContainer(
          duration: AppAnimation.durationSm,
          curve: AppAnimation.emphasizedCurve,
          // 44pt is the iOS minimum target; the label grows the box past it.
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? service.accent.withValues(alpha: 0.14)
                : scheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(
              color: selected
                  ? service.accent.withValues(alpha: 0.40)
                  : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? service.accent
                      : scheme.onSurfaceVariant.withValues(alpha: 0.40),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Flexible, so a long name at an accessibility reading size wraps
              // onto a second line and the chip grows taller. Unflexed, the
              // Row overflowed the wrap's available width by exactly its own
              // padding — and eliding "qBittor…" is not an option: the name is
              // the only thing the chip says.
              Flexible(
                child: Text(
                  service.title,
                  style: theme.textTheme.titleSmall!
                      .weight(FontWeight.w600)
                      .copyWith(color: labelColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Beat 3: the walk ────────────────────────────────────────────────────────

/// Which service this step is about, and how far in — hoisted out of the pager
/// so it can *roll* from one service to the next.
///
/// It sits beside the ring for the same reason the ring sits outside the
/// `PageView`: a `PageView` builds one child per page, so the walk's nine steps
/// are nine separate elements and nothing in one can animate into its
/// counterpart in the next. Held here it is a single widget across the whole
/// walk, and advancing rolls `Where does Radarr live?` into `Where does Sonarr
/// live?` — one word moving inside a sentence that holds still, on the same beat
/// as the ring rotating that service to noon. Two instruments, one clock,
/// answering the same question.
///
/// The service's accent travels with it: the eyebrow's ink is resolved per
/// service through `onTint`, so the line changes colour as it changes subject and
/// the room's own accent is what the change hands off to.
class OnboardingWalkSubject extends StatelessWidget {
  const OnboardingWalkSubject({
    super.key,
    required this.service,
    required this.position,
    required this.total,
  });

  final ServiceKey service;

  /// 1-based position in the walk, and how many services are in it.
  final int position;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The flow's spoken landmark: which service, and how far in.
          ReelLine(
            '${service.title} · $position of $total'.toUpperCase(),
            style: AppTheme.eyebrow(
              ServiceTheme.onTint(
                service.accent,
                surface: scheme.surface,
                tintAlpha: 0,
              ),
            ),
            options: ReelMotion.word,
            // Uppercase belongs in the eye, not the ear — and the spoken form
            // also spells out the separator the eye reads as a dot.
            semanticsLabel: '${service.title}, step $position of $total',
          ),
          const SizedBox(height: AppSpacing.sm),
          ReelLine(
            'Where does ${service.title} live?',
            style: theme.textTheme.headlineSmall!
                .weight(FontWeight.w700)
                .copyWith(color: scheme.onSurface),
            options: ReelMotion.word,
            // Wraps rather than rolls once the sentence stops fitting one line,
            // which for the longest service name happens well inside the
            // reading sizes this app supports.
            fallbackMaxLines: null,
          ),
        ],
      ),
    );
  }
}

/// One service, one screen: where it lives, how to authenticate, and whether it
/// answered.
///
/// The step's subject line lives in [OnboardingWalkSubject], above the pager.
class OnboardingWalk extends StatelessWidget {
  const OnboardingWalk({
    super.key,
    required this.service,
    required this.urlController,
    required this.apiKeyController,
    required this.usernameController,
    required this.passwordController,
    required this.status,
    required this.reason,
    required this.failureDetail,
    required this.verifying,
    required this.certificateProbe,
    required this.trustedFingerprint,
    this.affectedServices = const [],
    required this.next,
    required this.onTest,
    required this.onTrustCertificate,
    required this.onSuggestPort,
    required this.onSkip,
    required this.onAdvance,
    required this.onBack,
  });

  final ServiceKey service;

  final TextEditingController urlController;
  final TextEditingController apiKeyController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final ServiceConnectionStatus? status;
  final ServiceFailureReason? reason;

  /// The verbatim sentence the failure carried, when it carried one — see
  /// `ServiceDiagnosis.detail`. Null for almost every failure, where the
  /// reason-derived message is the better one.
  final String? failureDetail;
  final bool verifying;

  /// A certificate probe the last test ran into, waiting to be trusted.
  final UntrustedCertificateProbe? certificateProbe;
  final String? trustedFingerprint;

  /// Other services in this walk whose typed address shares this one's TLS
  /// origin — trusting or forgetting the certificate here covers them too.
  final List<ServiceKey> affectedServices;

  /// The next service in the walk, so the step can say how far there is to go.
  final ServiceKey? next;

  final Future<void> Function() onTest;
  final VoidCallback onTrustCertificate;
  final VoidCallback onSuggestPort;
  final VoidCallback onSkip;
  final VoidCallback onAdvance;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return OnboardingBeat(
      children: _form(context),
      actions: Column(
        children: [
          OnboardingFooter(
            secondary: OutlinedButton(
              onPressed: onSkip,
              child: Text('Skip ${service.title}'),
            ),
            primary: _TestOrAdvance(
              status: status,
              verifying: verifying,
              isLast: next == null,
              onTest: onTest,
              onAdvance: onAdvance,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onBack, child: const Text('Back')),
        ],
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      OnboardingField(
        label: 'Address',
        controller: urlController,
        isUrl: true,
        help:
            "${service.title}'s default port is ${service.defaultPort}. "
            'Behind a reverse proxy, use the address you reach it on.',
        trailing: _PortChip(port: service.defaultPort, onTap: onSuggestPort),
      ),
      if (service.usesApiKey) ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: service.credentialLabel,
          controller: apiKeyController,
          isSecret: true,
          hint: 'Paste the ${service.credentialLabel.toLowerCase()}',
          help: service.credentialPath == null
              ? null
              : '${service.title} → ${service.credentialPath}',
          warningFor: service == ServiceKey.plex ? _plexTokenWarning : null,
        ),
      ] else ...[
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: service.usernameLabel,
          controller: usernameController,
          hint: service == ServiceKey.nginxProxyManager
              ? 'The email you sign in with'
              : 'Optional',
        ),
        const SizedBox(height: AppSpacing.lg),
        OnboardingField(
          label: 'Password',
          controller: passwordController,
          isSecret: true,
          hint: 'Optional',
          help:
              'Leave both empty if your ${service.title} instance does not '
              'require a login.',
        ),
      ],
      if (_serviceNote(service) case final note?) ...[
        const SizedBox(height: AppSpacing.lg),
        Text(
          note,
          style: theme.textTheme.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (certificateProbe != null) ...[
        const SizedBox(height: AppSpacing.xl),
        _CertificateCard(
          service: service,
          origin:
              UrlUtils.certOrigin(urlController.text) ??
              urlController.text.trim(),
          probe: certificateProbe!,
          previousFingerprint: trustedFingerprint,
          sharedWith: affectedServices.where((s) => s != service).toList(),
          onTrust: onTrustCertificate,
        ),
      ],
      if (status != null && !verifying) ...[
        const SizedBox(height: AppSpacing.xl),
        _Outcome(
          service: service,
          status: status!,
          reason: reason,
          failureDetail: failureDetail,
        ),
      ],
      if (trustedFingerprint != null && certificateProbe == null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          affectedServices.length > 1
              ? "You trusted this server's own certificate — it also covers "
                    '${affectedServices.where((s) => s != service).map((s) => s.title).join(', ')}.'
              : "You trusted this server's own certificate.",
          style: theme.textTheme.bodySmall!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      if (next case final upcoming?) ...[
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: upcoming.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Next: ${upcoming.title}',
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

/// One button that changes its job once the service has answered: there is no
/// reason to make someone press Test and then press Next.
///
/// It is a **single** [ReelCommandButton] across that change rather than two
/// widgets swapped by a conditional, and that is the whole point: the same
/// control rolls `Test connection` → `Testing…` → `Next service`, so the reward
/// for a service answering is the button itself turning into the way forward.
/// Swapping widgets would reset the label controller and replace the text
/// instead of rolling it.
///
/// The spinner this replaced is not missed. A test behind a reverse proxy can
/// take fifteen seconds, and for all fifteen the old button said nothing at all
/// — the label had been swapped out for an 18pt ring. Here the label stays and
/// being in motion is what says busy.
class _TestOrAdvance extends StatelessWidget {
  const _TestOrAdvance({
    required this.status,
    required this.verifying,
    required this.isLast,
    required this.onTest,
    required this.onAdvance,
  });

  final ServiceConnectionStatus? status;
  final bool verifying;
  final bool isLast;
  final Future<void> Function() onTest;
  final VoidCallback onAdvance;

  @override
  Widget build(BuildContext context) {
    final connected = status == ServiceConnectionStatus.connected;
    final advanceLabel = isLast ? 'Finish' : 'Next service';

    return ReelCommandButton(
      label: connected ? advanceLabel : 'Test connection',
      // Absent on the advance arm: that press navigates, it does not wait, and a
      // waiting label would flash for one frame on the way out.
      busyLabel: connected ? null : 'Testing',
      // Not "Failed". The outcome card below already names the cause in a
      // sentence the user can act on; the button's job is to say what pressing
      // it again will do.
      failureLabel: connected ? null : 'Test again',
      // Both arms measured now, so the one transition this reservation exists
      // for — answered — moves a word and not the button's width.
      slotLabels: ['Test connection', 'Test again', advanceLabel],
      onPressed: verifying
          ? null
          : connected
          ? () async => onAdvance()
          : onTest,
    );
  }
}

/// The result of a test as a sentence. A badge saying UNREACHABLE names nothing
/// the user can act on; the resolved failure message names the cause.
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.service,
    required this.status,
    required this.reason,
    required this.failureDetail,
  });

  final ServiceKey service;
  final ServiceConnectionStatus status;
  final ServiceFailureReason? reason;
  final String? failureDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presentation = describeConnection(
      service,
      status: status,
      reason: reason,
    );
    final tone = statusToneColor(scheme, presentation.tone);
    final sentence = switch (status) {
      ServiceConnectionStatus.connected => '${service.title} answered.',
      ServiceConnectionStatus.notConfigured =>
        service.usesApiKey
            ? 'Enter the address and the ${service.credentialLabel.toLowerCase()}, then test.'
            : 'Enter the address, then test.',
      // The detail when the failure carried one, the reason-derived sentence
      // otherwise — the same rule `ServiceDiagnosis.messageFor` applies on the
      // settings screen, so the two surfaces cannot describe one test
      // differently.
      _ => failureDetail ?? connectionFailureMessage(service, reason),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              sentence,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The self-signed certificate moment, resolved inside the step.
///
/// A modal appearing on top of a failure the user has not read yet is an
/// ambush; on a home lab a server presenting its own certificate is normal,
/// so it gets a state rather than an interruption. [CertTrustContent] is the
/// same content [showCertTrustDialog] wraps in a modal for settings — the
/// evidence and words match wherever the user meets a certificate; only the
/// chrome around it (a card here, a dialog there) differs.
class _CertificateCard extends StatelessWidget {
  const _CertificateCard({
    required this.service,
    required this.origin,
    required this.probe,
    required this.onTrust,
    this.previousFingerprint,
    this.sharedWith = const [],
  });

  final ServiceKey service;

  /// The address this certificate was presented for, already resolved to
  /// [UrlUtils.certOrigin]'s canonical `https://host:port` form by the
  /// caller — the same string [SettingsModel.trustedCertificates] keys on.
  final String origin;
  final UntrustedCertificateProbe probe;
  final VoidCallback onTrust;
  final String? previousFingerprint;
  final List<ServiceKey> sharedWith;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rotated = probe.rotated;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: rotated
            ? scheme.errorContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusMd,
        border: Border.all(
          color: rotated ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CertTrustContent(
            origin: origin,
            probe: probe,
            previousFingerprint: previousFingerprint,
            sharedWith: sharedWith,
          ),
          const SizedBox(height: AppSpacing.md),
          // Rotated gets no visually-affirmative default: an outlined button
          // is what the first-trust case already used, so the escalation is
          // carried by the card's own tint and border above, not by demoting
          // this control further.
          OutlinedButton(
            onPressed: onTrust,
            style: rotated
                ? OutlinedButton.styleFrom(foregroundColor: scheme.error)
                : null,
            child: Text(
              rotated
                  ? 'Trust this certificate anyway'
                  : 'Trust and test again',
            ),
          ),
        ],
      ),
    );
  }
}

class _PortChip extends StatelessWidget {
  const _PortChip({required this.port, required this.onTap});

  final int port;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      label: 'Use port $port',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: AppRadius.borderRadiusSm,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            ':$port',
            style: theme.textTheme.labelSmall!
                .weight(FontWeight.w600)
                .tabular
                .copyWith(
                  color: ServiceTheme.onTint(
                    scheme.primary,
                    surface: scheme.surface,
                    tintAlpha: 0.14,
                  ),
                ),
          ),
        ),
      ),
    );
  }
}

// ── Beat 4: the close ───────────────────────────────────────────────────────

/// What the walk actually achieved, in words, plus a way to fix the one thing
/// that did not answer.
class OnboardingClose extends StatelessWidget {
  const OnboardingClose({
    super.key,
    required this.connected,
    required this.silent,
    required this.onFix,
    required this.onFinish,
    required this.onReview,
  });

  final List<ServiceKey> connected;
  final List<ServiceKey> silent;
  final void Function(ServiceKey) onFix;
  final Future<void> Function() onFinish;
  final VoidCallback onReview;

  /// The mixed outcome as its two painted lines.
  ///
  /// Two strings rather than one with a `\n` because these are the only headline
  /// in the app that **changes while it is being read**: the close mounts and
  /// *then* `_testUntested` checks everything the user never tested by hand, so
  /// the first painted value is "0 answer." and the truth arrives a second later.
  /// That used to be a hard swap — a headline that was briefly, visibly wrong.
  /// Rolled, the close reports as it learns, which is what it was always meant
  /// to do. A rolling line cannot contain a newline, so the split is required as
  /// well as clearer.
  List<String>? get _countLines {
    if (connected.isEmpty && silent.isEmpty) return null;
    if (silent.isEmpty) return null;
    final many = silent.length == 1
        ? "One doesn't."
        : "${silent.length} don't.";
    return ['${connected.length} answer.', many];
  }

  String get _body {
    if (connected.isEmpty && silent.isEmpty) {
      return 'Seekarr will stay empty until you add a service — you can do '
          'that any time in Settings, or from any dark card on Services.';
    }
    if (silent.isEmpty) {
      return 'Your whole stack is in one place. Everything you connected is '
          'ready to use.';
    }
    final names = silent.map((s) => s.title).join(', ');
    final verb = silent.length == 1 ? 'is' : 'are';
    return '$names $verb configured but nothing came back. Seekarr will keep '
        'trying — or you can look at it now.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headlineStyle = theme.textTheme.displaySmall!
        .weight(FontWeight.w800)
        .copyWith(color: scheme.onSurface);
    return OnboardingBeat(
      alignment: MainAxisAlignment.end,
      children: [
        if (_countLines case final lines?)
          for (final line in lines)
            ReelLine(
              line,
              style: headlineStyle,
              options: ReelMotion.figure,
              // Wrapping is what the plain headline did at accessibility sizes
              // and it stays the fallback, so a reading size that cannot hold
              // "12 don't." on one line loses the roll rather than the line.
              fallbackMaxLines: null,
            )
        else if (connected.isEmpty && silent.isEmpty)
          Text('Nothing connected yet.', style: headlineStyle)
        else
          _AccentedHeadline(
            before: "They're all ",
            accent: 'bound',
            after: ' now.',
            accentColor: AppColors.navActivity,
            style: headlineStyle,
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          _body,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
      actions: OnboardingFooter(
        secondary: silent.isEmpty
            ? OutlinedButton(onPressed: onReview, child: const Text('Review'))
            : OutlinedButton(
                onPressed: () => onFix(silent.first),
                child: Text('Fix ${silent.first.title}'),
              ),
        primary: _FinishButton(onFinish: onFinish),
      ),
    );
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onFinish});
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) => ReelCommandButton(
    label: 'Enter Seekarr',
    busyLabel: 'Opening',
    onPressed: onFinish,
  );
}

// ── Fields ──────────────────────────────────────────────────────────────────

/// Flags a pasted Plex JSON Web Token while it is still being typed.
///
/// A warning rather than an error: the token is well-formed and will work — for
/// seven days. After that it can only be renewed through plex.tv, which Seekarr
/// never calls, so the user would be left with a 401 and no way to read it.
String? _plexTokenWarning(String value) => value.trim().startsWith('eyJ')
    ? 'That token expires in 7 days and cannot be renewed here. Paste a '
          'long-lived device token instead.'
    : null;

/// Per-service facts worth saying at the moment they matter, rather than in a
/// help page nobody opens.
String? _serviceNote(ServiceKey service) {
  switch (service) {
    case ServiceKey.readarr:
      return 'Readarr development has stopped upstream. Existing instances keep '
          'working against its last released API, but expect no new '
          'server-side fixes.';
    case ServiceKey.unraid:
      return 'Enable the Unraid API first, under Settings → Management Access → '
          'Developer Options. The endpoint stays silent until it is on.';
    case ServiceKey.jellyfin:
      return 'The key signs in as an administrator but carries no user of its '
          'own, so pick whose watch state to read in Settings afterwards.';
    case ServiceKey.plex:
      return 'It must be a long-lived device token: one beginning "eyJ" expires '
          'in 7 days and Seekarr cannot renew it without contacting plex.tv.';
    default:
      return null;
  }
}

/// One labelled field, with the live checks that keep a typo from being reported
/// as a network fault.
class OnboardingField extends StatefulWidget {
  const OnboardingField({
    super.key,
    required this.label,
    required this.controller,
    this.isUrl = false,
    this.isSecret = false,
    this.hint,
    this.help,
    this.trailing,
    this.warningFor,
  });

  final String label;
  final TextEditingController controller;
  final bool isUrl;
  final bool isSecret;
  final String? hint;

  /// A steady line under the field — where the credential lives, what the
  /// default port is. Not a validation result.
  final String? help;

  final Widget? trailing;

  /// A live, non-blocking check on the typed value.
  final String? Function(String value)? warningFor;

  @override
  State<OnboardingField> createState() => _OnboardingFieldState();
}

class _OnboardingFieldState extends State<OnboardingField> {
  String? _error;
  String? _warning;

  /// Secrets start hidden but must be checkable: a 32-character key typed on a
  /// phone keyboard is unverifiable behind dots.
  bool _revealed = false;

  bool get _watches => widget.isUrl || widget.warningFor != null;

  @override
  void initState() {
    super.initState();
    if (_watches) {
      widget.controller.addListener(_validate);
      _validate();
    }
  }

  @override
  void dispose() {
    if (_watches) widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    final raw = widget.controller.text;
    if (!widget.isUrl) {
      final custom = raw.trim().isEmpty ? null : widget.warningFor?.call(raw);
      if (custom == _warning && _error == null) return;
      setState(() {
        _error = null;
        _warning = custom;
      });
      return;
    }
    // An untouched field is not scolded. A cleartext address outside the local
    // network is a warning rather than an error: it is a supported choice, just
    // one worth naming — along with the routes that avoid it.
    final error = raw.trim().isEmpty ? null : UrlUtils.validateServiceHost(raw);
    final warning = error == null ? _addressWarning(raw) : null;
    if (error == _error && warning == _warning) return;
    setState(() {
      _error = error;
      _warning = warning;
    });
  }

  /// Extends `cleartextWarning`'s remedy from "use https" to the three routes
  /// this audience actually uses.
  static String? _addressWarning(String raw) {
    if (UrlUtils.cleartextWarning(raw) == null) return null;
    return 'This address is off your local network and http:// sends your '
        'credentials in the clear. Reach it over a reverse proxy with TLS, a '
        'VPN like Tailscale, or a Cloudflare Tunnel instead.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final note = _error ?? _warning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: theme.textTheme.labelMedium!
              .weight(FontWeight.w600)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: AppRadius.borderRadiusMd,
            border: _error == null
                ? null
                : Border.all(color: scheme.error.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  obscureText: widget.isSecret && !_revealed,
                  keyboardType: widget.isUrl
                      ? TextInputType.url
                      : TextInputType.text,
                  textInputAction: widget.isUrl
                      ? TextInputAction.next
                      : TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Smart substitutions off as well as autocorrect: iOS
                  // otherwise rewrites `--` and quotes inside a typed address.
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    // https by default: the clients normalise a scheme-less
                    // host to TLS, and an http:// placeholder taught the
                    // opposite.
                    hintText: widget.isUrl
                        ? 'https://your-server:port'
                        : widget.hint,
                    hintStyle: theme.textTheme.bodyMedium!.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    isDense: true,
                    // Every state is borderless: the container draws the frame,
                    // and the app-wide focused border would paint a second box
                    // inside this one.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (widget.isSecret)
                Semantics(
                  button: true,
                  label: _revealed
                      ? 'Hide ${widget.label}'
                      : 'Show ${widget.label}',
                  child: IconButton(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: _revealed
                        ? 'Hide ${widget.label}'
                        : 'Show ${widget.label}',
                  ),
                ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              note,
              style: theme.textTheme.bodySmall!.copyWith(
                color: _error != null ? scheme.error : AppColors.warning,
              ),
            ),
          )
        else if (widget.help != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              widget.help!,
              style: theme.textTheme.bodySmall!.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
