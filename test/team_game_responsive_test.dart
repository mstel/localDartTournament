import 'package:dart_tournament_manager/features/team_game/application/team_game_display_launcher.dart';
import 'package:dart_tournament_manager/features/team_game/data/team_game_signal_repository.dart';
import 'package:dart_tournament_manager/features/team_game/domain/team_game_state.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_display_view.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_page.dart';
import 'package:dart_tournament_manager/features/team_game/presentation/team_game_run_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySignalRepository extends TeamGameSignalRepository {
  TeamGameState? state;

  _MemorySignalRepository(this.state);

  @override
  Future<TeamGameState?> load() async => state;

  @override
  Future<void> save(TeamGameState value) async => state = value;
}

class _NoopDisplayLauncher extends TeamGameDisplayLauncher {
  @override
  Future<bool> open() async => true;
}

void main() {
  final sizes = [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ];

  TeamGameState runningState() => TeamGameState.create(
    homeTeam: 'Heimmannschaft mit langem Namen',
    homePlayers: const ['Johannes Rau'],
    awayTeam: 'Gastmannschaft mit ebensolangem Namen',
    awayPlayers: const ['Mira Kern'],
  ).started();

  for (final size in sizes) {
    testWidgets('Team-Game-Setup bleibt bei $size bedienbar', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TeamGamePage(
            repository: _MemorySignalRepository(null),
            displayLauncher: _NoopDisplayLauncher(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('team-game-home-name')), findsOneWidget);
      expect(find.byKey(const ValueKey('team-game-away-name')), findsOneWidget);

      // Weite ListView-Kinder werden erst nach dem Scrollen materialisiert.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await tester.pumpAndSettle();

      for (final key in [
        'team-game-open-display',
        'team-game-start',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Team-Game-Laufansicht bleibt bei $size bedienbar', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _MemorySignalRepository(runningState());
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TeamGameRunPage(
            initialState: repository.state!,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final key in [
        'team-game-run-next',
        'team-game-run-end',
        'team-game-run-back',
        'team-game-run-leave',
        'team-game-run-open-display',
        'team-game-run-edit-names',
      ]) {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        expect(finder, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Team-Game-Zweitmonitor bleibt bei $size lesbar', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: TeamGameDisplayView(state: runningState()),
        ),
      );
      // Die Wechsel-Animation läuft nur einmal und muss wieder terminieren.
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('team-game-display-player')),
        findsOneWidget,
      );
      expect(find.text('Johannes Rau'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('winner message is large and readable on the second screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final finished = runningState().finished(TeamGameWinner.home);
    await tester.pumpWidget(
      MaterialApp(home: TeamGameDisplayView(state: finished)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('team-game-display-winner')),
      findsOneWidget,
    );
    expect(
      find.text('Team Heimmannschaft mit langem Namen hat gewonnen'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
