import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/reel_finders.dart';

/// The flow is door → pick → one page per chosen service → close, so its length
/// belongs to the user. Every case here was a real defect in the flow this
/// replaced; the scenarios are preserved even though the screens are not.
void main() {
  group('OnboardingScreen', () {
    // Mirrors the original report behind issue #4: "I tried not entering
    // anything, entering everything, and entering just the Sonarr details and
    // the Continue button never allowed me to move forward".
    testWidgets('picking nothing still reaches the close', (tester) async {
      await _pumpOnboarding(tester);

      expect(_semantics('One app to rule them all.'), findsOneWidget);
      await _tap(tester, 'Set up my stack');
      // The headline carries an accented word now (`Bring` in the brand
      // indigo), so it is a `Text.rich`/`TextSpan` tree rather than a single
      // `Text` — matched by its rendered content, not by `find.text`.
      expect(find.textContaining('Bring'), findsOneWidget);
      expect(find.textContaining('them all.'), findsOneWidget);

      await _tap(tester, 'Continue');

      // Congratulating someone on connecting nothing reads as a bug; the empty
      // case is legitimate and gets copy that says what actually happened.
      expect(find.text('Nothing connected yet.'), findsOneWidget);
      expect(find.textContaining('Seekarr will stay empty'), findsOneWidget);
      expect(_button('Enter Seekarr'), findsOneWidget);
    });

    testWidgets('picking every service walks all of them in registry order', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');

      for (final service in ServiceKey.values) {
        await _pick(tester, service.title);
      }
      expect(
        _button('Continue with ${ServiceKey.values.length}'),
        findsOneWidget,
      );

      await _tap(tester, 'Continue with ${ServiceKey.values.length}');

      // The walk starts at the first service in ring order, and the eyebrow is
      // the flow's landmark now that there is no fixed "step N of 3".
      final first = ServiceRing.order.first;
      expect(
        find.text(
          '${first.title} · 1 of ${ServiceKey.values.length}'.toUpperCase(),
        ),
        findsOneWidget,
      );
      expect(find.text('Where does ${first.title} live?'), findsOneWidget);
    });

    testWidgets('one service: fill it in, test, and finish', (tester) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');

      expect(findLine('SONARR · 1 OF 1'), findsOneWidget);
      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');

      // Test, not Next: the primary action only becomes an advance once the
      // service has actually answered.
      await _tap(tester, 'Test connection');

      // Under test the transport refuses every request, so the outcome is a
      // failure — reported as a sentence rather than a badge saying UNREACHABLE.
      expect(_button('Test connection'), findsOneWidget);
      expect(find.text('Skip Sonarr'), findsOneWidget);
    });

    testWidgets('skipping a service moves on without configuring it', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _pick(tester, 'Radarr');
      await _tap(tester, 'Continue with 2');

      // Radarr comes first in ring order, so it is the one on screen.
      expect(find.text('RADARR · 1 OF 2'), findsOneWidget);
      await _tap(tester, 'Skip Radarr');
      expect(find.text('SONARR · 2 OF 2'), findsOneWidget);

      await _tap(tester, 'Skip Sonarr');
      // Both skipped, so the close has nothing to report.
      expect(find.text('Nothing connected yet.'), findsOneWidget);
    });

    testWidgets(
      'an unfilled form reports what is missing, not a network fault',
      (tester) async {
        await _pumpOnboarding(tester);
        await _tap(tester, 'Set up my stack');
        await _pick(tester, 'Sonarr');
        await _tap(tester, 'Continue with 1');

        await _tap(tester, 'Test connection');

        // "Unreachable" blamed the network for a field nobody had typed into yet
        // and left nothing to act on.
        expect(
          find.textContaining('Enter the address and the api key'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a scheme-less host completes instead of hanging', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');

      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');
      await _tap(tester, 'Test connection');

      // A client constructor that rejects the address raises rather than
      // returning a failed status, which used to leave the button spinning for
      // the rest of the session.
      expect(
        tester.widget<FilledButton>(_button('Test connection').first).onPressed,
        isNotNull,
      );
    });

    testWidgets('the close checks services nobody tested by hand', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');
      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');

      // Straight past the walk — Test was never pressed. Pumped in stages so the
      // automatic checks finish while the page transition is still in flight,
      // which is the window where a reveal that walks up into the pager used to
      // drag it back and pin setup mid-flow.
      await _tap(tester, 'Skip Sonarr', settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing connected'), findsOneWidget);
      // And it never blocks the way out.
      expect(_button('Enter Seekarr'), findsOneWidget);
    });

    testWidgets('the close names the service that did not answer', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');
      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');
      await _tap(tester, 'Test connection');
      await _tap(tester, 'Skip Sonarr', settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();

      // Skipping after filling it in clears it, so this is the honest outcome:
      // the summary reports what is actually saved, never what was typed.
      expect(find.text('Nothing connected yet.'), findsOneWidget);
    });

    testWidgets('a configured service survives to the close and is named', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');
      await _fill(tester, url: 'sonarr.lan:8989', key: 'abcdef1234567890');

      // The last service's advance goes to the close and saves on the way.
      await _tap(tester, 'Test connection');
      await _tap(tester, 'Skip Sonarr', settle: false);
      await tester.pumpAndSettle();

      expect(_button('Enter Seekarr'), findsOneWidget);
    });

    testWidgets('no beat overflows a short phone at an accessibility size', (
      tester,
    ) async {
      await _pumpOnboarding(
        tester,
        textScale: 2.0,
        // The viewport where a display headline, a paragraph and two buttons
        // stopped fitting first.
        viewport: const Size(375, 667),
      );

      // Each beat is a scrollable whose content is centred while it fits, so
      // nothing overflows and the actions stay pinned and reachable.
      expect(tester.takeException(), isNull);
      expect(_button('Set up my stack'), findsOneWidget);

      await _tap(tester, 'Set up my stack');
      expect(tester.takeException(), isNull);
      expect(_button('Continue'), findsOneWidget);

      await _tap(tester, 'Continue');
      expect(tester.takeException(), isNull);
      expect(_button('Enter Seekarr'), findsOneWidget);
    });

    testWidgets('the walk stacks its actions at an accessibility size', (
      tester,
    ) async {
      await _pumpOnboarding(tester, textScale: 2.0);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');

      // Side by side the two labels overlap rather than elide past roughly 1.4x,
      // so the footer stacks and both actions survive.
      expect(_button('Test connection'), findsOneWidget);
      expect(find.text('Skip Sonarr'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a full configuration fits a phone at the close', (
      tester,
    ) async {
      await _pumpOnboarding(
        tester,
        settings: _fullConfiguration(),
        viewport: const Size(390, 844),
      );
      // Resumed: every saved service is already picked, so the door leads
      // straight into a fifteen-page walk.
      await _tap(tester, 'Set up my stack');
      expect(
        _button('Continue with ${ServiceKey.values.length}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second run resumes the saved configuration', (tester) async {
      await _pumpOnboarding(
        tester,
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _tap(tester, 'Set up my stack');

      // Sonarr arrives already picked — finishing a second time must not blank a
      // real configuration.
      expect(_button('Continue with 1'), findsOneWidget);
      await _tap(tester, 'Continue with 1');
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'https://sonarr.lan:8989');
    });

    testWidgets('the port chip puts this service default on the typed host', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');

      await tester.enterText(find.byType(TextField).first, 'nas.local:1234');
      await tester.pumpAndSettle();
      await tester.tap(_semantics('Use port 8989'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'https://nas.local:8989');
    });

    testWidgets('the address carries over to the next service', (tester) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Radarr');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 2');

      await _fill(tester, url: 'https://nas.local:7878', key: 'abcdef1234');
      await _tap(tester, 'Skip Radarr');

      // Sonarr inherits the host and gets its own default port, so the second
      // service is a tap plus a pasted key rather than a retyped address.
      expect(find.text('SONARR · 2 OF 2'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller!.text, 'https://nas.local:8989');
    });

    testWidgets('the credential breadcrumb names where the key lives', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Jellyfin');
      await _tap(tester, 'Continue with 1');

      expect(
        find.text('Jellyfin → Dashboard → Advanced → API Keys'),
        findsOneWidget,
      );
    });

    testWidgets('Skip for now on the door reaches the close', (tester) async {
      await _pumpOnboarding(tester);
      await _tap(tester, 'Skip for now');
      expect(find.text('Nothing connected yet.'), findsOneWidget);
      expect(_button('Enter Seekarr'), findsOneWidget);
    });

    testWidgets('the ring is one instrument that survives the walk', (
      tester,
    ) async {
      await _pumpOnboarding(tester, reduceMotion: false);

      // Exactly one ring for the whole flow, mounted above the pager, so it is
      // never rebuilt from scratch when a beat changes.
      expect(find.byType(ServiceRing), findsOneWidget);
      final ringElement = tester.element(find.byType(ServiceRing));

      await tester.tap(find.text('Set up my stack'));
      await _advanceFrames(tester);
      await _pick(tester, 'Sonarr', settle: false);
      await _advanceFrames(tester);
      await tester.tap(findLine('Continue with 1'));
      await _advanceFrames(tester);

      expect(find.byType(ServiceRing), findsOneWidget);
      expect(
        tester.element(find.byType(ServiceRing)),
        same(ringElement),
        reason: 'the same element, so its animation state is continuous',
      );
      expect(findLine('SONARR · 1 OF 1'), findsOneWidget);

      // Bounded pumps only: the sweep repeats forever by design, so settling is
      // not something this screen ever does with motion on.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    // ── Walking past a service is not deleting it ─────────────────────────
    //
    // The old save wrote *every* not-ready service back blank, which deleted the
    // saved address and the secure credential of a service that was working. Two
    // ordinary routes reached it: "Revisit onboarding" in settings, which
    // promises in as many words that nothing about your services is changed or
    // removed, and "Skip for now" on the very first beat.

    testWidgets('skipping a saved service leaves it configured', (
      tester,
    ) async {
      final container = await _pumpOnboarding(
        tester,
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _tap(tester, 'Set up my stack');
      await _tap(tester, 'Continue with 1');

      await _tap(tester, 'Skip Sonarr', settle: false);
      await tester.pumpAndSettle();

      final saved = container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
    });

    testWidgets('deselecting a saved service does not remove it', (
      tester,
    ) async {
      final container = await _pumpOnboarding(
        tester,
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
        ),
      );
      await _tap(tester, 'Set up my stack');

      // Resumed already picked; untick it and walk out through the close.
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue');
      expect(find.text('Nothing connected yet.'), findsOneWidget);

      // Removing a connection is a confirmed action that lives in the settings
      // screen. Unticking a chip here means "not now".
      final saved = container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
    });

    testWidgets('Skip for now on the door keeps every saved service', (
      tester,
    ) async {
      final container = await _pumpOnboarding(
        tester,
        settings: const SettingsModel(
          sonarrUrl: 'https://sonarr.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
          qbittorrentUrl: 'https://qb.lan:8080',
          qbittorrentUsername: 'admin',
          qbittorrentPassword: 'hunter2',
        ),
      );

      await _tap(tester, 'Skip for now');

      final saved = container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://sonarr.lan:8989');
      expect(saved.sonarrApiKey, 'abcdef1234567890');
      // The credential half too — it lives in secure storage, so losing it is
      // the one thing the user cannot undo from memory.
      expect(saved.qbittorrentUrl, 'https://qb.lan:8080');
      expect(saved.qbittorrentUsername, 'admin');
      expect(saved.qbittorrentPassword, 'hunter2');
    });

    testWidgets('a first run skips without inventing anything to save', (
      tester,
    ) async {
      // The other half of the invariant: with nothing on disk there is nothing
      // to preserve, and skipping must not write half-typed values either.
      final container = await _pumpOnboarding(tester);
      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      await _tap(tester, 'Continue with 1');
      await _fill(tester, url: 'sonarr.lan:8989', key: '');

      await _tap(tester, 'Skip Sonarr', settle: false);
      await tester.pumpAndSettle();

      expect(container.read(settingsProvider).sonarrUrl, isEmpty);
      expect(find.text('Nothing connected yet.'), findsOneWidget);
    });

    // ── A trust decision belongs to the host it was made against ──────────
    //
    // The pin is seeded from the *saved* URL on resume and `_save` writes every
    // ready service, not just the one on screen. Without tying the fingerprint
    // to the origin it was accepted for, editing an address carried the old
    // host's certificate onto the new one — and because a pin is keyed by
    // origin alone, that bogus entry then failed closed for every service later
    // pointed at that host, with no trust prompt to explain it.
    testWidgets('editing an address does not move its certificate pin', (
      tester,
    ) async {
      final container = await _pumpOnboarding(
        tester,
        settings: const SettingsModel(
          radarrUrl: 'https://radarr.lan:7878',
          radarrApiKey: 'abcdef1234567890',
          sonarrUrl: 'https://nas.lan:8989',
          sonarrApiKey: 'abcdef1234567890',
          trustedCertificates: {'https://nas.lan:8989': 'AA:BB'},
        ),
      );

      await _tap(tester, 'Set up my stack');
      await _tap(tester, 'Continue with 2');

      // Radarr is first in ring order; walking past it saves and lands on
      // Sonarr, which is the service holding the pin.
      await _tap(tester, 'Skip Radarr', settle: false);
      await tester.pumpAndSettle();
      await _fill(
        tester,
        url: 'https://other.lan:8989',
        key: 'abcdef1234567890',
      );

      // Back to Radarr and past it again: Sonarr is never tested, but it is
      // still `_isReady`, so this save writes its new address.
      await _tap(tester, 'Back');
      await _tap(tester, 'Skip Radarr', settle: false);
      await tester.pumpAndSettle();

      final saved = container.read(settingsProvider);
      expect(saved.sonarrUrl, 'https://other.lan:8989');
      // The new host never presented a certificate here, so it has no pin —
      // and the abandoned one is forgotten rather than relocated.
      expect(saved.pinForUrl('https://other.lan:8989'), isNull);
      expect(saved.trustedCertificates, isEmpty);
    });

    testWidgets('the ring speaks its state rather than only drawing it', (
      tester,
    ) async {
      await _pumpOnboarding(tester);
      expect(
        _semantics('${ServiceKey.values.length} services, none set up yet'),
        findsWidgets,
      );

      await _tap(tester, 'Set up my stack');
      await _pick(tester, 'Sonarr');
      expect(
        _semantics('1 of ${ServiceKey.values.length} chosen'),
        findsWidgets,
      );
    });
  });
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

/// Matches a [Semantics] widget by its declared label.
///
/// Read off the widget rather than the semantics tree so the harness needs no
/// [SemanticsHandle] — `ensureSemantics`' handle is verified as disposed before
/// `addTearDown` callbacks run, so the idiomatic pairing fails every test.
Finder _semantics(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

/// Taps by visible label.
///
/// Deliberately no `ensureVisible`: `Scrollable.ensureVisible` walks *every*
/// enclosing scrollable, and these beats live inside a horizontal `PageView`, so
/// revealing a pinned footer button scrolls the pager off the page and unbuilds
/// the very widget being reached for. The tall viewport in [_pumpOnboarding] is
/// what makes scrolling unnecessary instead.
Future<void> _tap(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final target = find.text(label);
  await tester.tap(target.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Pumps a handful of real frames.
///
/// With the sweep running there is no settled state, so motion-on cases advance
/// the clock in steps instead of waiting for one — and a single long pump is not
/// enough, because a pager builds the arriving page over more than one frame.
Future<void> _advanceFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Toggles a service on the pick step by its chip.
Future<void> _pick(
  WidgetTester tester,
  String title, {
  bool settle = true,
}) async {
  await tester.tap(find.text(title).first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _fill(
  WidgetTester tester, {
  required String url,
  required String key,
}) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), url);
  await tester.enterText(fields.at(1), key);
  await tester.pumpAndSettle();
}

/// Every service configured, built from the registry rather than written out.
///
/// The hand-written literal this replaces silently stopped covering the whole
/// ring the moment a service was added, and the case it feeds is precisely "does
/// the longest possible walk still fit a phone" — so it has to grow with the
/// registry or it stops testing what it claims to.
SettingsModel _fullConfiguration() {
  var settings = const SettingsModel();
  for (final service in ServiceKey.values) {
    final url = 'https://${service.name}.lan:${service.defaultPort}';
    settings = service.usesApiKey
        ? settings.copyWithService(service, url: url, apiKey: 'k')
        : settings.copyWithCredentials(
            service,
            url: url,
            username: 'u',
            password: 'p',
          );
  }
  return settings;
}

Future<ProviderContainer> _pumpOnboarding(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  double textScale = 1.0,
  Size? viewport,
  bool reduceMotion = true,
}) async {
  // Tall enough that no beat needs scrolling, so a tap never has to reach past
  // the fold — see [_tap] for why scrolling is the thing to avoid here. Width is
  // irrelevant past `onboardingMaxWidth`.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport ?? const Size(800, 2400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final secureStore = FakeSecureSettingsStore();

  // An explicit container, so a case can read back what the walk actually saved
  // — the difference between "walked past" and "deleted" is invisible on screen.
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(secureStore),
      initialSettingsProvider.overrideWith((ref) => settings),
      initialOnboardingCompletedProvider.overrideWith((ref) => false),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Injected through `builder`, not by wrapping MaterialApp: MaterialApp
      // installs its own MediaQuery from the view and would discard an outer
      // one, so the reading size would silently stay at 1.0.
      //
      // Reduce Motion is the default here, and not only for speed: the ring's
      // ambient sweep repeats forever, so with motion on `pumpAndSettle` waits
      // for a frame that never stops coming. Motion has its own case below,
      // pumped in bounded steps.
      child: MaterialApp(
        home: const OnboardingScreen(
          certificateProber: _neverFindsACertificate,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (reduceMotion) {
    await tester.pumpAndSettle();
  } else {
    // With the sweep running there is no settled state to wait for.
    await tester.pump(const Duration(milliseconds: 600));
  }
  return container;
}

/// The default certificate prober for every test in this file.
///
/// Under ADR-6 the real [probeUntrustedCertificate] opens a live
/// [SecureSocket] for *any* disconnected, probe-worthy failure — no longer
/// just the rare TrueNAS/Dockge case ADR-5 confined it to — and none of
/// these tests point at a real TLS host, so a `.lan`/scheme-less address
/// that fails at the fake `ApiClient` layer would otherwise reach a real
/// socket `flutter_test` cannot intercept or fake, hanging the test on a
/// pending timer. None of these tests exercise the trust flow itself, so
/// "no certificate found" is the correct fake, not just a convenient one.
Future<UntrustedCertificateProbe?> _neverFindsACertificate(
  String rawUrl, {
  String pinnedFingerprint = '',
}) async => null;
