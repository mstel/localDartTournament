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
    final normal = find.text('Normales- oder Ranglistenturnier erstellen');
    if (normal.evaluate().isNotEmpty) {
      await tester.ensureVisible(normal);
      await tester.tap(normal);
      await tester.pumpAndSettle();
    }
    final workflow = find.text('2 · Turnierstruktur');
    for (
      var attempt = 0;
      attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Anzahl Teilnehmende'),
      '16',
    );
    final generatePlayers = find.text('Teilnehmer erzeugen');
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
    await tester.tap(find.text('Teilnehmer erzeugen'));
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tap(workflow);
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
    await tester.ensureVisible(type);
    await tester.pumpAndSettle();
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

  testWidgets('double knockout exposes additional placement playoffs', (
    tester,
  ) async {
    await tester.pumpWidget(const DartTournamentApp());
    await tester.tap(find.text('Turnier erstellen'));
    await tester.pumpAndSettle();
    final normal = find.text('Normales- oder Ranglistenturnier erstellen');
    if (normal.evaluate().isNotEmpty) {
      await tester.ensureVisible(normal);
      await tester.tap(normal);
      await tester.pumpAndSettle();
    }
    final workflow = find.text('2 · Turnierstruktur');
    for (
      var attempt = 0;
      attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.widgetWithText(TextField, 'Anzahl Teilnehmende'),
      '16',
    );
    final generatePlayers = find.text('Teilnehmer erzeugen');
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
    await tester.tap(generatePlayers);
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 8 && workflow.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tap(workflow);
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
    await tester.ensureVisible(type);
    await tester.pumpAndSettle();
    await tester.tap(type.hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doppel-KO').last);
    await tester.pumpAndSettle();

    expect(find.text('Optionale Platzierungsspiele'), findsOneWidget);
    final fifthPlace = find.widgetWithText(FilterChip, 'Platz 5');
    for (
      var attempt = 0;
      attempt < 12 && fifthPlace.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    await tester.tap(fifthPlace.hitTestable());
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(fifthPlace).selected, isTrue);
  });

  testWidgets('placement tree renders beyond seventh place after restoring', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.tap(find.text('Partien & Ergebnisse').last);
    await tester.pumpAndSettle();
    final bracketButton = find.text('KO Baum öffnen');
    await tester.ensureVisible(bracketButton);
    await tester.tap(bracketButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('· Turnierbaum'), findsOneWidget);
    expect(find.byTooltip('Zurück zu Partien & Ergebnisse'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
