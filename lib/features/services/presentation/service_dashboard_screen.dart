import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/app_radius.dart';
import 'package:seekarr/core/app_spacing.dart';
import 'package:seekarr/core/theme.dart';
import 'package:seekarr/core/utils/route_utils.dart';
import 'package:seekarr/core/widgets/glass_app_bar.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';

class ServiceDashboardScreen extends StatefulWidget {
  final ServiceKey service;
  final Widget child;
  final Widget? trailingAction;

  const ServiceDashboardScreen({
    super.key,
    required this.service,
    required this.child,
    this.trailingAction,
  });

  @override
  State<ServiceDashboardScreen> createState() => _ServiceDashboardScreenState();
}

class _ServiceDashboardScreenState extends State<ServiceDashboardScreen> {
  bool _isPickerOpen = false;

  @override
  void didUpdateWidget(covariant ServiceDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      _isPickerOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // Glass band instead of an opaque surface strip, so the hosted
          // screen's ambient gradient reads continuously behind the app bar
          // and scrolling content frosts underneath.
          child: GlassSurface(
            child: SafeArea(
              bottom: false,
              child: _ServiceDashboardAppBar(
                service: widget.service,
                isPickerOpen: _isPickerOpen,
                trailingAction: widget.trailingAction,
                onTogglePicker: () {
                  setState(() => _isPickerOpen = !_isPickerOpen);
                },
              ),
            ),
          ),
        ),
        if (_isPickerOpen)
          Positioned(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: _ServicePicker(
              selectedService: widget.service,
              onSelected: (service) {
                setState(() => _isPickerOpen = false);
                if (service == widget.service) {
                  return;
                }
                context.pushReplacement('/services/${service.routeParam}');
              },
            ),
          ),
      ],
    );
  }
}

class _ServiceDashboardAppBar extends StatelessWidget {
  final ServiceKey service;
  final bool isPickerOpen;
  final Widget? trailingAction;
  final VoidCallback onTogglePicker;

  const _ServiceDashboardAppBar({
    required this.service,
    required this.isPickerOpen,
    this.trailingAction,
    required this.onTogglePicker,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle;

    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => RouteUtils.popOrGo(context, '/services'),
              tooltip: 'Back to Services',
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
            ),
            TextButton(
              key: const ValueKey('service-dashboard-switcher'),
              onPressed: onTogglePicker,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: service.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    service.title,
                    key: ValueKey(
                      'service-dashboard-title-${service.routeParam}',
                    ),
                    style: titleStyle,
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: isPickerOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (trailingAction != null)
              trailingAction!
            else
              IconButton(
                icon: Icon(Icons.monitor_heart_outlined, color: service.accent),
                onPressed: () => context.go('/activity'),
                tooltip: 'Activity',
              ),
          ],
        ),
      ),
    );
  }
}

class _ServicePicker extends StatelessWidget {
  final ServiceKey selectedService;
  final ValueChanged<ServiceKey> onSelected;

  const _ServicePicker({
    required this.selectedService,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      key: const ValueKey('service-dashboard-picker'),
      color: colorScheme.surfaceContainer,
      borderRadius: AppRadius.borderRadiusLg,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: AppRadius.borderRadiusLg,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final service in ServiceKey.values)
                _ServicePickerOption(
                  service: service,
                  selected: service == selectedService,
                  onTap: () => onSelected(service),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServicePickerOption extends StatelessWidget {
  final ServiceKey service;
  final bool selected;
  final VoidCallback onTap;

  const _ServicePickerOption({
    required this.service,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? colorScheme.surfaceContainerHigh : Colors.transparent,
      // The only indication of the current service is a bare check glyph, so
      // without `selected:` a screen-reader user cannot tell which row is
      // active. The key lives on the Semantics rather than the InkWell so
      // `tester.getSemantics` resolves this annotation instead of walking up to
      // an ancestor; the render object covers the same rect, so taps are
      // unaffected.
      child: Semantics(
        key: ValueKey('service-dashboard-option-${service.routeParam}'),
        container: true,
        button: true,
        selected: selected,
        excludeSemantics: true,
        label: service.title,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 13,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: service.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(service.icon, size: 16, color: service.accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    service.title,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.weight(FontWeight.w700)
                        .copyWith(color: colorScheme.onSurface),
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_rounded,
                    key: ValueKey(
                      'service-dashboard-selected-${service.routeParam}',
                    ),
                    size: 18,
                    color: service.accent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
