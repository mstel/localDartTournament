import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/modes/kratzer/kratzer_engine.dart';

void main() {
  TournamentPlayer player(int number) => TournamentPlayer.generated(number);

  test('round assignment balances 3–6 players across usable boards', () {
    const engine = KratzerEngine();
    final sevenPlayers = [
      for (var index = 1; index <= 7; index++) player(index),
    ];

    final twoBoards = engine.assignRound(
      players: sevenPlayers,
      availableBoards: [1, 2],
      round: 1,
    );
    expect(twoBoards.map((group) => group.players.length), [4, 3]);
    expect(twoBoards.map((group) => group.boardNumber), [1, 2]);
    expect(
      twoBoards.expand((group) => group.players).toSet(),
      sevenPlayers.toSet(),
    );

    final oneBoard = engine.assignRound(
      players: sevenPlayers,
      availableBoards: [2],
      round: 1,
    );
    expect(oneBoard, hasLength(1));
    expect(oneBoard.single.players, hasLength(6));
    expect(oneBoard.single.scratchEligiblePlayers, hasLength(6));
  });

  test('spare boards remain unused if fewer than three players fit', () {
    final assignments = const KratzerEngine().assignRound(
      players: [player(1), player(2), player(3), player(4), player(5)],
      availableBoards: [1, 2, 3],
      round: 1,
    );
    expect(assignments, hasLength(1));
    expect(assignments.single.players, hasLength(5));
  });

  test(
    'multi-group matches keep scratched but not eliminated players eligible',
    () {
      const engine = KratzerEngine();
      final players = [for (var index = 1; index <= 12; index++) player(index)];
      final firstRound = engine.assignRound(
        players: players,
        availableBoards: [1, 2],
        round: 1,
      );
      expect(firstRound.map((assignment) => assignment.players.length), [6, 6]);

      final priorScratches = [
        for (final assignment in firstRound)
          GroupMatch(
            isKratzer: true,
            players: assignment.players,
            scratchEligiblePlayers: assignment.scratchEligiblePlayers,
            scratchedPlayer: assignment.players.first,
            round: 1,
          ),
      ];
      final active = engine.activePlayers(
        players: players,
        completedMatches: priorScratches,
        lives: 2,
      );
      final nextRound = engine.assignRound(
        players: active,
        eliminatedFillers: players.where((p) => !active.contains(p)).toList(),
        availableBoards: [1, 2],
        round: 2,
      );

      expect(
        active,
        containsAll([firstRound[0].players.first, firstRound[1].players.first]),
      );
      expect(
        nextRound.expand((assignment) => assignment.scratchEligiblePlayers),
        containsAll([firstRound[0].players.first, firstRound[1].players.first]),
      );
    },
  );

  test(
    'a two-player tail is completed with an eliminated non-eligible filler',
    () {
      final assignments = const KratzerEngine().assignRound(
        players: [player(1), player(2)],
        eliminatedFillers: [player(3)],
        availableBoards: [1],
        round: 1,
      );
      expect(assignments.single.players, hasLength(3));
      expect(assignments.single.scratchEligiblePlayers.toSet(), {
        player(1),
        player(2),
      });
    },
  );

  test('only scratched players lose lives and one remaining player wins', () {
    const engine = KratzerEngine();
    final players = [player(1), player(2), player(3)];
    final matches = [
      for (var loss = 0; loss < 2; loss++)
        GroupMatch(
          isKratzer: true,
          players: players,
          scratchEligiblePlayers: players,
          scratchedPlayer: players.first,
          round: loss + 1,
        ),
      for (var loss = 0; loss < 3; loss++)
        GroupMatch(
          isKratzer: true,
          players: players,
          scratchEligiblePlayers: players,
          scratchedPlayer: players[1],
          round: loss + 3,
        ),
    ];
    expect(
      engine.activePlayers(
        players: players,
        completedMatches: matches,
        lives: 3,
      ),
      [players.first, players.last],
    );
    expect(engine.requiredScratches(8, 3), 21);
    expect(matches.first.winner, isNull);
    expect(matches.first.loser, players.first);
  });

  test('duration scales with board group size and adds empty-board time', () {
    const engine = KratzerEngine();
    final oneBoard = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 1,
      baseMatchMinutes: 4,
      boardIdleMinutes: 0,
    );
    final twoBoards = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 2,
      baseMatchMinutes: 4,
      boardIdleMinutes: 3,
    );
    expect(oneBoard.games, 3);
    expect(oneBoard.minutes, 20);
    expect(twoBoards.games, oneBoard.games);
    expect(twoBoards.minutes, greaterThan(oneBoard.minutes));
    expect(
      engine.estimatedGameCount(playerCount: 4, lives: 1, boards: 1),
      oneBoard.games,
    );
  });

  test('duration estimates enough games to eliminate all but one player', () {
    const engine = KratzerEngine();
    for (final players in [3, 4, 6, 7, 12]) {
      for (final lives in [1, 2, 5]) {
        for (final boards in [1, 2, 4]) {
          expect(
            engine.estimatedGameCount(
              playerCount: players,
              lives: lives,
              boards: boards,
            ),
            greaterThanOrEqualTo(engine.requiredScratches(players, lives)),
            reason: '$players players, $lives lives, $boards boards',
          );
        }
      }
    }
    expect(engine.estimatedGameCount(playerCount: 3, lives: 2, boards: 1), 4);
  });

  test(
    'tournament JSON preserves Kratzer round data and excludes rankings',
    () {
      final players = [player(1), player(2), player(3)];
      final match = GroupMatch(
        isKratzer: true,
        players: players,
        scratchEligiblePlayers: players,
        scratchedPlayer: players.first,
        round: 1,
        boardNumber: 2,
      );
      final tournament = CreatedTournament(
        name: 'Kratzer',
        players: players,
        stages: const [
          TournamentStage(name: 'Kratzer', type: 'kratzer', knockoutLives: 4),
        ],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Kratzer',
            rounds: [
              [match],
            ],
            eliminationLossLimit: 4,
            isKratzer: true,
            participants: players,
          ),
        ],
        countsForRanking: true,
        rankingIds: const ['ranking-id'],
      );

      final restored = CreatedTournament.fromJson(tournament.toJson());
      final restoredStage =
          restored.runStages.single as KnockoutTournamentRunStage;
      final restoredMatch = restoredStage.matches.single;
      expect(restored.isKratzerTournament, isTrue);
      expect(restored.countsForRanking, isFalse);
      expect(restoredStage.isKratzer, isTrue);
      expect(restoredStage.participants, players);
      expect(
        restoredMatch.participantLabel,
        'Spieler 1 · Spieler 2 · Spieler 3',
      );
      expect(restoredMatch.scratchedPlayer, players.first);
      expect(restoredMatch.winner, isNull);
      expect(restoredMatch.loser, players.first);
    },
  );
}
