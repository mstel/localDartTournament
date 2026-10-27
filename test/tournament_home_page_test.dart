import 'dart:async';

import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
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

    await tester.tap(find.byTooltip('Turnieraktionen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turnier löschen'));
    await tester.pumpAndSettle();

    expect(find.text('Turnier löschen?'), findsOneWidget);
    expect(find.textContaining('„Sommerpokal“'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(storage.tournaments.single.name, 'Sommerpokal');

    await tester.tap(find.byTooltip('Turnieraktionen'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('Turnieraktionen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turnier löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pump(const Duration(milliseconds: 300));

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

    await tester.tap(find.byTooltip('Turnieraktionen'));
    await tester.pumpAndSettle();
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
      await tester.drag(find.byType(ListView), const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(find.textContaining('besonders langen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
