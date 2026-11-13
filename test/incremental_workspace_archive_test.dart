import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/backups/data/backup_service.dart';
import 'package:dart_tournament_manager/features/backups/data/incremental_workspace_archive.dart';

void main() {
  test('roundtrips all raw tournaments and companion stores losslessly', () {
    final tournamentRoot = {
      'schemaVersion': 42,
      'archiveGeneration': 'local-only-generation',
      'customRootValue': {'preserve': true},
      'tournaments': [
        {
          'id': 'cup-2026',
          'name': 'Cup 2026',
          'finishedAt': '2026-05-01T18:00:00.000Z',
          'players': [
            {'id': 'player-a', 'name': 'A'},
          ],
          'matches': [
            {
              'homeLegs': 3,
              'awayLegs': 2,
              'bestPerformances': [170],
            },
          ],
        },
        {
          'id': 'cup-2025',
          'name': 'Cup 2025',
          'finishedAt': '2025-05-01T18:00:00.000Z',
          'players': [
            {'id': 'player-b', 'name': 'B'},
          ],
          'matches': [
            {
              'homeLegs': 2,
              'awayLegs': 3,
              'bestPerformances': [180],
            },
          ],
        },
      ],
    };
    final stores = <String, Uint8List?>{
      for (final name in BackupService.names) name: null,
      'tournaments.json': Uint8List.fromList(
        utf8.encode(jsonEncode(tournamentRoot)),
      ),
      'app_database.sqlite': Uint8List.fromList([1, 2, 3, 4]),
      'planning_settings.json': Uint8List.fromList(utf8.encode('{"boards":4}')),
    };

    final local = IncrementalWorkspaceArchive.fromStoreFiles(stores);
    final paths = {
      for (final key in local.objects.keys) key: 'user/objects/$key.bin',
    };
    final restored = IncrementalWorkspaceArchive.fromManifest(
      local.toManifest(paths),
    );
    for (final entry in local.objects.entries) {
      restored.objects[entry.key] = entry.value;
    }
    final result = restored.toStoreFiles();
    final restoredRoot =
        jsonDecode(utf8.decode(result['tournaments.json']!))
            as Map<String, dynamic>;

    expect(restoredRoot['customRootValue'], {'preserve': true});
    expect(restoredRoot.containsKey('archiveGeneration'), isFalse);
    expect(restoredRoot['tournaments'], tournamentRoot['tournaments']);
    expect(result['app_database.sqlite'], stores['app_database.sqlite']);
    expect(result['planning_settings.json'], stores['planning_settings.json']);
    expect(result['tournaments.json.v22.bak'], isNull);
  });

  test(
    'rejects duplicate tournament ids instead of silently dropping data',
    () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 42,
            'tournaments': [
              {'id': 'duplicate'},
              {'id': 'duplicate'},
            ],
          }),
        ),
      );
      final stores = {
        for (final name in BackupService.names) name: null,
        'tournaments.json': bytes,
        'app_database.sqlite': Uint8List.fromList([1]),
      };

      expect(
        () => IncrementalWorkspaceArchive.fromStoreFiles(stores),
        throwsFormatException,
      );
    },
  );

  test('marks only new or changed objects for the next upload', () {
    final stores = <String, Uint8List?>{
      for (final name in BackupService.names) name: null,
      'tournaments.json': Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schemaVersion': 42,
            'tournaments': [
              {'id': 'unchanged', 'legs': 12},
              {'id': 'changed', 'legs': 8},
            ],
          }),
        ),
      ),
      'app_database.sqlite': Uint8List.fromList([1, 2]),
    };
    final initial = IncrementalWorkspaceArchive.fromStoreFiles(stores);
    const prefix = 'account/workspace-v3/objects';
    final manifest = initial.toManifest({
      for (final entry in initial.objects.entries)
        entry.key: '$prefix/${sha256.convert(entry.value)}.bin',
    });
    final nextStores = Map<String, Uint8List?>.from(stores);
    nextStores['tournaments.json'] = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 42,
          'tournaments': [
            {'id': 'unchanged', 'legs': 12},
            {'id': 'changed', 'legs': 9},
            {'id': 'new', 'legs': 1},
          ],
        }),
      ),
    );
    final next = IncrementalWorkspaceArchive.fromStoreFiles(nextStores);

    expect(next.changedObjectKeys(manifest, objectPathPrefix: prefix), {
      'tournament:changed',
      'tournament:new',
    });
  });
}
