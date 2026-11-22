import '../data/tournament_storage.dart';
import '../data/tournament_trash.dart';
import '../domain/tournament_models.dart';
import 'tournament_timing.dart';
import 'result_entry_performance_trace.dart';

class _SaveProgressIntent {
  const _SaveProgressIntent({
    this.allowUnfinishingCompleted = false,
    this.trashReason,
  });

  final bool allowUnfinishingCompleted;
  final TournamentTrashReason? trashReason;
}

class TournamentRunController {
  TournamentRunController({TournamentStorage? storage}) : _storage = storage;

  final TournamentStorage? _storage;
  _SaveProgressIntent _activeIntent = const _SaveProgressIntent();

  /// Normale Fortschrittssaves dürfen ein abgeschlossenes Turnier nie wieder
  /// öffnen. Die Absicht wird über die überschreibbare [saveProgress]-Methode
  /// gereicht, damit vorhandene Test-Doubles weiterhin greifen.
  Future<void> saveProgress({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
  }) async {
    final intent = _activeIntent;
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
      () => storage.saveTournamentWithIntent(
        tournament,
        allowUnfinishingCompleted: intent.allowUnfinishingCompleted,
        trashReason: intent.trashReason,
      ),
    );
  }

  /// Wie [saveProgress], aber mit expliziter Absicht für destruktive Korrekturen
  /// und Wiederherstellungen.
  Future<void> saveProgressWithIntent({
    required CreatedTournament tournament,
    required int activeStageIndex,
    required Set<int> completedStageIndexes,
    bool allowUnfinishingCompleted = false,
    TournamentTrashReason? trashReason,
  }) async {
    final previous = _activeIntent;
    _activeIntent = _SaveProgressIntent(
      allowUnfinishingCompleted: allowUnfinishingCompleted,
      trashReason: trashReason,
    );
    try {
      await saveProgress(
        tournament: tournament,
        activeStageIndex: activeStageIndex,
        completedStageIndexes: completedStageIndexes,
      );
    } finally {
      _activeIntent = previous;
    }
  }
}
