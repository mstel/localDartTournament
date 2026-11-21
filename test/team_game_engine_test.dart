import 'dart:io';

import 'package:dart_tournament_manager/app/team_game_standalone_app.dart';
import 'package:dart_tournament_manager/features/team_game/application/team_game_display_session_registry.dart';
import 'package:dart_tournament_manager/features/team_game/data/team_game_signal_repository.dart';
import 'package:dart_tournament_manager/features/team_game/domain/team_game_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TeamGameState stateWith({
    List<String> homePlayers = const ['H1', 'H2'],
    List<String> awayPlayers = const ['G1', 'G2', 'G3'],
  }) {
    return TeamGameState.create(
      homeTeam: 'Heim',
      homePlayers: homePlayers,
      awayTeam: 'Gast',
      awayPlayers: awayPlayers,
    ).started();
  }

  List<String> sequence(TeamGameState state, int count) => [
    for (var i = 0; i < count; i++)
      '${state.turnAt(i)!.teamName}:${state.turnAt(i)!.player}',
  ];

  test('each team rotates through its own roster without a fixed end', () {
    final state = stateWith();

    expect(
      sequence(state, 10),
      [
        'Heim:H1',
        'Gast:G1',
        'Heim:H2',
        'Gast:G2',
        'Heim:H1',
        'Gast:G3',
        'Heim:H2',
        'Gast:G1',
        'Heim:H1',
        'Gast:G2',
      ],
    );
    expect(state.currentTurn?.player, 'H1');
    expect(state.canGoNext, isTrue);
  });

  test('a five against four roster keeps both teams cycling independently', () {
    final state = stateWith(
      homePlayers: const ['H1', 'H2', 'H3', 'H4', 'H5'],
      awayPlayers: const ['G1', 'G2', 'G3', 'G4'],
    );

    expect(
      sequence(state, 12),
      [
        'Heim:H1',
        'Gast:G1',
        'Heim:H2',
        'Gast:G2',
        'Heim:H3',
        'Gast:G3',
        'Heim:H4',
        'Gast:G4',
        'Heim:H5',
        'Gast:G1',
        'Heim:H1',
        'Gast:G2',
      ],
    );

    var advanced = state;
    for (var i = 0; i < 40; i++) {
      advanced = advanced.next();
      expect(advanced.canGoNext, isTrue);
      expect(advanced.currentTurn, isNotNull);
    }
  });

  test('empty roster entries and surrounding spaces are normalized', () {
    final state = TeamGameState.create(
      homeTeam: '  Heim  ',
      homePlayers: const [' Johannes Rau ', '', 'Nina'],
      awayTeam: ' Gast ',
      awayPlayers: const ['Alex', 'Sam', 'Tom', 'Lea'],
    );

    expect(state.home.teamName, 'Heim');
    expect(state.home.players, ['Johannes Rau', 'Nina']);
    expect(
      sequence(state, 10),
      [
        'Heim:Johannes Rau',
        'Gast:Alex',
        'Heim:Nina',
        'Gast:Sam',
        'Heim:Johannes Rau',
        'Gast:Tom',
        'Heim:Nina',
        'Gast:Lea',
        'Heim:Johannes Rau',
        'Gast:Alex',
      ],
    );
  });

  test('next never ends and previous clamps at the first turn', () {
    var state = stateWith(homePlayers: const ['H1'], awayPlayers: const ['G1']);

    expect(state.canGoBack, isFalse);
    expect(state.previous(), same(state));

    state = state.next().next().next();
    expect(state.currentIndex, 3);
    expect(state.currentTurn?.player, 'G1');
    expect(state.canGoNext, isTrue);
    expect(state.next().currentIndex, 4);

    state = state.previous().previous().previous().previous().previous();
    expect(state.currentIndex, 0);
    expect(state.currentTurn?.player, 'H1');
    expect(state.previous(), same(state));
  });

  test('empty rosters stay safe for navigation', () {
    final state = TeamGameState.create(
      homeTeam: 'Heim',
      homePlayers: const [],
      awayTeam: 'Gast',
      awayPlayers: const [],
    ).started();

    expect(state.hasPlayers, isFalse);
    expect(state.currentTurn, isNull);
    expect(state.canGoNext, isFalse);
    expect(state.canGoBack, isFalse);
    expect(state.turnAt(5), isNull);
    expect(state.next(), same(state));
    expect(state.previous(), same(state));
  });

  test('finished state carries the winning team name and no score', () {
    final state = stateWith().finished(TeamGameWinner.away);

    expect(state.status, TeamGameStatus.finished);
    expect(state.winner, TeamGameWinner.away);
    expect(state.winningTeamName, 'Gast');
    expect(state.toJson().containsKey('score'), isFalse);
    expect(state.toJson().containsKey('points'), isFalse);
  });

  test('prepared resets winner and turn but keeps the roster', () {
    final finished = stateWith().next().finished(TeamGameWinner.home);
    final prepared = finished.prepared();

    expect(prepared.status, TeamGameStatus.setup);
    expect(prepared.currentIndex, 0);
    expect(prepared.winner, isNull);
    expect(prepared.home.teamName, 'Heim');
    expect(prepared.home.players, finished.home.players);
    expect(prepared.away.players, finished.away.players);
    expect(
      prepared.currentTurn?.identity,
      finished.turnAt(0)?.identity,
    );
  });

  test('JSON roundtrip preserves status, turn and winner', () {
    final state = stateWith().next().finished(TeamGameWinner.home);
    final restored = TeamGameState.fromJsonString(state.toJsonString());

    expect(restored.toJson(), state.toJson());
    expect(restored.status, TeamGameStatus.finished);
    expect(restored.currentTurn?.player, 'G1');
    expect(restored.winningTeamName, 'Heim');
  });

  test('unknown newer schema versions are rejected', () {
    final json = stateWith().toJson();
    json['schemaVersion'] = 99;

    expect(() => TeamGameState.fromJson(json), throwsFormatException);
  });

  test('display refreshes only when the serialized signal changes', () {
    final state = stateWith();
    final identical = TeamGameState.fromJsonString(state.toJsonString());
    final advanced = state.next();

    expect(teamGameStateChanged(state, identical), isFalse);
    expect(teamGameStateChanged(state, advanced), isTrue);
    expect(teamGameStateChanged(null, state), isTrue);
    expect(teamGameStateChanged(null, null), isFalse);
  });

  group('versionierte Signaturdatei', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('team_game_engine_test');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    test('repository saves and loads the current signal', () async {
      final repository = TeamGameSignalRepository(
        directoryProvider: () async => directory,
      );
      final state = stateWith().next();

      expect(await repository.load(), isNull);
      await repository.save(state);
      expect((await repository.load())?.toJson(), state.toJson());

      await repository.clear();
      expect(await repository.load(), isNull);
    });

    test('display heartbeat can be detected and cleared', () async {
      final registry = TeamGameDisplaySessionRegistry(
        directoryProvider: () async => directory,
      );

      expect(await registry.isActive(), isFalse);
      await registry.heartbeat();
      expect(await registry.isActive(), isTrue);

      await registry.clear();
      expect(await registry.isActive(), isFalse);
    });
  });
}
