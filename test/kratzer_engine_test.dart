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

  test('fixed player counts use that many active players per board', () {
    const engine = KratzerEngine();
    final players = [for (var index = 1; index <= 15; index++) player(index)];

    final evenlyDistributed = engine.assignRound(
      players: players,
      availableBoards: [1, 2, 3, 4],
      round: 1,
    );
    expect(evenlyDistributed.map((assignment) => assignment.players.length), [
      4,
      4,
      4,
      3,
    ]);

    final assignments = engine.assignRound(
      players: players,
      availableBoards: [1, 2, 3, 4],
      round: 1,
      playersPerBoard: 4,
    );

    expect(assignments.map((assignment) => assignment.players.length), [
      4,
      4,
      4,
    ]);
    expect(
      assignments.expand((assignment) => assignment.scratchEligiblePlayers),
      hasLength(12),
    );
    final coveredPlayers = <TournamentPlayer>{};
    for (var round = 1; round <= 5; round++) {
      coveredPlayers.addAll(
        engine
            .assignRound(
              players: players,
              availableBoards: [1, 2, 3, 4],
              round: round,
              playersPerBoard: 4,
            )
            .expand((assignment) => assignment.scratchEligiblePlayers),
      );
    }
    expect(coveredPlayers, players.toSet());
  });

  test('equal scratch counts are kept together when possible', () {
    const engine = KratzerEngine();
    final players = [for (var index = 1; index <= 6; index++) player(index)];
    final history = [
      for (final scratched in players.skip(3))
        GroupMatch(
          isKratzer: true,
          players: players,
          scratchEligiblePlayers: players,
          scratchedPlayer: scratched,
          round: 1,
        ),
    ];

    final assignments = engine.assignRound(
      players: players,
      availableBoards: [1, 2],
      round: 4,
      preferSameScratchCount: true,
      completedMatches: history,
    );

    expect(
      assignments[0].scratchEligiblePlayers.toSet(),
      players.take(3).toSet(),
    );
    expect(
      assignments[1].scratchEligiblePlayers.toSet(),
      players.skip(3).toSet(),
    );
  });

  test(
    'equal-life preference avoids repeated opponents and balances games',
    () {
      const engine = KratzerEngine();
      final players = [for (var index = 1; index <= 5; index++) player(index)];
      final history = <GroupMatch>[
        GroupMatch(
          isKratzer: true,
          players: players.take(3).toList(),
          scratchEligiblePlayers: players.take(3).toList(),
          scratchedPlayer: players.first,
          round: 1,
        ),
      ];

      final nextRound = engine.assignRound(
        players: players,
        availableBoards: [1, 2],
        round: 2,
        playersPerBoard: 3,
        preferSameScratchCount: true,
        completedMatches: history,
      );
      final nextPlayers = nextRound.single.scratchEligiblePlayers;
      expect(nextPlayers, containsAll(players.skip(3)));
      expect(
        nextPlayers.where((candidate) => players.take(3).contains(candidate)),
        hasLength(1),
      );
      expect(
        nextPlayers.where((candidate) => players.take(3).contains(candidate)),
        isNot(contains(players.first)),
      );

      history.add(
        GroupMatch(
          isKratzer: true,
          players: nextPlayers,
          scratchEligiblePlayers: nextPlayers,
          round: 2,
        ),
      );
      final gamesPlayed = {for (final candidate in players) candidate: 0};
      for (final match in history) {
        for (final candidate in match.scratchEligiblePlayers) {
          gamesPlayed.update(candidate, (count) => count + 1);
        }
      }
      expect(
        gamesPlayed.values.reduce((a, b) => a > b ? a : b) -
            gamesPlayed.values.reduce((a, b) => a < b ? a : b),
        lessThanOrEqualTo(1),
      );
    },
  );

  test('groups repeat until a player is eliminated', () {
    const engine = KratzerEngine();
    final players = [for (var index = 1; index <= 6; index++) player(index)];
    final firstGroup = GroupMatch(
      isKratzer: true,
      players: players.take(3).toList(),
      scratchEligiblePlayers: players.take(3).toList(),
      round: 1,
      boardNumber: 1,
    );
    final secondGroup = GroupMatch(
      isKratzer: true,
      players: players.skip(3).toList(),
      scratchEligiblePlayers: players.skip(3).toList(),
      round: 1,
      boardNumber: 2,
    );

    final repeated = engine.assignNextRound(
      activePlayers: players,
      eliminatedPlayers: const [],
      availableBoards: [1, 2],
      round: 2,
      previousRound: [firstGroup, secondGroup],
      completedMatches: const [],
      playUntilElimination: true,
    );
    expect(repeated.map((assignment) => assignment.players), [
      firstGroup.players,
      secondGroup.players,
    ]);

    final currentResult = GroupMatch(
      isKratzer: true,
      players: firstGroup.players,
      scratchEligiblePlayers: firstGroup.scratchEligiblePlayers,
      scratchedPlayer: players.first,
      round: 1,
      boardNumber: 1,
    );
    final eliminationHistory = [
      for (var round = 1; round <= 2; round++)
        GroupMatch(
          isKratzer: true,
          players: firstGroup.players,
          scratchEligiblePlayers: firstGroup.scratchEligiblePlayers,
          scratchedPlayer: players.first,
          round: round,
          boardNumber: 1,
        ),
      currentResult,
      secondGroup,
    ];
    final active = engine.activePlayers(
      players: players,
      completedMatches: eliminationHistory,
      lives: 3,
    );
    final reshuffled = engine.assignNextRound(
      activePlayers: active,
      eliminatedPlayers: [players.first],
      availableBoards: [1, 2],
      round: 2,
      previousRound: [currentResult, secondGroup],
      completedMatches: eliminationHistory,
      playUntilElimination: true,
    );
    expect(
      reshuffled.expand((assignment) => assignment.scratchEligiblePlayers),
      isNot(contains(players.first)),
    );
  });

  test('starting scratches count toward lives and survive player JSON', () {
    const engine = KratzerEngine();
    final eliminated = player(1).copyWith(kratzerStartingScratches: 3);
    final scratched = player(2).copyWith(kratzerStartingScratches: 1);
    final active = player(3);
    final history = [
      GroupMatch(
        isKratzer: true,
        players: [eliminated, scratched, active],
        scratchEligiblePlayers: [eliminated, scratched, active],
        scratchedPlayer: scratched,
        round: 1,
      ),
    ];

    expect(
      engine.activePlayers(
        players: [eliminated, scratched, active],
        completedMatches: history,
        lives: 3,
      ),
      [scratched, active],
    );
    expect(TournamentPlayer.fromJson(scratched.toJson()), scratched);

    final firstRound = engine.assignRound(
      players: [scratched, active],
      eliminatedFillers: [eliminated],
      availableBoards: [1],
      round: 1,
    );
    expect(firstRound.single.players, contains(eliminated));
    expect(firstRound.single.scratchEligiblePlayers.toSet(), {
      scratched,
      active,
    });

    final stage = KnockoutTournamentRunStage(
      name: 'Kratzer',
      rounds: [history],
      isKratzer: true,
      eliminationLossLimit: 3,
      participants: [eliminated, scratched, active],
    );
    expect(stage.scratchesFor(scratched), 2);
    expect(stage.scratchesFor(eliminated), 3);
  });

  test(
    'Kratzer bonus lives are stored and can exceed the starting life limit',
    () {
      final players = [player(1), player(2), player(3)];
      final bonusMatch = GroupMatch(
        isKratzer: true,
        players: players,
        scratchEligiblePlayers: players,
        scratchedPlayer: players[0],
        kratzerBonusLives: [
          KratzerBonusLife(
            player: players[1],
            type: KratzerBonusLifeType.score180,
          ),
        ],
        round: 1,
      );
      final stage = KnockoutTournamentRunStage(
        name: 'Kratzer',
        rounds: [
          [bonusMatch],
        ],
        eliminationLossLimit: 1,
        isKratzer: true,
        kratzerBonusLifeFor180: true,
        participants: players,
      );
      final restoredTournament = CreatedTournament.fromJson(
        CreatedTournament(
          name: 'Kratzer',
          players: players,
          stages: const [],
          runStages: [stage],
        ).toJson(),
      );
      final restored =
          restoredTournament.runStages.single as KnockoutTournamentRunStage;
      final restoredMatch = restored.matches.single;

      expect(restored.kratzerBonusLifeFor180, isTrue);
      expect(restored.livesRemainingFor(players[1]), 2);
      expect(restoredMatch.kratzerBonusLives.single.player, players[1]);
      expect(
        restoredMatch.kratzerBonusLives.single.type,
        KratzerBonusLifeType.score180,
      );
      expect(
        const KratzerEngine().activePlayers(
          players: players,
          completedMatches: restored.matches,
          lives: restored.eliminationLossLimit,
        ),
        players.skip(1).toList(),
      );
    },
  );

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

  test('unused boards do not increase the Kratzer duration estimate', () {
    const engine = KratzerEngine();
    final oneBoard = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 1,
      baseMatchMinutes: 4,
    );
    final twoBoards = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 2,
      baseMatchMinutes: 4,
    );
    expect(oneBoard.games, 3);
    expect(oneBoard.minutes, 20);
    expect(twoBoards.games, oneBoard.games);
    expect(twoBoards.minutes, oneBoard.minutes);
    final estimateByBoardCount = [
      for (final boards in [3, 4, 5])
        engine
            .estimateDuration(
              playerCount: 8,
              lives: 3,
              boards: boards,
              baseMatchMinutes: 8,
            )
            .minutes,
    ];
    expect(estimateByBoardCount[1], lessThanOrEqualTo(estimateByBoardCount[0]));
    expect(estimateByBoardCount[2], lessThanOrEqualTo(estimateByBoardCount[1]));
    expect(
      engine.estimatedGameCount(playerCount: 4, lives: 1, boards: 1),
      oneBoard.games,
    );
  });

  test('Kratzer adds board change time only between active rounds', () {
    const engine = KratzerEngine();
    final withoutIdle = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 1,
      baseMatchMinutes: 4,
    );
    final withIdle = engine.estimateDuration(
      playerCount: 4,
      lives: 1,
      boards: 1,
      baseMatchMinutes: 4,
      boardIdleMinutes: 3,
    );

    expect(withIdle.rounds, greaterThan(1));
    expect(withIdle.minutes, withoutIdle.minutes + (withIdle.rounds - 1) * 3);
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

  test('duration estimate reflects configured players per board', () {
    const engine = KratzerEngine();
    final evenlyDistributed = engine.estimateDuration(
      playerCount: 12,
      lives: 2,
      boards: 4,
      baseMatchMinutes: 4,
    );
    final sixPerBoard = engine.estimateDuration(
      playerCount: 12,
      lives: 2,
      boards: 4,
      playersPerBoard: 6,
      baseMatchMinutes: 4,
    );

    expect(sixPerBoard.minutes, isNot(evenlyDistributed.minutes));
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
          TournamentStage(
            name: 'Kratzer',
            type: 'kratzer',
            knockoutLives: 4,
            kratzerPlayersPerBoard: 4,
            kratzerPreferSameScratchCount: true,
            kratzerPlayUntilElimination: true,
            kratzerBonusLifeFor180: true,
            kratzerBonusLifeForHighFinish: true,
          ),
        ],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Kratzer',
            rounds: [
              [match],
            ],
            eliminationLossLimit: 4,
            isKratzer: true,
            kratzerPlayersPerBoard: 4,
            kratzerPreferSameScratchCount: true,
            kratzerPlayUntilElimination: true,
            kratzerBonusLifeFor180: true,
            kratzerBonusLifeForHighFinish: true,
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
      expect(restored.stages.single.kratzerPlayersPerBoard, 4);
      expect(restored.stages.single.kratzerPreferSameScratchCount, isTrue);
      expect(restored.stages.single.kratzerPlayUntilElimination, isTrue);
      expect(restored.stages.single.kratzerBonusLifeFor180, isTrue);
      expect(restored.stages.single.kratzerBonusLifeForHighFinish, isTrue);
      expect(restoredStage.kratzerPlayersPerBoard, 4);
      expect(restoredStage.kratzerPreferSameScratchCount, isTrue);
      expect(restoredStage.kratzerPlayUntilElimination, isTrue);
      expect(restoredStage.kratzerBonusLifeFor180, isTrue);
      expect(restoredStage.kratzerBonusLifeForHighFinish, isTrue);
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
