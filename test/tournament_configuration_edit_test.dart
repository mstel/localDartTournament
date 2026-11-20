import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;

class _MemoryTournamentStorage extends TournamentStorage {
  CreatedTournament? saved;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    saved = CreatedTournament.fromJson(tournament.toJson());
  }
}

CreatedTournament _tournament({
  required bool hasResult,
  LeagueMatch? leagueMatch,
}) {
  final players = [
    TournamentPlayer.generated(1),
    TournamentPlayer.generated(2),
  ];
  final match = GroupMatch(
    homePlayer: players[0],
    awayPlayer: players[1],
    round: 1,
    homeLegs: hasResult ? 3 : null,
    awayLegs: hasResult ? 1 : null,
  );
  return CreatedTournament(
    name: 'Konfigurationstest',
    players: players,
    leagueMatch: leagueMatch,
    stages: [TournamentStage(name: 'Gruppenphase', type: 'groups')],
    runStages: [
      GroupTournamentRunStage(
        name: 'Gruppenphase',
        groupPlayType: 'round_robin',
        qualificationPlan: null,
        tieBreakers: defaultGroupTieBreakers,
        groups: [
          TournamentGroup(
            name: 'Gruppe A',
            playType: 'round_robin',
            players: players,
            matches: [match],
          ),
        ],
      ),
    ],
  );
}

void main() {
  for (final hasResult in [false, true]) {
    testWidgets(
      'configuration editing is ${hasResult ? 'disabled' : 'enabled'} when result=$hasResult',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final storage = _MemoryTournamentStorage();
        await tester.pumpWidget(
          MaterialApp(
            home: TournamentRunPage(
              tournament: _tournament(hasResult: hasResult),
              tournamentStorage: storage,
              runController: TournamentRunController(storage: storage),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Einstellungen'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Turnierkonfiguration bearbeiten'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final editButton = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Turnierkonfiguration bearbeiten'),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(editButton.onPressed == null, hasResult);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('fixed schedule edit dialogs open from run settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _MemoryTournamentStorage();
    final tournament = _tournament(hasResult: false)
      ..directorModeEnabled = true
      ..directorPlayOrderMode = 'fixed_schedule';

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: tournament,
          tournamentStorage: storage,
          runController: TournamentRunController(storage: storage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('director-settings')));
    await tester.pumpAndSettle();

    final perBoardButton = find.byKey(
      const ValueKey('edit-fixed-schedule-per-board'),
    );
    final overallButton = find.byKey(
      const ValueKey('edit-fixed-schedule-overall'),
    );
    await tester.scrollUntilVisible(
      perBoardButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(perBoardButton, findsOneWidget);
    expect(overallButton, findsOneWidget);

    await tester.tap(perBoardButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Spielplan je Board bearbeiten'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    await tester.tap(overallButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Gesamten Spielplan bearbeiten'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('director settings persist when the page is reopened', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _MemoryTournamentStorage();
    final controller = TournamentRunController(storage: storage);
    final tournament = _tournament(hasResult: false);

    Finder labeledDropdown(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == label,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: tournament,
          tournamentStorage: storage,
          runController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('director-settings')));
    await tester.pumpAndSettle();
    final directorSwitch = find.widgetWithText(
      SwitchListTile,
      'Spielleiter-Modus aktivieren',
    );
    await tester.ensureVisible(directorSwitch);
    await tester.tap(directorSwitch);
    await tester.pumpAndSettle();

    final playOrderDropdown = labeledDropdown('Spielplanmodus');
    await tester.scrollUntilVisible(
      playOrderDropdown,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(playOrderDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fester Spielplan').last);
    await tester.pumpAndSettle();

    final assignmentDropdown = labeledDropdown('Board Zuweisung');
    await tester.scrollUntilVisible(
      assignmentDropdown,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(assignmentDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turnierweit optimiert').last);
    await tester.pumpAndSettle();

    expect(storage.saved, isNotNull);
    expect(storage.saved!.directorModeEnabled, isTrue);
    expect(storage.saved!.directorPlayOrderMode, 'fixed_schedule');
    expect(storage.saved!.directorSchedulingStrategy, 'global');

    final reopened = CreatedTournament.fromJson(storage.saved!.toJson());
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          key: const ValueKey('reopened-run-page'),
          tournament: reopened,
          tournamentStorage: storage,
          runController: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('director-settings')));
    await tester.pumpAndSettle();

    final restoredSwitch = find.widgetWithText(
      SwitchListTile,
      'Spielleiter-Modus aktivieren',
    );
    await tester.ensureVisible(restoredSwitch);
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: restoredSwitch, matching: find.byType(Switch)),
          )
          .value,
      isTrue,
    );
    expect(find.text('Fester Spielplan'), findsOneWidget);
    expect(find.text('Turnierweit optimiert'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('league fixed schedule offers both board suggestion modes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _MemoryTournamentStorage();
    final tournament = _tournament(
      hasResult: false,
      leagueMatch: LeagueMatch.adjusted(
        homeTeam: 'Heim',
        awayTeam: 'Gast',
        homePlayers: const ['Teilnehmer 1'],
        awayPlayers: const ['Teilnehmer 2'],
        singlesPerPlayer: 1,
        doublesCount: 0,
      ),
    )..directorPlayOrderMode = 'fixed_schedule';

    Finder labeledDropdown(String label) => find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == label,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TournamentRunPage(
          tournament: tournament,
          tournamentStorage: storage,
          runController: TournamentRunController(storage: storage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('director-settings')));
    await tester.pumpAndSettle();

    final suggestionDropdown = labeledDropdown('Partievorschläge');
    await tester.scrollUntilVisible(
      suggestionDropdown,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(suggestionDropdown);
    await tester.pumpAndSettle();
    expect(
      find.text('Flexible Boardwahl - Gespiegelte Partievorschläge'),
      findsWidgets,
    );
    expect(
      find.text('Fest zugewiesene Partien - Keine Doppelungen'),
      findsWidgets,
    );
    await tester.tap(
      find.text('Fest zugewiesene Partien - Keine Doppelungen').last,
    );
    await tester.pumpAndSettle();

    expect(storage.saved, isNotNull);
    expect(storage.saved!.directorMultiBoardAssignmentBehavior, 'assigned');
    expect(tester.takeException(), isNull);
  });
}
