import 'dart:convert';
import 'dart:io';

/// Loads a JSON fixture from `test/fixtures/<path>`.
///
/// `flutter test` runs with the package root as the working directory, so the
/// relative path resolves regardless of which test file loads it. Fixtures are
/// the recorded shape of a service response — built from the official API docs
/// and replaceable with a live capture — used to keep model parsing honest.
dynamic jsonFixture(String path) =>
    jsonDecode(File('test/fixtures/$path').readAsStringSync());

Map<String, dynamic> jsonFixtureMap(String path) =>
    jsonFixture(path) as Map<String, dynamic>;

List<dynamic> jsonFixtureList(String path) =>
    jsonFixture(path) as List<dynamic>;
