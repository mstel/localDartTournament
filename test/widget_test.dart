import 'package:dart_tournament_manager/main.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openTournamentCreation(WidgetTester tester) async {
    await tester.tap(find.text('Turnier erstellen'));
    await tester.pumpAndSettle();
    final normal = find.text('Normales- oder Ranglistenturnier erstellen');
    if (normal.evaluate().isNotEmpty) {
      await tester.ensureVisible(normal);
      await tester.tap(normal);
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
      if (workflow.evaluate().isNotEmpty &&
          find.byKey(const ValueKey('stage-type-field')).evaluate().isEmpty) {
        await tester.tap(workflow);
        await tester.pumpAndSettle();
      }
    }
  }

  Future<void> revealPlayerGenerator(WidgetTester tester) async {
    final target = find.text('Spieler erzeugen');
    for (
      var attempt = 0;
      attempt < 8 && target.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
  }

  Future<void> revealInCurrentForm(WidgetTester tester, Finder target) async {
    for (
      var attempt = 0;
      attempt < 12 && target.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      final rect = tester.getRect(target.first);
      final viewportHeight =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final delta = rect.bottom < 0 || rect.top < 0 ? 400.0 : -400.0;
      if (rect.top < viewportHeight && rect.bottom > 0) break;
      await tester.drag(find.byType(ListView).last, Offset(0, delta));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openReviewSection(WidgetTester tester) async {
    final review = find.text('3 · Prüfen & anlegen');
    for (
      var attempt = 0;
      attempt < 12 && review.hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    if (find.text('Turnier anlegen').evaluate().isEmpty &&
        review.evaluate().isNotEmpty) {
      await tester.tap(review);
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpUntilRunPage(WidgetTester tester) async {
    final runPage = find.byType(TournamentRunPage);
    for (
      var attempt = 0;
      attempt < 20 && runPage.evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      runPage,
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .whereType<String>()
          .join(' | '),
    );
  }

  Future<void> selectTournamentDashboard(WidgetTester tester) async {
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField &&
          widget.decoration.labelText == 'Turnieransicht',
    );
    if (selector.evaluate().isNotEmpty) {
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard').last);
    } else {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dashboard').first);
    }
    await tester.pumpAndSettle();
  }

  Future<void> selectTournamentResults(WidgetTester tester) async {
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField &&
          widget.decoration.labelText == 'Turnieransicht',
    );
    if (selector.evaluate().isNotEmpty) {
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ergebnisse').last);
    } else {
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ergebnisse').first);
    }
    await tester.pumpAndSettle();
  }

  Future<void> openFullTournamentBracket(WidgetTester tester) async {
    final knockoutButton = find.text('KO Baum öffnen');
    final bracketButton = knockoutButton.evaluate().isNotEmpty
        ? knockoutButton
        : find.text('Vorschau nächste Etappe');
    await tester.ensureVisible(bracketButton);
    await tester.tap(bracketButton);
    await tester.pumpAndSettle();
  }

  Future<void> enterMatchResult(
    WidgetTester tester, {
    required String homePlayer,
    required String awayPlayer,
    required String homeLegs,
    required String awayLegs,
  }) async {
    final matchTile = find.byWidgetPredicate(
      (widget) =>
          widget is MatchResultTile &&
          widget.match.homePlayer?.name == homePlayer &&
          widget.match.awayPlayer?.name == awayPlayer,
    );
    final resultButton = find.descendant(
      of: matchTile,
      matching: find.byTooltip('Ergebnis eingeben'),
    );
    await tester.ensureVisible(resultButton);
    await tester.tap(resultButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('home-legs-field')),
      homeLegs,
    );
    await tester.enterText(
      find.byKey(const ValueKey('away-legs-field')),
      awayLegs,
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
  }

  Future<void> selectTournamentStage(
    WidgetTester tester,
    String stageName,
  ) async {
    final selector = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField &&
          widget.decoration.labelText == 'Etappe',
    );
    if (selector.evaluate().isNotEmpty) {
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(stageName).last);
    } else {
      await tester.tap(find.text(stageName).last);
    }
    await tester.pumpAndSettle();
  }

  testWidgets('creates a knockout-only tournament', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '4');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K.-o.-Runde').last);
    await tester.pumpAndSettle();

    expect(find.text('Start mit allen Spielern'), findsOneWidget);
    expect(find.text('4 Weiter'), findsOneWidget);
    expect(find.text('4er Feld'), findsOneWidget);
    expect(find.text('Bracket-Vorschau'), findsOneWidget);
    expect(find.text('Zufall'), findsOneWidget);
    expect(find.text('Cross seeded'), findsNothing);

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 Etappen im Turnier'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Etappen im Turnier'), findsOneWidget);

    await tester.tap(find.byTooltip('Etappe bearbeiten'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-name-field'), skipOffstage: false),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stage-name-field'), skipOffstage: false),
      'KO pur',
    );
    await tester.ensureVisible(
      find.byTooltip('Etappe speichern', skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe speichern'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('KO pur'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('KO pur'), findsOneWidget);

    await openReviewSection(tester);
    await revealInCurrentForm(tester, find.text('Turnier anlegen'));
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await pumpUntilRunPage(tester);

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(find.text('Neues Turnier (Normales Turnier)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers double and triple knockout formats', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '6');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    expect(find.text('Doppel-KO'), findsWidgets);
    expect(find.text('Triple-KO'), findsWidgets);
    await tester.tap(find.text('Doppel-KO').last);
    await tester.pumpAndSettle();

    expect(find.text('Zufall'), findsOneWidget);
    expect(find.text('Cross seeded'), findsNothing);
    expect(find.text('Halbfinale'), findsWidgets);
    expect(find.text('Losers Bracket'), findsOneWidget);
    expect(find.text('Finale'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Triple-KO').last);
    await tester.pumpAndSettle();

    expect(find.text('Zufall'), findsOneWidget);
    expect(find.text('Cross seeded'), findsNothing);
    expect(find.textContaining('automatisch gesetzt'), findsWidgets);
    expect(find.text('Halbfinale'), findsWidgets);
    expect(find.text('1 Niederlage Bracket'), findsOneWidget);
    expect(find.text('2 Niederlagen Bracket'), findsOneWidget);
    expect(find.textContaining('Verlierer Spiel'), findsWidgets);
    expect(find.text('Finale'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gruppenphase').last);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-play-type-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jeder gegen jeden').last);
    await tester.pumpAndSettle();
    expect(find.text('Doppel-KO in der Gruppe'), findsWidgets);
    expect(find.text('Triple-KO in der Gruppe'), findsWidgets);
    await tester.tap(find.text('Triple-KO in der Gruppe').last);
    await tester.pumpAndSettle();
  });

  testWidgets('double knockout run starts with round one title', (
    tester,
  ) async {
    final players = List.generate(
      8,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final tournament = CreatedTournament(
      name: 'Doppel-KO Test',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Doppel-K.-o.',
          type: 'double_knockout',
          knockoutParticipantCount: 8,
          knockoutBracketSize: 8,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Doppel-K.-o.',
          eliminationLossLimit: 2,
          rounds: [
            [
              GroupMatch(
                homePlayer: players[0],
                awayPlayer: players[7],
                round: 1,
                label: 'Winners Runde 1',
              ),
              GroupMatch(
                homePlayer: players[1],
                awayPlayer: players[6],
                round: 1,
                label: 'Winners Runde 1',
              ),
            ],
            [
              GroupMatch(round: 2, label: 'Winners Runde 2'),
              GroupMatch(round: 2, label: 'Losers Runde 1'),
            ],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentDashboard(tester);

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(find.text('Turnieransicht'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KO bracket refreshes scores and qualifiers after editing', (
    tester,
  ) async {
    final players = [
      for (var index = 1; index <= 4; index++)
        TournamentPlayer.generated(index),
    ];
    final firstMatch = GroupMatch(
      homePlayer: players[0],
      awayPlayer: players[1],
      round: 1,
    );
    final tournament = CreatedTournament(
      name: 'KO Ergebnis-Aktualisierung',
      players: players,
      stages: const [
        TournamentStage(
          name: 'KO',
          type: 'single_knockout',
          knockoutParticipantCount: 4,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'KO',
          rounds: [
            [
              firstMatch,
              GroupMatch(
                homePlayer: players[2],
                awayPlayer: players[3],
                round: 1,
              ),
            ],
            [GroupMatch(round: 2)],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentResults(tester);
    await openFullTournamentBracket(tester);

    final firstBracketMatch = find.byKey(
      const ValueKey('knockout-match-card-1'),
    );
    final editResult = find.descendant(
      of: firstBracketMatch,
      matching: find.byTooltip('Ergebnis'),
    );
    await tester.ensureVisible(editResult);
    await tester.tap(editResult);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-legs-field')), '2');
    await tester.enterText(find.byKey(const ValueKey('away-legs-field')), '0');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    final stage = tournament.runStages.single as KnockoutTournamentRunStage;
    expect(firstMatch.homeLegs, 2);
    expect(stage.rounds.last.single.homePlayer, players[0]);
    expect(
      find.descendant(of: firstBracketMatch, matching: find.text('2')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('knockout-match-card-3')),
        matching: find.text(players[0].name),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resetting a group stage removes generated deciders', (
    tester,
  ) async {
    final players = [
      for (var index = 1; index <= 3; index++)
        TournamentPlayer.generated(index),
    ];
    final matches = [
      for (var home = 0; home < players.length; home++)
        for (var away = home + 1; away < players.length; away++)
          GroupMatch(
            homePlayer: players[home],
            awayPlayer: players[away],
            round: 1,
            homeLegs: 1,
            awayLegs: 1,
          ),
    ];
    final group = TournamentGroup(
      name: 'Gruppe A',
      playType: 'round_robin',
      players: players,
      matches: matches,
    );
    final tournament = CreatedTournament(
      name: 'Gruppen-Decider zurücksetzen',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Gruppen',
          type: 'groups',
          groupSizes: [3],
          qualifiedParticipantCount: 2,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppen',
          groupPlayType: 'round_robin',
          groups: [group],
          qualificationPlan: const QualificationPlan(
            totalQualifiers: 2,
            fixedPerGroup: 2,
            extraCount: 0,
            extraRank: 0,
            eligibleGroupSize: null,
            extraGroups: [],
            fixedByGroup: [2],
          ),
          tieBreakers: const ['points', 'legDifference', 'legsFor'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    expect(group.matches.where((match) => match.isDecider), isNotEmpty);
    await selectTournamentDashboard(tester);
    await tester.ensureVisible(find.text('Etappe zurücksetzen'));
    await tester.tap(find.text('Etappe zurücksetzen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();

    expect(group.matches.where((match) => match.isDecider), isEmpty);
    expect(matches.every((match) => !match.hasResult), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('double knockout with many byes accepts first results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final players = List.generate(
      10,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final tournament = CreatedTournament(
      name: 'Doppel-KO Freilose',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Doppel-K.-o.',
          type: 'double_knockout',
          knockoutParticipantCount: 10,
          knockoutBracketSize: 16,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Doppel-K.-o.',
          eliminationLossLimit: 2,
          rounds: [
            [
              for (var index = 0; index < 6; index++)
                GroupMatch(
                  homePlayer: players[index],
                  round: 1,
                  allowsBye: true,
                  label: 'Automatisch gesetzt',
                ),
              GroupMatch(
                homePlayer: players[6],
                awayPlayer: players[9],
                round: 1,
                allowsBye: true,
                label: 'Winners Runde 1',
              ),
              GroupMatch(
                homePlayer: players[7],
                awayPlayer: players[8],
                round: 1,
                allowsBye: true,
                label: 'Winners Runde 1',
              ),
            ],
            [
              for (var index = 0; index < 4; index++)
                GroupMatch(round: 2, label: 'Winners Runde 2'),
              for (var index = 0; index < 4; index++)
                GroupMatch(
                  round: 2,
                  label: 'Losers Runde 1',
                  homePlayer: index == 0 ? players[6] : null,
                  awayPlayer: index == 0 ? players[6] : null,
                  homeLegs: index == 0 ? 2 : null,
                  awayLegs: index == 0 ? 1 : null,
                ),
            ],
            [
              for (var index = 0; index < 4; index++)
                GroupMatch(round: 3, label: 'Losers Runde 2'),
            ],
            [
              for (var index = 0; index < 2; index++)
                GroupMatch(round: 4, label: 'Winners Runde 3'),
            ],
            [
              for (var index = 0; index < 2; index++)
                GroupMatch(round: 5, label: 'Losers Runde 3'),
            ],
            [GroupMatch(round: 6, label: 'Losers Runde 4')],
            [GroupMatch(round: 7, label: 'Winners Runde 4')],
            [GroupMatch(round: 8, label: 'Losers Runde 5')],
            [GroupMatch(round: 9, label: 'Grand Final')],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentResults(tester);

    await enterMatchResult(
      tester,
      homePlayer: 'Spieler 7',
      awayPlayer: 'Spieler 10',
      homeLegs: '2',
      awayLegs: '0',
    );
    await enterMatchResult(
      tester,
      homePlayer: 'Spieler 8',
      awayPlayer: 'Spieler 9',
      homeLegs: '2',
      awayLegs: '0',
    );

    await openFullTournamentBracket(tester);
    expect(find.textContaining('· Turnierbaum'), findsOneWidget);
    expect(find.byTooltip('Zurück zu Ergebnisse'), findsOneWidget);
    expect(find.text('Spieler 8'), findsWidgets);
    expect(find.text('Spieler 9'), findsWidgets);
    expect(find.text('Spieler 10'), findsWidgets);

    final runStage = tournament.runStages.first as KnockoutTournamentRunStage;
    final firstLosersMatches = runStage.rounds
        .expand((round) => round)
        .where((match) => match.label == 'Losers Runde 1')
        .toList();
    expect(firstLosersMatches, hasLength(4));
    final firstLosersMatch = firstLosersMatches[0];
    expect(firstLosersMatch.homePlayer, players[9]);
    expect(firstLosersMatch.awayPlayer, isNull);
    expect(firstLosersMatch.homeLegs, isNull);
    expect(firstLosersMatch.awayLegs, isNull);
    final secondLosersMatch = firstLosersMatches[1];
    expect(secondLosersMatch.homePlayer, isNull);
    expect(secondLosersMatch.awayPlayer, isNull);
    final thirdLosersMatch = firstLosersMatches[2];
    expect(thirdLosersMatch.homePlayer, players[8]);
    expect(thirdLosersMatch.awayPlayer, isNull);
    final fourthLosersMatch = firstLosersMatches[3];
    expect(fourthLosersMatch.homePlayer, isNull);
    expect(fourthLosersMatch.awayPlayer, isNull);
  });

  testWidgets('repairs old malformed double knockout losers bracket', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final players = List.generate(
      10,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final tournament = CreatedTournament(
      name: 'Altes Doppel-KO',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Doppel-K.-o.',
          type: 'double_knockout',
          knockoutParticipantCount: 10,
          knockoutBracketSize: 16,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Doppel-K.-o.',
          eliminationLossLimit: 2,
          rounds: [
            [
              for (var index = 0; index < 6; index++)
                GroupMatch(
                  homePlayer: players[index],
                  round: 1,
                  allowsBye: true,
                  label: 'Automatisch gesetzt',
                ),
              GroupMatch(
                homePlayer: players[6],
                awayPlayer: players[9],
                round: 1,
                allowsBye: true,
                label: 'Winners Runde 1',
              ),
              GroupMatch(
                homePlayer: players[7],
                awayPlayer: players[8],
                round: 1,
                allowsBye: true,
                label: 'Winners Runde 1',
              ),
            ],
            [
              for (var index = 0; index < 4; index++)
                GroupMatch(round: 2, label: 'Winners Runde 2'),
              GroupMatch(round: 2, label: 'Losers Runde 1'),
              GroupMatch(round: 2, label: 'Losers Runde 2'),
              GroupMatch(round: 2, label: 'Losers Runde 3'),
              GroupMatch(round: 2, label: 'Losers Runde 4'),
            ],
            [GroupMatch(round: 3, label: 'Losers Runde 5')],
            [GroupMatch(round: 4, label: 'Losers Runde 6')],
            [GroupMatch(round: 5, label: 'Losers Runde 7')],
            [GroupMatch(round: 6, label: 'Losers Runde 8')],
            [GroupMatch(round: 7, label: 'Losers Runde 9')],
            [GroupMatch(round: 8, label: 'Grand Final')],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentResults(tester);

    expect(find.text('Losers Runde 9'), findsNothing);
    expect(find.byType(TournamentRunPage), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Ergebnis eingeben').first);
    await tester.tap(find.byTooltip('Ergebnis eingeben').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-legs-field')), '2');
    await tester.enterText(find.byKey(const ValueKey('away-legs-field')), '0');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    await openFullTournamentBracket(tester);
    expect(find.textContaining('· Turnierbaum'), findsOneWidget);
  });

  testWidgets('triple knockout run shows separate loss brackets', (
    tester,
  ) async {
    final players = List.generate(
      4,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final tournament = CreatedTournament(
      name: 'Triple-KO Test',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Triple-K.-o.',
          type: 'triple_knockout',
          knockoutParticipantCount: 4,
          knockoutBracketSize: 4,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Triple-K.-o.',
          eliminationLossLimit: 3,
          rounds: [
            [
              GroupMatch(
                homePlayer: players[0],
                awayPlayer: players[3],
                round: 1,
                label: '0 Niederlagen Runde 1',
              ),
              GroupMatch(
                homePlayer: players[1],
                awayPlayer: players[2],
                round: 1,
                label: '0 Niederlagen Runde 1',
              ),
            ],
            [GroupMatch(round: 2, label: '1 Niederlage Runde 1')],
            [GroupMatch(round: 3, label: '2 Niederlagen Runde 1')],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentDashboard(tester);

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('triple knockout with many byes accepts first results', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final players = List.generate(
      10,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final tournament = CreatedTournament(
      name: 'Triple-KO Freilose',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Triple-K.-o.',
          type: 'triple_knockout',
          knockoutParticipantCount: 10,
          knockoutBracketSize: 16,
        ),
      ],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Triple-K.-o.',
          eliminationLossLimit: 3,
          rounds: [
            [
              for (var index = 0; index < 6; index++)
                GroupMatch(
                  homePlayer: players[index],
                  round: 1,
                  allowsBye: true,
                  label: 'Automatisch gesetzt',
                ),
              GroupMatch(
                homePlayer: players[6],
                awayPlayer: players[9],
                round: 1,
                allowsBye: true,
                label: '0 Niederlagen Runde 1',
              ),
              GroupMatch(
                homePlayer: players[7],
                awayPlayer: players[8],
                round: 1,
                allowsBye: true,
                label: '0 Niederlagen Runde 1',
              ),
            ],
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();
    await selectTournamentResults(tester);

    await enterMatchResult(
      tester,
      homePlayer: 'Spieler 7',
      awayPlayer: 'Spieler 10',
      homeLegs: '2',
      awayLegs: '0',
    );
    await enterMatchResult(
      tester,
      homePlayer: 'Spieler 8',
      awayPlayer: 'Spieler 9',
      homeLegs: '2',
      awayLegs: '1',
    );

    await openFullTournamentBracket(tester);
    expect(find.textContaining('· Turnierbaum'), findsOneWidget);
    expect(find.byTooltip('Zurück zu Ergebnisse'), findsOneWidget);
    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(find.text('Spieler 8'), findsWidgets);
    expect(find.text('Spieler 7'), findsWidgets);

    final runStage = tournament.runStages.first as KnockoutTournamentRunStage;
    expect(
      runStage.rounds
          .expand((round) => round)
          .where((match) => match.label == '1 Niederlage Runde 1'),
      hasLength(4),
    );
    expect(
      runStage.rounds
          .expand((round) => round)
          .where((match) => match.label == '2 Niederlagen Runde 1'),
      hasLength(2),
    );
    expect(
      runStage.rounds
          .expand((round) => round)
          .where((match) => match.label == 'Triple-KO Finalrunde'),
      hasLength(1),
    );

    final firstLossRound = runStage.rounds
        .expand((round) => round)
        .where((match) => match.label == '1 Niederlage Runde 1')
        .toList();
    final droppedPlayers = firstLossRound
        .expand((match) => [match.homePlayer, match.awayPlayer])
        .whereType<TournamentPlayer>()
        .toSet();
    expect(droppedPlayers, {players[9], players[8]});
    final realMatch = firstLossRound.singleWhere((match) => match.hasPlayers);
    expect(
      {realMatch.homePlayer, realMatch.awayPlayer},
      {players[9], players[8]},
    );
    expect(realMatch.hasResult, isFalse);
  });

  testWidgets('sets round robin repeats per group', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '6');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-count-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '2',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('round-robin-repeat-plus-2'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('round-robin-repeat-plus-2')));
    await tester.pumpAndSettle();

    expect(find.text('Begegnungen pro Paar'), findsNothing);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('9 Spiele in dieser Etappe'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 Etappen im Turnier'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Etappen im Turnier'), findsOneWidget);
    expect(
      find.textContaining('Begegnungen: Gruppe A 1x, Gruppe B 2x'),
      findsOneWidget,
    );
  });

  testWidgets('creates deciders for tied best-of group candidates', (
    tester,
  ) async {
    final players = List.generate(
      10,
      (index) => TournamentPlayer.generated(index + 1),
    );
    final groups = [
      for (var groupIndex = 0; groupIndex < 5; groupIndex++)
        TournamentGroup(
          name: groupLabel(groupIndex + 1),
          playType: 'round_robin',
          players: [players[groupIndex * 2], players[groupIndex * 2 + 1]],
          matches: [
            GroupMatch(
              homePlayer: players[groupIndex * 2],
              awayPlayer: players[groupIndex * 2 + 1],
              homeLegs: 2,
              awayLegs: 1,
              round: 1,
            ),
          ],
        ),
    ];
    final tournament = CreatedTournament(
      name: 'Beste-N Decider Test',
      players: players,
      stages: const [
        TournamentStage(
          name: 'Gruppenphase',
          type: 'groups',
          groupSizes: [2, 2, 2, 2, 2],
          qualifiedParticipantCount: 8,
        ),
      ],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: groups,
          qualificationPlan: const QualificationPlan(
            totalQualifiers: 8,
            fixedPerGroup: 1,
            extraCount: 3,
            extraRank: 2,
            eligibleGroupSize: 2,
            extraGroups: [1, 2, 3, 4, 5],
            fixedByGroup: [1, 1, 1, 1, 1],
          ),
          tieBreakers: defaultGroupTieBreakers,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(home: TournamentRunPage(tournament: tournament)),
    );
    await tester.pumpAndSettle();

    final bestOfDeciders = groups
        .expand((group) => group.matches)
        .where((match) => match.label == 'Beste-N Decider')
        .toList();
    expect(bestOfDeciders, hasLength(10));
    expect(
      bestOfDeciders.every((match) => match.isDecider && match.hasPlayers),
      isTrue,
    );
  });

  testWidgets('creates mini knockout groups', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '6');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-play-type-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-play-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mini-KO in der Gruppe').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '2',
    );
    await tester.pumpAndSettle();

    expect(find.text('Begegnungen pro Paar'), findsNothing);
    expect(
      find.text('0 Spiele in dieser Etappe', skipOffstage: false),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 Etappen im Turnier'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Mini-KO in der Gruppe'), findsOneWidget);

    await openReviewSection(tester);
    await tester.dragUntilVisible(
      find.text('Turnier anlegen'),
      find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await pumpUntilRunPage(tester);

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini knockout preview handles top three from five players', (
    tester,
  ) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '5');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-play-type-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('group-play-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mini-KO in der Gruppe').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '1',
    );
    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('group-qualifier-count-field'),
        skipOffstage: false,
      ),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey('group-qualifier-count-field'),
        skipOffstage: false,
      ),
      '3',
    );

    expect(tester.takeException(), isNull);

    await revealInCurrentForm(tester, find.byTooltip('Etappe hinzufügen'));
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await openReviewSection(tester);
    await revealInCurrentForm(tester, find.text('Turnier anlegen'));
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await pumpUntilRunPage(tester);

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sets play type for a single group', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '6');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-count-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '2',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const ValueKey('group-play-type-2-round_robin'),
        skipOffstage: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('group-play-type-2-round_robin')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mini-KO').last);
    await tester.pumpAndSettle();

    expect(find.text('3 Spiele in dieser Etappe'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('round-robin-repeat-plus-2'),
        skipOffstage: false,
      ),
      findsNothing,
    );

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('1 Etappen im Turnier'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'Spieltypen: Gruppe A Jeder gegen jeden, '
        'Gruppe B Mini-KO in der Gruppe',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cross seed gives byes to top group winners', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '24');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-count-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '6',
    );
    await tester.enterText(
      find.byKey(const ValueKey('group-qualifier-count-field')),
      '12',
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K.-o.-Runde').last);
    await tester.pumpAndSettle();

    expect(find.text('12 Weiter'), findsOneWidget);
    expect(find.text('16er Feld'), findsOneWidget);
    expect(find.text('4 Freilose'), findsWidgets);
    expect(
      find.text(
        'Cross Seed vergibt Freilose automatisch an die bestplatzierten Teilnehmer.',
      ),
      findsOneWidget,
    );

    for (final label in [
      '1. Gruppe A',
      '1. Gruppe B',
      '1. Gruppe C',
      '1. Gruppe D',
    ]) {
      final labelFinder = find.text(label);
      expect(labelFinder, findsOneWidget);
      final labelTopLeft = tester.getTopLeft(labelFinder);
      final byeFinder = find.text('Freilos').evaluate().where((element) {
        final box = element.renderObject! as RenderBox;
        final topLeft = box.localToGlobal(Offset.zero);
        return (topLeft.dy - labelTopLeft.dy).abs() < 42;
      });
      expect(byeFinder.length, greaterThanOrEqualTo(1));
    }
  });

  testWidgets('cross seed pairs high group places against lower places', (
    tester,
  ) async {
    await tester.pumpWidget(const DartTournamentApp());

    await openTournamentCreation(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '23');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-count-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '7',
    );
    await tester.enterText(
      find.byKey(const ValueKey('group-qualifier-count-field')),
      '16',
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byTooltip('Etappe hinzufügen'),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Etappe hinzufügen'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K.-o.-Runde').last);
    await tester.pumpAndSettle();

    void expectSamePreviewMatch(String firstLabel, String secondLabel) {
      final firstFinder = find.text(firstLabel);
      final secondFinder = find.text(secondLabel);
      expect(firstFinder, findsOneWidget);
      expect(secondFinder, findsOneWidget);
      final firstTopLeft = tester.getTopLeft(firstFinder);
      final secondTopLeft = tester.getTopLeft(secondFinder);
      expect((firstTopLeft.dy - secondTopLeft.dy).abs() < 42, isTrue);
    }

    expect(find.text('16 Weiter'), findsOneWidget);
    expectSamePreviewMatch('1. Gruppe A', '3. Gruppe B');
    expectSamePreviewMatch('1. Gruppe B', '3. Gruppe A');
    expectSamePreviewMatch('1. Gruppe C', '2. Gruppe G');
    expectSamePreviewMatch('1. Gruppe D', '2. Gruppe F');
    expectSamePreviewMatch('1. Gruppe E', '2. Gruppe D');
    expectSamePreviewMatch('1. Gruppe F', '2. Gruppe E');
    expectSamePreviewMatch('1. Gruppe G', '2. Gruppe C');
  });

  testWidgets('opens tournament creation and manages players', (tester) async {
    await tester.pumpWidget(const DartTournamentApp());

    expect(find.text('Dart Turnierverwaltung'), findsWidgets);
    expect(find.text('Turniere'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Ranglisten'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Ranglisten'), findsWidgets);

    await openTournamentCreation(tester);

    expect(find.text('Turnier erstellen'), findsWidgets);
    expect(find.text('Turniername'), findsOneWidget);
    expect(find.text('Turnierformat'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('stage-type-field')),
        matching: find.text('Gruppenphase'),
      ),
      findsOneWidget,
    );
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Anzahl'), '9');
    await revealPlayerGenerator(tester);
    await tester.tap(find.text('Spieler erzeugen'));
    await tester.pumpAndSettle();

    expect(find.text('9 Spieler im Turnier'), findsOneWidget);
    expect(find.text('Spieler 1'), findsOneWidget);
    expect(find.text('Spieler 4'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Umbenennen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Umbenennen').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextField, 'Spielername'),
      ),
      'Anna',
    );
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Spieler 1'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Spielername'),
      'Max',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('10 Spieler im Turnier'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-count-field')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-count-field')),
      '3',
    );
    await tester.pumpAndSettle();

    expect(find.text('3 Spieler'), findsNWidgets(2));
    expect(find.text('4 Spieler'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('group-play-type-field'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('Jeder gegen jeden', skipOffstage: false), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('group-qualifier-count-field'),
        skipOffstage: false,
      ),
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(
        const ValueKey('group-qualifier-count-field'),
        skipOffstage: false,
      ),
      '4',
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Qualifikation im Detail'));
    await tester.tap(find.text('Qualifikation im Detail'));
    await tester.pumpAndSettle();

    expect(find.text('4 Weiterkommende'), findsOneWidget);
    expect(find.text('Top 1 je Gruppe'), findsOneWidget);
    expect(find.text('Beste 1 der 2. Plätze'), findsOneWidget);
    expect(find.text('Zusatz aus Gruppe A'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('extra-group-chip-2'), skipOffstage: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('extra-group-chip-2')));
    await tester.pumpAndSettle();

    expect(find.text('Zusatz aus Gruppe A, Gruppe B'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('extra-group-chip-2')));
    await tester.pumpAndSettle();
    expect(find.text('Zusatz aus Gruppe A'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-name-field'), skipOffstage: false),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stage-name-field'), skipOffstage: false),
      'Vorrunde',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('1 Etappen im Turnier'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Etappen im Turnier'), findsOneWidget);
    expect(find.text('Vorrunde'), findsOneWidget);
    expect(find.textContaining('12 Spiele'), findsWidgets);
    expect(find.textContaining('Beste 1 der 2. Plätze'), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('stage-type-field')),
      -400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-type-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('K.-o.-Runde').last);
    await tester.pumpAndSettle();

    expect(find.text('Übernahme aus vorheriger Etappe'), findsOneWidget);
    expect(find.text('4 Weiter'), findsOneWidget);
    expect(find.text('4er Feld'), findsOneWidget);
    expect(find.text('0 Freilose'), findsWidgets);
    expect(find.text('Cross seeded'), findsOneWidget);
    expect(find.text('Zufall'), findsOneWidget);
    expect(find.text('Bracket-Vorschau'), findsOneWidget);
    expect(find.text('Spiel 1'), findsWidgets);
    expect(find.text('Finale'), findsOneWidget);
    expect(find.text('1. Gruppe A'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('stage-name-field'), skipOffstage: false),
      'Endrunde',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('2 Etappen im Turnier'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('2 Etappen im Turnier'), findsOneWidget);
    expect(find.text('Endrunde'), findsOneWidget);
    expect(find.textContaining('K.-o.-Runde'), findsWidgets);

    await openReviewSection(tester);
    await revealInCurrentForm(tester, find.text('Turnier anlegen'));
    await tester.tap(find.text('Turnier anlegen'));
    await pumpUntilRunPage(tester);
    await selectTournamentDashboard(tester);

    expect(find.text('Neues Turnier (Normales Turnier)'), findsOneWidget);
    expect(find.text('Spielplan'), findsOneWidget);
    expect(find.text('Letzte Ergebnisse'), findsOneWidget);
    expect(find.text('Runde 1'), findsNothing);

    await selectTournamentStage(tester, '2. Endrunde');

    expect(find.byType(TournamentRunPage), findsOneWidget);
    expect(find.text('Turnieransicht'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await selectTournamentStage(tester, '1. Vorrunde');
    await selectTournamentResults(tester);

    expect(find.textContaining('Offene Spiele'), findsOneWidget);

    await tester.tap(find.byTooltip('Ergebnis eingeben').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-legs-field')), '2');
    await tester.enterText(find.byKey(const ValueKey('away-legs-field')), '1');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('2:1'), findsWidgets);

    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Ergebnis eingeben').at(1)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ergebnis eingeben').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('home-legs-field')), '2');
    await tester.enterText(find.byKey(const ValueKey('away-legs-field')), '0');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    for (var remaining = 0; remaining < 24; remaining++) {
      final openScore = find.text('-:-');
      if (openScore.evaluate().isEmpty) break;
      await Scrollable.ensureVisible(
        tester.element(openScore.first),
        alignment: 0.5,
      );
      await tester.tap(openScore.first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('home-legs-field')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('away-legs-field')),
        '${remaining % 2}',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
    }

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await selectTournamentDashboard(tester);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Etappe abschließen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Etappe abschließen'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Endrunde'), findsWidgets);
    expect(find.text('Spielplan'), findsOneWidget);
    expect(find.text('Letzte Ergebnisse'), findsOneWidget);
  });
}
