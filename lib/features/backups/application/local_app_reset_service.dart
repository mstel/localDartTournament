import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../../shared/persistence/storage_access.dart';
import '../data/backup_service.dart';
import 'supabase_workspace_sync_service.dart';

/// Resets this installation's local stores after preserving a raw snapshot.
class LocalAppResetService {
  const LocalAppResetService();

  Future<Directory> reset() async {
    final backup = await BackupService.create();
    await SupabaseWorkspaceSyncService.instance
        .pauseSynchronizationForFreshStart();
    return StorageAccess.run(() async {
      final archive = await preserveAndClearStores(
        storeFiles: backup.files.values,
        backupDirectory: backup.backupDirectory,
      );
      StorageAccess.markLocalDataChanged();
      StorageAccess.requireRestart(
        'Die lokalen Daten dieses Geräts wurden zurückgesetzt. Eine bytegetreue Sicherung liegt unter ${archive.path}. Die Cloud-Synchronisierung bleibt pausiert; bitte starte die App neu.',
      );
      return archive;
    });
  }

  static Future<Directory> preserveAndClearStores({
    required Iterable<File> storeFiles,
    required Directory backupDirectory,
    DateTime? now,
  }) async {
    final timestamp = (now ?? DateTime.now())
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final archive = Directory(
      path.join(backupDirectory.path, 'factory-reset-$timestamp'),
    );
    await archive.create(recursive: true);
    final stores = await _collectStoreFiles(storeFiles);
    final snapshots = <(File, List<int>)>[];
    for (final store in stores) {
      snapshots.add((store, await store.readAsBytes()));
    }
    for (final (store, bytes) in snapshots) {
      final destination = File(
        path.join(archive.path, path.basename(store.path)),
      );
      await destination.writeAsBytes(bytes, flush: true);
      final copy = await destination.readAsBytes();
      if (sha256.convert(copy) != sha256.convert(bytes)) {
        throw FileSystemException(
          'Die lokale Sicherung konnte nicht verifiziert werden.',
          destination.path,
        );
      }
    }
    final deleted = <File>[];
    try {
      for (final store in stores) {
        try {
          await store.delete();
          deleted.add(store);
        } catch (_) {
          if (!await store.exists()) deleted.add(store);
          rethrow;
        }
      }
    } catch (error, stackTrace) {
      Object? rollbackError;
      for (final store in deleted.reversed) {
        try {
          await File(
            path.join(archive.path, path.basename(store.path)),
          ).copy(store.path);
        } catch (restoreError) {
          rollbackError ??= restoreError;
        }
      }
      if (rollbackError != null) {
        throw StateError(
          'Zurücksetzen fehlgeschlagen: $error. '
          'Wiederherstellung aus ${archive.path} fehlgeschlagen: $rollbackError',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return archive;
  }

  static Future<List<File>> _collectStoreFiles(
    Iterable<File> storeFiles,
  ) async {
    final files = <String, File>{};
    for (final store in storeFiles) {
      final parent = store.parent;
      if (!await parent.exists()) continue;
      final base = path.basename(store.path);
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = path.basename(entity.path);
        if (name == base ||
            name.startsWith('$base.') ||
            name.startsWith('$base-')) {
          files[entity.path] = entity;
        }
      }
    }
    return files.values.toList(growable: false);
  }
}
