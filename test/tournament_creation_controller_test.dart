import 'package:dart_tournament_manager/features/tournaments/application/tournament_creation_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new tournaments default to four boards and persist before returning',
    () async {
      final storage = _RecordingTournamentStorage();
      final tournament = await TournamentCreationController(storage: storage)
          .createTournament(
            name: 'Testturnier',
            players: const [],
            stages: const [],
            runStages: const [],
          );

      expect(tournament.boardCount, 4);
      expect(storage.savedTournament, same(tournament));
    },
  );

  test(
    'updating configuration keeps the tournament identity and resets run state',
    () async {
      final storage = _RecordingTournamentStorage();
      final existing = CreatedTournament(
        id: 'existing-id',
        name: 'Altes Turnier',
        players: const [],
        stages: const [],
        runStages: const [],
        activeStageIndex: 1,
        boardCount: 2,
        startedAt: DateTime(2026),
        finishedAt: DateTime(2026),
        pausedAt: DateTime(2026),
        completedStageIndexes: {0},
        blockedBoards: {1},
        totalPausedSeconds: 30,
      );

      final updated = await TournamentCreationController(storage: storage)
          .updateTournament(
            existing,
            name: 'Aktualisiertes Turnier',
            players: const [],
            stages: const [],
            runStages: const [],
            boardCount: 3,
            countsForRanking: false,
            rankingIds: const [],
            settingsChanged: true,
          );

      expect(updated.id, existing.id);
      expect(updated.name, 'Aktualisiertes Turnier');
      expect(updated.boardCount, 3);
      expect(updated.activeStageIndex, 0);
      expect(updated.completedStageIndexes, isEmpty);
      expect(updated.startedAt, isNull);
      expect(updated.finishedAt, isNull);
      expect(updated.pausedAt, isNull);
      expect(updated.blockedBoards, isEmpty);
      expect(updated.totalPausedSeconds, 0);
      expect(storage.savedTournament, same(updated));
    },
  );

  test(
    'updating a tournament with results is rejected without saving',
    () async {
      final storage = _RecordingTournamentStorage();
      final home = TournamentPlayer.generated(1);
      final away = TournamentPlayer.generated(2);
      final existing = CreatedTournament(
        name: 'Turnier mit Ergebnis',
        players: [home, away],
        stages: const [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'KO',
            rounds: [
              [
                GroupMatch(
                  homePlayer: home,
                  awayPlayer: away,
                  round: 1,
                  homeLegs: 2,
                  awayLegs: 1,
                ),
              ],
            ],
          ),
        ],
      );

      final controller = TournamentCreationController(storage: storage);
      expect(controller.hasRecordedResults(existing), isTrue);
      await expectLater(
        controller.updateTournament(
          existing,
          name: 'Überschrieben',
          players: existing.players,
          stages: existing.stages,
          runStages: existing.runStages,
          boardCount: existing.boardCount,
          countsForRanking: existing.countsForRanking,
          rankingIds: existing.rankingIds,
          settingsChanged: false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(storage.savedTournament, isNull);
    },
  );

  test(
    'creating a copy keeps the bracket but clears scores and match state',
    () async {
      final storage = _RecordingTournamentStorage();
      final home = TournamentPlayer.generated(1);
      final away = TournamentPlayer.generated(2);
      final runStage = KnockoutTournamentRunStage(
        name: 'KO',
        rounds: [
          [
            GroupMatch(
              homePlayer: home,
              awayPlayer: away,
              round: 1,
              homeLegs: 2,
              awayLegs: 1,
              boardNumber: 1,
              startedAt: DateTime(2026),
              finishedAt: DateTime(2026),
            ),
          ],
        ],
      );

      final copy = await TournamentCreationController(storage: storage)
          .createTournamentCopy(
            name: 'Kopie',
            players: [home, away],
            stages: const [],
            runStages: [runStage],
          );
      final copiedMatch = (copy.runStages.single as KnockoutTournamentRunStage)
          .rounds
          .single
          .single;

      expect(copy.id, isNotEmpty);
      expect(copiedMatch.homePlayer?.name, home.name);
      expect(copiedMatch.awayPlayer?.name, away.name);
      expect(copiedMatch.hasResult, isFalse);
      expect(copiedMatch.boardNumber, isNull);
      expect(copiedMatch.startedAt, isNull);
      expect(copiedMatch.finishedAt, isNull);
      expect(storage.savedTournament, same(copy));
    },
  );
}

class _RecordingTournamentStorage extends TournamentStorage {
  CreatedTournament? savedTournament;

  @override
  Future<void> saveTournament(CreatedTournament tournament) async {
    savedTournament = tournament;
  }
}
