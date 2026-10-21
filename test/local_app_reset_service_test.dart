import 'dart:io';

import 'package:dart_tournament_manager/features/backups/application/local_app_reset_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local_reset_test_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'archives raw stores and sidecars before deleting only active copies',
    () async {
      final data = Directory('${root.path}/account')..createSync();
      final backupDirectory = Directory('${data.path}/backups');
      final files = <String, List<int>>{
        'tournaments.json': '[{"schemaVersion":24}]'.codeUnits,
        'tournaments.json.v22.bak': '{"schemaVersion":22}'.codeUnits,
        'tournaments.json.v23.bak': '{"schemaVersion":23}'.codeUnits,
        'tournaments.json.bak': 'separate backup'.codeUnits,
        'app_database.sqlite': [0, 1, 2, 255],
        'app_database.sqlite-wal': [3, 4, 5],
        'planning_settings.json': '{"format":99}'.codeUnits,
      };
      for (final entry in files.entries) {
        await File('${data.path}/${entry.key}').writeAsBytes(entry.value);
      }
      await backupDirectory.create();
      final priorBackup = File('${backupDirectory.path}/existing.dartbackup');
      await priorBackup.writeAsString('keep');
      final storeFiles = [
        File('${data.path}/tournaments.json'),
        File('${data.path}/tournaments.json.v22.bak'),
        File('${data.path}/app_database.sqlite'),
        File('${data.path}/planning_settings.json'),
      ];

      final archive = await LocalAppResetService.preserveAndClearStores(
        storeFiles: storeFiles,
        backupDirectory: backupDirectory,
        now: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      for (final entry in files.entries) {
        expect(
          await File('${archive.path}/${entry.key}').readAsBytes(),
          entry.value,
          reason: '${entry.key} is preserved byte-for-byte',
        );
        expect(await File('${data.path}/${entry.key}').exists(), isFalse);
      }
      expect(await priorBackup.readAsString(), 'keep');
    },
  );

  test(
    'keeps source stores when a recovery snapshot cannot be created',
    () async {
      final data = Directory('${root.path}/account')..createSync();
      final backupDirectory = Directory('${root.path}/backups')..createSync();
      final source = File('${data.path}/tournaments.json');
      final bytes = '{"schemaVersion":24,"unreadable":true}'.codeUnits;
      await source.writeAsBytes(bytes);
      final timestamp = DateTime.utc(
        2026,
        1,
        2,
        3,
        4,
        5,
      ).toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      await File(
        '${backupDirectory.path}/factory-reset-$timestamp',
      ).writeAsString('block snapshot directory creation');

      await expectLater(
        LocalAppResetService.preserveAndClearStores(
          storeFiles: [source],
          backupDirectory: backupDirectory,
          now: DateTime.utc(2026, 1, 2, 3, 4, 5),
        ),
        throwsA(anything),
      );

      expect(await source.readAsBytes(), bytes);
    },
  );
}
