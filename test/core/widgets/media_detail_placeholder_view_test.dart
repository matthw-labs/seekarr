import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_detail_back_button.dart';
import 'package:cupola/core/widgets/media_detail_placeholder_view.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    home: child,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        padding: const EdgeInsets.only(top: 59),
      ),
      child: c!,
    ),
  );
}

void main() {
  group('MediaDetailPlaceholderView', () {
    testWidgets('routes a not-configured throw to the settings placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Sonarr not configured'),
            serviceName: 'Sonarr',
            accent: Colors.purple,
          ),
        ),
      );

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('names the service and demotes the exception on a failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Connection refused'),
            serviceName: 'Radarr',
            accent: Colors.amber,
          ),
        ),
      );

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text("Couldn't load Radarr"), findsOneWidget);
      // The diagnostics stay on screen — a self-hoster can act on them — just
      // not as the opening line.
      expect(find.textContaining('Connection refused'), findsOneWidget);
    });

    testWidgets('gives a not-found item the empty-state voice', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MediaDetailPlaceholderView.notFound(
            icon: Icons.tv_off_rounded,
            title: 'Series not found in Bazarr',
            serviceName: 'Bazarr',
            accent: Colors.blue,
          ),
        ),
      );

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(find.text('Series not found in Bazarr'), findsOneWidget);
      expect(find.byIcon(Icons.tv_off_rounded), findsOneWidget);
    });

    testWidgets('a failure offers a retry and reports the tap', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Connection refused'),
            serviceName: 'Radarr',
            accent: Colors.amber,
            onRetry: () => retries++,
          ),
        ),
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('a failure without a retry is not a dead end by accident', (
      tester,
    ) async {
      // No callback means no button: a "Try again" that cannot try is worse
      // than none. Callers withhold it only where a retry cannot help.
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Connection refused'),
            serviceName: 'Radarr',
          ),
        ),
      );

      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('a not-found item can retry in the empty-state voice', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.notFound(
            icon: Icons.tv_off_rounded,
            title: 'Series not found in Bazarr',
            message: 'Bazarr picks new titles up on its next sync.',
            serviceName: 'Bazarr',
            accent: Colors.blue,
            onRetry: () => retries++,
          ),
        ),
      );

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);
      expect(
        find.text('Bazarr picks new titles up on its next sync.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('a missing configuration is sent to Settings, not to a retry', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Sonarr not configured'),
            serviceName: 'Sonarr',
            onRetry: () {},
          ),
        ),
      );

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('wears glass chrome over an accent-lit room, not a flat strip', (
      tester,
    ) async {
      const accent = Color(0xFFF59E0B);
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('boom'),
            serviceName: 'Radarr',
            accent: accent,
          ),
        ),
      );

      // The room is lit by the service's own accent, like the loaded page.
      final ambient = tester.widget<AmbientBackground>(
        find.byType(AmbientBackground),
      );
      expect(ambient.accent, accent);

      // The bar is a gradient scrim, never an opaque surface strip — and never
      // a BackdropFilter (No-Blur-Under-Scroll).
      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(find.byType(GlassSurface), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, Colors.transparent);
    });

    testWidgets('back button carries the tooltip and pops', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MediaDetailPlaceholderView.error(
                        error: Exception('boom'),
                        serviceName: 'Radarr',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(MediaDetailBackButton), findsOneWidget);

      final tooltip = const DefaultMaterialLocalizations().backButtonTooltip;
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('every control on the page clears a 44pt target', (
      tester,
    ) async {
      var retries = 0;
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('boom'),
            serviceName: 'Radarr',
            accent: Colors.amber,
            onRetry: () => retries++,
            onBack: () {},
          ),
        ),
      );

      // The back button's own square is the target, and it is a real hit box
      // rather than a padded-out decoration — see media_detail_back_button_test.
      // >= rather than == : inside a `GlassAppBar` the leading slot arrives
      // tightly constrained to 56, so the button's square is stretched to fill
      // it. On the hero, where it is `Positioned`, it is exactly 44.
      final back = tester.getRect(find.byType(MediaDetailBackButton));
      expect(
        back.shortestSide,
        greaterThanOrEqualTo(MediaDetailBackButton.targetSize),
      );

      // `FilledButton.tonalIcon` *paints* at Material's 40pt height; the target
      // is the `MaterialTapTargetSize.padded` box around it, which is what
      // `getRect` on the button element returns. Both are asserted, and the
      // bottom edge is tapped, because a target that measures 48 and only
      // responds over the middle 40 is the defect this file already found once
      // on the back button.
      //
      // `byWidgetPredicate`, not `byType`: `FilledButton.tonalIcon` builds a
      // private `_FilledButtonWithIcon` subclass, which `byType` will not match.
      final retryFinder = find.byWidgetPredicate((w) => w is FilledButton);
      final retry = tester.getRect(retryFinder);
      expect(retry.height, greaterThanOrEqualTo(44));
      final retryPaint = tester.getRect(
        find.descendant(of: retryFinder, matching: find.byType(Material)).first,
      );
      expect(retryPaint.height, lessThan(retry.height));
      await tester.tapAt(Offset(retry.center.dx, retry.bottom - 1));
      await tester.pump();
      expect(
        retries,
        1,
        reason: 'the whole padded target must respond, not just the paint',
      );

      // The two controls are the page's only targets and sit in different
      // regions, so there is no adjacency to crowd.
      expect(back.bottom + 8, lessThan(retry.top));
    });

    testWidgets('names both controls for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('boom'),
            serviceName: 'Radarr',
            accent: Colors.amber,
            onRetry: () {},
            onBack: () {},
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSemantics(
          find.descendant(
            of: find.byType(MediaDetailBackButton),
            matching: find.byType(IconButton),
          ),
        ),
        containsSemantics(
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
          tooltip: const DefaultMaterialLocalizations().backButtonTooltip,
        ),
      );
      expect(
        tester.getSemantics(find.byWidgetPredicate((w) => w is FilledButton)),
        containsSemantics(
          isButton: true,
          isEnabled: true,
          hasTapAction: true,
          label: 'Try again',
        ),
      );
      handle.dispose();
    });

    testWidgets('an accessibility reading size scrolls instead of clipping', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MediaDetailPlaceholderView.error(
            error: Exception('Lidarr not configured'),
            serviceName: 'Lidarr',
            accent: Colors.pink,
          ),
          textScale: 3.0,
        ),
      );
      await tester.pumpAndSettle();

      // The page owns the viewport: the leaf state grows past it inside a
      // scroll view rather than painting an overflow stripe.
      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
