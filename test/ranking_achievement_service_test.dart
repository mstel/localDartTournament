import 'dart:io';

import 'package:dart_tournament_manager/features/achievements/application/ranking_achievement_service.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_elo_calculator.dart';
import 'package:dart_tournament_manager/features/statistics/domain/best_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/imported_tournament_archive.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refresh calculates ranking results and persists repeatably', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ranking_achievement_service_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);
    final winnerProfile = await database.createPlayerProfile(
      displayName: 'Winner',
    );
    final opponentProfile = await database.createPlayerProfile(
      displayName: 'Opponent',
    );
    final ranking = const LocalRanking(
      id: 'ranking-achievements',
      name: 'DC Unzenberg 2026',
      achievementsEnabled: true,
    );
    await database.saveLocalRanking(ranking);
    await database.setRankingPlayers(ranking.id, [
      winnerProfile.id,
      opponentProfile.id,
    ]);

    final winner = TournamentPlayer(
      profileId: winnerProfile.id,
      name: winnerProfile.displayName,
      isGenerated: false,
    );
    final opponent = TournamentPlayer(
      profileId: opponentProfile.id,
      name: opponentProfile.displayName,
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'Test event',
      tournamentDate: DateTime(2026, 4, 10),
      players: [winner, opponent],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [winner, opponent],
              knockoutRounds: [
                [
                  GroupMatch(
                    homePlayer: winner,
                    awayPlayer: opponent,
                    round: 2,
                    homeLegs: 3,
                    awayLegs: 2,
                    finishedAt: DateTime(2026, 4, 10, 21),
                    bestPerformances: [
                      BestPerformance(
                        type: BestPerformanceType.score180,
                        playerName: winner.name,
                        playerProfileId: winner.profileId,
                        value: 180,
                      ),
                    ],
                  ),
                ],
              ],
              matches: [
                GroupMatch(
                  homePlayer: winner,
                  awayPlayer: opponent,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 1,
                  finishedAt: DateTime(2026, 4, 10, 20),
                  bestPerformances: [
                    BestPerformance(
                      type: BestPerformanceType.bigFish170,
                      playerName: winner.name,
                      playerProfileId: winner.profileId,
                      value: 170,
                    ),
                  ],
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const ['points', 'legDifference', 'legsFor'],
        ),
      ],
      rankingIds: [ranking.id],
      finishedAt: DateTime(2026, 4, 10, 21),
      completedStageIndexes: {0},
      showAchievementNotifications: false,
    );

    final service = RankingAchievementService(database: database);
    final first = await service.refreshPlayer(
      ranking: ranking,
      playerProfileId: winnerProfile.id,
      tournaments: [tournament],
    );
    final second = await service.refreshPlayer(
      ranking: ranking,
      playerProfileId: winnerProfile.id,
      tournaments: [tournament],
    );

    expect(
      first.evaluation.progress['tournament_participation_1']!.isCompleted,
      isTrue,
    );
    expect(
      first.evaluation.progress['first_tournament_win']!.isCompleted,
      isTrue,
    );
    expect(first.evaluation.progress['score170_checkout']!.isCompleted, isTrue);
    expect(first.evaluation.progress['first_score180']!.isCompleted, isTrue);
    expect(first.evaluation.progress['ranking_mvp']!.isCompleted, isFalse);
    expect(first.evaluation.progress['ranking_gold']!.isCompleted, isFalse);
    expect(first.evaluation.progress['legs_won_10']!.currentValue, 6);
    expect(
      first.evaluation.progress['training_sessions_10']!.currentValue,
      1,
    );
    expect(second.evaluation.totalExperiencePoints, 165);
    final completedRanking = ranking.copyWith(isCompleted: true);
    final finalized = await service.refreshPlayer(
      ranking: completedRanking,
      playerProfileId: winnerProfile.id,
      tournaments: [tournament],
    );
    expect(finalized.evaluation.progress['ranking_gold']!.isCompleted, isTrue);
    expect(finalized.evaluation.progress['ranking_mvp']!.isCompleted, isTrue);
    expect(finalized.evaluation.totalExperiencePoints, 290);
    final restoredTournament = CreatedTournament.fromJson(tournament.toJson());
    final restoredGroup =
        (restoredTournament.runStages.single as GroupTournamentRunStage)
            .groups
            .single;
    expect(restoredGroup.matches, hasLength(2));
    expect(
      identical(
        restoredGroup.matches.last,
        restoredGroup.knockoutRounds.single.single,
      ),
      isTrue,
    );
    final restoredProgress = await service.refreshPlayer(
      ranking: completedRanking,
      playerProfileId: winnerProfile.id,
      tournaments: [restoredTournament],
    );
    expect(
      restoredProgress.evaluation.progress['legs_won_10']!.currentValue,
      6,
    );
    expect(
      restoredProgress.evaluation.progress['training_sessions_10']!.currentValue,
      1,
    );
    expect(
      restoredProgress.evaluation.progress['score170_checkout']!.currentValue,
      1,
    );
    final stored = await database.loadRankingAchievementProgress(
      ranking.id,
      winnerProfile.id,
    );
    expect(stored['first_tournament_win']!['status'], 'completed');
    expect(stored['first_tournament_win']!['unlocked_at'], isNotNull);
    expect(stored['first_tournament_win']!['is_final'], 0);
    expect(stored['ranking_gold']!['is_final'], 1);

    final corrected = CreatedTournament.fromJson(tournament.toJson());
    final correctedStage =
        corrected.runStages.single as GroupTournamentRunStage;
    final correctedMatch = correctedStage.groups.single.matches.singleWhere(
      (match) => match.bestPerformances.any(
        (performance) => performance.type == BestPerformanceType.bigFish170,
      ),
    );
    correctedMatch
      ..homeLegs = 0
      ..awayLegs = 3;
    final afterCorrection = await service.refreshPlayer(
      ranking: completedRanking,
      playerProfileId: winnerProfile.id,
      tournaments: [corrected],
    );
    expect(
      afterCorrection.evaluation.progress['ranking_gold']!.isCompleted,
      isTrue,
    );
  });

  test('refresh refuses to calculate a disabled ranking', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ranking_achievement_disabled_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(baseDirectory: directory);
    final profile = await database.createPlayerProfile(displayName: 'Spieler');
    final ranking = const LocalRanking(
      id: 'disabled-ranking',
      name: 'Disabled',
    );
    await database.saveLocalRanking(ranking);

    await expectLater(
      RankingAchievementService(database: database).refreshPlayer(
        ranking: ranking,
        playerProfileId: profile.id,
        tournaments: const [],
      ),
      throwsStateError,
    );
  });

  test(
    'placement matches contribute third and fourth place achievements',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ranking_achievement_placement_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final database = LocalAppDatabase(baseDirectory: directory);
      final profiles = [
        await database.createPlayerProfile(displayName: 'Champion'),
        await database.createPlayerProfile(displayName: 'Runner-up'),
        await database.createPlayerProfile(displayName: 'Third'),
        await database.createPlayerProfile(displayName: 'Fourth'),
      ];
      final ranking = const LocalRanking(
        id: 'placement-ranking',
        name: 'Placement ranking',
        achievementsEnabled: true,
      );
      await database.saveLocalRanking(ranking);
      await database.setRankingPlayers(
        ranking.id,
        profiles.map((profile) => profile.id).toList(),
      );
      final players = [
        for (final profile in profiles)
          TournamentPlayer(
            profileId: profile.id,
            name: profile.displayName,
            isGenerated: false,
          ),
      ];
      GroupMatch resolvedMatch({
        required int round,
        required TournamentPlayer winner,
        required TournamentPlayer loser,
        int? placementRank,
      }) => GroupMatch(
        homePlayer: winner,
        awayPlayer: loser,
        round: round,
        homeLegs: 3,
        awayLegs: 1,
        finishedAt: DateTime(2026, 4, 10, 20 + round),
        placementRank: placementRank,
      );

      final stage = KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [
            resolvedMatch(round: 1, winner: players[0], loser: players[2]),
            resolvedMatch(round: 1, winner: players[1], loser: players[3]),
          ],
          [resolvedMatch(round: 2, winner: players[0], loser: players[1])],
        ],
        placementMatches: [
          resolvedMatch(
            round: 101,
            winner: players[2],
            loser: players[3],
            placementRank: 3,
          ),
        ],
      );
      final tournament = CreatedTournament(
        name: 'Placement event',
        tournamentDate: DateTime(2026, 4, 10),
        players: players,
        stages: const [],
        runStages: [stage],
        rankingIds: [ranking.id],
        finishedAt: DateTime(2026, 4, 10, 22),
        completedStageIndexes: {0},
      );
      final service = RankingAchievementService(database: database);

      final third = await service.refreshPlayer(
        ranking: ranking,
        playerProfileId: profiles[2].id,
        tournaments: [tournament],
      );
      final fourth = await service.refreshPlayer(
        ranking: ranking,
        playerProfileId: profiles[3].id,
        tournaments: [tournament],
      );
      expect(third.evaluation.progress['third_places_3']!.currentValue, 1);
      expect(fourth.evaluation.progress['fourth_places_5']!.currentValue, 1);
    },
  );

  test('imported tournament ranks contribute placement achievements', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ranking_achievement_imported_placement_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);
    final profiles = [
      await database.createPlayerProfile(displayName: 'Champion'),
      await database.createPlayerProfile(displayName: 'Runner-up'),
      await database.createPlayerProfile(displayName: 'Third'),
      await database.createPlayerProfile(displayName: 'Fourth'),
    ];
    final ranking = const LocalRanking(
      id: 'imported-placement-ranking',
      name: 'Imported placement ranking',
      achievementsEnabled: true,
    );
    await database.saveLocalRanking(ranking);
    await database.setRankingPlayers(
      ranking.id,
      profiles.map((profile) => profile.id).toList(),
    );
    final players = [
      for (final profile in profiles)
        TournamentPlayer(
          profileId: profile.id,
          name: profile.displayName,
          isGenerated: false,
        ),
    ];
    final tournament = CreatedTournament(
      name: 'Imported event',
      tournamentDate: DateTime(2026, 4, 10),
      players: players,
      stages: const [],
      runStages: const [],
      importedArchive: ImportedTournamentArchive(
        sourceId: 'source',
        url: 'https://challonge.example/tournament',
        mode: 'single elimination',
        participants: [
          for (var index = 0; index < players.length; index++)
            {
              'name': players[index].name,
              'profileId': players[index].profileId,
              'finalRank': index + 1,
            },
        ],
        matches: const [],
      ),
      rankingIds: [ranking.id],
      finishedAt: DateTime(2026, 4, 10, 22),
    );
    final progress = await RankingAchievementService(database: database)
        .refreshPlayer(
          ranking: ranking,
          playerProfileId: profiles[2].id,
          tournaments: [tournament],
        );

    expect(progress.evaluation.progress['third_places_3']!.currentValue, 1);
  });

  test('Elo upset requires a rating advantage of at least 200', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ranking_achievement_elo_upset_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);
    final underdogProfile = await database.createPlayerProfile(
      displayName: 'Underdog',
    );
    final favoriteProfile = await database.createPlayerProfile(
      displayName: 'Favorite',
    );
    const ranking = LocalRanking(
      id: 'elo-upset-ranking',
      name: 'Elo upset ranking',
      achievementsEnabled: true,
    );
    await database.saveLocalRanking(ranking);
    await database.setRankingPlayers(ranking.id, [
      underdogProfile.id,
      favoriteProfile.id,
    ]);

    final underdog = TournamentPlayer(
      profileId: underdogProfile.id,
      name: underdogProfile.displayName,
      isGenerated: false,
    );
    final favorite = TournamentPlayer(
      profileId: favoriteProfile.id,
      name: favoriteProfile.displayName,
      isGenerated: false,
    );
    final tournament = CreatedTournament(
      name: 'Upset event',
      tournamentDate: DateTime(2026, 4, 10),
      players: [underdog, favorite],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: [underdog, favorite],
              matches: [
                GroupMatch(
                  homePlayer: underdog,
                  awayPlayer: favorite,
                  round: 1,
                  homeLegs: 3,
                  awayLegs: 2,
                  finishedAt: DateTime(2026, 4, 10, 20),
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const ['points', 'legDifference', 'legsFor'],
        ),
      ],
      rankingIds: [ranking.id],
    );

    LocalEloSnapshot snapshotForFavoriteRating(int favoriteRating) =>
        LocalEloSnapshot(const [], {
          underdogProfile.id: [
            LocalEloHistoryItem(
              tournamentId: tournament.id,
              matchIndex: 0,
              playedAt: DateTime(2026, 4, 10, 20),
              tournamentName: tournament.name,
              opponentName: favorite.name,
              score: '3:2',
              delta: 11,
              ratingAfter: 1010,
              kFactor: 25,
              expectedScore: 0.5,
            ),
          ],
          favoriteProfile.id: [
            LocalEloHistoryItem(
              tournamentId: tournament.id,
              matchIndex: 0,
              playedAt: DateTime(2026, 4, 10, 20),
              tournamentName: tournament.name,
              opponentName: underdog.name,
              score: '2:3',
              delta: -10,
              ratingAfter: favoriteRating - 10,
              kFactor: 25,
              expectedScore: 0.5,
            ),
          ],
        });

    final service = RankingAchievementService(database: database);
    final exactThreshold = await service.refreshPlayer(
      ranking: ranking,
      playerProfileId: underdogProfile.id,
      tournaments: [tournament],
      eloSnapshot: snapshotForFavoriteRating(1199),
    );
    expect(
      exactThreshold.evaluation.progress['elo_upset']!.isCompleted,
      isTrue,
    );

    final belowThreshold = await service.refreshPlayer(
      ranking: ranking,
      playerProfileId: underdogProfile.id,
      tournaments: [tournament],
      eloSnapshot: snapshotForFavoriteRating(1198),
    );
    expect(
      belowThreshold.evaluation.progress['elo_upset']!.isCompleted,
      isFalse,
    );
  });
}
