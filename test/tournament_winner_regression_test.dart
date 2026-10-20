import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/local_statistics.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/player_withdrawal.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/imported_tournament_archive.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_winner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const anna = TournamentPlayer(
    profileId: 'profile-anna',
    name: 'Anna',
    isGenerated: false,
  );
  const ben = TournamentPlayer(
    profileId: 'profile-ben',
    name: 'Ben',
    isGenerated: false,
  );

  test('identifies the final winner by profile ID', () {
    final tournament = CreatedTournament(
      name: 'Finale',
      players: const [anna, ben],
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'K.-o.',
          rounds: [
            [
              GroupMatch(
                homePlayer: anna,
                awayPlayer: ben,
                round: 1,
                homeLegs: 3,
                awayLegs: 1,
              ),
            ],
          ],
        ),
      ],
    );

    expect(TournamentWinner.profileId(tournament), 'profile-anna');
  });

  test('only a completed, untied final group has a winner', () {
    CreatedTournament groupTournament(int homeLegs, int awayLegs) =>
        CreatedTournament(
          name: 'Finalgruppe',
          players: const [anna, ben],
          stages: const [],
          runStages: [
            GroupTournamentRunStage(
              name: 'Finalgruppe',
              groupPlayType: 'round_robin',
              groups: [
                TournamentGroup(
                  name: 'Finalgruppe',
                  playType: 'round_robin',
                  players: const [anna, ben],
                  matches: [
                    GroupMatch(
                      homePlayer: anna,
                      awayPlayer: ben,
                      round: 1,
                      homeLegs: homeLegs,
                      awayLegs: awayLegs,
                    ),
                  ],
                ),
              ],
              qualificationPlan: null,
              tieBreakers: const ['points', 'legDifference', 'legsFor'],
            ),
          ],
          completedStageIndexes: {0},
        );

    expect(TournamentWinner.profileId(groupTournament(2, 0)), 'profile-anna');
    expect(TournamentWinner.profileId(groupTournament(1, 1)), isNull);
    final unfinished = groupTournament(2, 0)..completedStageIndexes.clear();
    expect(TournamentWinner.profileId(unfinished), isNull);
  });

  test('group winner honours head-to-head results counted for standings', () {
    final tournament = CreatedTournament(
      name: 'Round robin',
      players: const [anna, ben],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Finalgruppe',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Finalgruppe',
              playType: 'round_robin',
              players: const [anna, ben],
              matches: [
                GroupMatch(
                  homePlayer: ben,
                  awayPlayer: anna,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 0,
                ),
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: ben,
                  round: 2,
                  homeLegs: 1,
                  awayLegs: 0,
                ),
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: ben,
                  round: 3,
                  homeLegs: 3,
                  awayLegs: 0,
                  withdrawalIgnored: true,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const ['points', 'headToHead'],
        ),
      ],
      completedStageIndexes: {0},
    );

    expect(TournamentWinner.profileId(tournament), 'profile-ben');
  });

  test('group winner uses a completed decider for equal standings', () {
    final tournament = CreatedTournament(
      name: 'Decider',
      players: const [anna, ben],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Finalgruppe',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Finalgruppe',
              playType: 'round_robin',
              players: const [anna, ben],
              matches: [
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: ben,
                  round: 1,
                  homeLegs: 1,
                  awayLegs: 1,
                ),
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: ben,
                  round: 2,
                  homeLegs: 1,
                  awayLegs: 0,
                  isDecider: true,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const ['points', 'headToHead'],
        ),
      ],
      completedStageIndexes: {0},
    );

    expect(TournamentWinner.profileId(tournament), 'profile-anna');
  });

  test('Swiss group winner is selected after withdrawals are ordered', () {
    const cy = TournamentPlayer(
      profileId: 'profile-cy',
      name: 'Cy',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'Swiss',
      players: const [anna, ben, cy],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Swiss',
          groupPlayType: 'swiss',
          groups: [
            TournamentGroup(
              name: 'Swiss',
              playType: 'swiss',
              players: const [anna, ben, cy],
              matches: [
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: ben,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 0,
                ),
                GroupMatch(
                  homePlayer: anna,
                  awayPlayer: cy,
                  round: 2,
                  homeLegs: 3,
                  awayLegs: 0,
                ),
                GroupMatch(
                  homePlayer: ben,
                  awayPlayer: cy,
                  round: 3,
                  homeLegs: 1,
                  awayLegs: 0,
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const ['points'],
        ),
      ],
      completedStageIndexes: {0},
      withdrawals: [
        PlayerWithdrawal(
          playerKey: 'profile-anna',
          mode: WithdrawalResultMode.loseAll,
          createdAt: DateTime.utc(2025),
        ),
      ],
    );

    expect(TournamentWinner.profileId(tournament), 'profile-ben');
  });

  test('mini knockout group winner comes from its final match', () {
    final tournament = CreatedTournament(
      name: 'Mini-KO final',
      players: const [anna, ben],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Finale',
          groupPlayType: 'mini_knockout',
          groups: [
            TournamentGroup(
              name: 'Finale',
              playType: 'mini_knockout',
              players: const [anna, ben],
              matches: const [],
              knockoutRounds: [
                [
                  GroupMatch(
                    homePlayer: anna,
                    awayPlayer: ben,
                    round: 1,
                    homeLegs: 2,
                    awayLegs: 1,
                  ),
                ],
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
      completedStageIndexes: {0},
    );

    expect(TournamentWinner.profileId(tournament), 'profile-anna');
  });

  test('uses imported final placement rather than the last match winner', () {
    final tournament = CreatedTournament(
      name: 'Import',
      players: const [anna, ben],
      stages: const [],
      runStages: const [],
      importedArchive: ImportedTournamentArchive(
        sourceId: 'source',
        url: 'https://example.test/tournament',
        mode: 'single elimination',
        participants: const [
          {
            'id': '1',
            'name': 'Anna',
            'profileId': 'profile-anna',
            'finalRank': 1,
          },
          {
            'id': '2',
            'name': 'Ben',
            'profileId': 'profile-ben',
            'finalRank': 2,
          },
        ],
        matches: const [
          {'winner_id': '2'},
        ],
      ),
    );

    expect(TournamentWinner.profileId(tournament), 'profile-anna');
  });

  test('profile statistics count and calculate tournament wins', () async {
    final directory = await Directory.systemTemp.createTemp(
      'tournament_winner_stats_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(
      baseDirectory: Directory('${directory.path}/database'),
    );
    final annaProfile = await database.createPlayerProfile(displayName: 'Anna');
    final annaPlayer = TournamentPlayer(
      profileId: annaProfile.id,
      name: annaProfile.displayName,
      isGenerated: false,
    );
    final benPlayer = TournamentPlayer(
      profileId: 'profile-ben',
      name: 'Ben',
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      id: 'anna-wins',
      name: 'Anna wins',
      players: [annaPlayer, benPlayer],
      stages: const [],
      runStages: [
        KnockoutTournamentRunStage(
          name: 'Finale',
          rounds: [
            [
              GroupMatch(
                homePlayer: annaPlayer,
                awayPlayer: benPlayer,
                round: 1,
                homeLegs: 3,
                awayLegs: 1,
              ),
            ],
          ],
        ),
      ],
    );
    final storage = TournamentStorage(
      file: File('${directory.path}${Platform.pathSeparator}tournaments.json'),
    );
    await storage.saveTournament(tournament);

    final statistics = await LocalStatisticsService(
      database: database,
      storage: storage,
    ).forPlayers({annaProfile.id});

    expect(statistics.tournamentWins, 1);
    expect(statistics.tournamentWinRate, 100);
  });
}
