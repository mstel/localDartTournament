import 'package:dart_tournament_manager/features/accounts/data/supabase_account_config.dart';
import 'package:dart_tournament_manager/features/accounts/domain/account_user.dart';
import 'package:dart_tournament_manager/features/accounts/presentation/widgets/account_menu_card.dart';
import 'package:dart_tournament_manager/features/accounts/application/account_session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup clears the saved session and uses non-persistent auth storage',
    () async {
      SharedPreferences.setMockInitialValues({
        SupabaseAccountConfig.sessionStorageKey(SupabaseAccountConfig.url):
            'saved-session-fixture',
        'unrelated-setting': 'keep',
      });
      final preferences = await SharedPreferences.getInstance();
      await SupabaseAccountConfig.clearPersistedSession(
        preferences: preferences,
      );

      expect(
        preferences.containsKey(
          SupabaseAccountConfig.sessionStorageKey(SupabaseAccountConfig.url),
        ),
        isFalse,
      );
      expect(preferences.getString('unrelated-setting'), 'keep');

      final storage = SupabaseAccountConfig.authOptions.localStorage!;
      await storage.initialize();
      await storage.persistSession('session-created-during-this-run');
      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    },
  );

  testWidgets('explicit logout clears the active account from the menu', (
    tester,
  ) async {
    final store = _FakeAccountSessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountMenuCard(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Abmelden'), findsOneWidget);

    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();

    expect(store.signOutCalls, 1);
    expect(find.text('Anmelden'), findsOneWidget);
  });
}

class _FakeAccountSessionStore implements AccountSessionStore {
  AccountUser? account = AccountUser(
    id: 'test-user',
    username: 'test',
    displayName: 'Test account',
    email: 'test@example.invalid',
    avatarUrl: null,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    lastLogin: null,
    isActive: true,
  );
  int signOutCalls = 0;

  @override
  String get signInLabel => 'Test-Account';

  @override
  bool get supportsPasswordReset => false;

  @override
  Future<AccountUser?> loadCurrentAccount() async => account;

  @override
  Future<AccountUser?> signInAccount({
    required String email,
    required String password,
  }) async => account;

  @override
  Future<AccountUser> registerAccount({
    required String displayName,
    required String email,
    required String password,
  }) async => account!;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signOutCurrentAccount() async {
    signOutCalls++;
    account = null;
  }
}
