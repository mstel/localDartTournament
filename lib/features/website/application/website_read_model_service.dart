import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/application/local_ranking_series_service.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../statistics/domain/local_statistics.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';

class WebsiteReadModelService {
  WebsiteReadModelService({
    LocalAppDatabase? database,
    TournamentStorage? tournamentStorage,
  }) : _database = database ?? LocalAppDatabase(),
       _tournamentStorage = tournamentStorage ?? TournamentStorage();

  static const schemaVersion = 1;
  static const objectName = 'website-read-model.json';
  static const tournamentIndexObjectName = 'website-tournament-index.json';
  final LocalAppDatabase _database;
  final TournamentStorage _tournamentStorage;

  Future<Map<String, dynamic>> create() async {
    final profiles = await _database.loadPlayerProfiles();
    final rankings = await _database.loadLocalRankings();
    final completed =
        completedTournaments(await _tournamentStorage.loadTournaments())..sort((
          left,
          right,
        ) {
          final leftDate = left.finishedAt ?? left.startedAt ?? left.createdAt;
          final rightDate = right.finishedAt ?? right.startedAt ?? right.createdAt;
          final byDate = rightDate.compareTo(leftDate);
          return byDate != 0 ? byDate : left.id.compareTo(right.id);
        });

    final statistics = LocalStatisticsService(database: _database);
    final playerStatistics = <Map<String, dynamic>>[];
    final bestPerformances = <Map<String, dynamic>>[];
    for (final profile in profiles) {
      final result = await statistics.forPlayersFromTournaments({
        profile.id,
      }, completed);
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
      });
      for (final performance in result.bestPerformances) {
        bestPerformances.add({...performance.toJson(), 'playerId': profile.id});
      }
    }

    final rankingStandings = <Map<String, dynamic>>[];
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
          {'id': ranking.id, 'name': ranking.name, 'type': ranking.type.name},
      ],
      'rankingStandings': rankingStandings,
      'statistics': playerStatistics,
      'bestPerformances': _uniquePerformances(bestPerformances),
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

  static Map<String, dynamic> createTournamentIndex(
    Map<String, dynamic> readModel,
  ) {
    final tournaments =
        (readModel['completedTournaments'] as List<dynamic>? ?? const []);
    return {
      'schemaVersion': schemaVersion,
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

  static List<Map<String, dynamic>> _uniquePerformances(
    List<Map<String, dynamic>> performances,
  ) {
    final seen = <String>{};
    return [
      for (final performance in performances)
        if (seen.add(
          '${performance['playerId']}|${performance['type']}|'
          '${performance['playerName']}|${performance['value']}',
        ))
          performance,
    ];
  }
}
