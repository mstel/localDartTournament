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
          final byFinishedAt = right.finishedAt!.compareTo(left.finishedAt!);
          return byFinishedAt != 0 ? byFinishedAt : left.id.compareTo(right.id);
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
        for (final tournament in completed) tournament.toJson(),
      ],
    };
  }

  static List<CreatedTournament> completedTournaments(
    Iterable<CreatedTournament> tournaments,
  ) => [
    for (final tournament in tournaments)
      if (tournament.finishedAt != null && !tournament.reopenedForCorrections)
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
