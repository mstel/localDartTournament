import 'package:dart_tournament_manager/features/statistics/application/scolia_tournament_legs_service.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends TournamentStorage {
  _FakeStorage(this.tournaments);

  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;
}

void main() {
  const player = TournamentPlayer(
    profileId: 'player-1',
    name: 'Ada',
    isGenerated: false,
  );
  const opponent = TournamentPlayer(
    profileId: 'player-2',
    name: 'Bert',
    isGenerated: false,
  );

  CreatedTournament tournament({
    required String id,
    required DateTime date,
    required List<GroupMatch> matches,
    bool countsForRanking = true,
  }) {
    return CreatedTournament(
      id: id,
      name: id,
      players: const [player, opponent],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppe',
          groupPlayType: 'round_robin',
          qualificationPlan: null,
          tieBreakers: defaultGroupTieBreakers,
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: const [player, opponent],
              matches: matches,
            ),
          ],
        ),
      ],
      tournamentDate: date,
      countsForRanking: countsForRanking,
      rankingIds: const ['ranking-1'],
    );
  }

  GroupMatch match(int homeLegs, int awayLegs, DateTime date) => GroupMatch(
    homePlayer: player,
    awayPlayer: opponent,
    round: 1,
    homeLegs: homeLegs,
    awayLegs: awayLegs,
    finishedAt: date,
  );

  test('uses only ranked tournaments of the selected month', () async {
    final service = ScoliaTournamentLegsService(
      storage: _FakeStorage([
        tournament(
          id: 'october-a',
          date: DateTime(2026, 10, 5),
          matches: [match(3, 1, DateTime(2026, 10, 5))],
        ),
        tournament(
          id: 'october-b',
          date: DateTime(2026, 10, 18),
          matches: [match(2, 2, DateTime(2026, 10, 18))],
        ),
        tournament(
          id: 'friendly',
          date: DateTime(2026, 10, 20),
          matches: [match(9, 0, DateTime(2026, 10, 20))],
          countsForRanking: false,
        ),
        tournament(
          id: 'september',
          date: DateTime(2026, 9, 20),
          matches: [match(5, 5, DateTime(2026, 9, 20))],
        ),
      ]),
    );

    final legs = await service.weightedLegsForMonth(
      playerId: 'player-1',
      year: 2026,
      month: 10,
    );

    expect(legs, 8);
  });

  test(
    'returns zero when the player has no ranked matches in the month',
    () async {
      final service = ScoliaTournamentLegsService(
        storage: _FakeStorage([
          tournament(
            id: 'october',
            date: DateTime(2026, 10, 5),
            matches: [match(3, 1, DateTime(2026, 10, 5))],
          ),
        ]),
      );

      final legs = await service.weightedLegsForMonth(
        playerId: 'other-player',
        year: 2026,
        month: 10,
      );

      expect(legs, 0);
    },
  );
}
