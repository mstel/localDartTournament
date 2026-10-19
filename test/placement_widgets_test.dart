import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/main.dart';

void main() {
  testWidgets('places can be selected independently in creation', (
    tester,
  ) async {
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
        workflow.hitTestable().evaluate().isNotEmpty) {
      await tester.tap(workflow);
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '16');
    final generatePlayers = find.text('Spieler erzeugen');
    for (
      var attempt = 0;
      attempt < 8 && generatePlayers.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      generatePlayers,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    await tester.tap(find.text('K.-o.-Runde').last);
    await tester.pumpAndSettle();
    for (final place in [5, 7, 15]) {
      final chip = find.widgetWithText(FilterChip, 'Platz $place');
      for (
        var attempt = 0;
        attempt < 12 && chip.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(ListView).last, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(chip.hitTestable());
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(chip).selected, isTrue);
    }
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Platz 3'))
          .selected,
      isFalse,
    );
  });

  testWidgets('placement tree renders beyond seventh place after restoring', (
    tester,
  ) async {
    final players = List.generate(16, (i) => TournamentPlayer.generated(i + 1));
    const config = TournamentStage(
      name: 'KO',
      type: 'single_knockout',
      placementPlaces: [3, 5, 7, 9, 15],
    );
    final tournament = CreatedTournament(
      name: 'Platzierungen',
      players: players,
      stages: [config],
      runStages: [],
    );
    final runtime = ProductionTournamentRuntime(tournament);
    tournament.runStages.add(runtime.build(config, players));
    final loaded = CreatedTournament.fromJson(tournament.toJson());
    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: loaded)),
    );
    await tester.pumpAndSettle();
    final viewSelector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField &&
          widget.decoration.labelText == 'Turnieransicht',
    );
    await tester.tap(viewSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ergebnisse').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Platzierungsspiele', skipOffstage: false),
      500,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 50,
    );
    expect(find.text('Platzierungsspiele'), findsOneWidget);
    expect(find.text('Spiel um Platz 15', skipOffstage: false), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
