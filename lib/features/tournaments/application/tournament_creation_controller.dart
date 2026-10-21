import '../data/tournament_storage.dart';
import '../domain/tournament_models.dart';

class TournamentCreationController {
  const TournamentCreationController({TournamentStorage? storage})
    : _storage = storage;

  final TournamentStorage? _storage;

  CreatedTournament createTournament({
    int boardCount = 4,
    bool countsForRanking = false,
    List<String> rankingIds = const [],
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
  }) {
    final tournament = _buildTournament(
      boardCount: boardCount,
      name: name,
      players: players,
      stages: stages,
      runStages: runStages,
      countsForRanking: countsForRanking,
      rankingIds: rankingIds,
    );
    (_storage ?? TournamentStorage()).saveTournament(tournament);
    return tournament;
  }

  CreatedTournament _buildTournament({
    int boardCount = 4,
    required String name,
    required List<TournamentPlayer> players,
    required List<TournamentStage> stages,
    required List<TournamentRunStage> runStages,
    bool countsForRanking = true,
    List<String> rankingIds = const [],
  }) {
    return CreatedTournament(
      boardCount: boardCount.clamp(1, 64),
      name: name.trim().isEmpty ? 'Neues Turnier' : name.trim(),
      players: List.unmodifiable(players),
      stages: List.unmodifiable(stages),
      runStages: runStages,
      countsForRanking: countsForRanking,
      rankingIds: List.unmodifiable(rankingIds),
    );
  }
}
