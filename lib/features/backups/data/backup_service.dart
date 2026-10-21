import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:sqlite3/sqlite3.dart';

import '../../../shared/persistence/storage_access.dart';
import '../../settings/data/planning_settings_storage.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';

class BackupPreview {
  BackupPreview(this.createdAt, this.tournaments, this.files, List<int> bytes)
    : _bytes = Uint8List.fromList(bytes);
  final DateTime createdAt;
  final int tournaments;
  final List<String> files;
  final Uint8List _bytes;
}

/// Fixed file allowlist: archive entries can never specify destination paths.
class BackupService {
  BackupService({
    required Map<String, File> files,
    required this.backupDirectory,
  }) : files = Map.unmodifiable(files) {
    if (files.length != names.length ||
        !files.keys.toSet().containsAll(names)) {
      throw ArgumentError('Unvollständige Speicherorte');
    }
  }

  static const names = [
    'tournaments.json',
    'tournaments.json.v22.bak',
    'app_database.sqlite',
    'planning_settings.json',
  ];
  static const categoryNames = [
    'tournaments.json',
    'app_database.sqlite',
    'planning_settings.json',
  ];
  static const maximumBytes = 128 * 1024 * 1024;
  final Map<String, File> files;
  final Directory backupDirectory;
  Directory get _transaction =>
      Directory(path.join(backupDirectory.path, 'restore_transaction'));

  static Future<BackupService> create() async {
    final tournaments = await TournamentStorage().storageFile();
    return BackupService(
      files: {
        names[0]: tournaments,
        names[1]: await LocalAppDatabase().databaseFile(),
        names[2]: await PlanningSettingsStorage().storageFile(),
      },
      backupDirectory: Directory(path.join(tournaments.parent.path, 'backups')),
    );
  }

  Future<Uint8List> exportBytes({Set<String>? categories}) =>
      StorageAccess.run(() async {
        final snapshot = await _snapshot(
          consistentDatabase: true,
          categories: categories,
        );
        final bytes = _encode(snapshot);
        await inspect(bytes);
        return bytes;
      });

  Future<void> exportTo(
    File destination, {
    Set<String>? categories,
  }) => StorageAccess.run(() async {
    // A save dialog must not be able to replace live stores or recovery files.
    final parent = await destination.parent.resolveSymbolicLinks();
    for (final store in files.values) {
      await store.parent.create(recursive: true);
      final root = await store.parent.resolveSymbolicLinks();
      if (path.equals(root, parent) || path.isWithin(root, parent)) {
        throw const FormatException(
          'Bitte außerhalb des App-Datenordners speichern.',
        );
      }
    }
    final bytes = await exportBytes(categories: categories);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
  });

  Future<Map<String, Uint8List?>> _snapshot({
    bool consistentDatabase = false,
    Set<String>? categories,
  }) async {
    final result = <String, Uint8List?>{};
    for (final entry in files.entries) {
      if (categories != null &&
          !categories.contains(entry.key) &&
          !(entry.key == 'tournaments.json.v22.bak' &&
              categories.contains('tournaments.json'))) {
        continue;
      }
      if (!await entry.value.exists()) {
        result[entry.key] = null;
      } else if (consistentDatabase && entry.key == 'app_database.sqlite') {
        final temporary = await Directory.systemTemp.createTemp(
          'dart_backup_sqlite_',
        );
        try {
          final database = sqlite3.open(
            entry.value.path,
            mode: OpenMode.readOnly,
          );
          try {
            final copy = File(path.join(temporary.path, 'snapshot.sqlite'));
            database.execute('VACUUM INTO ?', [copy.path]);
            result[entry.key] = await copy.readAsBytes();
          } finally {
            database.close();
          }
        } finally {
          await temporary.delete(recursive: true);
        }
      } else {
        result[entry.key] = await entry.value.readAsBytes();
      }
    }
    return result;
  }

  Uint8List _encode(Map<String, Uint8List?> snapshot) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'app': 'dart-tournament-backup',
          'version': 1,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'files': {
            for (final entry in snapshot.entries)
              entry.key: entry.value == null
                  ? null
                  : {
                      'sha256': sha256.convert(entry.value!).toString(),
                      'data': base64Encode(entry.value!),
                    },
          },
        }),
      ),
    );
    if (bytes.length > maximumBytes) {
      throw const FormatException('Backup ist größer als 128 MB.');
    }
    return bytes;
  }

  Map<String, Uint8List?> _decode(List<int> bytes) {
    if (bytes.length > maximumBytes) {
      throw const FormatException('Backup ist größer als 128 MB.');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json['app'] != 'dart-tournament-backup' ||
        json['version'] != 1 ||
        json['createdAt'] is! String ||
        DateTime.tryParse(json['createdAt'] as String) == null ||
        json['files'] is! Map) {
      throw const FormatException('Unbekanntes oder neueres Backupformat.');
    }
    final entries = json['files'] as Map;
    final keys = entries.keys.cast<String>().toSet();
    final validKeys = keys.isNotEmpty && keys.every((k) => names.contains(k));
    if (!validKeys) {
      throw const FormatException(
        'Backup enthält keine oder unbekannte Dateien.',
      );
    }
    final result = <String, Uint8List?>{};
    for (final name in names) {
      if (!entries.containsKey(name)) {
        result[name] = null;
        continue;
      }
      final entry = entries[name];
      if (entry == null) {
        result[name] = null;
        continue;
      }
      if (entry is! Map ||
          entry['data'] is! String ||
          entry['sha256'] is! String) {
        throw const FormatException('Ungültiger Backupeintrag.');
      }
      final data = base64Decode(entry['data'] as String);
      if (sha256.convert(data).toString() != entry['sha256']) {
        throw FormatException('Prüfsumme stimmt nicht: $name');
      }
      result[name] = data;
    }
    return result;
  }

  Future<BackupPreview> inspect(List<int> bytes) => StorageAccess.run(() async {
    final snapshot = _decode(bytes);
    final temporary = await Directory.systemTemp.createTemp(
      'dart_backup_check_',
    );
    var count = 0;
    try {
      for (final entry in snapshot.entries) {
        if (entry.value == null) continue;
        final file = File(path.join(temporary.path, entry.key));
        await file.writeAsBytes(entry.value!, flush: true);
      }
      for (final entry in snapshot.entries) {
        if (entry.value == null) continue;
        final file = File(path.join(temporary.path, entry.key));
        switch (entry.key) {
          case 'tournaments.json':
            count = (await TournamentStorage(
              file: file,
            ).loadTournaments()).length;
          case 'tournaments.json.v22.bak':
            break;
          case 'planning_settings.json':
            await PlanningSettingsStorage(file: file).load();
          case 'app_database.sqlite':
            final database = sqlite3.open(file.path, mode: OpenMode.readOnly);
            try {
              final version =
                  database.select('PRAGMA user_version').first.values.single
                      as int;
              if (version < 1 ||
                  version > LocalAppDatabase.schemaVersion ||
                  database.select('PRAGMA quick_check').single.values.single !=
                      'ok') {
                throw const FormatException(
                  'Datenbank beschädigt oder aus neuerer App-Version.',
                );
              }
            } finally {
              database.close();
            }
            // Exercise actual migrations and queries on an isolated copy only.
            final store = LocalAppDatabase(baseDirectory: temporary);
            await store.loadPlayerProfiles();
        }
      }
      final json = jsonDecode(utf8.decode(bytes)) as Map;
      return BackupPreview(
        DateTime.parse(json['createdAt'] as String),
        count,
        List.unmodifiable(snapshot.keys.where((key) => snapshot[key] != null)),
        bytes,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  /// Original bytes are kept even if the current store is damaged.
  /// A journal allows startup to undo an interrupted multi-file replacement.
  Future<File> restore(
    BackupPreview preview, {
    bool restartApp = true,
    Set<String>? selectedCategories,
  }) => StorageAccess.run(() async {
    await inspect(preview._bytes);
    final replacement = _decode(preview._bytes);
    await recoverInterruptedRestore();
    final original = await _snapshot();
    await backupDirectory.create(recursive: true);
    final safety = File(
      path.join(
        backupDirectory.path,
        'before_restore_${DateTime.now().microsecondsSinceEpoch}.dartbackup',
      ),
    );
    await safety.writeAsBytes(_encode(original), flush: true);
    await _transaction.create(recursive: true);
    final journal = File(path.join(_transaction.path, 'original.dartbackup'));
    final journalTemporary = File('${journal.path}.tmp');
    await journalTemporary.writeAsBytes(_encode(original), flush: true);
    await journalTemporary.rename(journal.path);
    try {
      final selectedNames = selectedCategories == null
          ? null
          : Set<String>.from(selectedCategories);
      if (selectedNames != null &&
          selectedNames.contains('tournaments.json') &&
          replacement['tournaments.json.v22.bak'] != null) {
        selectedNames.add('tournaments.json.v22.bak');
      }
      await _install(replacement, selectedNames: selectedNames);
      final committed = File(path.join(_transaction.path, 'committed.tmp'));
      await committed.writeAsString('1', flush: true);
      await committed.rename(path.join(_transaction.path, 'committed'));
    } catch (_) {
      try {
        await _install(original);
        await _transaction.delete(recursive: true);
      } catch (_) {
        StorageAccess.requireRestart(
          'Wiederherstellung unterbrochen. Bitte App schließen. '
          'Beim nächsten Start wird der vorherige Stand wiederhergestellt. '
          'Die Sicherung liegt unter ${safety.path}.',
        );
        rethrow;
      }
      rethrow;
    }
    if (restartApp) {
      StorageAccess.requireRestart(
        'Backup wiederhergestellt. Bitte schließe die App und starte sie neu. '
        'Sicherung des vorherigen Stands:\n${safety.path}',
      );
    } else {
      StorageAccess.replaceSession();
    }
    // A committed journal is safe to clean up at the next startup as well.
    try {
      await _transaction.delete(recursive: true);
    } on FileSystemException {
      /* retry at startup */
    }
    return safety;
  });

  Future<void> recoverInterruptedRestore() => StorageAccess.run(() async {
    final journal = File(path.join(_transaction.path, 'original.dartbackup'));
    if (!await journal.exists()) return;
    if (!await File(path.join(_transaction.path, 'committed')).exists()) {
      await _install(_decode(await journal.readAsBytes()));
    }
    await _transaction.delete(recursive: true);
  });

  Future<void> _install(
    Map<String, Uint8List?> snapshot, {
    Set<String>? selectedNames,
  }) async {
    for (final name in names) {
      if (selectedNames != null && !selectedNames.contains(name)) {
        continue;
      }
      final target = files[name]!;
      final data = snapshot[name];
      if (data == null) {
        if (await target.exists()) await target.delete();
      } else {
        await target.parent.create(recursive: true);
        final temporary = File('${target.path}.restore.tmp');
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename(target.path);
      }
    }
  }
}
