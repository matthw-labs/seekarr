import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:seekarr/core/models/media_preview.dart';
import 'package:seekarr/core/widgets/content_card.dart';
import 'package:seekarr/features/discover/domain/models/seerr_request.dart';
import 'package:seekarr/features/services/domain/service_summary.dart';
import 'package:seekarr/features/services/presentation/services_provider.dart';
import 'package:seekarr/features/services/presentation/services_screen.dart';
import 'package:seekarr/features/settings/data/settings_provider.dart';
import 'package:seekarr/features/settings/domain/service_key.dart';
import 'package:seekarr/features/settings/domain/settings_model.dart';

import '../../../test_helpers/model_builders.dart';

void main() {
  testWidgets('renders service status grid and dashboard sections', (
    tester,
  ) async {
    await _pumpServices(tester);
    await _pumpDashboard(tester);

    expect(find.text('Services'), findsOneWidget);
    expect(find.text('Seerr'), findsWidgets);
    expect(find.text('Radarr'), findsWidgets);
    expect(find.text('Sonarr'), findsWidgets);
    expect(find.text('Lidarr'), findsWidgets);
    expect(find.text('3 requests'), findsOneWidget);
    expect(find.text('12 movies'), findsOneWidget);
    expect(find.text('7 series'), findsOneWidget);
    expect(find.text('Offline'), findsWidgets);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Trending One'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recent Requests'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('A Quiet Place'), findsOneWidget);
    expect(_contentCardWithImage('/quiet-place.jpg'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Recently Added · Movies'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dune'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('The Boys'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('The Boys'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Furiosa'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Furiosa'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('service status cards render in a horizontal scroller', (
    tester,
  ) async {
    await _pumpServices(tester);
    await _pumpDashboard(tester);

    final horizontalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.right,
    );

    expect(horizontalScrollable, findsAtLeastNWidgets(1));
  });

  testWidgets('shows empty queue state when there are no downloads', (
    tester,
  ) async {
    await _pumpServices(
      tester,
      queueBuilder: (ref) async => const <ServiceQueueItem>[],
    );
    await _pumpDashboard(tester);

    await tester.scrollUntilVisible(
      find.text('Downloading'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No active downloads'), findsOneWidget);
  });

  testWidgets('see all routes to canonical Radarr and Sonarr homes', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/services',
      routes: [
        GoRoute(
          path: '/services',
          builder: (context, state) => const ServicesScreen(),
        ),
        GoRoute(
          path: '/services/radarr',
          builder: (context, state) =>
              const Scaffold(body: Text('Radarr Home')),
        ),
        GoRoute(
          path: '/services/sonarr',
          builder: (context, state) =>
              const Scaffold(body: Text('Sonarr Home')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await _pumpServicesRouter(tester, router);
    await _pumpDashboard(tester);

    await tester.scrollUntilVisible(
      find.text('Recently Added · Movies'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_sectionHeaderTapTarget('Recently Added · Movies'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/services/radarr');
    expect(find.text('Radarr Home'), findsOneWidget);

    router.go('/services');
    await _pumpDashboard(tester);

    await tester.scrollUntilVisible(
      find.text('Recently Added · Series'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(_sectionHeaderTapTarget('Recently Added · Series'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/services/sonarr');
    expect(find.text('Sonarr Home'), findsOneWidget);
  });
}

Future<void> _pumpServices(
  WidgetTester tester, {
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(queueBuilder: queueBuilder),
      child: const MaterialApp(home: ServicesScreen()),
    ),
  );
}

Future<void> _pumpServicesRouter(
  WidgetTester tester,
  GoRouter router, {
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _providerOverrides(queueBuilder: queueBuilder),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder _contentCardWithImage(String imagePath) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ContentCard && widget.imageUrl?.contains(imagePath) == true,
    skipOffstage: false,
  );
}

Finder _sectionHeaderTapTarget(String title) {
  return find
      .ancestor(of: find.text(title), matching: find.byType(InkWell))
      .first;
}

List<Override> _providerOverrides({
  Future<List<ServiceQueueItem>> Function(Ref ref)? queueBuilder,
}) {
  return [
    currentSettingsProvider.overrideWith(
      (ref) => const SettingsModel(
        seerrUrl: 'http://seerr.local:5055',
        seerrApiKey: 'key',
        radarrUrl: 'http://radarr.local:7878',
        radarrApiKey: 'key',
        sonarrUrl: 'http://sonarr.local:8989',
        sonarrApiKey: 'key',
        lidarrUrl: 'http://lidarr.local:8686',
        lidarrApiKey: 'key',
      ),
    ),
    serviceSummaryProvider.overrideWith(_summaryBuilder),
    servicesTrendingProvider.overrideWith(
      (ref) async => const [
        MediaPreview(
          id: 1,
          title: 'Trending One',
          releaseDate: '2024-01-01',
          mediaType: 'movie',
        ),
      ],
    ),
    servicesRequestsProvider.overrideWith(
      (ref) async => const [
        SeerrRequest(
          id: 1,
          status: RequestStatus.pendingApproval,
          media: RequestMedia(
            title: 'A Quiet Place',
            tmdbId: 123,
            posterPath: '/quiet-place.jpg',
            status: MediaAvailability.available,
          ),
          createdAt: '2024-01-01',
          type: 'movie',
          requestedBy: RequestedBy(id: 1, displayName: 'sarah'),
        ),
      ],
    ),
    servicesMoviesProvider.overrideWith(
      (ref) async => [
        buildMovie(
          id: 10,
          title: 'Dune',
          images: const [
            {
              'coverType': 'poster',
              'remoteUrl': 'https://example.com/dune.jpg',
            },
          ],
        ),
      ],
    ),
    servicesSeriesProvider.overrideWith(
      (ref) async => [buildSeries(id: 20, title: 'The Boys')],
    ),
    servicesMusicProvider.overrideWith((ref) async => const []),
    servicesQueueProvider.overrideWith(
      queueBuilder ??
          (ref) async => const [
            ServiceQueueItem(
              service: ServiceKey.radarr,
              title: 'Furiosa',
              subtitle: 'Movie · Furiosa.2024.2160p.WEB-DL-GROUP',
              progress: 0.75,
              warning: null,
            ),
          ],
    ),
  ];
}

Future<ServiceSummary> _summaryBuilder(Ref ref, ServiceKey service) async {
  switch (service) {
    case ServiceKey.seerr:
      return const ServiceSummary(
        service: ServiceKey.seerr,
        status: ServiceSummaryStatus.online,
        host: 'seerr.local:5055',
        version: '2.5.1',
        itemCount: 3,
        itemLabel: 'requests',
      );
    case ServiceKey.radarr:
      return const ServiceSummary(
        service: ServiceKey.radarr,
        status: ServiceSummaryStatus.online,
        host: 'radarr.local:7878',
        version: '5.4.6',
        itemCount: 12,
        itemLabel: 'movies',
      );
    case ServiceKey.sonarr:
      return const ServiceSummary(
        service: ServiceKey.sonarr,
        status: ServiceSummaryStatus.online,
        host: 'sonarr.local:8989',
        version: '4.0.2',
        itemCount: 7,
        itemLabel: 'series',
      );
    case ServiceKey.lidarr:
      return const ServiceSummary(
        service: ServiceKey.lidarr,
        status: ServiceSummaryStatus.offline,
        host: 'lidarr.local:8686',
        version: null,
        itemCount: null,
        itemLabel: 'artists',
      );
    case ServiceKey.qbittorrent:
      return const ServiceSummary(
        service: ServiceKey.qbittorrent,
        status: ServiceSummaryStatus.offline,
        host: '',
        version: null,
        itemCount: null,
        itemLabel: 'torrents',
      );
    case ServiceKey.bazarr:
      return const ServiceSummary(
        service: ServiceKey.bazarr,
        status: ServiceSummaryStatus.offline,
        host: '',
        version: null,
        itemCount: null,
        itemLabel: 'subtitles',
      );
    case ServiceKey.truenas:
      return const ServiceSummary(
        service: ServiceKey.truenas,
        status: ServiceSummaryStatus.offline,
        host: '',
        version: null,
        itemCount: null,
        itemLabel: 'pools',
      );
  }
}
