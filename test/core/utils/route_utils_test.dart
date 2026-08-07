import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:cupola/core/utils/route_utils.dart';

void main() {
  group('RouteUtils', () {
    group('safeIntParam', () {
      test('returns parsed integer for valid value', () {
        final state = _createState(pathParameters: {'id': '42'});

        expect(RouteUtils.safeIntParam(state, 'id'), 42);
      });

      test('returns null for non-numeric value', () {
        final state = _createState(pathParameters: {'id': 'abc'});

        expect(RouteUtils.safeIntParam(state, 'id'), isNull);
      });

      test('returns null for missing parameter', () {
        final state = _createState();

        expect(RouteUtils.safeIntParam(state, 'id'), isNull);
      });

      test('returns null for empty parameter', () {
        final state = _createState(pathParameters: {'id': ''});

        expect(RouteUtils.safeIntParam(state, 'id'), isNull);
      });
    });

    group('safeExtra', () {
      test('returns typed extra when type matches', () {
        const extra = _TestExtra();
        final state = _createState(extra: extra);

        expect(RouteUtils.safeExtra<_TestExtra>(state), same(extra));
      });

      test('returns null when extra is null', () {
        final state = _createState();

        expect(RouteUtils.safeExtra<_TestExtra>(state), isNull);
      });

      test('returns null when extra has wrong type', () {
        final state = _createState(extra: 'wrong');

        expect(RouteUtils.safeExtra<_TestExtra>(state), isNull);
      });
    });
  });
}

GoRouterState _createState({
  Map<String, String> pathParameters = const {},
  Object? extra,
}) {
  final configuration = RouteConfiguration(
    ValueNotifier<RoutingConfig>(
      RoutingConfig(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const SizedBox.shrink(),
          ),
        ],
      ),
    ),
    navigatorKey: GlobalKey<NavigatorState>(),
  );

  return GoRouterState(
    configuration,
    uri: Uri.parse('/'),
    matchedLocation: '/',
    fullPath: '/',
    pathParameters: pathParameters,
    extra: extra,
    pageKey: const ValueKey<String>('test'),
  );
}

class _TestExtra {
  const _TestExtra();
}
