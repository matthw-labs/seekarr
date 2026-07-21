import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Tier-3 contract test (plan §7.4). Unraid has no formal OpenAPI spec, so the
/// committed GraphQL SDL is the contract: a lightweight substring check (no gql
/// dependency) fails loudly if a type/field the [UnraidClient] queries is
/// renamed upstream. Refresh `unraid/schema.graphql` from introspection against
/// a pinned instance to update the contract (plan §9 contract-drift job).
void main() {
  group('Unraid GraphQL SDL contract', () {
    final sdl = File('test/fixtures/unraid/schema.graphql').readAsStringSync();

    test('the queried types and fields still exist in the schema', () {
      for (final needle in const [
        // top-level queries
        'info:',
        'array:',
        'dockerContainers:',
        // info → os → distro/release/uptime
        'type Os',
        'distro:',
        'release:',
        'uptime:',
        // array → state / capacity.kilobytes / disks
        'type Array',
        'type ArrayCapacity',
        'kilobytes:',
        'type ArrayDisk',
        'temp:',
        // dockerContainers fields
        'type DockerContainer',
        'names:',
        'autoStart:',
      ]) {
        expect(
          sdl,
          contains(needle),
          reason: 'Unraid schema changed: "$needle" is gone',
        );
      }
    });
  });
}
