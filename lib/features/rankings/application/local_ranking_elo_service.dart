import '../domain/local_elo_calculator.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../domain/local_ranking.dart';

class LocalRankingEloService {
  const LocalRankingEloService({
    required LocalAppDatabase database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase _database;
  final TournamentStorage? _tournamentStorage;

  Future<LocalEloSnapshot> calculate(LocalRanking ranking) async {
    final tournaments = await (_tournamentStorage ?? TournamentStorage())
        .loadTournaments();
    return _calculate(ranking, tournaments);
  }

  Future<LocalEloSnapshot> calculateThroughTournament(
    LocalRanking ranking,
    CreatedTournament target, {
    required bool includeTournament,
  }) async {
    final tournaments = await (_tournamentStorage ?? TournamentStorage())
        .loadTournaments();
    final targetDate = target.startedAt ?? target.createdAt;
    final relevant = tournaments.where((tournament) {
      final date = tournament.startedAt ?? tournament.createdAt;
      final comparison = date.compareTo(targetDate);
      final orderComparison = comparison == 0
          ? tournament.id.compareTo(target.id)
          : comparison;
      return includeTournament ? orderComparison <= 0 : orderComparison < 0;
    });
    return _calculate(ranking, relevant.toList());
  }

  Future<LocalEloSnapshot> _calculate(
    LocalRanking ranking,
    Iterable<CreatedTournament> tournaments,
  ) async {
    if (ranking.type != RankingType.elo) {
      throw ArgumentError.value(
        ranking.type,
        'ranking.type',
        'Not an Elo ranking',
      );
    }
    final ids = await _database.loadRankingPlayerIds(ranking.id);
    final profiles = await _database.loadPlayerProfiles();
    final byId = {for (final profile in profiles) profile.id: profile};
    final players = {
      for (final id in ids)
        if (byId[id] case final profile?) profile.id: profile.displayName,
    };
    return LocalEloCalculator().calculate(
      players: players,
      tournaments: tournaments.toList(),
      rankingId: ranking.id,
      startRating: ranking.startRating,
      newPlayerK: ranking.newPlayerK,
      normalPlayerK: ranking.normalPlayerK,
      proPlayerK: ranking.proPlayerK,
      matchesBeforeNormal: ranking.matchesBeforeNormal,
      proRatingThreshold: ranking.proRatingThreshold,
      minimumParticipationTournaments: ranking.requireMinimumParticipations
          ? ranking.minimumParticipations
          : 0,
      allowDecayBelowStartRating: ranking.allowDecayBelowStartRating,
      absenceDecayEnabled: ranking.absenceDecayEnabled,
      absenceDecayPoints: ranking.absenceDecayPoints,
      inactivityDecayEnabled: ranking.inactivityDecayEnabled,
      inactivityGraceTournaments: ranking.inactivityGraceTournaments,
      inactivityDecayPoints: ranking.inactivityDecayPoints,
      validFromYear: ranking.validFromYear,
      validToYear: ranking.validToYear,
      validFromDate: ranking.validFromDate,
      validToDate: ranking.validToDate,
    );
  }
}
