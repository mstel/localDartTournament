import 'package:dart_tournament_manager/features/backups/presentation/cloud_backup_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('operator sign-in actions and remember-me option are ordered', (
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
    final googleButton = find.text('Mit Google anmelden');
    final forgotPassword = find.text('Passwort vergessen?');
    final registerButton = find.text('Registrieren');
    expect(loginButton, findsOneWidget);
    expect(rememberMe, findsOneWidget);
    expect(
      tester.getCenter(loginButton).dy,
      lessThan(tester.getCenter(rememberMe).dy),
    );
    expect(
      tester.getCenter(rememberMe).dy,
      lessThan(tester.getCenter(googleButton).dy),
    );
    expect(
      tester.getCenter(googleButton).dy,
      lessThan(tester.getCenter(forgotPassword).dy),
    );
    expect(
      tester.getCenter(forgotPassword).dy,
      lessThan(tester.getCenter(registerButton).dy),
    );

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
}
