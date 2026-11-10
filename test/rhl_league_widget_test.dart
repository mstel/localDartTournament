import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_match_page.dart';
import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_team_dialogs.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentRunPage;

class _MemoryStorage extends TournamentStorage {
  CreatedTournament? saved;
  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    saved = CreatedTournament.fromJson(tournament.toJson());
  }
}

void main() {
  testWidgets('captains can assign any roster players to open doubles', (
    tester,
  ) async {
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: const ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
      starterCount: 4,
      maxReservePlayers: 2,
      singlesPerPlayer: 1,
      doublesCount: 1,
    );
    Map<int, List<int>>? assignments;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                assignments = await showDialog<Map<int, List<int>>>(
                  context: context,
                  builder: (context) =>
                      LeagueTeamPairingsDialog(league: league, teamSide: 0),
                );
              },
              child: const Text('Doppelpartner zuweisen Heimteam'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Doppelpartner zuweisen Heimteam'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('league-pairing-0-4-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H5 · Ersatzspieler').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('league-pairing-0-4-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H6 · Ersatzspieler').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();

    expect(assignments, {
      4: [4, 5],
    });
    league.games[4].home = assignments![4]!;
    expect(LeagueMatch.fromJson(league.toJson()).games[4].home, [4, 5]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team roster shows active and reserve status', (tester) async {
    final league = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['H1', 'H2', 'H3', 'H4', 'H5'],
      awayPlayers: const ['G1', 'G2', 'G3', 'G4'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LeagueRosterDialog(league: league, teamSide: 0)),
      ),
    );
    expect(find.text('Aktiv'), findsNWidgets(4));
    expect(find.text('Ersatzspieler'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  int estimatedMinutes(WidgetTester tester) {
    final text = tester
        .widget<Text>(find.textContaining('Voraussichtliche Dauer:'))
        .data!;
    final hours =
        RegExp(r'(\d+) (?:Std\.|Stunden)').firstMatch(text)?.group(1) ?? '0';
    final minutes =
        RegExp(r'(\d+) (?:Min\.|Minuten)').firstMatch(text)?.group(1) ?? '0';
    return int.parse(hours) * 60 + int.parse(minutes);
  }

  testWidgets('adjusted mode exposes fixture and duration settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: _MemoryStorage())),
    );
    expect(find.text('Traditionell'), findsOneWidget);
    expect(find.text('Angepasst'), findsOneWidget);
    expect(find.text('Geräte zuordnen'), findsNothing);

    await tester.tap(find.text('Angepasst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angepasster Spielplan'));
    await tester.pumpAndSettle();

    expect(
      find.text('Name des angepassten Liga-/Freundschaftsspiels'),
      findsOneWidget,
    );
    expect(find.text('Einzel je Spieler'), findsOneWidget);
    expect(find.text('Doppel je Mannschaft'), findsOneWidget);
    expect(find.text('X01-Punktzahl'), findsOneWidget);
    expect(
      find.text('Angepasstes Liga-/Freundschaftsspiel anlegen'),
      findsOneWidget,
    );
    expect(find.textContaining('10 Begegnungen'), findsOneWidget);
    expect(find.textContaining('Voraussichtliche Dauer:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjusted duration refreshes when the game format changes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: _MemoryStorage())),
    );
    await tester.tap(find.text('Angepasst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angepasster Spielplan'));
    await tester.pumpAndSettle();

    final initialDuration = estimatedMinutes(tester);
    final x01Field = find.byKey(const ValueKey('league-x01-501'));
    await tester.tap(x01Field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('901').last);
    await tester.pumpAndSettle();
    final longerX01Duration = estimatedMinutes(tester);
    expect(longerX01Duration, greaterThan(initialDuration));

    final legsField = find.byKey(const ValueKey('league-legs-5'));
    await tester.tap(legsField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('9 Legs').last);
    await tester.pumpAndSettle();
    expect(estimatedMinutes(tester), greaterThan(longerX01Duration));
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjusted setup creates ten starters with an uneven bench', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: storage)),
    );
    await tester.tap(find.text('Angepasst'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Angepasster Spielplan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heimteam & Aufstellung'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gastteam & Aufstellung'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gastteam & Aufstellung'));
    await tester.pumpAndSettle();

    for (var player = 0; player < 4; player++) {
      for (var team = 0; team < 2; team++) {
        final addButtons = find.text('Spieler / Ersatzspieler hinzufügen');
        await tester.scrollUntilVisible(
          addButtons.at(team),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(addButtons.at(team));
        await tester.pumpAndSettle();
      }
    }

    final starterCount = find.byKey(const ValueKey('starter-count-4-10-10'));
    await tester.scrollUntilVisible(
      starterCount,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(starterCount);
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').last);
    await tester.pumpAndSettle();

    final addButtons = find.text('Spieler / Ersatzspieler hinzufügen');
    await tester.scrollUntilVisible(
      addButtons.last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(addButtons.last);
    await tester.pumpAndSettle();

    final createButton = find.text(
      'Angepasstes Liga-/Freundschaftsspiel anlegen',
    );
    await tester.scrollUntilVisible(
      createButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    final createdLeague = storage.saved!.leagueMatch!;
    expect(createdLeague.starterCount, 10);
    expect(createdLeague.activePlayers(0), hasLength(10));
    expect(createdLeague.activePlayers(1), hasLength(10));
    expect(createdLeague.reservePlayers(0), isEmpty);
    expect(createdLeague.reservePlayers(1), [10]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creates league and saves a team result', (tester) async {
    final storage = _MemoryStorage();
    await tester.pumpWidget(
      MaterialApp(home: LeagueMatchPage(storage: storage)),
    );
    expect(find.textContaining('Neues Ligaspiel'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('league-name')),
      'Vereinsliga · Spieltag 3',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ligaspiel anlegen'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ligaspiel anlegen'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.games.length, 18);
    expect(storage.saved!.name, 'Vereinsliga · Spieltag 3');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('league-result-0')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ergebnis').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3:1'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.homePoints, 1);
    await tester.tap(find.text('Ergebnis').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ergebnis entfernen'));
    await tester.pumpAndSettle();
    expect(storage.saved!.leagueMatch!.homePoints, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live team substitution confirms and updates future fixtures', (
    tester,
  ) async {
    final storage = _MemoryStorage();
    final league = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
    );
    final tournament = CreatedTournament(
      name: 'Liga',
      players: [
        for (final name in [...league.homePlayers, ...league.awayPlayers])
          TournamentPlayer(name: name, isGenerated: false),
      ],
      stages: [],
      runStages: [],
      leagueMatch: league,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LeagueMatchPage(tournament: tournament, storage: storage),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Auswechselungen Heimteam'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Auswechselungen Heimteam'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog).last;
    await tester.tap(find.descendant(of: dialog, matching: find.text('H1')));
    await tester.tap(find.descendant(of: dialog, matching: find.text('H5')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Auswechseln')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auswechseln bestätigen?'), findsOneWidget);
    expect(
      find.textContaining('Ihre Mannschaft hat danach noch 1 Auswechselungen'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ja, auswechseln'));
    await tester.pumpAndSettle();

    expect(storage.saved!.leagueMatch!.games[0].home, [4]);
    expect(storage.saved!.leagueMatch!.activePlayers(0), contains(4));
    expect(storage.saved!.leagueMatch!.substitutionsRemaining(0), 1);
    expect(find.text('1 Auswechselungen verfügbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('league run settings expose and persist team substitutions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = _MemoryStorage();
    final league = LeagueMatch.rhl(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: ['H1', 'H2', 'H3', 'H4', 'H5', 'H6'],
      awayPlayers: ['G1', 'G2', 'G3', 'G4', 'G5', 'G6'],
    );
    final tournament = CreatedTournament(
      name: 'Liga',
      players: [
        for (final name in [...league.homePlayers, ...league.awayPlayers])
          TournamentPlayer(name: name, isGenerated: false),
      ],
      stages: [],
      runStages: [],
      leagueMatch: league,
      directorModeEnabled: true,
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
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Leitung'), findsOneWidget);
    expect(find.text('Ergebnisse'), findsOneWidget);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Heimteam · Heim'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heimteam · Heim'));
    await tester.pumpAndSettle();
    expect(find.text('Aktiv'), findsNWidgets(4));
    expect(find.text('Ersatzspieler'), findsNWidgets(2));
    await tester.scrollUntilVisible(
      find.text('Teamoptionen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Teamoptionen'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Auswechselungen Heimteam'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auswechselungen Heimteam'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog).last;
    await tester.tap(find.descendant(of: dialog, matching: find.text('H1')));
    await tester.tap(find.descendant(of: dialog, matching: find.text('H5')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Auswechseln')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ja, auswechseln'));
    await tester.pumpAndSettle();

    expect(storage.saved!.leagueMatch!.games[0].home, [4]);
    expect(storage.saved!.leagueMatch!.substitutionsRemaining(0), 1);
    expect(find.text('1 Auswechselungen verfügbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
