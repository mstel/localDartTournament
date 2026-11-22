import 'package:dart_tournament_manager/features/team_game/application/team_game_display_launcher.dart';
import 'package:dart_tournament_manager/features/team_game/data/team_game_signal_repository.dart';
import 'package:dart_tournament_manager/features/team_game/domain/team_game_state.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySignalRepository extends TeamGameSignalRepository {
  TeamGameState? state;

  @override
  Future<TeamGameState?> load() async => state;

  @override
  Future<void> save(TeamGameState value) async => state = value;
}

class _FakeDisplayLauncher implements TeamGameDisplayLauncher {
  int openCount = 0;

  @override
  bool get supportsSeparateWindow => true;

  @override
  Future<bool> open() async {
    openCount++;
    return true;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TeamGameState runningState() => TeamGameState.create(
    homeTeam: 'Heim',
    homePlayers: const ['Johannes Rau', 'Hannes Baur'],
    awayTeam: 'Gast',
    awayPlayers: const ['Mira Kern'],
  ).started();

  testWidgets('run page exposes all six main controls', (tester) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState();

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGameRunPage(
          initialState: repository.state!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Johannes Rau'), findsOneWidget);
    expect(find.text('ist am Zug'), findsOneWidget);
    expect(find.textContaining('RUNDE'), findsNothing);
    expect(find.byKey(const ValueKey('team-game-run-next')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-run-end')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-run-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-run-leave')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('team-game-run-open-display')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('team-game-run-edit-names')),
      findsOneWidget,
    );
    expect(find.text('Zweitmonitor ansicht öffnen'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('next, back and finish synchronize the signal', (tester) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState();

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGameRunPage(
          initialState: repository.state!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('team-game-run-next')));
    await tester.pumpAndSettle();
    expect(repository.state!.currentIndex, 1);
    expect(repository.state!.currentTurn?.player, 'Mira Kern');
    expect(find.text('Mira Kern'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('team-game-run-back')));
    await tester.pumpAndSettle();
    expect(repository.state!.currentIndex, 0);
    expect(find.text('Johannes Rau'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('team-game-run-end')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-game-winner-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('team-game-winner-cancel')));
    await tester.pumpAndSettle();
    expect(repository.state!.status, TeamGameStatus.running);

    await tester.tap(find.byKey(const ValueKey('team-game-run-end')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-game-winner-away')));
    await tester.pumpAndSettle();

    expect(repository.state!.status, TeamGameStatus.finished);
    expect(repository.state!.winner, TeamGameWinner.away);
    expect(find.text('Team Gast hat gewonnen'), findsOneWidget);
  });

  testWidgets('leaving asks for confirmation and "Nein" keeps the game', (
    tester,
  ) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-run'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TeamGameRunPage(
                  initialState: repository.state!,
                  repository: repository,
                ),
              ),
            ),
            child: const Text('Run öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-run')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('team-game-run-leave')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('team-game-leave-dialog')), findsOneWidget);
    expect(find.text('Sind sie sicher ?'), findsOneWidget);
    expect(find.text('Ja'), findsOneWidget);
    expect(find.text('Nein'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('team-game-leave-no')));
    await tester.pumpAndSettle();

    expect(repository.state!.status, TeamGameStatus.running);
    expect(find.byType(TeamGameRunPage), findsOneWidget);
  });

  testWidgets('confirming the leave dialog resets the signal and pops', (
    tester,
  ) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState().next().finished(TeamGameWinner.home);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-run'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TeamGameRunPage(
                  initialState: repository.state!,
                  repository: repository,
                ),
              ),
            ),
            child: const Text('Run öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-run')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('team-game-run-leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-game-leave-yes')));
    await tester.pumpAndSettle();

    expect(repository.state!.status, TeamGameStatus.setup);
    expect(repository.state!.winner, isNull);
    expect(repository.state!.currentIndex, 0);
    expect(find.byType(TeamGameRunPage), findsNothing);
  });

  testWidgets('second monitor stays reachable while the game is running', (
    tester,
  ) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState();
    final launcher = _FakeDisplayLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGameRunPage(
          initialState: repository.state!,
          repository: repository,
          displayLauncher: launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('team-game-run-open-display')));
    await tester.pumpAndSettle();

    expect(launcher.openCount, 1);
    expect(repository.state!.status, TeamGameStatus.running);
    expect(find.text('Zweitmonitoransicht geöffnet.'), findsOneWidget);
  });

  testWidgets('editing names keeps the running turn and winner', (tester) async {
    final repository = _MemorySignalRepository();
    repository.state = runningState().next().finished(TeamGameWinner.away);

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGameRunPage(
          initialState: repository.state!,
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('team-game-run-edit-names')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('team-game-home-name')), findsOneWidget);
    expect(find.text('Heim'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('team-game-home-name')),
      'Neues Heim',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final saveButton = find.byKey(const ValueKey('team-game-save-setup'));
    await tester.scrollUntilVisible(
      saveButton,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.byType(TeamGameRunPage), findsOneWidget);
    expect(repository.state!.home.teamName, 'Neues Heim');
    expect(repository.state!.status, TeamGameStatus.finished);
    expect(repository.state!.winner, TeamGameWinner.away);
    expect(repository.state!.currentIndex, 1);
  });
}
