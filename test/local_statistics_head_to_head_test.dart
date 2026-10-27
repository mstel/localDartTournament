import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabase extends LocalAppDatabase {
  @override
  Future<List<PlayerProfile>> loadPlayerProfiles() async => [
    for (final (id, name) in [
      ('left', 'Anna Lang'),
      ('right', 'Ben Kurz'),
      ('teammate', 'Chris Beispiel'),
    ])
      PlayerProfile(
        id: id,
        displayName: name,
        country: '',
        city: '',
        dartsSetupJson: '',
        createdAt: DateTime.utc(2026),
        isActive: true,
      ),
  ];
}

void main() {
  test('direct encounters count only opposing selected players', () async {
    final left = TournamentPlayer(
      profileId: 'left',
      name: 'Anna Lang',
      isGenerated: false,
    );
    final right = TournamentPlayer(
      profileId: 'right',
      name: 'Ben Kurz',
      isGenerated: false,
    );
    final teammate = TournamentPlayer(
      profileId: 'teammate',
      name: 'Chris Beispiel',
      isGenerated: false,
    );
    final earlier = DateTime.utc(2026, 2, 1);
    final later = DateTime.utc(2026, 4, 1);
    final tournament = CreatedTournament(
      id: 'matches',
      name: 'Trainingsabend',
      createdAt: earlier,
      players: [left, right, teammate],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppe',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'A',
              playType: 'round_robin',
              players: [left, right, teammate],
              matches: [
                GroupMatch(
                  homePlayer: left,
                  awayPlayer: right,
                  round: 1,
                  homeLegs: 2,
                  awayLegs: 1,
                  finishedAt: earlier,
                ),
                GroupMatch(
                  homePlayer: right,
                  awayPlayer: left,
                  round: 2,
                  homeLegs: 2,
                  awayLegs: 0,
                  finishedAt: later,
                ),
                GroupMatch(
                  homePlayer: TournamentPlayer.team([left, right]),
                  awayPlayer: teammate,
                  round: 3,
                  homeLegs: 2,
                  awayLegs: 0,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
    );

    final summary = await LocalStatisticsService(
      database: _FakeDatabase(),
    ).directEncounters('left', 'right', [tournament]);

    expect(summary.leftWins, 1);
    expect(summary.rightWins, 1);
    expect(summary.draws, 0);
    expect(summary.encounters, hasLength(2));
    expect(summary.encounters.first.date, later.toLocal());
    expect(summary.encounters.first.leftScore, 0);
    expect(summary.encounters.first.rightScore, 2);
  });
}
