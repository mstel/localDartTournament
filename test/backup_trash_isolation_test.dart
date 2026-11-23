import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/backups/data/backup_service.dart';
import 'package:dart_tournament_manager/features/backups/data/incremental_workspace_archive.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_trash.dart'
    show TournamentTrash, TournamentTrashReason;
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';

void main() {
  late Directory root;
  late BackupService service;
  late TournamentStorage storage;
  late TournamentTrash trash;

  setUp(() async {
    StorageAccess.restartRequired.value = false;
    root = await Directory.systemTemp.createTemp('backup_trash_isolation_');
    final data = Directory('${root.path}${Platform.pathSeparator}data')
      ..createSync(recursive: true);
    service = BackupService(
      files: {
        for (final name in BackupService.names)
          name: File('${data.path}${Platform.pathSeparator}$name'),
      },
      backupDirectory: Directory('${data.path}${Platform.pathSeparator}backups'),
    );
    storage = TournamentStorage(file: service.files['tournaments.json']);
    trash = TournamentTrash(
      file: File(
        '${data.path}${Platform.pathSeparator}tournament_trash.json',
      ),
    );
  });

  tearDown(() async {
    StorageAccess.restartRequired.value = false;
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('trash is local-only and restoring reactivates the tournament', () async {
    const name = 'Nur im Papierkorb';
    final completed = CreatedTournament(
      id: 'trash-only',
      name: name,
      players: const [],
      stages: const [],
      runStages: const [],
      finishedAt: DateTime.utc(2026, 10, 20),
    );
    await storage.saveTournament(completed);
    await storage.deleteTournament(completed.id);

    expect(await storage.loadTournaments(), isEmpty);
    final trashFile = await trash.storageFile();
    expect(await trashFile.exists(), isTrue);
    final entries = await trash.list();
    expect(entries, isNotEmpty);
    expect(
      entries.every((entry) => entry.tournamentId == completed.id),
      isTrue,
    );

    expect(BackupService.names, isNot(contains('tournament_trash.json')));

    final bytes = await service.exportBytes();
    final backup = jsonDecode(utf8.decode(bytes)) as Map;
    final files = backup['files'] as Map;
    expect(files.keys, isNot(contains('tournament_trash.json')));
    final exportedTournaments = utf8.decode(
      base64Decode(files['tournaments.json']['data'] as String),
    );
    expect(exportedTournaments, isNot(contains(name)));

    // This is the same snapshot that SupabaseWorkspaceSyncService uploads.
    final storeFiles = await service.exportStoreFiles();
    expect(storeFiles.keys.toSet(), BackupService.names.toSet());
    final incremental = IncrementalWorkspaceArchive.fromStoreFiles(storeFiles);
    expect(
      incremental.objects.keys,
      isNot(contains('store:tournament_trash.json')),
    );
    expect(incremental.tournamentOrder, isEmpty);
    final manifest = incremental.toManifest({
      for (final key in incremental.objects.keys) key: 'objects/$key',
    });
    expect(jsonEncode(manifest), isNot(contains('tournament_trash')));
    expect(
      incremental.toStoreFiles().keys,
      isNot(contains('tournament_trash.json')),
    );

    final entry = entries.singleWhere(
      (item) => item.reason == TournamentTrashReason.deleted,
    );
    await storage.saveTournamentWithIntent(
      entry.toTournament(),
      allowUnfinishingCompleted: true,
    );
    await trash.remove(entry.entryId);

    expect((await storage.loadTournaments()).single.id, completed.id);
    final restoredBytes = await service.exportBytes();
    final restoredBackup = jsonDecode(utf8.decode(restoredBytes)) as Map;
    final restoredTournaments = utf8.decode(
      base64Decode(
        (restoredBackup['files'] as Map)['tournaments.json']['data'] as String,
      ),
    );
    expect(restoredTournaments, contains(completed.id));
  });
}
