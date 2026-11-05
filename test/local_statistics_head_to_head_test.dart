import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/statistics/domain/monthly_player_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/imported_tournament_archive.dart';
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

  @override
  Future<List<MonthlyPlayerPerformance>> loadMonthlyPlayerPerformances(
    Set<String> playerProfileIds, {
    int? year,
  }) async => const [];
}

class _FakeTournamentStorage extends TournamentStorage {
  _FakeTournamentStorage(this.tournaments);

  final List<CreatedTournament> tournaments;

  @override
  Future<List<CreatedTournament>> loadTournaments() async => tournaments;
}

void main() {
  test('converted Challonge best performances are not counted twice', () async {
    final player = TournamentPlayer(
      profileId: 'left',
      name: 'Anna Lang',
      isGenerated: false,
    );
    final opponent = TournamentPlayer(
      profileId: 'right',
      name: 'Ben Kurz',
      isGenerated: false,
    );
    const performance = BestPerformance(
      type: BestPerformanceType.score180,
      playerName: 'Anna Lang',
      playerProfileId: 'left',
      value: 180,
    );
    final tournament = CreatedTournament(
      id: 'converted',
      name: 'Challonge converted',
      players: [player, opponent],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppe',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'A',
              playType: 'round_robin',
              players: [player, opponent],
              matches: [
                GroupMatch(
                  homePlayer: player,
                  awayPlayer: opponent,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                  bestPerformances: const [performance],
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
      importedArchive: ImportedTournamentArchive(
        sourceId: '1',
        url: 'https://challonge.com/example',
        mode: 'round robin',
        participants: const [
          {'id': '1', 'name': 'Anna Lang', 'profileId': 'left'},
          {'id': '2', 'name': 'Ben Kurz', 'profileId': 'right'},
        ],
        matches: [
          {
            'player1_id': '1',
            'player2_id': '2',
            'bestPerformances': [performance.toJson()],
          },
        ],
        nativeValidation: const {'status': 'valid'},
      ),
    );

    final statistics = await LocalStatisticsService(
      database: _FakeDatabase(),
      storage: _FakeTournamentStorage([tournament]),
    ).forPlayers({'left'});

    expect(statistics.bestPerformances, hasLength(1));
    expect(
      statistics.bestPerformances.single.type,
      BestPerformanceType.score180,
    );
  });

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
