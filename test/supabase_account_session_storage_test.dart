import 'dart:convert';

import 'package:dart_tournament_manager/features/accounts/data/supabase_account_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remembered Supabase session survives a storage restart', () async {
    final storage = _MemoryLocalStorage();
    final firstRun = SupabaseAccountSessionStorage(storage: storage);
    await firstRun.initialize();
    await firstRun.persistSession('supabase-session');

    final restartedApp = SupabaseAccountSessionStorage(storage: storage);
    await restartedApp.initialize();

    expect(await restartedApp.hasAccessToken(), isTrue);
    expect(await restartedApp.accessToken(), 'supabase-session');
  });

  test('unremembered Supabase session is removed and not restored', () async {
    final storage = _MemoryLocalStorage()..session = 'old-session';
    final currentRun = SupabaseAccountSessionStorage(storage: storage);
    await currentRun.initialize();
    await currentRun.setPersistSession(false);
    await currentRun.persistSession('new-session');

    final restartedApp = SupabaseAccountSessionStorage(storage: storage);
    await restartedApp.initialize();

    expect(await restartedApp.hasAccessToken(), isFalse);
    expect(await restartedApp.accessToken(), isNull);
  });

  test('password sign-in follows the remember-me choice', () async {
    for (final persist in [true, false]) {
      final storage = _MemoryLocalStorage();
      final sessionStorage = SupabaseAccountSessionStorage(storage: storage);
      if (!persist) await sessionStorage.setPersistSession(false);

      final supabase = await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-key',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(_sessionResponse()),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        authOptions: FlutterAuthClientOptions(
          autoRefreshToken: false,
          localStorage: sessionStorage,
          pkceAsyncStorage: _MemoryPkceStorage(),
        ),
      );
      try {
        await supabase.client.auth.signInWithPassword(
          email: 'operator@example.com',
          password: 'password123',
        );
        await Future<void>.delayed(Duration.zero);
        expect(storage.session != null, persist);
      } finally {
        await supabase.dispose();
      }
    }
  });
}

Map<String, Object?> _sessionResponse() {
  final now = DateTime.now().toUtc();
  return {
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'expires_in': 3600,
    'expires_at':
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    'refresh_token': 'test-refresh-token',
    'user': {
      'id': '00000000-0000-4000-8000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'operator@example.com',
      'app_metadata': {
        'provider': 'email',
        'providers': ['email'],
      },
      'user_metadata': {},
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'email_confirmed_at': now.toIso8601String(),
      'confirmed_at': now.toIso8601String(),
      'last_sign_in_at': now.toIso8601String(),
    },
  };
}

class _MemoryLocalStorage extends LocalStorage {
  String? session;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => session != null;

  @override
  Future<String?> accessToken() async => session;

  @override
  Future<void> removePersistedSession() async => session = null;

  @override
  Future<void> persistSession(String persistSessionString) async {
    session = persistSessionString;
  }
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> removeItem({required String key}) async {}

  @override
  Future<void> setItem({required String key, required String value}) async {}
}
