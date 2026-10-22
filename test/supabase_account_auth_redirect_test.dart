import 'dart:convert';

import 'package:dart_tournament_manager/features/accounts/data/supabase_account_config.dart';
import 'package:dart_tournament_manager/features/accounts/data/supabase_account_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registration and password reset use the app auth callback', () async {
    final requests = <http.Request>[];
    final supabase = await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: _MemoryLocalStorage(),
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
    final store = SupabaseAccountSessionStore(client: supabase.client);

    try {
      await expectLater(
        store.registerAccount(
          displayName: 'Operator',
          email: 'operator@example.com',
          password: 'password123',
        ),
        throwsA(isA<AuthException>()),
      );
      await store.sendPasswordResetEmail(email: 'operator@example.com');

      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(
          request.url.queryParameters['redirect_to'],
          SupabaseAccountConfig.authRedirectUri,
        );
      }
    } finally {
      await supabase.dispose();
    }
  });

  test('auth callback uses the registered custom URI scheme', () {
    final callback = Uri.parse(SupabaseAccountConfig.authRedirectUri);

    expect(callback.scheme, 'dartturnier');
    expect(callback.host, 'auth');
    expect(callback.path, '/callback');
  });
}

class _MemoryLocalStorage extends LocalStorage {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => false;

  @override
  Future<String?> accessToken() async => null;

  @override
  Future<void> removePersistedSession() async {}

  @override
  Future<void> persistSession(String persistSessionString) async {}
}

class _MemoryPkceStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> removeItem({required String key}) async {}

  @override
  Future<void> setItem({required String key, required String value}) async {}
}
