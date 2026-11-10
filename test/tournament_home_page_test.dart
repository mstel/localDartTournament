import 'dart:async';

import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/challonge/domain/challonge_tournament.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/pages/tournament_results_page.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show TournamentHomePage, TournamentRunPage;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTournamentStorage extends TournamentStorage {
  FakeTournamentStorage({
    List<CreatedTournament> tournaments = const [],
    this.failLoad = false,
    this.deleteCompletion,
  }) : tournaments = List.of(tournaments);

  final List<CreatedTournament> tournaments;
  final bool failLoad;
  final Completer<void>? deleteCompletion;

  @override
  Future<List<CreatedTournament>> loadTournaments() async {
    if (failLoad) throw const FormatException('Ungültiger Turnierspeicher');
    return List.unmodifiable(tournaments);
  }

  @override
  Future<void> deleteTournament(String id) async {
    await deleteCompletion?.future;
    tournaments.removeWhere((tournament) => tournament.id == id);
  }

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    final index = tournaments.indexWhere((item) => item.id == tournament.id);
    if (index < 0) {
      tournaments.insert(0, tournament);
    } else {
      tournaments[index] = tournament;
    }
  }
}

void main() {
  late FakeTournamentStorage storage;

  setUp(() {
    storage = FakeTournamentStorage();
  });

  Future<void> showPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: TournamentHomePage(storage: storage)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> openTournamentActions(WidgetTester tester) async {
    final actions = find.byTooltip('Turnieraktionen');
    final scrollable = find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      actions,
      200,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(actions);
    await tester.pumpAndSettle();
  }

  testWidgets('load error does not show an empty state or zero count', (
    tester,
  ) async {
    storage = FakeTournamentStorage(failLoad: true);

    await showPage(tester);

    expect(find.text('Turniere konnten nicht geladen werden.'), findsOneWidget);
    expect(find.text('Noch keine Turniere gespeichert.'), findsNothing);
    expect(find.text('0 gespeicherte Turniere'), findsNothing);
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });

  testWidgets('empty state appears only after a successful empty load', (
    tester,
  ) async {
    await showPage(tester);

    expect(find.text('Noch keine Turniere gespeichert.'), findsOneWidget);
    expect(find.text('0 gespeicherte Turniere'), findsOneWidget);
    expect(find.text('Turniere konnten nicht geladen werden.'), findsNothing);
  });

  testWidgets('completed tournament end date can be updated from overview', (
    tester,
  ) async {
    final tournament = CreatedTournament(
      id: 'historic',
      name: 'Historisches Turnier',
      players: const [],
      stages: const [],
      runStages: const [],
      tournamentDate: DateTime(2026, 8, 15),
    )..finishedAt = DateTime(2026, 8, 15, 18);
    storage.tournaments.add(tournament);
    await showPage(tester);
    expect(find.text('15.08.2026'), findsOneWidget);

    await openTournamentActions(tester);
    await tester.tap(find.text('Enddatum festlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Turnier-Enddatum auswählen'), findsOneWidget);

    await tester.tap(find.text('20'));
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Endzeit auswählen'), findsOneWidget);
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(tournament.finishedAt, DateTime(2026, 8, 20, 18));
    expect(storage.tournaments.single.finishedAt, DateTime(2026, 8, 20, 18));
  });

  testWidgets(
    'setting an old end date shifts match timestamps and keeps times',
    (tester) async {
      final home = TournamentPlayer(name: 'Home', isGenerated: false);
      final away = TournamentPlayer(name: 'Away', isGenerated: false);
      final firstMatch = GroupMatch(
        homePlayer: home,
        awayPlayer: away,
        round: 1,
        startedAt: DateTime(2026, 11, 6, 15, 20),
        finishedAt: DateTime(2026, 11, 6, 15, 42),
      );
      final secondMatch = GroupMatch(
        homePlayer: away,
        awayPlayer: home,
        round: 2,
        startedAt: DateTime(2026, 11, 6, 16, 5),
        finishedAt: DateTime(2026, 11, 6, 16, 31),
      );
      final tournament = CreatedTournament(
        id: 'imported-historic',
        name: 'Vereinsheim Unzenberg 2026 - 17. Spieltag',
        players: [home, away],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'KO',
            rounds: [
              [firstMatch, secondMatch],
            ],
          ),
        ],
        tournamentDate: DateTime(2026, 5, 6),
        startedAt: DateTime(2026, 11, 6, 14),
        finishedAt: DateTime(2026, 5, 6, 18),
      );
      storage.tournaments.add(tournament);
      await showPage(tester);

      await openTournamentActions(tester);
      await tester.tap(find.text('Enddatum festlegen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6').last);
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(tournament.startedAt, DateTime(2026, 5, 6, 14));
      expect(tournament.finishedAt, DateTime(2026, 5, 6, 18));
      expect(firstMatch.startedAt, DateTime(2026, 5, 6, 15, 20));
      expect(firstMatch.finishedAt, DateTime(2026, 5, 6, 15, 42));
      expect(secondMatch.startedAt, DateTime(2026, 5, 6, 16, 5));
      expect(secondMatch.finishedAt, DateTime(2026, 5, 6, 16, 31));
    },
  );

  testWidgets('deleting a tournament requires name-specific confirmation', (
    tester,
  ) async {
    final tournament = CreatedTournament(
      id: 'delete-me',
      name: 'Sommerpokal',
      players: const [],
      stages: const [],
      runStages: const [],
    );
    storage.tournaments.add(tournament);
    await showPage(tester);

    await openTournamentActions(tester);
    await tester.tap(find.text('Turnier löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Turnier löschen?'), findsOneWidget);
    expect(find.textContaining('„Sommerpokal“'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(storage.tournaments.single.name, 'Sommerpokal');

    await openTournamentActions(tester);
    await tester.tap(find.text('Turnier löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();

    expect(storage.tournaments, isEmpty);
    expect(find.text('Noch keine Turniere gespeichert.'), findsOneWidget);
  });

  testWidgets('deletion displays progress until storage confirms completion', (
    tester,
  ) async {
    final completion = Completer<void>();
    storage = FakeTournamentStorage(deleteCompletion: completion);
    storage.tournaments.add(
      CreatedTournament(
        id: 'progress',
        name: 'Pokal',
        players: const [],
        stages: const [],
        runStages: const [],
      ),
    );
    await showPage(tester);
    await openTournamentActions(tester);
    await tester.tap(find.text('Turnier löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Turnier löschen?'), findsNothing);
    expect(storage.tournaments, hasLength(1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(storage.tournaments, isEmpty);
  });

  testWidgets('search filters tournament names without changing the total', (
    tester,
  ) async {
    for (final name in ['Sommerpokal', 'Winterpokal']) {
      storage.tournaments.add(
        CreatedTournament(
          id: name,
          name: name,
          players: const [],
          stages: const [],
          runStages: const [],
        ),
      );
    }
    await showPage(tester);

    await tester.enterText(find.byType(TextField), 'Sommer');
    await tester.pumpAndSettle();

    expect(find.text('Sommerpokal'), findsOneWidget);
    expect(find.text('Winterpokal'), findsNothing);
    expect(find.text('2 gespeicherte Turniere'), findsOneWidget);
  });

  testWidgets('overview filters by tournament kind, year and ranking', (
    tester,
  ) async {
    storage.tournaments
      ..add(
        CreatedTournament(
          id: 'ranked-2025',
          name: 'Ranglistencup 2025',
          players: const [],
          stages: const [],
          runStages: const [],
          tournamentDate: DateTime(2025, 6, 1),
          countsForRanking: true,
          rankingIds: const ['club-ranking'],
        ),
      )
      ..add(
        CreatedTournament(
          id: 'normal-2026',
          name: 'Normales Turnier 2026',
          players: const [],
          stages: const [],
          runStages: const [],
          tournamentDate: DateTime(2026, 3, 1),
          countsForRanking: false,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: TournamentHomePage(
          storage: storage,
          loadRankings: () async => const [
            LocalRanking(id: 'club-ranking', name: 'Vereinsrangliste'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ranglistencup 2025'), findsOneWidget);
    expect(find.text('Normales Turnier 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tournament-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nur Ranglistenturniere').last);
    await tester.pumpAndSettle();
    expect(find.text('Ranglistencup 2025'), findsOneWidget);
    expect(find.text('Normales Turnier 2026'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tournament-year-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tournament-ranking-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vereinsrangliste').last);
    await tester.pumpAndSettle();

    expect(find.text('Ranglistencup 2025'), findsOneWidget);
    expect(find.text('Normales Turnier 2026'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not show open ranking button on tournament card', (
    tester,
  ) async {
    storage.tournaments.add(
      CreatedTournament(
        id: 'turnier-1',
        name: 'Vereinsturnier',
        players: const [],
        stages: const [],
        runStages: const [],
      ),
    );
    await showPage(tester);

    expect(find.byTooltip('Rangliste öffnen'), findsNothing);
  });

  testWidgets('copying a tournament creates a separate named entry', (
    tester,
  ) async {
    final original = CreatedTournament(
      id: 'turnier-1',
      name: 'Vereinsturnier',
      players: const [],
      stages: const [],
      runStages: const [],
    );
    storage.tournaments.add(original);
    await showPage(tester);

    await openTournamentActions(tester);
    await tester.tap(find.text('Turnier kopieren'));
    await tester.pumpAndSettle();

    expect(storage.tournaments, hasLength(2));
    final copy = storage.tournaments.firstWhere(
      (tournament) => tournament.id != original.id,
    );
    expect(copy.name, 'Vereinsturnier - Kopie');
    expect(copy.players, original.players);
    expect(copy.stages, original.stages);
  });

  testWidgets(
    'converts an imported Challonge archive and allows reopening completed results',
    (tester) async {
      final source = ChallongeTournament({
        'id': 77,
        'name': 'Challonge Finale',
        'state': 'complete',
        'tournament_type': 'round robin',
        'created_at': '2026-04-04T12:00:00Z',
        'started_at': '2026-04-04T13:00:00Z',
        'completed_at': '2026-04-04T14:00:00Z',
        'participants': [
          {'id': 1, 'name': 'Anna', 'final_rank': 1},
          {'id': 2, 'name': 'Ben', 'final_rank': 2},
        ],
        'matches': [
          {
            'id': 12,
            'round': 1,
            'state': 'complete',
            'group_id': 'Gruppe A',
            'group_type': 'round robin',
            'player1_id': 1,
            'player2_id': 2,
            'winner_id': 1,
            'scores_csv': '2-1',
            'started_at': '2026-04-04T13:10:00Z',
            'completed_at': '2026-04-04T13:20:00Z',
          },
        ],
      });
      storage.tournaments.add(
        source.convert({'1': 'profile-anna', '2': 'profile-ben'}),
      );
      await showPage(tester);

      await openTournamentActions(tester);
      await tester.tap(find.text('Zu Dart-Turnier konvertieren'));
      await tester.pumpAndSettle();

      final converted = storage.tournaments.single;
      expect(converted.importedArchive!.usesNativeLogic, isTrue);
      expect(converted.completedStageIndexes, {0});
      expect(find.byType(TournamentResultsPage), findsOneWidget);
      expect(find.text('Turnier abgeschlossen'), findsOneWidget);
      expect(find.byTooltip('Einstellungen'), findsOneWidget);

      await tester.tap(find.byTooltip('Einstellungen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turnier erneut öffnen'));
      await tester.pumpAndSettle();

      expect(find.byType(TournamentRunPage), findsOneWidget);
      expect(storage.tournaments.single.finishedAt, isNull);
      expect(storage.tournaments.single.completedStageIndexes, isEmpty);
    },
  );

  testWidgets('returning from a renamed tournament shows the saved name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final players = [
      TournamentPlayer.generated(1),
      TournamentPlayer.generated(2),
    ];
    final original = CreatedTournament(
      id: 'rename-me',
      name: 'Alter Name',
      players: players,
      stages: const [TournamentStage(name: 'Gruppen', type: 'groups')],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppen',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: players,
              matches: [
                GroupMatch(
                  homePlayer: players.first,
                  awayPlayer: players.last,
                  round: 1,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
        ),
      ],
    );
    storage.tournaments.add(original);
    await showPage(tester);

    await tester.tap(find.text('Alter Name'));
    await tester.pumpAndSettle();
    expect(find.byType(TournamentRunPage), findsOneWidget);

    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Turniername',
    );
    await tester.enterText(nameField, 'Neuer Name');
    await tester.tap(find.text('Namen speichern'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Neuer Name'), findsOneWidget);
    expect(find.text('Alter Name'), findsNothing);
  });

  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('tournament list fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      storage.tournaments.add(
        CreatedTournament(
          id: 'responsive',
          name: 'Turnier mit einem besonders langen deutschen Namen',
          players: const [],
          stages: const [],
          runStages: const [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TournamentHomePage(storage: storage),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.textContaining('besonders langen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.textContaining('besonders langen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
