import '../domain/local_elo_calculator.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
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
    final tournaments = await (_tournamentStorage ?? TournamentStorage())
        .loadTournaments();
    return LocalEloCalculator().calculate(
      players: players,
      tournaments: tournaments,
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
