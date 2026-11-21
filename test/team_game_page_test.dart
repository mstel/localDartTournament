import 'package:dart_tournament_manager/features/team_game/application/team_game_display_launcher.dart';
import 'package:dart_tournament_manager/features/team_game/data/team_game_signal_repository.dart';
import 'package:dart_tournament_manager/features/team_game/domain/team_game_state.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_page.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySignalRepository extends TeamGameSignalRepository {
  TeamGameState? state;

  @override
  Future<TeamGameState?> load() async => state;

  @override
  Future<void> save(TeamGameState value) async => state = value;

  @override
  Future<void> clear() async => state = null;
}

class _FakeDisplayLauncher extends TeamGameDisplayLauncher {
  _FakeDisplayLauncher({this.shouldOpen = true});

  bool shouldOpen;
  int openCount = 0;

  @override
  Future<bool> open() async {
    openCount++;
    return shouldOpen;
  }
}

void main() {
  testWidgets('setup captures both rosters and starts the alternating run', (
    tester,
  ) async {
    final repository = _MemorySignalRepository();
    final launcher = _FakeDisplayLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGamePage(
          repository: repository,
          displayLauncher: launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Team Game'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('team-game-open-display')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-home-name')), findsOneWidget);
    expect(find.byKey(const ValueKey('team-game-away-name')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('team-game-home-name')),
      'Heim Adler',
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-game-home-player-0')),
      'Johannes Rau',
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-game-away-player-0')),
      'Mira Kern',
    );
    await tester.tap(find.byKey(const ValueKey('team-game-away-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('team-game-away-player-1')),
      'Lena Vogt',
    );

    // Die ListView baut weit unten liegende Kinder erst nach dem Scrollen.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('team-game-open-display')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-game-open-display')));
    await tester.pumpAndSettle();

    expect(launcher.openCount, 1);
    expect(repository.state, isNotNull);
    expect(repository.state!.status, TeamGameStatus.setup);
    expect(repository.state!.home.teamName, 'Heim Adler');
    expect(repository.state!.home.players, ['Johannes Rau']);
    expect(repository.state!.away.players, ['Mira Kern', 'Lena Vogt']);
    expect(repository.state!.turns.map((turn) => turn.player).toList(), [
      'Johannes Rau',
      'Mira Kern',
      'Lena Vogt',
    ]);

    // Die Snackbar von "Zweitmonitor geöffnet" darf den Startbutton nicht verdecken.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('team-game-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-game-start')));
    await tester.pumpAndSettle();

    expect(find.byType(TeamGameRunPage), findsOneWidget);
    expect(repository.state!.status, TeamGameStatus.running);
    expect(repository.state!.currentTurn?.player, 'Johannes Rau');
  });

  testWidgets('validation blocks an empty team name', (tester) async {
    final repository = _MemorySignalRepository();
    final launcher = _FakeDisplayLauncher();

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGamePage(
          repository: repository,
          displayLauncher: launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('team-game-home-name')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('team-game-open-display')));
    await tester.pumpAndSettle();

    expect(
      find.text('Bitte beide Mannschaftsnamen eingeben.'),
      findsOneWidget,
    );
    expect(repository.state, isNull);
    expect(launcher.openCount, 0);
  });

  testWidgets('mobile fallback shows the display inside the app', (tester) async {
    final repository = _MemorySignalRepository();
    final launcher = _FakeDisplayLauncher(shouldOpen: false);

    await tester.pumpWidget(
      MaterialApp(
        home: TeamGamePage(
          repository: repository,
          displayLauncher: launcher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('team-game-home-player-0')),
      'Johannes Rau',
    );
    await tester.enterText(
      find.byKey(const ValueKey('team-game-away-player-0')),
      'Mira Kern',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('team-game-open-display')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-game-open-display')));
    await tester.pump();

    expect(find.byKey(const ValueKey('team-game-display-player')), findsOneWidget);
    expect(find.text('Johannes Rau'), findsWidgets);
    expect(launcher.openCount, 1);
  });
}
