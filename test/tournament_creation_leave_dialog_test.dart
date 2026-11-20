import 'package:dart_tournament_manager/tournament_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _leaveMessage =
    'Möchten Sie wirklich die Seite verlassen? Vorgenommene Änderungen gehen verloren';

Future<void> _pumpCreationWithBackStack(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Center(child: Text('Vorherige Seite'))),
    ),
  );
  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const TournamentCreationPage(skipEntryChoices: true),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Turnier erstellen'), findsOneWidget);
}

void main() {
  testWidgets('back without changes leaves the creation page directly', (
    tester,
  ) async {
    await _pumpCreationWithBackStack(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text(_leaveMessage), findsNothing);
    expect(find.text('Vorherige Seite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back with changes asks for confirmation', (tester) async {
    await _pumpCreationWithBackStack(tester);

    await tester.enterText(
      find.byKey(const ValueKey('tournament-name-field')),
      'Open Cup',
    );
    // enterText setzt den Controller im Widget-Test ohne onChanged auszulösen.
    tester
        .widget<TextField>(find.byKey(const ValueKey('tournament-name-field')))
        .onChanged!('Open Cup');
    await tester.pump();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Vorherige Seite'), findsNothing);
    expect(find.text(_leaveMessage), findsOneWidget);
    expect(find.text('Ja'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);
    expect(find.text('Turnier erstellen'), findsOneWidget);

    // „Nein“ behält die Eingaben und lässt den Dialog erneut erscheinen.
    await tester.tap(find.byKey(const ValueKey('leave-creation-cancel')));
    await tester.pumpAndSettle();
    expect(find.text(_leaveMessage), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('tournament-name-field')),
          )
          .controller!
          .text,
      'Open Cup',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text(_leaveMessage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('leave-creation-confirm')));
    await tester.pumpAndSettle();
    expect(find.text(_leaveMessage), findsNothing);
    expect(find.text('Vorherige Seite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('participant input changes are guarded as well', (tester) async {
    for (final key in ['player-name-field', 'player-count-field']) {
      await _pumpCreationWithBackStack(tester);
      final field = find.byKey(ValueKey(key));
      tester.widget<TextField>(field).onChanged!('9');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text(_leaveMessage), findsOneWidget, reason: key);
      expect(tester.takeException(), isNull, reason: key);

      await tester.tap(find.byKey(const ValueKey('leave-creation-confirm')));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('system back is guarded as well', (tester) async {
    await _pumpCreationWithBackStack(tester);
    await tester.enterText(
      find.byKey(const ValueKey('tournament-name-field')),
      'Open Cup',
    );
    tester
        .widget<TextField>(find.byKey(const ValueKey('tournament-name-field')))
        .onChanged!('Open Cup');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text(_leaveMessage), findsOneWidget);
    expect(find.text('Turnier erstellen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
