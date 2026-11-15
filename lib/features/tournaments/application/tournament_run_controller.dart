import '../data/tournament_storage.dart';
import '../domain/tournament_models.dart';
import 'tournament_timing.dart';
import 'result_entry_performance_trace.dart';

class TournamentRunController {
  const TournamentRunController({TournamentStorage? storage})
    : _storage = storage;

  final TournamentStorage? _storage;

  Future<void> saveProgress({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
  }) async {
    tournament.activeStageIndex = activeStageIndex;
    tournament.completedStageIndexes
      ..clear()
      ..addAll(completedStageIndexes);
    final storage = _storage ?? TournamentStorage();
    await ResultEntryPerformanceTrace.measureAsync(
      'run_timing_prepare',
      () => TournamentTiming.prepare(tournament),
    );
    await ResultEntryPerformanceTrace.measureAsync(
      'run_archive_save',
      () => storage.saveTournament(tournament),
    );
  }
}
