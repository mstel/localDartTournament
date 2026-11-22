import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/tournament_run_controller.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_trash.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  late Directory directory;
  late File storageFile;
  late TournamentTrash trash;
  late TournamentStorage storage;
  late TournamentRunController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('trash-storage-test-');
    storageFile = File('${directory.path}/tournaments.json');
    trash = TournamentTrash(
      file: File('${directory.path}/tournament_trash.json'),
    );
    storage = TournamentStorage(file: storageFile, trash: trash);
    controller = TournamentRunController(storage: storage);
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  CreatedTournament tournament(String id, {required bool completed}) {
    return CreatedTournament(
      id: id,
      name: 'Turnier $id',
      players: const [],
      stages: const [],
      runStages: const [],
      finishedAt: completed ? DateTime(2026, 11, 20) : null,
    );
  }

  test('completed archive entries survive stale active copies', () async {
    final completed = tournament('completed', completed: true);
    await storage.saveTournament(completed);

    final staleActive = tournament('completed', completed: false);
    await expectLater(
      controller.saveProgress(
        tournament: staleActive,
        activeStageIndex: 0,
        completedStageIndexes: const {},
      ),
      throwsA(isA<StateError>()),
    );

    final restored = (await storage.loadTournaments()).single;
    expect(restored.id, 'completed');
    expect(restored.finishedAt, isNotNull);
    final entries = await trash.list();
    expect(
      entries.any(
        (entry) => entry.reason == TournamentTrashReason.staleActiveCopy,
      ),
      isTrue,
    );
  });

  test('explicit reset keeps the reset result and snapshots the old state',
      () async {
    final completed = tournament('reset-me', completed: true);
    await storage.saveTournament(completed);
    await storage.snapshotTournament(
      completed,
      reason: TournamentTrashReason.reset,
    );

    final reset = tournament('reset-me', completed: false)
      ..reopenedForCorrections = true;
    await controller.saveProgressWithIntent(
      tournament: reset,
      activeStageIndex: 0,
      completedStageIndexes: const {},
      allowUnfinishingCompleted: true,
      trashReason: TournamentTrashReason.reset,
    );

    final restored = (await storage.loadTournaments()).single;
    expect(restored.finishedAt, isNull);
    final entries = await trash.list();
    expect(
      entries.any((entry) => entry.reason == TournamentTrashReason.reset),
      isTrue,
    );
  });

  test('deleting a completed tournament preserves a trash restore point',
      () async {
    final completed = tournament('deleted', completed: true);
    await storage.saveTournament(completed);
    await storage.deleteTournament('deleted');

    expect(await storage.loadTournaments(), isEmpty);
    final entries = await trash.list();
    expect(
      entries.any(
        (entry) =>
            entry.tournamentId == 'deleted' &&
            entry.reason == TournamentTrashReason.deleted,
      ),
      isTrue,
    );
  });

  test('trash file is independent of the tournaments backup', () async {
    final completed = tournament('backup-safe', completed: true);
    await storage.snapshotTournament(
      completed,
      reason: TournamentTrashReason.reopened,
    );
    await storage.snapshotTournament(
      completed,
      reason: TournamentTrashReason.reset,
    );
    final trashFile = await trash.storageFile();
    expect(File('${trashFile.path}.bak').existsSync(), isTrue);
    expect(File('${storageFile.path}.bak').existsSync(), isFalse);
  });
}
