import 'package:dart_tournament_manager/features/backups/presentation/cloud_backup_panel.dart';
import 'package:dart_tournament_manager/features/accounts/application/account_session_store.dart';
import 'package:dart_tournament_manager/features/accounts/domain/account_user.dart';
import 'package:dart_tournament_manager/features/accounts/presentation/widgets/account_menu_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('operator sign-in hides public registration and Google auth', (
    tester,
  ) async {
    OperatorSignInResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<OperatorSignInResult>(
                  context: context,
                  builder: (_) => const OperatorSignInDialog(),
                );
              },
              child: const Text('Open login'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();

    final loginButton = find.widgetWithText(FilledButton, 'Anmelden');
    final rememberMe = find.byType(CheckboxListTile);
    final forgotPassword = find.text('Passwort vergessen?');
    final registerButton = find.text('Registrieren');
    expect(loginButton, findsOneWidget);
    expect(rememberMe, findsOneWidget);
    expect(forgotPassword, findsOneWidget);
    expect(find.text('Mit Google anmelden'), findsNothing);
    expect(registerButton, findsNothing);

    expect(tester.widget<CheckboxListTile>(rememberMe).value, isTrue);
    await tester.enterText(
      find.byType(TextField).at(0),
      'operator@example.com',
    );
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(rememberMe);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(rememberMe).value, isFalse);

    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    expect(result?.persistSession, isFalse);
    expect(result?.email, 'operator@example.com');
  });

  testWidgets('account menu only exposes operator sign-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccountMenuCard(store: _SignedOutStore())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Account erstellen'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _SignedOutStore implements AccountSessionStore {
  @override
  String get signInLabel => 'Supabase Online-Account';

  @override
  bool get supportsPasswordReset => false;

  @override
  Future<AccountUser?> loadCurrentAccount() async => null;

  @override
  Future<AccountUser?> signInAccount({
    required String email,
    required String password,
  }) async => null;

  @override
  Future<AccountUser> registerAccount({
    required String displayName,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signOutCurrentAccount() async {}
}
