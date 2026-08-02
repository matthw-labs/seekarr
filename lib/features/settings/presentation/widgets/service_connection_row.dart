import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:seekarr/core/widgets/app_card.dart';
import 'package:seekarr/core/widgets/status_badge.dart';
import 'package:seekarr/features/settings/data/service_connection_provider.dart';
import 'package:seekarr/features/settings/data/service_verification.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/connection_presentation.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

/// One service inside a [SettingsGroupCard]: its accent icon, its host, and the
/// live state of the connection.
///
/// A healthy row shows the host and lets the glyph carry "connected"; a broken
/// one leads with the cause, because that is the only thing the user came to
/// find out. The spoken form always names the state, since the glyph and the
/// tint are the only things carrying it on screen.
class ServiceConnectionRow extends ConsumerWidget {
  const ServiceConnectionRow({
    super.key,
    required this.service,
    required this.onTap,
  });

  final ServiceKey service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final settings = ref.watch(currentSettingsProvider);
    final url = settings.urlFor(service);
    final host = service.extractHost(url) ?? url;

    if (!settings.isServiceConfigured(service)) {
      final presentation = describeConnection(
        service,
        status: ServiceConnectionStatus.notConfigured,
      );
      return SettingsCard.grouped(
        leading: Icon(service.icon),
        title: service.title,
        subtitle: presentation.label,
        accentColor: service.accent,
        semanticLabel: '${service.title}, ${presentation.label}',
        semanticHint: 'sets up ${service.title}',
        onTap: onTap,
        trailing: Icon(Icons.add_rounded, color: colorScheme.onSurfaceVariant),
      );
    }

    final asyncDiagnosis = ref.watch(serviceDiagnosisProvider(service));
    final diagnosis = asyncDiagnosis.when(
      loading: () => const ServiceDiagnosis.checking(),
      // A provider that threw tells us the same thing a failed probe does: we
      // could not confirm the service, and we cannot say why.
      error: (_, __) =>
          const ServiceDiagnosis(ServiceConnectionStatus.disconnected),
      data: (value) => value,
    );
    final presentation = describeConnection(
      service,
      status: diagnosis.status,
      reason: diagnosis.reason,
    );
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      // Connected: the host is the useful line and the glyph says the rest.
      // Broken: the cause comes first, with the host still there to check.
      subtitle: presentation.needsAttention
          ? '${presentation.label} · $host'
          : host,
      subtitleLeading: _StatusGlyph(
        presentation: presentation,
        color: toneColor,
        checking: diagnosis.status == ServiceConnectionStatus.checking,
      ),
      subtitleColor: presentation.needsAttention ? toneColor : null,
      accentColor: service.accent,
      semanticLabel: '${service.title}, ${presentation.label}, $host',
      semanticHint: 'opens ${service.title} settings',
      onTap: onTap,
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({
    required this.presentation,
    required this.color,
    required this.checking,
  });

  final ConnectionPresentation presentation;
  final Color color;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(presentation.icon, size: 16, color: color);
  }
}
