import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/backups/data/backup_service.dart';
import 'package:dart_tournament_manager/features/settings/data/planning_settings_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';

void main() {
  late Directory root;
  late BackupService service;
  late TournamentStorage tournaments;
  late LocalAppDatabase database;
  setUp(() async {
    StorageAccess.restartRequired.value = false;
    root = await Directory.systemTemp.createTemp('backup_test_');
    final data = Directory('${root.path}/data');
    await data.create();
    service = BackupService(
      files: {
        for (final name in BackupService.names)
          name: File('${data.path}/$name'),
      },
      backupDirectory: Directory('${data.path}/backups'),
    );
    tournaments = TournamentStorage(file: service.files['tournaments.json']);
    database = LocalAppDatabase(baseDirectory: data);
  });
  tearDown(() async {
    StorageAccess.restartRequired.value = false;
    await root.delete(recursive: true);
  });

  Future<void> seed() async {
    await tournaments.saveTournament(
      CreatedTournament(
        name: 'Gesichert',
        players: [],
        stages: [],
        runStages: [
          KnockoutTournamentRunStage(
            name: 'Finale',
            rounds: [
              [
                GroupMatch(
                    round: 1,
                    homePlayer: TournamentPlayer.generated(1),
                    awayPlayer: TournamentPlayer.generated(2),
                  )
                  ..homeLegs = 2
                  ..awayLegs = 1,
              ],
            ],
          ),
        ],
      ),
    );
    await database.createPlayerProfile(displayName: 'Eigener Spieler');
    await PlanningSettingsStorage(
      file: service.files['planning_settings.json'],
    ).save(
      TournamentPlanningParameters.fromValues({
        PlanningParameter.maximumGroups: 7,
      }),
    );
  }

  test(
    'all active stores roundtrip with results and a pre-restore backup',
    () async {
      await seed();
      final bytes = await service.exportBytes();
      final preview = await service.inspect(bytes);
      expect(preview.tournaments, 1);
      expect(preview.files.length, 3);
      await tournaments.saveTournament(
        CreatedTournament(name: 'Neu', players: [], stages: [], runStages: []),
      );
      final before = await service.files['tournaments.json']!.readAsString();
      final safety = await service.restore(preview);
      expect(StorageAccess.restartRequired.value, isTrue);
      await expectLater(tournaments.loadTournaments(), throwsStateError);
      // Simulate a new process: old controllers cannot continue in the real app.
      StorageAccess.restartRequired.value = false;
      final restored = await tournaments.loadTournaments();
      expect(restored.single.name, 'Gesichert');
      expect(
        (restored.single.runStages.single as KnockoutTournamentRunStage)
            .matches
            .single
            .homeLegs,
        2,
      );
      expect(
        (await database.loadPlayerProfiles()).any(
          (p) => p.displayName == 'Eigener Spieler',
        ),
        isTrue,
      );
      expect(
        (await PlanningSettingsStorage(
          file: service.files['planning_settings.json'],
        ).load()).value(PlanningParameter.maximumGroups),
        7,
      );
      final original =
          jsonDecode(
                await safety.readAsString(),
              )['files']['tournaments.json']['data']
              as String;
      expect(utf8.decode(base64Decode(original)), before);
    },
  );

  test(
    'update backup validates schema 24 without a cross-store proof file',
    () async {
      const current =
          '{"schemaVersion":24,"tournaments":[],"cache":{"marker":"keep"}}';
      final tournamentFile = service.files['tournaments.json']!;
      await tournamentFile.writeAsString(current);

      final bytes = await service.exportBytes();
      final preview = await service.inspect(bytes);

      expect(preview.tournaments, 0);
      expect(await tournamentFile.readAsString(), current);
      final archive = jsonDecode(utf8.decode(bytes)) as Map;
      final saved = base64Decode(
        archive['files']['tournaments.json']['data'] as String,
      );
      expect(utf8.decode(saved), current);
    },
  );

  test(
    'unknown versions, paths and checksums are rejected without writes',
    () async {
      await seed();
      final bytes = await service.exportBytes();
      final before = await service.files['tournaments.json']!.readAsBytes();
      for (final kind in [
        'version',
        'path',
        'checksum',
        'storeVersion',
        'invalidDatabase',
      ]) {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        switch (kind) {
          case 'version':
            json['version'] = 99;
          case 'path':
            (json['files'] as Map)['../outside'] = null;
          case 'checksum':
            json['files']['tournaments.json']['sha256'] = 'wrong';
          case 'storeVersion':
            final data = utf8.encode('{"schemaVersion":99,"tournaments":[]}');
            json['files']['tournaments.json'] = {
              'data': base64Encode(data),
              'sha256': sha256.convert(data).toString(),
            };
          case 'invalidDatabase':
            final data = utf8.encode('not a database');
            json['files']['app_database.sqlite'] = {
              'data': base64Encode(data),
              'sha256': sha256.convert(data).toString(),
            };
        }
        await expectLater(
          service.inspect(utf8.encode(jsonEncode(json))),
          throwsA(anything),
        );
        expect(await service.files['tournaments.json']!.readAsBytes(), before);
      }
    },
  );

  test('interrupted restore is rolled back on next startup', () async {
    await seed();
    final bytes = await service.exportBytes();
    final journal = File(
      '${service.backupDirectory.path}/restore_transaction/original.dartbackup',
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsBytes(bytes);
    await service.files['tournaments.json']!.writeAsString('interrupted');
    await service.recoverInterruptedRestore();
    expect((await tournaments.loadTournaments()).single.name, 'Gesichert');
    expect(await journal.parent.exists(), isFalse);
  });

  test('committed restore is retained during startup cleanup', () async {
    await seed();
    final journal = File(
      '${service.backupDirectory.path}/restore_transaction/original.dartbackup',
    );
    await journal.parent.create(recursive: true);
    await journal.writeAsBytes(await service.exportBytes());
    await File('${journal.parent.path}/committed').writeAsString('1');
    await tournaments.saveTournament(
      CreatedTournament(name: 'Neu', players: [], stages: [], runStages: []),
    );
    await service.recoverInterruptedRestore();
    expect((await tournaments.loadTournaments()).length, 2);
  });

  test('failure after first replacement restores original files', () async {
    await seed();
    final preview = await service.inspect(await service.exportBytes());
    await tournaments.saveTournament(
      CreatedTournament(name: 'Neu', players: [], stages: [], runStages: []),
    );
    final before = await service.files['tournaments.json']!.readAsString();
    final blocker = File('${root.path}/not_a_directory');
    await blocker.writeAsString('block');
    final brokenDestination = BackupService(
      files: {
        ...service.files,
        'app_database.sqlite': File('${blocker.path}/app_database.sqlite'),
      },
      backupDirectory: service.backupDirectory,
    );
    await expectLater(
      brokenDestination.restore(preview),
      throwsA(isA<FileSystemException>()),
    );
    expect(await service.files['tournaments.json']!.readAsString(), before);
    expect(StorageAccess.restartRequired.value, isFalse);
  });

  test(
    'backup waits for writes and later writes cannot overwrite a restore',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final writing = StorageAccess.run(() async {
        entered.complete();
        await release.future;
        await seed();
      });
      await entered.future;
      var exported = false;
      final backup = service.exportBytes().then((bytes) {
        exported = true;
        return bytes;
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(exported, isFalse);
      release.complete();
      await writing;
      final preview = await service.inspect(await backup);
      final restoring = service.restore(preview);
      final lateWrite = tournaments.saveTournament(
        CreatedTournament(
          id: 'stale',
          name: 'Stale write',
          players: const [],
          stages: const [],
          runStages: const [],
        ),
      );
      await expectLater(lateWrite, throwsStateError);
      await restoring;
    },
  );

  test(
    'concurrent settings writes remain valid and missing stores reset',
    () async {
      final empty = await service.inspect(await service.exportBytes());
      await seed();
      await Future.wait(
        List.generate(
          12,
          (i) =>
              PlanningSettingsStorage(
                file: service.files['planning_settings.json'],
              ).save(
                TournamentPlanningParameters.fromValues({
                  PlanningParameter.maximumGroups: i + 1,
                }),
              ),
        ),
      );
      expect(
        (await PlanningSettingsStorage(
          file: service.files['planning_settings.json'],
        ).load()).value(PlanningParameter.maximumGroups),
        12,
      );
      await service.restore(empty);
      for (final file in service.files.values) {
        expect(await file.exists(), isFalse);
      }
    },
  );

  test('export cannot overwrite app stores', () async {
    await seed();
    await expectLater(
      service.exportTo(service.files['tournaments.json']!),
      throwsFormatException,
    );
    final destination = File('${root.path}/external.dartbackup');
    await service.exportTo(destination);
    expect(
      (await service.inspect(await destination.readAsBytes())).tournaments,
      1,
    );
  });
}
