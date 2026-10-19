import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/main.dart';

void main() {
  testWidgets(
    'creation defaults to deciding final and offers five-life brackets',
    (tester) async {
      await tester.pumpWidget(const DartTournamentApp());
      await tester.tap(find.text('Turnier erstellen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Normales- oder Ranglistenturnier erstellen'));
      await tester.pumpAndSettle();
      final workflow = find.text('2 · Turnierablauf');
      for (
        var attempt = 0;
        attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      if (find.byKey(const ValueKey('stage-type-field')).evaluate().isEmpty &&
          workflow.evaluate().isNotEmpty) {
        await tester.tap(workflow);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '4');
      final generatePlayers = find.text('Spieler erzeugen');
      for (
        var attempt = 0;
        attempt < 8 && generatePlayers.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Spieler erzeugen'));
      await tester.pumpAndSettle();
      final type = find.byKey(const ValueKey('stage-type-field'));
      for (
        var attempt = 0;
        attempt < 12 && type.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(type.hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doppel-KO').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('final-ends-tournament')),
            )
            .value,
        isTrue,
      );
      await tester.tap(type);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kratzer-Modus').last);
      await tester.pumpAndSettle();
      final lives = find.byKey(const ValueKey('kratzer-lives-3'));
      await tester.ensureVisible(lives);
      await tester.tap(lives);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 Leben').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('kratzer-lives-5')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('4 Niederlagen Bracket', skipOffstage: false),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 50,
      );
      expect(find.text('4 Niederlagen Bracket'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
