import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/application/local_ranking_series_service.dart';
import '../../rankings/application/ranking_year_review_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../achievements/application/ranking_achievement_service.dart';
import '../../statistics/domain/local_statistics.dart';
import '../../statistics/domain/player_monthly_performance.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';

class WebsiteReadModelService {
  WebsiteReadModelService({
    LocalAppDatabase? database,
    TournamentStorage? tournamentStorage,
    DateTime Function()? clock,
  }) : _database = database ?? LocalAppDatabase(),
       _tournamentStorage = tournamentStorage ?? TournamentStorage(),
       _clock = clock ?? DateTime.now;

  static const schemaVersion = 2;
  static const tournamentIndexSchemaVersion = 1;
  static const resourceSchemaVersion = 2;
  static const objectName = 'website-read-model.json';
  static const tournamentIndexObjectName = 'website-tournament-index.json';
  static const resourceManifestObjectName = 'website-v2-manifest.json';
  static const resourcePageSize = 10;
  static const _resourceObjectNames = {
    'players': 'website-v2-players.json',
    'rankings': 'website-v2-rankings.json',
    'statistics': 'website-v2-statistics.json',
    'performance': 'website-v2-performance.json',
    'achievements': 'website-v2-achievements.json',
  };
  final LocalAppDatabase _database;
  final TournamentStorage _tournamentStorage;
  final DateTime Function() _clock;

  Future<Map<String, dynamic>> create() async {
    final profiles = await _database.loadPlayerProfiles();
    final rankings = await _database.loadLocalRankings();
    final completed =
        completedTournaments(await _tournamentStorage.loadTournaments())..sort((
          left,
          right,
        ) {
          final leftDate = left.finishedAt ?? left.startedAt ?? left.createdAt;
          final rightDate =
              right.finishedAt ?? right.startedAt ?? right.createdAt;
          final byDate = rightDate.compareTo(leftDate);
          return byDate != 0 ? byDate : left.id.compareTo(right.id);
        });

    final statistics = LocalStatisticsService(database: _database);
    final playerStatistics = <Map<String, dynamic>>[];
    final bestPerformances = <Map<String, dynamic>>[];
    final currentForms = <Map<String, dynamic>>[];
    for (final profile in profiles) {
      final result = await statistics.forPlayersFromTournaments({
        profile.id,
      }, completed);
      final currentForm = calculateCurrentFormPerformance(
        combineMonthlyPlayerPerformances(
          recorded: await _database.loadPlayerMonthlyPerformance(profile.id),
          imported: await _database.loadMonthlyPlayerPerformances({profile.id}),
        ),
        now: _clock(),
      );
      final currentFormJson = currentForm.toJson();
      currentForms.add({'playerId': profile.id, ...currentFormJson});
      playerStatistics.add({
        'playerId': profile.id,
        'tournaments': result.tournaments,
        'matches': result.matches,
        'wins': result.wins,
        'losses': result.losses,
        'draws': result.draws,
        'tournamentWins': result.tournamentWins,
        'legsWon': result.legsWon,
        'legsLost': result.legsLost,
        'legsDrawn': result.legsDrawn,
        'setsWon': result.setsWon,
        'setsLost': result.setsLost,
        'currentForm': currentFormJson,
      });
      for (final occurrence in result.bestPerformanceOccurrences) {
        bestPerformances.add({
          ...occurrence.performance.toJson(),
          'playerId': profile.id,
          'tournamentId': occurrence.tournamentId,
          'tournamentName': occurrence.tournamentName,
        });
      }
    }

    final rankingStandings = <Map<String, dynamic>>[];
    final eloHistory = <Map<String, dynamic>>[];
    final eloService = LocalRankingEloService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    );
    final seriesService = LocalRankingSeriesService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    );
    for (final ranking in rankings) {
      if (ranking.type == RankingType.elo) {
        final snapshot = await eloService.calculate(
          ranking,
          tournaments: completed,
        );
        for (final playerHistory in snapshot.history.entries) {
          final historyByTournament = <String, List<LocalEloHistoryItem>>{};
          for (final item in playerHistory.value) {
            historyByTournament
                .putIfAbsent(item.tournamentId, () => [])
                .add(item);
          }
          for (final tournamentHistory in historyByTournament.values) {
            final orderedHistory = tournamentHistory.toList()
              ..sort((left, right) {
                final byDate = left.playedAt.compareTo(right.playedAt);
                return byDate != 0
                    ? byDate
                    : left.matchIndex.compareTo(right.matchIndex);
              });
            final last = orderedHistory.last;
            eloHistory.add({
              'rankingId': ranking.id,
              'playerId': playerHistory.key,
              'tournamentId': last.tournamentId,
              'tournamentName': last.tournamentName,
              'occurredAt': last.playedAt.toUtc().toIso8601String(),
              'ratingAfter': last.ratingAfter,
              'delta': tournamentHistory.fold<int>(
                0,
                (total, item) => total + item.delta,
              ),
            });
          }
        }
        rankingStandings.add({
          'rankingId': ranking.id,
          'entries': [
            for (var index = 0; index < snapshot.entries.length; index++)
              {
                'position': index + 1,
                'playerId': snapshot.entries[index].id,
                'name': snapshot.entries[index].name,
                'rating': snapshot.entries[index].rating,
                'matches': snapshot.entries[index].matches,
                'wins': snapshot.entries[index].wins,
                'losses': snapshot.entries[index].losses,
                'draws': snapshot.entries[index].draws,
              },
          ],
        });
      } else {
        final entries = await seriesService.calculate(
          ranking,
          tournaments: completed,
        );
        rankingStandings.add({
          'rankingId': ranking.id,
          'entries': [
            for (var index = 0; index < entries.length; index++)
              {
                'position': index + 1,
                'playerId': entries[index].player.id,
                'name': entries[index].player.displayName,
                'points': entries[index].points,
                'participations': entries[index].participations,
                'setsWon': entries[index].setsWon,
                'firstPlaces': entries[index].firstPlaces,
                'secondPlaces': entries[index].secondPlaces,
                'thirdPlaces': entries[index].thirdPlaces,
                'bestPerformances': entries[index].bestPerformances,
              },
          ],
        });
      }
    }

    final achievementStandings = <Map<String, dynamic>>[];
    final achievementService = RankingAchievementService(
      database: _database,
      tournamentStorage: _tournamentStorage,
    );
    final profileById = {for (final profile in profiles) profile.id: profile};
    for (final ranking in rankings.where(
      (ranking) => ranking.achievementsEnabled,
    )) {
      final refreshed = await achievementService.refreshRanking(
        ranking,
        tournaments: completed,
      );
      final playerEntries = refreshed.entries.toList()
        ..sort(
          (left, right) => profileById[left.key]!.displayName
              .toLowerCase()
              .compareTo(profileById[right.key]!.displayName.toLowerCase()),
        );
      achievementStandings.add({
        'rankingId': ranking.id,
        'rankingName': ranking.name,
        'rankingType': ranking.type.name,
        'players': [
          for (final entry in playerEntries)
            {
              'playerId': entry.key,
              'playerName': profileById[entry.key]!.displayName,
              'level': entry.value.evaluation.level,
              'totalExperiencePoints':
                  entry.value.evaluation.totalExperiencePoints,
              'levelEligibleExperiencePoints':
                  entry.value.evaluation.levelEligibleExperiencePoints,
              'levelStartExperiencePoints':
                  entry.value.evaluation.levelStartExperiencePoints,
              'nextLevelExperiencePoints':
                  entry.value.evaluation.nextLevelExperiencePoints,
              'experiencePointsToNextLevel':
                  entry.value.evaluation.experiencePointsToNextLevel,
              'levelProgress': entry.value.evaluation.levelProgress,
              'achievements': [
                for (final progress in entry.value.evaluation.progress.values)
                  {
                    'id': progress.definition.id,
                    'name': progress.definition.name,
                    'description': progress.definition.description,
                    'alternativeDescription':
                        progress.definition.alternativeDescription,
                    'category': progress.definition.category.name,
                    'currentValue': progress.currentValue,
                    'alternativeCurrentValue': progress.alternativeCurrentValue,
                    'target': progress.definition.target,
                    'alternativeTarget': progress.definition.alternativeTarget,
                    'status': progress.status.name,
                    'isCompleted': progress.isCompleted,
                    'experiencePoints': progress.definition.experiencePoints,
                    'contributesToLevel':
                        progress.definition.contributesToLevel,
                    'unlockedAt': progress.unlockedAt
                        ?.toUtc()
                        .toIso8601String(),
                  },
              ],
            },
        ],
      });
    }

    return {
      'schemaVersion': schemaVersion,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'players': [
        for (final profile in profiles)
          {
            'id': profile.id,
            'firstName': profile.firstName,
            'lastName': profile.lastName,
            'fullName': profile.displayName,
            'nickname': profile.nickname,
            'country': profile.country,
            'city': profile.city,
            'createdAt': profile.createdAt.toUtc().toIso8601String(),
          },
      ],
      'rankings': [
        for (final ranking in rankings)
          {
            'id': ranking.id,
            'name': ranking.name,
            'type': ranking.type.name,
            'requireMinimumParticipations':
                ranking.requireMinimumParticipations,
            'minimumParticipations': ranking.minimumParticipations,
            'achievementsEnabled': ranking.achievementsEnabled,
            'achievementTargets': ranking.achievementTargets,
            'achievementParameters': ranking.achievementParameters,
            'achievementAlternativeTargets':
                ranking.achievementAlternativeTargets,
          },
      ],
      'rankingStandings': rankingStandings,
      'eloHistory': eloHistory,
      'rankingAchievements': achievementStandings,
      'statistics': playerStatistics,
      'currentForm': currentForms,
      'bestPerformances': bestPerformances,
      'completedTournaments': [
        for (final tournament in completed)
          {
            ...tournament.toJson(),
            // Ensure finishedAt is always present for the website; fall back
            // to startedAt or createdAt for legacy Challonge imports where the
            // public page scrape did not provide a completion timestamp.
            if (tournament.finishedAt == null)
              'finishedAt': (tournament.startedAt ?? tournament.createdAt)
                  .toUtc()
                  .toIso8601String(),
          },
      ],
    };
  }

  /// Builds independently downloadable v2 resources without changing v1.
  Future<Map<String, Map<String, dynamic>>> createVersion2Resources(
    Map<String, dynamic> readModel,
  ) async {
    final generatedAt = readModel['generatedAt'];
    final players = (readModel['players'] as List).cast<Map<String, dynamic>>();
    final tournaments = createTournamentIndex(readModel);
    final resources = <String, Map<String, dynamic>>{
      'players': _version2Resource('players', generatedAt, {
        'players': players,
      }),
      'rankings': _version2Resource('rankings', generatedAt, {
        'rankings': readModel['rankings'],
        'rankingStandings': readModel['rankingStandings'],
        'eloHistory': readModel['eloHistory'] ?? const [],
      }),
      'statistics': _version2Resource('statistics', generatedAt, {
        'statistics': readModel['statistics'],
        'bestPerformances': readModel['bestPerformances'],
        'currentForm': readModel['currentForm'],
      }),
      'achievements': _version2Resource('achievements', generatedAt, {
        'rankingAchievements': readModel['rankingAchievements'] ?? const [],
      }),
    };

    final monthlyPerformance = <Map<String, dynamic>>[];
    final importedMonthlyStatistics = <Map<String, dynamic>>[];
    final combinedMonthlyPerformance = <PlayerMonthlyPerformance>[];
    for (final player in players) {
      final playerId = player['id'] as String;
      final imported = await _database.loadMonthlyPlayerPerformances({
        playerId,
      });
      final entries = combineMonthlyPlayerPerformances(
        recorded: await _database.loadPlayerMonthlyPerformance(playerId),
        imported: imported,
      );
      combinedMonthlyPerformance.addAll(entries);
      for (final entry in entries) {
        monthlyPerformance.add({
          'playerId': entry.playerId,
          'period': entry.periodKey,
          'year': entry.year,
          'month': entry.month,
          'matches': entry.matches,
          'weightedLegs': entry.weightedLegs,
          'scoring': entry.scoring,
          'average': entry.average,
          'checkoutQuote': entry.checkoutRate,
        });
      }
      for (final entry in imported) {
        importedMonthlyStatistics.add({
          'playerId': entry.playerProfileId,
          'sourcePlayerName': entry.sourcePlayerName,
          'period': entry.month,
          'year': entry.monthDate.year,
          'month': entry.monthDate.month,
          'threeDartAverage': entry.threeDartAverage,
          'firstNineAverage': entry.firstNineAverage,
          'checkoutPercentage': entry.checkoutPercentage,
          'legs': entry.legs,
          'matches': entry.matches,
        });
      }
    }
    final monthlyClubPerformance =
        RankingYearReviewService.aggregateMonthlyClubPerformance(
          combinedMonthlyPerformance,
        );
    resources['performance'] = _version2Resource('performance', generatedAt, {
      'monthlyPerformance': monthlyPerformance,
      'monthlyClubPerformance': [
        for (final entry in monthlyClubPerformance)
          {
            'year': entry.year,
            'month': entry.month,
            'period': '${entry.year}-${entry.month.toString().padLeft(2, '0')}',
            'matches': entry.matches,
            'weightedLegs': entry.weightedLegs,
            'scoring': entry.scoring,
            'average': entry.average,
            'checkoutQuote': entry.checkoutRate,
          },
      ],
      'importedMonthlyStatistics': importedMonthlyStatistics,
      'currentForm': readModel['currentForm'],
    });

    final tournamentSummaries =
        tournaments['completedTournaments'] as List<dynamic>;
    final pageCount = (tournamentSummaries.length / resourcePageSize).ceil();
    final pageTotal = pageCount == 0 ? 1 : pageCount;
    for (var page = 1; page <= pageTotal; page++) {
      final start = (page - 1) * resourcePageSize;
      final end = (start + resourcePageSize)
          .clamp(0, tournamentSummaries.length)
          .toInt();
      resources['tournaments:$page'] = _version2Resource(
        'tournaments',
        generatedAt,
        {
          'completedTournaments': tournamentSummaries.sublist(start, end),
          'tournamentPage': {
            'page': page,
            'pageSize': resourcePageSize,
            'total': tournamentSummaries.length,
            'hasMore': end < tournamentSummaries.length,
          },
        },
      );
    }
    return resources;
  }

  static Map<String, dynamic> _version2Resource(
    String resource,
    Object? generatedAt,
    Map<String, dynamic> content,
  ) => {
    'schemaVersion': resourceSchemaVersion,
    'resource': resource,
    'generatedAt': generatedAt,
    ...content,
  };

  static String version2ResourceObjectName(String resource, {int? page}) {
    if (resource == 'tournaments') {
      if (page == null || page < 1) {
        throw ArgumentError.value(page, 'page', 'Must be a positive page.');
      }
      return 'website-v2-tournaments-page-$page.json';
    }
    final objectName = _resourceObjectNames[resource];
    if (objectName == null) {
      throw ArgumentError.value(
        resource,
        'resource',
        'Unknown website resource.',
      );
    }
    return objectName;
  }

  static Map<String, dynamic> createTournamentIndex(
    Map<String, dynamic> readModel,
  ) {
    final tournaments =
        (readModel['completedTournaments'] as List<dynamic>? ?? const []);
    return {
      'schemaVersion': tournamentIndexSchemaVersion,
      'generatedAt': readModel['generatedAt'],
      'completedTournaments': [
        for (final tournament in tournaments.cast<Map<String, dynamic>>())
          {
            'id': tournament['id'],
            'name': tournament['name'],
            'finishedAt': tournament['finishedAt'],
            'startedAt': tournament['startedAt'],
            'createdAt': tournament['createdAt'],
            'playerCount':
                (tournament['players'] as List<dynamic>? ?? const []).length,
            'matchCount': _matchCount(tournament),
            'mode': _mode(tournament),
            'hasImportedArchive': tournament['importedArchive'] != null,
          },
      ],
    };
  }

  static int _matchCount(Map<String, dynamic> tournament) {
    var count = 0;
    for (final stage in tournament['runStages'] as List<dynamic>? ?? const []) {
      if (stage is! Map<String, dynamic>) continue;
      if (stage['kind'] == 'groups') {
        for (final group in stage['groups'] as List<dynamic>? ?? const []) {
          if (group is Map<String, dynamic>) {
            count += (group['matches'] as List<dynamic>? ?? const []).length;
          }
        }
      } else if (stage['kind'] == 'single_knockout') {
        for (final round in stage['rounds'] as List<dynamic>? ?? const []) {
          if (round is List) count += round.length;
        }
        count +=
            (stage['placementMatches'] as List<dynamic>? ?? const []).length;
      }
    }
    if (tournament['leagueMatch'] != null) count++;
    return count;
  }

  static String _mode(Map<String, dynamic> tournament) {
    final archive = tournament['importedArchive'];
    if (archive is Map<String, dynamic> && archive['mode'] is String) {
      return archive['mode'] as String;
    }
    final stages = tournament['stages'] as List<dynamic>? ?? const [];
    if (stages.isNotEmpty && stages.first is Map<String, dynamic>) {
      final firstStage = stages.first as Map<String, dynamic>;
      final type = firstStage['type'];
      if (type is String) {
        if (type == 'groups') {
          final runStages =
              tournament['runStages'] as List<dynamic>? ?? const [];
          if (runStages.isNotEmpty && runStages.first is Map<String, dynamic>) {
            final playType =
                (runStages.first as Map<String, dynamic>)['groupPlayType'];
            if (playType is String) return 'groups:$playType';
          }
        }
        return type;
      }
    }
    final runStages = tournament['runStages'] as List<dynamic>? ?? const [];
    if (runStages.isNotEmpty && runStages.first is Map<String, dynamic>) {
      final firstRunStage = runStages.first as Map<String, dynamic>;
      final kind = firstRunStage['kind'];
      if (kind == 'groups' && firstRunStage['groupPlayType'] is String) {
        return 'groups:${firstRunStage['groupPlayType']}';
      }
      if (kind is String) return kind;
    }
    return 'unknown';
  }

  static List<CreatedTournament> completedTournaments(
    Iterable<CreatedTournament> tournaments,
  ) => [
    for (final tournament in tournaments)
      if (!tournament.reopenedForCorrections &&
          (tournament.finishedAt != null || tournament.importedArchive != null))
        tournament,
  ];
}
