import 'package:dart_tournament_manager/features/tournaments/application/player_withdrawal_service.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/player_withdrawal.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const anna = TournamentPlayer(
    profileId: 'anna',
    name: 'Anna',
    isGenerated: false,
  );
  const ben = TournamentPlayer(
    profileId: 'ben',
    name: 'Ben',
    isGenerated: false,
  );

  CreatedTournament tournamentWith(GroupMatch match) => CreatedTournament(
    name: 'Testturnier',
    players: const [anna, ben],
    stages: const [TournamentStage(name: 'KO', type: 'single_knockout')],
    runStages: [
      KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [match],
        ],
      ),
    ],
  );

  test('withdrawal phase is versioned and legacy data remains readable', () {
    final withdrawal = PlayerWithdrawal(
      playerKey: 'anna',
      mode: WithdrawalResultMode.loseAll,
      createdAt: DateTime.utc(2025, 1, 1),
      stageIndex: 2,
    );

    expect(PlayerWithdrawal.fromJson(withdrawal.toJson()).stageIndex, 2);
    expect(
      PlayerWithdrawal.fromJson(
        {...withdrawal.toJson(), 'version': 1}..remove('stageIndex'),
      ).stageIndex,
      isNull,
    );
    expect(const PlayerWithdrawalService().canRestore(withdrawal, 2), isTrue);
    expect(const PlayerWithdrawalService().canRestore(withdrawal, 1), isFalse);
  });

  test(
    'annulling a withdrawal restores the prior match state from storage',
    () {
      final startedAt = DateTime.utc(2025, 2, 1, 18);
      final finishedAt = startedAt.add(const Duration(minutes: 12));
      final match = GroupMatch(
        homePlayer: anna,
        awayPlayer: ben,
        round: 1,
        homeLegs: 2,
        awayLegs: 1,
        boardNumber: 3,
        startedAt: startedAt,
        finishedAt: finishedAt,
        startedPlayers: 'anna|ben',
        achievementNotifications: const [
          TournamentAchievementNotice(
            playerProfileId: 'anna',
            playerName: 'Anna',
            achievementName: 'High Finish',
            explanation: 'Beispiel',
            rankingName: 'Liga',
          ),
        ],
      );
      final tournament = tournamentWith(match);
      final withdrawal = PlayerWithdrawal(
        playerKey: 'anna',
        mode: WithdrawalResultMode.loseAll,
        createdAt: DateTime.utc(2025, 2, 2),
        stageIndex: 0,
      );
      tournament.withdrawals.add(withdrawal);

      const service = PlayerWithdrawalService();
      expect(service.reconcile(tournament), isTrue);
      expect(match.homeLegs, 0);
      expect(match.awayLegs, 2);

      final persisted = CreatedTournament.fromJson(tournament.toJson());
      final persistedMatch =
          (persisted.runStages.single as KnockoutTournamentRunStage)
              .matches
              .single;
      expect(persistedMatch.withdrawalSnapshot, isNotNull);

      expect(
        service.remove(
          persisted,
          persisted.withdrawals.single,
          annulResults: true,
        ),
        isTrue,
      );
      expect(persistedMatch.homeLegs, 2);
      expect(persistedMatch.awayLegs, 1);
      expect(persistedMatch.startedAt, startedAt);
      expect(persistedMatch.finishedAt, finishedAt);
      expect(persistedMatch.boardNumber, 3);
      expect(persistedMatch.achievementNotifications, hasLength(1));
      expect(persistedMatch.withdrawalSignature, isNull);
      expect(persistedMatch.withdrawalSnapshot, isNull);
    },
  );

  test(
    'keeping withdrawal results removes the policy but preserves the score',
    () {
      final match = GroupMatch(homePlayer: anna, awayPlayer: ben, round: 1);
      final tournament = tournamentWith(match);
      final withdrawal = PlayerWithdrawal(
        playerKey: 'anna',
        mode: WithdrawalResultMode.loseOpen,
        createdAt: DateTime.utc(2025, 3, 1),
        stageIndex: 0,
      );
      tournament.withdrawals.add(withdrawal);

      const service = PlayerWithdrawalService();
      service.reconcile(tournament);
      final dropScore = (match.homeLegs, match.awayLegs);

      expect(
        service.remove(tournament, withdrawal, annulResults: false),
        isTrue,
      );
      expect(tournament.withdrawals, isEmpty);
      expect((match.homeLegs, match.awayLegs), dropScore);
      expect(match.withdrawalSignature, isNull);
      expect(match.withdrawalSnapshot, isNull);
    },
  );
}
