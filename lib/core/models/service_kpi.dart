import 'package:flutter/material.dart';

/// A single key metric shown in a [ServiceKpiPeek] rail.
///
/// Kept transport-agnostic: each service builds its own list of KPIs from
/// whatever data it already has loaded, so the peek stays a pure presentation
/// concern.
@immutable
class ServiceKpi {
  /// Short uppercase-friendly label (e.g. "Missing", "Down").
  final String label;

  /// Preformatted value string (e.g. "128", "2.4 MB/s", "94%").
  final String value;

  /// Small leading icon.
  final IconData icon;

  /// Optional accent override; defaults to the service accent at render time.
  final Color? accent;

  /// Optional tap handler (e.g. jump to a filtered view).
  final VoidCallback? onTap;

  const ServiceKpi({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
    this.onTap,
  });
}
