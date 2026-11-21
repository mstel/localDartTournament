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

  test('turns alternate home and away and continue with the longer roster', () {
    final state = stateWith();

    expect(
      state.turns.map((turn) => '${turn.teamName}:${turn.player}').toList(),
      ['Heim:H1', 'Gast:G1', 'Heim:H2', 'Gast:G2', 'Gast:G3'],
    );
    expect(state.currentTurn?.player, 'H1');
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
      state.turns.map((turn) => '${turn.teamName}:${turn.player}').toList(),
      [
        'Heim:Johannes Rau',
        'Gast:Alex',
        'Heim:Nina',
        'Gast:Sam',
        'Gast:Tom',
        'Gast:Lea',
      ],
    );
  });

  test('next and previous clamp at both ends', () {
    var state = stateWith(homePlayers: const ['H1'], awayPlayers: const ['G1']);

    expect(state.canGoBack, isFalse);
    expect(state.previous().currentIndex, 0);

    state = state.next();
    expect(state.currentTurn?.player, 'G1');
    expect(state.canGoNext, isFalse);
    expect(state.next().currentIndex, 1);

    state = state.previous();
    expect(state.currentTurn?.player, 'H1');
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
    expect(
      prepared.turns.map((turn) => turn.identity).toList(),
      finished.turns.map((turn) => turn.identity).toList(),
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
