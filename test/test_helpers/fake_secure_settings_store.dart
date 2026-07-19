import 'package:seekarr/features/settings/data/settings_service.dart';

class FakeSecureSettingsStore implements SecureSettingsStore {
  final Map<String, String> _storage = {};

  /// When non-null, every [write] and [delete] throws this message wrapped in
  /// an [Exception]. Used to simulate Keychain / secure-storage failures in
  /// widget tests that need to exercise the error UI path.
  String? failureMessage;

  @override
  Future<void> delete({required String key}) async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage.clear();
  }

  @override
  Future<String?> read({required String key}) async {
    return _storage[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final message = failureMessage;
    if (message != null) throw Exception(message);
    _storage[key] = value;
  }
}
