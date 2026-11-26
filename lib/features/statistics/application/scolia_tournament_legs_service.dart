import '../domain/tournament_monthly_results.dart';
import '../../tournaments/data/tournament_storage.dart';

/// Derives the legs shown in the cumulative Scolia entry from the matches
/// that were actually recorded for a player in ranking tournaments.
///
/// Scolia only reports cumulative match counts. The leg count of a month is
/// therefore taken from the local tournament results, while the cumulative
/// match count remains an input of the Scolia measurement point.
class ScoliaTournamentLegsService {
  ScoliaTournamentLegsService({TournamentStorage? storage})
    : _storage = storage ?? TournamentStorage();

  final TournamentStorage _storage;

  Future<int> weightedLegsForMonth({
    required String playerId,
    required int year,
    required int month,
  }) async {
    final tournaments = await _storage.loadTournaments();
    final rated = tournaments.where(
      (tournament) => tournament.countsForRanking,
    );
    final results = const TournamentMonthlyResultCalculator().calculate(
      rated,
      playerIds: {playerId},
    );
    return results
        .where(
          (result) =>
              result.playerId == playerId &&
              result.year == year &&
              result.month == month,
        )
        .fold<int>(0, (sum, result) => sum + result.weightedLegs);
  }
}
