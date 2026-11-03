import '../data/tournament_storage.dart';

class TournamentActivityLogger {
  const TournamentActivityLogger({TournamentStorage? storage})
    : _storage = storage;

  final TournamentStorage? _storage;

  Future<void> recordRankingRename({
    required String rankingId,
    required String oldName,
    required String newName,
  }) async {
    final storage = _storage ?? TournamentStorage();
    final tournaments = await storage.loadTournaments();
    for (final tournament in tournaments) {
      if (!tournament.rankingIds.contains(rankingId)) continue;
      tournament.addActivity(
        'ranking_name_changed',
        'Ranglistenname geändert: $oldName → $newName',
      );
      await storage.saveTournament(tournament);
    }
  }
}
