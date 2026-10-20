import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAccountSessionStorage extends LocalStorage {
  SupabaseAccountSessionStorage({required LocalStorage storage})
    : _storage = storage;

  final LocalStorage _storage;
  bool _persistSession = true;

  bool get persistsSession => _persistSession;

  Future<void> setPersistSession(bool persist) async {
    _persistSession = persist;
    if (!persist) {
      await _storage.removePersistedSession();
    }
  }

  @override
  Future<void> initialize() => _storage.initialize();

  @override
  Future<bool> hasAccessToken() =>
      _persistSession ? _storage.hasAccessToken() : Future.value(false);

  @override
  Future<String?> accessToken() =>
      _persistSession ? _storage.accessToken() : Future.value(null);

  @override
  Future<void> removePersistedSession() => _storage.removePersistedSession();

  @override
  Future<void> persistSession(String persistSessionString) {
    if (!_persistSession) return Future.value();
    return _storage.persistSession(persistSessionString);
  }
}
