import 'dart:convert';

import '../../rankings/domain/local_ranking.dart';
import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/application/local_ranking_series_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../statistics/domain/best_performance.dart';
import '../../statistics/domain/player_monthly_performance.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/engines/group_standings_engine.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_winner.dart';
import '../domain/achievement_catalog.dart';
import '../domain/achievement_definition.dart';
import '../domain/achievement_engine.dart';

class RankingAchievementSnapshot {
  const RankingAchievementSnapshot({
    required this.evaluation,
    required this.sourceHash,
  });

  final AchievementEvaluation evaluation;
  final String sourceHash;
}

class RankingAchievementService {
  const RankingAchievementService({
    required LocalAppDatabase database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase _database;
  final TournamentStorage? _tournamentStorage;

  String notificationExplanation(AchievementProgress progress) {
    final value = _formatMetric(progress.currentValue);
    final target = _formatMetric(progress.definition.target);
    final detail = switch (progress.definition.metric) {
      AchievementMetric.eloUpsetWins =>
        'Du hast einen Gegner besiegt, der zum Zeitpunkt des Matches '
            'mindestens ${_formatMetric(progress.definition.parameterTarget ?? 200)} ELO-Punkte mehr hatte.',
      AchievementMetric.firstScore180 || AchievementMetric.score180Count =>
        'Du hast ${value == '1' ? 'eine 180 geworfen' : '$value 180er geworfen'}.',
      AchievementMetric.legsWon => 'Du hast insgesamt $value Legs gewonnen.',
      AchievementMetric.distinctOpponentsBeaten =>
        'Du hast gegen mindestens $value verschiedene Teilnehmer gewonnen.',
      AchievementMetric.tournamentParticipations =>
        'Du hast an $value Turnieren dieser Rangliste teilgenommen.',
      AchievementMetric.tournamentWins =>
        'Du hast $value Turniere dieser Rangliste gewonnen.',
      AchievementMetric.score171Count || AchievementMetric.firstScore171 =>
        'Du hast $value Aufnahmen mit mindestens 171 Punkten erzielt.',
      AchievementMetric.bullseyeFinishCount =>
        'Du hast $value Bullseye-Finishes erzielt.',
      AchievementMetric.bigFish170Count =>
        'Du hast $value 170-Aufnahmen erzielt.',
      AchievementMetric.highFinishCount =>
        'Du hast $value High Finishes erzielt.',
      AchievementMetric.shortLegCount =>
        'Du hast insgesamt $value Shortlegs gespielt.',
      AchievementMetric.rankingGold =>
        'Du hast die Rangliste auf Platz eins beendet.',
      AchievementMetric.rankingSilver =>
        'Du hast die Rangliste auf Platz zwei beendet.',
      AchievementMetric.rankingBronze =>
        'Du hast die Rangliste auf Platz drei beendet.',
      AchievementMetric.rankingMvp =>
        'Du hast die meisten Leistungskategorien dieser Rangliste auf Platz eins beendet.',
      _ =>
        'Du hast $value von $target für „${progress.definition.name}“ erreicht.',
    };
    return 'Aufgabe: ${progress.definition.description}\n$detail';
  }

  Future<AchievementEvaluation?> loadPlayerEvaluation({
    required LocalRanking ranking,
    required String playerProfileId,
  }) async {
    if (!ranking.achievementsEnabled) return null;
    if (!(await _eligibleRankingPlayerIds(ranking)).contains(playerProfileId)) {
      return null;
    }
    final stored = await _database.loadRankingAchievementProgress(
      ranking.id,
      playerProfileId,
    );
    final definitions = AchievementCatalog.withTargets(
      ranking.achievementTargets,
      parameters: ranking.achievementParameters,
      alternativeTargets: ranking.achievementAlternativeTargets,
    );
    final progress = <String, AchievementProgress>{
      for (final definition in definitions)
        definition.id: _storedAchievementProgress(
          definition,
          stored[definition.id],
        ),
    };
    var totalExperiencePoints = 0;
    var levelEligibleExperiencePoints = 0;
    for (final item in progress.values) {
      if (!item.isCompleted) continue;
      totalExperiencePoints += item.definition.experiencePoints;
      if (item.definition.contributesToLevel) {
        levelEligibleExperiencePoints += item.definition.experiencePoints;
      }
    }
    final thresholds = AchievementCatalog.levelThresholds;
    var level = 1;
    for (var index = 1; index < thresholds.length; index++) {
      if (levelEligibleExperiencePoints < thresholds[index]) break;
      level = index + 1;
    }
    return AchievementEvaluation(
      progress: progress,
      totalExperiencePoints: totalExperiencePoints,
      levelEligibleExperiencePoints: levelEligibleExperiencePoints,
      level: level,
      levelStartExperiencePoints: thresholds[level - 1],
      nextLevelExperiencePoints: level == thresholds.length
          ? null
          : thresholds[level],
    );
  }

  Future<Map<String, RankingAchievementSnapshot>> refreshRanking(
    LocalRanking ranking, {
    Iterable<CreatedTournament>? tournaments,
  }) async {
    if (!ranking.achievementsEnabled) return const {};
    final playerIds = await _eligibleRankingPlayerIds(ranking);
    final source =
        tournaments?.toList() ??
        await (_tournamentStorage ?? TournamentStorage()).loadTournaments();
    final eloSnapshot = ranking.type == RankingType.elo
        ? await LocalRankingEloService(
            database: _database,
            tournamentStorage: _tournamentStorage,
          ).calculate(ranking, tournaments: source)
        : null;
    final mvpPlayerIds = ranking.isCompleted
        ? await _rankingMvpPlayerIds(ranking, playerIds, source)
        : const <String>{};
    final result = <String, RankingAchievementSnapshot>{};
    for (final playerId in playerIds) {
      result[playerId] = await refreshPlayer(
        ranking: ranking,
        playerProfileId: playerId,
        tournaments: source,
        eloSnapshot: eloSnapshot,
        mvpPlayerIds: mvpPlayerIds,
      );
    }
    return result;
  }

  Future<RankingAchievementSnapshot> refreshPlayer({
    required LocalRanking ranking,
    required String playerProfileId,
    Iterable<CreatedTournament>? tournaments,
    LocalEloSnapshot? eloSnapshot,
    Set<String>? mvpPlayerIds,
  }) async {
    if (!ranking.achievementsEnabled) {
      throw StateError('Achievements sind für diese Rangliste deaktiviert.');
    }
    if (!(await _eligibleRankingPlayerIds(ranking)).contains(playerProfileId)) {
      throw StateError(
        'Teilnehmer muss im Katalog und der Rangliste zugewiesen sein.',
      );
    }

    final allTournaments =
        tournaments ??
        await (_tournamentStorage ?? TournamentStorage()).loadTournaments();
    final relevant =
        allTournaments
            .where(
              (tournament) =>
                  tournament.countsForRanking &&
                  tournament.rankingIds.contains(ranking.id) &&
                  ranking.includesTournamentDate(tournament.effectiveDate),
            )
            .toList()
          ..sort(_compareTournaments);
    final monthlyPerformance = combineMonthlyPlayerPerformances(
      recorded: await _database.loadPlayerMonthlyPerformance(playerProfileId),
      imported: await _database.loadMonthlyPlayerPerformances({
        playerProfileId,
      }),
    );
    final sourceHash = _fingerprint(ranking, relevant, monthlyPerformance);
    final stored = await _database.loadRankingAchievementProgress(
      ranking.id,
      playerProfileId,
    );
    final definitions = AchievementCatalog.withTargets(
      ranking.achievementTargets,
      parameters: ranking.achievementParameters,
      alternativeTargets: ranking.achievementAlternativeTargets,
    );
    final sourceChanged =
        stored.isEmpty ||
        stored.values.any((row) => row['source_hash'] != sourceHash);
    final changedTargetIds = <String>{};
    for (final definition in definitions) {
      final defaultTarget = AchievementCatalog.definitions
          .singleWhere((item) => item.id == definition.id)
          .target;
      final defaultAlternativeTarget = AchievementCatalog.definitions
          .singleWhere((item) => item.id == definition.id)
          .alternativeTarget;
      final defaultParameterTarget = AchievementCatalog.definitions
          .singleWhere((item) => item.id == definition.id)
          .parameterTarget;
      final storedTarget = (stored[definition.id]?['target_value'] as num?)
          ?.toDouble();
      final storedAlternativeTarget =
          (stored[definition.id]?['alternative_target_value'] as num?)
              ?.toDouble();
      if (definition.target != defaultTarget ||
          (storedTarget != null && storedTarget != definition.target) ||
          definition.alternativeTarget != defaultAlternativeTarget ||
          definition.parameterTarget != defaultParameterTarget ||
          (storedAlternativeTarget != null &&
              storedAlternativeTarget != (definition.alternativeTarget ?? 0))) {
        changedTargetIds.add(definition.id);
      }
    }

    final permanentlyUnlocked = <String>{};
    final unlockedAt = <String, DateTime>{};
    for (final entry in stored.entries) {
      final row = entry.value;
      if (row['unlocked_at'] is String) {
        final timestamp = DateTime.tryParse(row['unlocked_at']! as String);
        if (timestamp != null) unlockedAt[entry.key] = timestamp;
      }
      final definition = definitions
          .where((definition) => definition.id == entry.key)
          .firstOrNull;
      final storedTarget = (row['target_value'] as num?)?.toDouble();
      final storedAlternativeTarget = (row['alternative_target_value'] as num?)
          ?.toDouble();
      final targetUnchanged =
          definition != null &&
          storedTarget == definition.target &&
          storedAlternativeTarget == (definition.alternativeTarget ?? 0);
      final categoryTargetChanged =
          definition?.isCategoryCompletion == true &&
          changedTargetIds.any(
            (id) => definitions.any(
              (candidate) =>
                  candidate.id == id &&
                  candidate.category == definition!.completionCategory,
            ),
          );
      if (row['is_final'] == 1 && targetUnchanged && !categoryTargetChanged) {
        permanentlyUnlocked.add(entry.key);
      }
      if (targetUnchanged &&
          row['status'] == AchievementStatus.completed.name &&
          _isPerformanceMilestone(definition)) {
        permanentlyUnlocked.add(entry.key);
      }
    }

    final values = _calculateMetrics(
      ranking,
      playerProfileId,
      relevant,
      monthlyPerformance,
      eloSnapshot: eloSnapshot,
    );
    if (sourceChanged) {
      unlockedAt.addAll(
        await _historicalUnlockDates(
          ranking: ranking,
          profileId: playerProfileId,
          tournaments: relevant,
          monthlyPerformance: monthlyPerformance,
          definitions: definitions,
          eloSnapshot: eloSnapshot,
        ),
      );
    }
    final hasParticipation = relevant.any(
      (tournament) => _containsPlayer(tournament.players, playerProfileId),
    );
    if (ranking.isCompleted && hasParticipation) {
      final position = await _rankingPosition(
        ranking,
        playerProfileId,
        relevant,
      );
      if (position == 1) {
        values[AchievementMetric.rankingGold] = 1;
      } else if (position == 2) {
        values[AchievementMetric.rankingSilver] = 1;
      } else if (position == 3) {
        values[AchievementMetric.rankingBronze] = 1;
      }
      final finalMvpPlayerIds =
          mvpPlayerIds ??
          await _rankingMvpPlayerIds(
            ranking,
            await _eligibleRankingPlayerIds(ranking),
            relevant,
          );
      values[AchievementMetric.rankingMvp] =
          finalMvpPlayerIds.contains(playerProfileId) ? 1 : 0;
    }
    final evaluation = const AchievementEngine().evaluate(
      values: values,
      rankingCompleted: ranking.isCompleted,
      definitions: definitions,
      permanentlyUnlocked: permanentlyUnlocked,
      unlockedAt: unlockedAt,
    );

    final now = DateTime.now().toUtc();
    await _database.saveRankingAchievementProgress(
      rankingId: ranking.id,
      playerProfileId: playerProfileId,
      progress: [
        for (final progress in evaluation.progress.values)
          _storedProgress(
            progress,
            sourceHash: sourceHash,
            previous: stored[progress.definition.id],
            now: now,
          ),
      ],
    );
    return RankingAchievementSnapshot(
      evaluation: evaluation,
      sourceHash: sourceHash,
    );
  }

  Future<List<String>> _eligibleRankingPlayerIds(LocalRanking ranking) async {
    final catalogIds = (await _database.loadPlayerProfiles())
        .map((profile) => profile.id)
        .toSet();
    return [
      for (final playerId in await _database.loadRankingPlayerIds(ranking.id))
        if (catalogIds.contains(playerId)) playerId,
    ];
  }

  Map<AchievementMetric, double> _calculateMetrics(
    LocalRanking ranking,
    String profileId,
    List<CreatedTournament> tournaments,
    List<PlayerMonthlyPerformance> monthlyPerformance, {
    LocalEloSnapshot? eloSnapshot,
    DateTime? through,
  }) {
    final values = <AchievementMetric, double>{};
    final participationTournaments = <CreatedTournament>[];
    final tournamentWinsList = <CreatedTournament>[];
    final matchRecords = <_PlayerMatchRecord>[];
    final beatenOpponents = <String>{};
    final lossesByOpponent = <String, int>{};
    final legsWonByOpponent = <String, int>{};
    var tournamentWins = 0;
    var secondPlaces = 0;
    var thirdPlaces = 0;
    var fourthPlaces = 0;
    var legsWon = 0;
    var legsLost = 0;
    var score180s = 0;
    var score171s = 0;
    var nineDarters = 0;
    var bigFish170s = 0;
    var bullseyeFinishes = 0;
    var highFinishes = 0;
    var shortLegs = 0;
    var shutoutMatchWins = 0;

    void recordPerformance(BestPerformance performance) {
      switch (performance.normalizedType) {
        case BestPerformanceType.score180:
          score180s++;
        case BestPerformanceType.score171Plus:
          score171s++;
        case BestPerformanceType.highFinish:
          highFinishes++;
        case BestPerformanceType.bullseyeFinish:
          bullseyeFinishes++;
          if (performance.value != null && performance.value! > 100) {
            highFinishes++;
          }
        case BestPerformanceType.shortLeg:
          shortLegs++;
          if (performance.value == 9) nineDarters++;
        case BestPerformanceType.bigFish170:
          bigFish170s++;
        case BestPerformanceType.score170:
          break;
      }
    }

    for (final tournament in tournaments) {
      if (tournament.players.any((player) => player.isTeam)) continue;
      final date = tournament.effectiveDate;
      final participationDate =
          tournament.startedAt ??
          tournament.tournamentDate ??
          tournament.createdAt;
      if (_containsPlayer(tournament.players, profileId) &&
          (through == null || !participationDate.isAfter(through))) {
        participationTournaments.add(tournament);
      }

      final tournamentFinishedAt = tournament.finishedAt ?? date;
      final tournamentCompleteByDate =
          tournament.finishedAt != null &&
          (through == null || !tournamentFinishedAt.isAfter(through));
      final winnerId =
          tournament.finishedAt == null || !tournamentCompleteByDate
          ? null
          : TournamentWinner.profileId(tournament);
      if (winnerId == profileId) {
        tournamentWins++;
        tournamentWinsList.add(tournament);
      }
      final placement = tournamentCompleteByDate
          ? _placementFor(tournament, profileId)
          : null;
      if (placement == 2) secondPlaces++;
      if (placement == 3) thirdPlaces++;
      if (placement == 4) fourthPlaces++;

      final matches = _matches(tournament);
      for (final match in matches) {
        if (match.hasTeamParticipant) continue;
        if (!match.countsForStatistics) continue;
        final matchDate = match.finishedAt ?? date;
        if (through != null && matchDate.isAfter(through)) continue;
        final sides = _matchSides(match);
        final homePlayers = sides.$1;
        final awayPlayers = sides.$2;
        final homeHasPlayer = homePlayers.any(
          (player) => _individualProfileIds(player).contains(profileId),
        );
        final awayHasPlayer = awayPlayers.any(
          (player) => _individualProfileIds(player).contains(profileId),
        );
        if (homeHasPlayer && match.homeLegs != null) {
          legsWon += match.homeLegs!;
          legsLost += match.awayLegs ?? 0;
          if (match.awayLegs == 0) shutoutMatchWins++;
          for (final opponent in awayPlayers) {
            for (final opponentId in _individualProfileIds(opponent)) {
              legsWonByOpponent.update(
                opponentId,
                (count) => count + match.homeLegs!,
                ifAbsent: () => match.homeLegs!,
              );
            }
          }
        } else if (awayHasPlayer && match.awayLegs != null) {
          legsWon += match.awayLegs!;
          legsLost += match.homeLegs ?? 0;
          if (match.homeLegs == 0) shutoutMatchWins++;
          for (final opponent in homePlayers) {
            for (final opponentId in _individualProfileIds(opponent)) {
              legsWonByOpponent.update(
                opponentId,
                (count) => count + match.awayLegs!,
                ifAbsent: () => match.awayLegs!,
              );
            }
          }
        }

        final winner = match.winner;
        final loser = match.loser;
        if (winner != null && loser != null) {
          final winnerIds = _individualProfileIds(winner);
          final loserIds = _individualProfileIds(loser);
          if (winnerIds.contains(profileId)) {
            for (final opponentId in loserIds) {
              beatenOpponents.add(opponentId);
            }
            matchRecords.add(_PlayerMatchRecord(date: matchDate, won: true));
          } else if (loserIds.contains(profileId)) {
            for (final opponentId in winnerIds) {
              lossesByOpponent.update(
                opponentId,
                (count) => count + 1,
                ifAbsent: () => 1,
              );
            }
            matchRecords.add(_PlayerMatchRecord(date: matchDate, won: false));
          }
        }

        for (final performance in match.bestPerformances) {
          if (!_performanceBelongsTo(match, performance, profileId)) continue;
          recordPerformance(performance);
        }
      }
      if (!matches.any((match) => match.bestPerformances.isNotEmpty) &&
          (through == null || !date.isAfter(through))) {
        for (final archived in _archivedBestPerformances(tournament)) {
          if (archived.$2 == profileId) recordPerformance(archived.$1);
        }
      }
    }

    values[AchievementMetric.tournamentParticipations] =
        participationTournaments.length.toDouble();
    values[AchievementMetric.tournamentWins] = tournamentWins.toDouble();
    values[AchievementMetric.secondPlaces] = (secondPlaces + tournamentWins)
        .toDouble();
    values[AchievementMetric.thirdPlaces] =
        (thirdPlaces + secondPlaces + tournamentWins).toDouble();
    values[AchievementMetric.fourthPlaces] =
        (fourthPlaces + thirdPlaces + secondPlaces + tournamentWins).toDouble();
    values[AchievementMetric.legsWon] = legsWon.toDouble();
    values[AchievementMetric.legsLost] = legsLost.toDouble();
    values[AchievementMetric.shutoutMatchWins] = shutoutMatchWins.toDouble();
    values[AchievementMetric.legsWonAgainstSameOpponent] = legsWonByOpponent
        .values
        .fold<int>(0, (maximum, count) => count > maximum ? count : maximum)
        .toDouble();
    values[AchievementMetric.score180Count] = score180s.toDouble();
    values[AchievementMetric.firstScore180] = score180s > 0 ? 1 : 0;
    values[AchievementMetric.score171Count] = score171s.toDouble();
    values[AchievementMetric.firstScore171] = score171s > 0 ? 1 : 0;
    values[AchievementMetric.nineDarterCount] = nineDarters.toDouble();
    values[AchievementMetric.bigFish170Count] = bigFish170s.toDouble();
    values[AchievementMetric.bullseyeFinishCount] = bullseyeFinishes.toDouble();
    values[AchievementMetric.highFinishCount] = highFinishes.toDouble();
    values[AchievementMetric.shortLegCount] = shortLegs.toDouble();
    values[AchievementMetric.distinctOpponentsBeaten] = beatenOpponents.length
        .toDouble();
    values[AchievementMetric.lossesToSameOpponent] = lossesByOpponent.values
        .fold<int>(0, (maximum, count) => count > maximum ? count : maximum)
        .toDouble();

    matchRecords.sort((left, right) => left.date.compareTo(right.date));
    var winStreak = 0;
    var maxWinStreak = 0;
    var lossStreak = 0;
    var winsAfterLossStreak = 0;
    for (final record in matchRecords) {
      if (record.won) {
        winStreak++;
        if (winStreak > maxWinStreak) maxWinStreak = winStreak;
        if (lossStreak >= 5) winsAfterLossStreak++;
        lossStreak = 0;
      } else {
        winStreak = 0;
        lossStreak++;
      }
    }
    values[AchievementMetric.matchWinStreak] = maxWinStreak.toDouble();
    values[AchievementMetric.winsAfterLossStreak] = winsAfterLossStreak
        .toDouble();

    values[AchievementMetric.consecutiveTournamentParticipations] =
        _longestConsecutive(participationTournaments, tournaments).toDouble();
    values[AchievementMetric.tournamentWinStreak] = _longestTournamentWinStreak(
      tournamentWinsList,
      tournaments,
    ).toDouble();

    final eligibleMonths = monthlyPerformance.where(
      (entry) =>
          entry.weightedLegs >= 10 &&
          _rankingIncludesMonth(entry.year, entry.month, ranking) &&
          (through == null ||
              !DateTime(
                entry.year,
                entry.month + 1,
                0,
                23,
                59,
                59,
              ).isAfter(through)),
    );
    final months = eligibleMonths.toList();
    values[AchievementMetric.monthlyAverage] = _maximum(
      months.map((entry) => entry.average),
    );
    values[AchievementMetric.monthlyScoring] = _maximum(
      months.map((entry) => entry.scoring),
    );
    values[AchievementMetric.monthlyCheckoutRate] = _maximum(
      months.map((entry) => entry.checkoutRate),
    );
    final activePeriods =
        matchRecords
            .map((record) => DateTime(record.date.year, record.date.month))
            .where(
              (month) =>
                  _rankingIncludesMonth(month.year, month.month, ranking),
            )
            .toSet()
            .toList()
          ..sort();
    values[AchievementMetric.consecutiveActiveMonths] =
        _longestConsecutiveMonths(activePeriods).toDouble();
    values[AchievementMetric.activeMonthsInYear] = _maximumActiveMonthsInYear(
      activePeriods,
    ).toDouble();
    values[AchievementMetric.trainingSessions] = participationTournaments.length
        .toDouble();
    values[AchievementMetric.eloUpsetWins] = _eloUpsetWins(
      profileId,
      tournaments,
      eloSnapshot,
      through: through,
      minimumDifference: ranking.achievementParameters['elo_upset'] ?? 200.0,
    ).toDouble();
    values[AchievementMetric
        .consecutiveWinsAgainstLowerElo] = _consecutiveWinsAgainstLowerElo(
      profileId,
      tournaments,
      eloSnapshot,
      through: through,
      minimumDifference: ranking.achievementParameters['elo_upset'] ?? 200.0,
    ).toDouble();
    values[AchievementMetric.rankingGold] = 0;
    values[AchievementMetric.rankingSilver] = 0;
    values[AchievementMetric.rankingBronze] = 0;
    values[AchievementMetric.rankingMvp] = 0;
    return values;
  }

  Future<Set<String>> _rankingMvpPlayerIds(
    LocalRanking ranking,
    List<String> playerIds,
    List<CreatedTournament> tournaments,
  ) async {
    final relevant = tournaments
        .where(
          (tournament) =>
              tournament.countsForRanking &&
              tournament.rankingIds.contains(ranking.id) &&
              ranking.includesTournamentDate(tournament.effectiveDate),
        )
        .toList();
    final categoryScores = <String, Map<String, double?>>{
      for (final playerId in playerIds)
        playerId: await _mvpCategoryScores(ranking, playerId, relevant),
    };
    final categoryWins = {for (final playerId in playerIds) playerId: 0};
    final categories = categoryScores.values
        .expand((scores) => scores.keys)
        .toSet();
    for (final category in categories) {
      final scores = <String, double>{
        for (final playerId in playerIds)
          if (categoryScores[playerId]?[category] case final score?
              when score > 0)
            playerId: score,
      };
      if (scores.isEmpty) continue;
      final best = scores.values.reduce(
        (left, right) => left > right ? left : right,
      );
      for (final entry in scores.entries) {
        if (entry.value == best) {
          categoryWins.update(entry.key, (count) => count + 1);
        }
      }
    }
    final mostCategoryWins = categoryWins.values.fold<int>(
      0,
      (most, count) => count > most ? count : most,
    );
    if (mostCategoryWins == 0) return const {};
    return {
      for (final entry in categoryWins.entries)
        if (entry.value == mostCategoryWins) entry.key,
    };
  }

  Future<Map<String, double?>> _mvpCategoryScores(
    LocalRanking ranking,
    String profileId,
    List<CreatedTournament> tournaments,
  ) async {
    if (!tournaments.any(
      (tournament) => _containsPlayer(tournament.players, profileId),
    )) {
      return const {};
    }
    final monthlyPerformance = await _database.loadPlayerMonthlyPerformance(
      profileId,
    );
    final metrics = _calculateMetrics(
      ranking,
      profileId,
      tournaments,
      monthlyPerformance,
    );
    return {
      'participations': metrics[AchievementMetric.tournamentParticipations]!,
      'legs_won': metrics[AchievementMetric.legsWon]!,
      'legs_lost': metrics[AchievementMetric.legsLost]!,
      '180s': metrics[AchievementMetric.score180Count]!,
      '170s': metrics[AchievementMetric.bigFish170Count]!,
      '171_plus': metrics[AchievementMetric.score171Count]!,
      'best_performances':
          metrics[AchievementMetric.score180Count]! +
          metrics[AchievementMetric.bigFish170Count]! +
          metrics[AchievementMetric.score171Count]! +
          metrics[AchievementMetric.highFinishCount]! +
          metrics[AchievementMetric.bullseyeFinishCount]! +
          metrics[AchievementMetric.shortLegCount]!,
      'shortlegs': metrics[AchievementMetric.shortLegCount]!,
      'high_finishes': metrics[AchievementMetric.highFinishCount]!,
      'average': _bestMonthlyValue(
        monthlyPerformance,
        ranking,
        (entry) => entry.average,
      ),
      'scoring': _bestMonthlyValue(
        monthlyPerformance,
        ranking,
        (entry) => entry.scoring,
      ),
      'checkout_rate': _bestMonthlyValue(
        monthlyPerformance,
        ranking,
        (entry) => entry.checkoutRate,
      ),
      'tournament_wins': metrics[AchievementMetric.tournamentWins]!,
      'bullseye_finishes': metrics[AchievementMetric.bullseyeFinishCount]!,
    };
  }

  double? _bestMonthlyValue(
    List<PlayerMonthlyPerformance> monthlyPerformance,
    LocalRanking ranking,
    double? Function(PlayerMonthlyPerformance) valueFor,
  ) {
    final eligibleValues = monthlyPerformance
        .where(
          (entry) =>
              entry.weightedLegs >= 10 &&
              _rankingIncludesMonth(entry.year, entry.month, ranking),
        )
        .map(valueFor)
        .whereType<double>()
        .toList();
    return eligibleValues.isEmpty
        ? null
        : eligibleValues.reduce((left, right) => left > right ? left : right);
  }

  int _eloUpsetWins(
    String profileId,
    List<CreatedTournament> tournaments,
    LocalEloSnapshot? snapshot, {
    DateTime? through,
    required double minimumDifference,
  }) {
    if (snapshot == null) return 0;
    var upsetWins = 0;
    for (final tournament in tournaments) {
      final matches = _orderedMatches(tournament);
      for (final entry in matches.indexed) {
        final match = entry.$2;
        if (!match.countsForStatistics ||
            match.homePlayer == null ||
            match.awayPlayer == null) {
          continue;
        }
        if (through != null &&
            (match.finishedAt ?? tournament.effectiveDate).isAfter(through)) {
          continue;
        }
        final homeId = match.homePlayer!.profileId ?? match.homePlayer!.name;
        final awayId = match.awayPlayer!.profileId ?? match.awayPlayer!.name;
        final homeHistory = _historyForMatch(
          snapshot,
          homeId,
          tournament.id,
          entry.$1,
        );
        final awayHistory = _historyForMatch(
          snapshot,
          awayId,
          tournament.id,
          entry.$1,
        );
        if (homeHistory == null || awayHistory == null) continue;
        final difference = homeHistory.ratingBefore - awayHistory.ratingBefore;
        if (match.winner == match.homePlayer &&
            difference <= -minimumDifference &&
            homeId == profileId) {
          upsetWins++;
        } else if (match.winner == match.awayPlayer &&
            difference >= minimumDifference &&
            awayId == profileId) {
          upsetWins++;
        }
      }
    }
    return upsetWins;
  }

  int _consecutiveWinsAgainstLowerElo(
    String profileId,
    List<CreatedTournament> tournaments,
    LocalEloSnapshot? snapshot, {
    DateTime? through,
    required double minimumDifference,
  }) {
    if (snapshot == null) return 0;
    final events = <(DateTime, bool, int)>[];
    var sequence = 0;
    for (final tournament in tournaments) {
      for (final entry in _orderedMatches(tournament).indexed) {
        final match = entry.$2;
        if (!match.countsForStatistics ||
            match.homePlayer == null ||
            match.awayPlayer == null) {
          continue;
        }
        if (through != null &&
            (match.finishedAt ?? tournament.effectiveDate).isAfter(through)) {
          continue;
        }
        final homeId = match.homePlayer!.profileId ?? match.homePlayer!.name;
        final awayId = match.awayPlayer!.profileId ?? match.awayPlayer!.name;
        if (homeId != profileId && awayId != profileId) continue;
        final playerIsHome = homeId == profileId;
        final playerHistory = _historyForMatch(
          snapshot,
          profileId,
          tournament.id,
          entry.$1,
        );
        final opponentHistory = _historyForMatch(
          snapshot,
          playerIsHome ? awayId : homeId,
          tournament.id,
          entry.$1,
        );
        final hasLowerRatedOpponent =
            playerHistory != null &&
            opponentHistory != null &&
            playerHistory.ratingBefore - opponentHistory.ratingBefore >=
                minimumDifference;
        final won = playerIsHome
            ? match.winner == match.homePlayer
            : match.winner == match.awayPlayer;
        events.add((
          match.finishedAt ?? tournament.effectiveDate,
          won && hasLowerRatedOpponent,
          sequence++,
        ));
      }
    }
    events.sort((left, right) {
      final byDate = left.$1.compareTo(right.$1);
      return byDate != 0 ? byDate : left.$3.compareTo(right.$3);
    });
    var currentStreak = 0;
    var longestStreak = 0;
    for (final event in events) {
      currentStreak = event.$2 ? currentStreak + 1 : 0;
      if (currentStreak > longestStreak) longestStreak = currentStreak;
    }
    return longestStreak;
  }

  LocalEloHistoryItem? _historyForMatch(
    LocalEloSnapshot snapshot,
    String playerId,
    String tournamentId,
    int matchIndex,
  ) => snapshot.history[playerId]
      ?.where(
        (item) =>
            item.tournamentId == tournamentId &&
            item.matchIndex == matchIndex &&
            item.decayReason == null,
      )
      .firstOrNull;

  List<GroupMatch> _orderedMatches(CreatedTournament tournament) => [
    for (final stage in tournament.runStages)
      if (stage is KnockoutTournamentRunStage)
        ...stage.matches
      else if (stage is GroupTournamentRunStage)
        for (final group in stage.groups) ...[
          ...group.matches,
          ...group.knockoutRounds.expand((round) => round),
          ...group.placementMatches,
        ],
  ];

  bool _rankingIncludesMonth(int year, int month, LocalRanking? ranking) {
    if (ranking == null) return true;
    final firstDay = DateTime(year, month);
    final lastDay = DateTime(year, month + 1, 0);
    final startsAt =
        (ranking.validFromDate == null
            ? null
            : DateTime(
                ranking.validFromDate!.year,
                ranking.validFromDate!.month,
                ranking.validFromDate!.day,
              )) ??
        (ranking.validFromYear == null
            ? null
            : DateTime(ranking.validFromYear!, 1));
    final endsAt =
        (ranking.validToDate == null
            ? null
            : DateTime(
                ranking.validToDate!.year,
                ranking.validToDate!.month,
                ranking.validToDate!.day,
              )) ??
        (ranking.validToYear == null
            ? null
            : DateTime(ranking.validToYear!, 12, 31));
    return (startsAt == null || !lastDay.isBefore(startsAt)) &&
        (endsAt == null || !firstDay.isAfter(endsAt));
  }

  Future<int?> _rankingPosition(
    LocalRanking ranking,
    String profileId,
    List<CreatedTournament> tournaments,
  ) async {
    if (ranking.type == RankingType.elo) {
      final standings = await LocalRankingEloService(
        database: _database,
        tournamentStorage: _tournamentStorage,
      ).calculate(ranking, tournaments: tournaments);
      final index = standings.entries.indexWhere(
        (entry) => entry.id == profileId,
      );
      return index < 0 ? null : index + 1;
    }
    final standings = await LocalRankingSeriesService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    ).calculate(ranking, tournaments: tournaments);
    final index = standings.indexWhere((entry) => entry.player.id == profileId);
    return index < 0 ? null : index + 1;
  }

  double _maximum(Iterable<double?> values) => values
      .whereType<double>()
      .fold<double>(0, (max, value) => value > max ? value : max);

  double _longestConsecutiveMonths(List<DateTime> periods) {
    var current = 0;
    var maximum = 0;
    DateTime? previous;
    for (final period in periods) {
      if (previous != null &&
          (period.year != previous.year ||
              period.month != previous.month + 1)) {
        if (period.year != previous.year + 1 ||
            previous.month != 12 ||
            period.month != 1) {
          current = 0;
        }
      }
      current++;
      if (current > maximum) maximum = current;
      previous = period;
    }
    return maximum.toDouble();
  }

  double _maximumActiveMonthsInYear(List<DateTime> periods) {
    final counts = <int, Set<int>>{};
    for (final period in periods) {
      counts.putIfAbsent(period.year, () => <int>{}).add(period.month);
    }
    return counts.values
        .fold<int>(
          0,
          (maximum, months) =>
              months.length > maximum ? months.length : maximum,
        )
        .toDouble();
  }

  double _longestConsecutive(
    List<CreatedTournament> participations,
    List<CreatedTournament> tournaments,
  ) {
    final participationIds = participations.map((item) => item.id).toSet();
    var current = 0;
    var maximum = 0;
    for (final tournament in tournaments) {
      if (participationIds.contains(tournament.id)) {
        current++;
        if (current > maximum) maximum = current;
      } else {
        current = 0;
      }
    }
    return maximum.toDouble();
  }

  double _longestTournamentWinStreak(
    List<CreatedTournament> wins,
    List<CreatedTournament> tournaments,
  ) {
    final winIds = wins.map((item) => item.id).toSet();
    var current = 0;
    var maximum = 0;
    for (final tournament in tournaments) {
      if (winIds.contains(tournament.id)) {
        current++;
        if (current > maximum) maximum = current;
      } else {
        current = 0;
      }
    }
    return maximum.toDouble();
  }

  bool _containsPlayer(List<TournamentPlayer> players, String profileId) =>
      players.any(
        (player) => _individualProfileIds(player).contains(profileId),
      );

  Set<String> _individualProfileIds(TournamentPlayer player) => {
    for (final individual in player.individuals)
      if (individual.profileId != null) individual.profileId!,
  };

  bool _performanceBelongsTo(
    GroupMatch match,
    BestPerformance performance,
    String profileId,
  ) {
    if (performance.playerProfileId != null) {
      return performance.playerProfileId == profileId;
    }
    final name = performance.playerName.trim().toLowerCase();
    if (name.isEmpty) return false;
    return [
      match.homePlayer,
      match.awayPlayer,
    ].whereType<TournamentPlayer>().any(
      (side) => side.individuals.any(
        (player) =>
            player.profileId == profileId &&
            player.name.trim().toLowerCase() == name,
      ),
    );
  }

  List<(BestPerformance, String)> _archivedBestPerformances(
    CreatedTournament tournament,
  ) {
    final archive = tournament.importedArchive;
    if (archive == null) return const [];
    final participantById = <String, Map<String, dynamic>>{};
    for (final participant in archive.participants) {
      final id = participant['id'];
      if (id is! String || id.isEmpty) continue;
      participantById[id] = participant;
      for (final alias in participant['groupPlayerIds'] as List? ?? const []) {
        participantById['$alias'] = participant;
      }
    }
    final performances = <(BestPerformance, String)>[];
    for (final match in archive.matches) {
      final matchPlayerIds = [
        '${match['player1_id'] ?? ''}',
        '${match['player2_id'] ?? ''}',
      ];
      final serialized = match['bestPerformances'];
      if (serialized is! List) continue;
      for (final item in serialized.whereType<Map>()) {
        final performance = BestPerformance.fromJson(
          Map<String, dynamic>.from(item),
        );
        final explicitProfileId = performance.playerProfileId;
        if (explicitProfileId != null && explicitProfileId.isNotEmpty) {
          performances.add((performance, explicitProfileId));
          continue;
        }
        final normalizedName = performance.playerName.trim().toLowerCase();
        if (normalizedName.isEmpty) continue;
        final matchingProfileIds = {
          for (final participantId in matchPlayerIds)
            if (participantById[participantId] case final participant?
                when participant['name'] is String &&
                    (participant['name'] as String).trim().toLowerCase() ==
                        normalizedName &&
                    participant['profileId'] is String)
              participant['profileId'] as String,
        };
        if (matchingProfileIds.length == 1) {
          performances.add((performance, matchingProfileIds.single));
        }
      }
    }
    return performances;
  }

  (List<TournamentPlayer>, List<TournamentPlayer>) _matchSides(
    GroupMatch match,
  ) => (
    match.homePlayer == null ? const [] : [match.homePlayer!],
    match.awayPlayer == null ? const [] : [match.awayPlayer!],
  );

  List<GroupMatch> _matches(CreatedTournament tournament) =>
      _orderedMatches(tournament).toSet().toList();

  int? _placementFor(CreatedTournament tournament, String profileId) {
    if (tournament.finishedAt == null) return null;
    if (tournament.importedArchive != null) {
      return _importedPlacementFor(tournament, profileId);
    }
    if (TournamentWinner.profileId(tournament) == null) return null;
    final finalStage = tournament.runStages.lastOrNull;
    if (finalStage is GroupTournamentRunStage &&
        finalStage.groups.length == 1) {
      final group = finalStage.groups.single;
      final standings = const GroupStandingsEngine().calculate(
        group,
        finalStage.tieBreakers,
        tournament: tournament,
      );
      final position = standings.indexWhere(
        (standing) =>
            _individualProfileIds(standing.player).contains(profileId),
      );
      if (position >= 0) {
        if (position > 0 &&
            const GroupStandingsEngine().compare(
                  standings[position - 1],
                  standings[position],
                  finalStage.tieBreakers,
                  matches: group.matches,
                ) ==
                0) {
          return null;
        }
        if (position + 1 < standings.length &&
            const GroupStandingsEngine().compare(
                  standings[position],
                  standings[position + 1],
                  finalStage.tieBreakers,
                  matches: group.matches,
                ) ==
                0) {
          return null;
        }
        return position + 1;
      }
      return null;
    }
    if (finalStage is KnockoutTournamentRunStage &&
        finalStage.rounds.isNotEmpty) {
      for (final match in finalStage.placementMatches) {
        final rank = match.placementRank;
        if (rank == null || !match.hasResult) continue;
        if (match.winner != null &&
            _individualProfileIds(match.winner!).contains(profileId)) {
          return rank;
        }
        if (match.loser != null &&
            _individualProfileIds(match.loser!).contains(profileId)) {
          return rank + 1;
        }
      }
      final finalRound = finalStage.rounds.last;
      if (finalRound.length == 1 && finalRound.single.hasResult) {
        final winner = finalRound.single.winner;
        final loser = finalRound.single.loser;
        if (winner != null &&
            _individualProfileIds(winner).contains(profileId)) {
          return 1;
        }
        if (loser != null && _individualProfileIds(loser).contains(profileId)) {
          return 2;
        }
      }
    }
    return null;
  }

  int? _importedPlacementFor(CreatedTournament tournament, String profileId) {
    final archive = tournament.importedArchive;
    if (archive == null) return null;
    final matchingParticipants = archive.participants.where((participant) {
      final rank = participant['finalRank'];
      if (rank is! num || rank < 1) return false;
      final archivedProfileId = participant['profileId'];
      if (archivedProfileId is String && archivedProfileId.isNotEmpty) {
        return archivedProfileId == profileId;
      }
      final name = participant['name'];
      if (name is! String || name.trim().isEmpty) return false;
      final matchingPlayers = tournament.players
          .where((player) => player.name == name)
          .toList();
      return matchingPlayers.length == 1 &&
          matchingPlayers.single.profileId == profileId;
    }).toList();
    if (matchingParticipants.length != 1) return null;
    return (matchingParticipants.single['finalRank'] as num).toInt();
  }

  int _compareTournaments(CreatedTournament left, CreatedTournament right) {
    final date = left.effectiveDate.compareTo(right.effectiveDate);
    return date != 0 ? date : left.id.compareTo(right.id);
  }

  Future<Map<String, DateTime>> _historicalUnlockDates({
    required LocalRanking ranking,
    required String profileId,
    required List<CreatedTournament> tournaments,
    required List<PlayerMonthlyPerformance> monthlyPerformance,
    required List<AchievementDefinition> definitions,
    required LocalEloSnapshot? eloSnapshot,
  }) async {
    final timestamps = <DateTime>{};
    for (final tournament in tournaments) {
      timestamps.add(
        tournament.startedAt ??
            tournament.tournamentDate ??
            tournament.createdAt,
      );
      if (tournament.finishedAt != null) {
        timestamps.add(tournament.finishedAt!);
      }
      for (final match in _matches(tournament)) {
        final timestamp = match.finishedAt ?? match.startedAt;
        if (timestamp != null) timestamps.add(timestamp);
      }
    }
    for (final entry in monthlyPerformance) {
      if (!_rankingIncludesMonth(entry.year, entry.month, ranking)) continue;
      timestamps.add(DateTime(entry.year, entry.month + 1, 0, 23, 59, 59));
    }
    final orderedTimestamps = timestamps.toList()..sort();
    final unlockedAt = <String, DateTime>{};
    DateTime? rankingCompletedAt;
    int? finalPosition;
    Set<String> mvpPlayerIds = const {};
    if (ranking.isCompleted && tournaments.isNotEmpty) {
      rankingCompletedAt = tournaments
          .map(
            (tournament) => tournament.finishedAt ?? tournament.effectiveDate,
          )
          .reduce((left, right) => left.isAfter(right) ? left : right);
      if (tournaments.any(
        (tournament) => _containsPlayer(tournament.players, profileId),
      )) {
        finalPosition = await _rankingPosition(ranking, profileId, tournaments);
        mvpPlayerIds = await _rankingMvpPlayerIds(
          ranking,
          await _eligibleRankingPlayerIds(ranking),
          tournaments,
        );
      }
    }
    for (final timestamp in orderedTimestamps) {
      final values = _calculateMetrics(
        ranking,
        profileId,
        tournaments,
        monthlyPerformance,
        eloSnapshot: eloSnapshot,
        through: timestamp,
      );
      final rankingCompletedByDate =
          rankingCompletedAt != null && !rankingCompletedAt.isAfter(timestamp);
      if (rankingCompletedByDate) {
        values[AchievementMetric.rankingGold] = finalPosition == 1 ? 1 : 0;
        values[AchievementMetric.rankingSilver] = finalPosition == 2 ? 1 : 0;
        values[AchievementMetric.rankingBronze] = finalPosition == 3 ? 1 : 0;
        values[AchievementMetric.rankingMvp] = mvpPlayerIds.contains(profileId)
            ? 1
            : 0;
      }
      final evaluation = const AchievementEngine().evaluate(
        values: values,
        rankingCompleted: rankingCompletedByDate,
        definitions: definitions,
      );
      for (final progress in evaluation.progress.values) {
        if (!progress.isCompleted ||
            progress.definition.requiresCompletedRanking) {
          continue;
        }
        unlockedAt.putIfAbsent(progress.definition.id, () => timestamp);
      }
    }
    return unlockedAt;
  }

  String _fingerprint(
    LocalRanking ranking,
    List<CreatedTournament> tournaments,
    List<PlayerMonthlyPerformance> monthlyPerformance,
  ) {
    final source = jsonEncode({
      'achievementCalculationVersion': 3,
      'ranking': ranking.toJson(),
      'tournaments': [for (final item in tournaments) item.toJson()],
      'monthlyPerformance': [
        for (final item in monthlyPerformance)
          [
            item.year,
            item.month,
            item.weightedLegs,
            item.scoring,
            item.average,
            item.checkoutRate,
          ],
      ],
    });
    var hash = 0x811c9dc5;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, Object?> _storedProgress(
    AchievementProgress progress, {
    required String sourceHash,
    required Map<String, Object?>? previous,
    required DateTime now,
  }) {
    final definition = progress.definition;
    final completed = progress.isCompleted;
    final finalAward = completed && definition.requiresCompletedRanking;
    final wasFinal = previous?['is_final'] == 1;
    final isPermanentMilestone =
        completed && _isPerformanceMilestone(definition);
    final previousUnlockedAt = previous?['unlocked_at'] as String?;
    final recalculatedUnlockedAt = progress.unlockedAt
        ?.toUtc()
        .toIso8601String();
    final unlockedAt =
        recalculatedUnlockedAt ??
        (wasFinal
            ? previousUnlockedAt
            : completed
            ? previousUnlockedAt ?? now.toIso8601String()
            : null);
    return {
      'achievement_id': definition.id,
      'current_value': progress.currentValue,
      'alternative_current_value': progress.alternativeCurrentValue,
      'target_value': definition.target,
      'alternative_target_value': definition.alternativeTarget ?? 0,
      'status': progress.status.name,
      'unlocked_at': unlockedAt,
      'explanation': definition.description,
      'is_final': (finalAward || wasFinal || isPermanentMilestone) ? 1 : 0,
      'source_hash': sourceHash,
    };
  }

  AchievementProgress _storedAchievementProgress(
    AchievementDefinition definition,
    Map<String, Object?>? row,
  ) {
    final currentValue = (row?['current_value'] as num?)?.toDouble() ?? 0;
    final alternativeCurrentValue =
        (row?['alternative_current_value'] as num?)?.toDouble() ?? 0;
    final status = AchievementStatus.values.firstWhere(
      (value) => value.name == row?['status'],
      orElse: () => AchievementStatus.locked,
    );
    final unlockedAt = row?['unlocked_at'] is String
        ? DateTime.tryParse(row!['unlocked_at']! as String)
        : null;
    return AchievementProgress(
      definition: definition,
      currentValue: currentValue,
      alternativeCurrentValue: alternativeCurrentValue,
      status: status,
      unlockedAt: unlockedAt,
    );
  }

  bool _isPerformanceMilestone(AchievementDefinition definition) =>
      definition.metric == AchievementMetric.monthlyAverage ||
      definition.metric == AchievementMetric.monthlyScoring ||
      definition.metric == AchievementMetric.monthlyCheckoutRate;

  String _formatMetric(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

class _PlayerMatchRecord {
  const _PlayerMatchRecord({required this.date, required this.won});

  final DateTime date;
  final bool won;
}
