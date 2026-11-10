import 'package:dart_tournament_manager/features/tournaments/application/knockout_advancement_policy.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = KnockoutAdvancementPolicy();

  List<TournamentPlayer> players(int count) => [
    for (var index = 0; index < count; index++)
      TournamentPlayer(
        profileId: 'player-$index',
        name: 'Spieler $index',
        isGenerated: false,
      ),
  ];

  List<GroupMatch> round(List<TournamentPlayer> participants) => [
    for (var index = 0; index < participants.length; index += 2)
      GroupMatch(
        homePlayer: participants[index],
        awayPlayer: participants[index + 1],
        round: 1,
        homeLegs: 3,
        awayLegs: 0,
      ),
  ];

  test('stops a single-elimination stage at the configured active count', () {
    final field = players(8);
    final openingRound = round(field);

    expect(
      policy.hasReachedAdvancingCount(
        rounds: [openingRound],
        lossLimit: 1,
        advancingCount: 4,
      ),
      isTrue,
    );
    expect(
      policy.hasReachedAdvancingCount(
        rounds: [openingRound],
        lossLimit: 1,
        advancingCount: 3,
      ),
      isFalse,
    );
  });

  test(
    'double elimination waits until players have reached the loss limit',
    () {
      final field = players(8);
      final openingRound = round(field);
      final survivors = [for (final match in openingRound) match.homePlayer!];
      final secondLosses = [
        for (var index = 0; index < openingRound.length; index++)
          GroupMatch(
            homePlayer: openingRound[index].awayPlayer,
            awayPlayer: survivors[index],
            round: 2,
            homeLegs: 0,
            awayLegs: 3,
          ),
      ];

      expect(
        policy.hasReachedAdvancingCount(
          rounds: [openingRound, secondLosses],
          lossLimit: 2,
          advancingCount: 4,
        ),
        isTrue,
      );
      expect(policy.limitAdvancingPlayers(field, 4), field.take(4).toList());
    },
  );

  test('advancing count survives tournament-stage serialization', () {
    final stage = TournamentStage(
      name: 'Doppel-KO',
      type: 'double_knockout',
      knockoutParticipantCount: 8,
      knockoutAdvancingCount: 4,
    );

    expect(TournamentStage.fromJson(stage.toJson()).knockoutAdvancingCount, 4);
  });
}
