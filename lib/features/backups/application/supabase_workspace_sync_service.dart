import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/persistence/app_data_directory.dart';
import '../../../shared/persistence/storage_access.dart';
import '../data/backup_service.dart';
import '../data/supabase_backup_repository.dart';
import '../../website/application/website_read_model_service.dart';

/// Keeps one private complete workspace per authenticated Supabase account.
/// Cloud synchronization is user-triggered; local edits stay on this device
/// until the user synchronizes or uploads them.
class SupabaseWorkspaceSyncService {
  static final instance = SupabaseWorkspaceSyncService._();
  static const _localOnlyPreview = bool.fromEnvironment(
    'LOCAL_ONLY_PREVIEW',
    defaultValue: false,
  );

  SupabaseWorkspaceSyncService._() : _repository = SupabaseBackupRepository();

  SupabaseWorkspaceSyncService({SupabaseBackupRepository? repository})
    : _repository = repository ?? SupabaseBackupRepository();

  static final status = ValueNotifier<String>('Lokale Daten sind bereit');
  final SupabaseBackupRepository _repository;
  bool _busy = false;
  bool _pausePending = false;
  bool _started = false;
  int _localChangeRevision = 0;
  Future<void> _pendingLocalChangeWrite = Future<void>.value();
  late final VoidCallback _changeListener = _onLocalChange;

  void start() {
    if (_started) return;
    _started = true;
    StorageAccess.localDataRevision.addListener(_changeListener);
    unawaited(_prepareLocalWorkspace());
  }

  Future<void> activateAccount(String? accountId) async {
    if (accountId == null || _localOnlyPreview) {
      if (accountId == null) {
        status.value =
            'Lokal gespeichert · Cloud-Abgleich nur nach Anmeldung manuell';
      }
      return;
    }
    final accountDirectory = await appDataDirectory();
    final stateFile = File(
      path.join(accountDirectory.path, 'supabase_sync_state.json'),
    );
    final localWorkspaceExists =
        await File(
          path.join(accountDirectory.path, 'tournaments.json'),
        ).exists() ||
        await File(
          path.join(accountDirectory.path, 'app_database.sqlite'),
        ).exists();
    final legacyDirectory = await appDataDirectory(
      includeSupabaseAccount: false,
    );
    final ownerMarker = File(
      path.join(legacyDirectory.path, 'supabase_workspace_owner'),
    );
    if (localWorkspaceExists) {
      await copyMatchingSchema24Proof(
        activeTournamentFile: File(
          path.join(accountDirectory.path, 'tournaments.json'),
        ),
        sourceProofFile: File(
          path.join(legacyDirectory.path, 'tournaments.json.v22.bak'),
        ),
      );
      await ownerMarker.parent.create(recursive: true);
      if (!await ownerMarker.exists()) {
        await ownerMarker.writeAsString(accountId, flush: true);
      }
      // A previous app version may already have created this account's local
      // files without sync metadata. Treat them as unsynced edits so an older
      // cloud snapshot cannot silently replace them on first launch.
      if (!await stateFile.exists()) {
        await _writeState({'dirty': true});
      }
      final state = await _readState();
      if (state['syncPaused'] == true &&
          await _hasLocalTournamentData(accountDirectory)) {
        state
          ..remove('syncPaused')
          ..['dirty'] = true;
        await _writeState(state);
      }
      await _setManualSyncStatus();
      return;
    }
    if (await ownerMarker.exists()) {
      await _setManualSyncStatus();
      return;
    }
    // Claim the old local-only workspace once. Do not seed another Supabase
    // account from the same legacy data directory. Any existing cloud
    // snapshot is checked only after the user starts a manual sync.
    final files = [
      'tournaments.json',
      'app_database.sqlite',
      'planning_settings.json',
    ];
    var copied = false;
    for (final name in files) {
      final source = File(path.join(legacyDirectory.path, name));
      if (!await source.exists()) continue;
      final target = File(path.join(accountDirectory.path, name));
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      copied = true;
    }
    final legacyTournamentFile = File(
      path.join(legacyDirectory.path, 'tournaments.json'),
    );
    final accountTournamentFile = File(
      path.join(accountDirectory.path, 'tournaments.json'),
    );
    if (await legacyTournamentFile.exists()) {
      final sourceProof = File('${legacyTournamentFile.path}.v22.bak');
      final targetProof = File('${accountTournamentFile.path}.v22.bak');
      if (await sourceProof.exists() && !await targetProof.exists()) {
        await sourceProof.copy(targetProof.path);
      }
    }
    await ownerMarker.parent.create(recursive: true);
    await ownerMarker.writeAsString(accountId, flush: true);
    if (copied) {
      final state = await _readState();
      state['dirty'] = true;
      await _writeState(state);
    }
    // The state file is account-scoped; creating it here also makes a later
    // sync distinguish this account from the legacy local-only store.
    if (!await stateFile.exists()) await _writeState({'dirty': copied});
    await _setManualSyncStatus();
  }

  /// Copies only a genuine matching schema-22 proof; never replaces a proof.
  static Future<bool> copyMatchingSchema24Proof({
    required File activeTournamentFile,
    required File sourceProofFile,
  }) async {
    final targetProofFile = File('${activeTournamentFile.path}.v22.bak');
    if (await targetProofFile.exists() ||
        !await activeTournamentFile.exists() ||
        !await sourceProofFile.exists()) {
      return false;
    }

    final current = jsonDecode(await activeTournamentFile.readAsString());
    final proof = jsonDecode(await sourceProofFile.readAsString());
    if (current is! Map<String, dynamic> ||
        current['schemaVersion'] != 24 ||
        proof is! Map<String, dynamic> ||
        proof['schemaVersion'] != 22) {
      return false;
    }
    final currentComparable = Map<String, dynamic>.from(current)
      ..remove('schemaVersion');
    final proofComparable = Map<String, dynamic>.from(proof)
      ..remove('schemaVersion');
    if (!_sameJsonValue(currentComparable, proofComparable)) return false;

    await sourceProofFile.copy(targetProofFile.path);
    return true;
  }

  Future<void> _prepareLocalWorkspace() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) await activateAccount(user.id);
      final state = await _readState();
      status.value = state['dirty'] == true
          ? 'Lokale Änderungen · Cloud-Abgleich manuell ausstehend'
          : user == null
          ? 'Lokal gespeichert · Cloud-Abgleich nur manuell'
          : 'Bereit · Cloud-Abgleich nur manuell';
    } catch (error) {
      status.value = 'Lokale Daten bereit · Cloud-Abgleich nur manuell: $error';
    }
  }

  void _onLocalChange() {
    _localChangeRevision++;
    _pendingLocalChangeWrite = _pendingLocalChangeWrite.then<void>(
      (_) => _markDirtyAndResumeIfReady(),
      onError: (Object _, StackTrace _) => _markDirtyAndResumeIfReady(),
    );
    unawaited(
      _pendingLocalChangeWrite.catchError((Object error) {
        status.value = 'Lokale Änderung konnte nicht vorgemerkt werden: $error';
      }),
    );
  }

  Future<void> _markDirtyAndResumeIfReady() async {
    await _setDirty(true);
    status.value = 'Lokale Änderungen · Cloud-Abgleich manuell ausstehend';
    String? accountId;
    try {
      accountId = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return;
    }
    if (accountId == null) return;
    final directory = await appDataDirectory();
    if (!await _hasLocalTournamentData(directory)) return;
    final state = await _readState();
    if (state['syncPaused'] != true) return;
    state
      ..remove('syncPaused')
      ..['dirty'] = true;
    await _writeState(state);
    status.value = 'Lokale Änderungen · Cloud-Abgleich manuell ausstehend';
  }

  Future<bool> _hasLocalTournamentData(Directory directory) async {
    return hasLocalTournamentData(
      File(path.join(directory.path, 'tournaments.json')),
    );
  }

  @visibleForTesting
  static Future<bool> hasLocalTournamentData(File file) async {
    if (!await file.exists()) return false;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final tournaments = decoded['tournaments'];
      return tournaments is List &&
          tournaments.isNotEmpty &&
          tournaments.every((item) => item is Map<String, dynamic>);
    } on FormatException {
      return false;
    }
  }

  Future<File> get _stateFile async => File(
    path.join((await appDataDirectory()).path, 'supabase_sync_state.json'),
  );

  Future<Map<String, dynamic>> _readState() async {
    final file = await _stateFile;
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, dynamic> ? json : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeState(Map<String, dynamic> value) async {
    final file = await _stateFile;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }

  Future<void> _setManualSyncStatus() async {
    final state = await _readState();
    status.value = state['dirty'] == true
        ? 'Lokale Änderungen · Cloud-Abgleich manuell ausstehend'
        : 'Bereit · Cloud-Abgleich nur manuell';
  }

  Future<void> _setDirty(bool dirty) async {
    final state = await _readState();
    state['dirty'] = dirty;
    if (dirty) {
      state['lastLocalChangeAt'] = DateTime.now().toUtc().toIso8601String();
    }
    await _writeState(state);
  }

  Future<void> synchronize() async {
    if (_localOnlyPreview) {
      status.value =
          'Lokaler Testmodus · automatische Cloud-Synchronisierung ist deaktiviert';
      return;
    }
    if (_pausePending) {
      status.value =
          'Cloud-Abgleich nicht gestartet · ein lokaler Neustart wird vorbereitet';
      return;
    }
    if (_busy) {
      status.value =
          'Cloud-Abgleich nicht gestartet · ein anderer Cloud-Vorgang läuft bereits';
      return;
    }
    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        status.value = 'Nicht angemeldet · lokal gespeichert';
        return;
      }
    } catch (error) {
      status.value = 'Supabase-Anmeldung konnte nicht geprüft werden: $error';
      return;
    }
    _busy = true;
    status.value = 'Prüfe Cloud-Datenstand …';
    try {
      await _pendingLocalChangeWrite;
      final localRevision = _localChangeRevision;
      final state = await _readState();
      if (state['syncPaused'] == true) {
        status.value =
            'Synchronisierung pausiert · neuer lokaler Datenstand bleibt auf diesem Gerät';
        return;
      }
      final hasIncrementalWorkspace = await _repository
          .hasIncrementalWorkspace();
      final remoteUpdatedAt = await _repository.backupUpdatedAt();
      if (!hasIncrementalWorkspace) {
        if (remoteUpdatedAt == null) {
          await _push();
          return;
        }
        final legacyLastSynced = DateTime.tryParse(
          '${state['lastSyncedAt'] ?? ''}',
        );
        if (state['dirty'] == true) {
          final accountDirectory = await appDataDirectory();
          final localHasTournamentData = await hasLocalTournamentData(
            File(path.join(accountDirectory.path, 'tournaments.json')),
          );
          if (!localHasTournamentData ||
              legacyLastSynced == null ||
              remoteUpdatedAt.isAfter(legacyLastSynced)) {
            status.value =
                'Cloud und dieses Gerät haben Änderungen · vor der Archivmigration bitte einen Stand auswählen';
            return;
          }
          await _push();
          return;
        }
        status.value = 'Migriere das vorhandene Cloud-Backup …';
        final backups = await BackupService.create();
        final legacy = await _repository.download(backups);
        await backups.restore(legacy, restartApp: false);
        await _writeState({'dirty': true});
        await _push();
        return;
      }
      if (remoteUpdatedAt == null) {
        await _push();
        return;
      }
      final lastSynced = DateTime.tryParse('${state['lastSyncedAt'] ?? ''}');
      final remoteIsNewer =
          lastSynced == null || remoteUpdatedAt.isAfter(lastSynced);
      if (state['dirty'] == true) {
        if (remoteIsNewer) {
          status.value =
              'Cloud und dieses Gerät haben Änderungen · Abgleich erforderlich';
          return;
        }
        await _push();
        return;
      }
      if (remoteIsNewer) {
        await _pendingLocalChangeWrite;
        if (localRevision != _localChangeRevision) {
          status.value =
              'Lokale Änderungen während des Abgleichs · Cloud-Stand nicht geladen';
          return;
        }
        status.value = 'Lade neueren Datenstand aus Supabase …';
        final backups = await BackupService.create();
        final localSnapshot = await StorageAccess.run(backups.exportStoreFiles);
        if (localRevision != _localChangeRevision) {
          status.value =
              'Lokale Änderungen während des Abgleichs · Cloud-Stand nicht geladen';
          return;
        }
        final remote = await _repository.downloadChangedObjects(
          backups,
          currentFiles: localSnapshot,
        );
        await backups.restore(remote, restartApp: false);
        await _publishWebsiteReadModel();
        final downloadedUpdatedAt =
            await _repository.backupUpdatedAt() ?? remoteUpdatedAt;
        await _writeState({
          'dirty': false,
          'lastSyncedAt': downloadedUpdatedAt.toUtc().toIso8601String(),
        });
        status.value = 'Aktueller Datenstand aus Supabase geladen';
      } else {
        if (!await _repository.hasWebsiteReadModel() ||
            !await _repository.hasWebsiteTournamentIndex() ||
            !await _repository.hasWebsiteResources()) {
          await _publishWebsiteReadModel();
        }
        status.value = 'Mit Supabase synchronisiert';
      }
    } catch (error) {
      status.value = 'Synchronisierung wartet auf Verbindung: $error';
    } finally {
      _busy = false;
    }
  }

  static bool _sameJsonValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key) ||
            !_sameJsonValue(entry.value, right[entry.key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameJsonValue(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }

  Future<void> _push() async {
    status.value = 'Sichere Änderungen in Supabase …';
    var preparedRevision = _localChangeRevision;
    var website = await _createWebsiteReadModel();
    late ({Map<String, Uint8List?> files, int revision}) snapshot;
    late BackupService backups;
    while (true) {
      await _pendingLocalChangeWrite;
      if (preparedRevision != _localChangeRevision) {
        preparedRevision = _localChangeRevision;
        website = await _createWebsiteReadModel();
        continue;
      }
      backups = await BackupService.create();
      snapshot = await StorageAccess.run(() async {
        final files = await backups.exportStoreFiles();
        return (files: files, revision: _localChangeRevision);
      });
      if (snapshot.revision == preparedRevision) break;
      preparedRevision = snapshot.revision;
      website = await _createWebsiteReadModel();
    }
    final timestamp = await _repository.uploadIncrementalWorkspace(
      snapshot.files,
      backups: backups,
    );
    await _repository.uploadWebsiteReadModel(
      website.readModel,
      version2Resources: website.resources,
    );
    await _pendingLocalChangeWrite;
    if (snapshot.revision != _localChangeRevision) {
      final latestState = await _readState();
      await _writeState({
        ...latestState,
        'dirty': true,
        'lastSyncedAt': timestamp.toUtc().toIso8601String(),
      });
      status.value =
          'Cloud-Datenstand hochgeladen · neuere lokale Änderungen warten noch auf den nächsten Abgleich';
      return;
    }
    await _writeState({
      'dirty': false,
      'lastSyncedAt': timestamp.toUtc().toIso8601String(),
    });
    if (snapshot.revision != _localChangeRevision) {
      await _pendingLocalChangeWrite;
      await _setDirty(true);
      status.value =
          'Cloud-Datenstand hochgeladen · neuere lokale Änderungen warten noch auf den nächsten Abgleich';
      return;
    }
    status.value = 'Mit Supabase synchronisiert';
  }

  Future<void> _publishWebsiteReadModel() async {
    final website = await _createWebsiteReadModel();
    await _repository.uploadWebsiteReadModel(
      website.readModel,
      version2Resources: website.resources,
    );
  }

  Future<
    ({
      Map<String, dynamic> readModel,
      Map<String, Map<String, dynamic>> resources,
    })
  >
  _createWebsiteReadModel() async {
    final service = WebsiteReadModelService();
    final readModel = await service.create();
    final resources = await service.createVersion2Resources(readModel);
    return (readModel: readModel, resources: resources);
  }

  /// User-confirmed resolution for simultaneous offline changes.
  Future<void> uploadLocalVersion() async {
    if (_pausePending) {
      status.value =
          'Hochladen nicht gestartet · ein lokaler Neustart wird vorbereitet';
      return;
    }
    if (_busy) {
      status.value =
          'Hochladen nicht gestartet · ein anderer Cloud-Vorgang läuft bereits';
      return;
    }
    _busy = true;
    try {
      final state = await _readState();
      state.remove('syncPaused');
      state['dirty'] = true;
      await _writeState(state);
      await _push();
    } finally {
      _busy = false;
    }
  }

  /// User-confirmed resolution that replaces the local account workspace.
  Future<void> downloadRemoteVersion({BackupPreview? preview}) async {
    if (_pausePending) {
      status.value =
          'Cloud-Datenstand nicht geladen · ein lokaler Neustart wird vorbereitet';
      return;
    }
    if (_busy) {
      status.value =
          'Cloud-Datenstand nicht geladen · ein anderer Cloud-Vorgang läuft bereits';
      return;
    }
    _busy = true;
    try {
      final backups = await BackupService.create();
      final remote = preview ?? await _repository.download(backups);
      await backups.restore(remote, restartApp: false);
      if (!await _repository.hasIncrementalWorkspace()) {
        await _writeState({'dirty': true});
        await _push();
        return;
      }
      final downloadedUpdatedAt = await _repository.backupUpdatedAt();
      await _writeState({
        'dirty': false,
        'lastSyncedAt': (downloadedUpdatedAt ?? remote.createdAt)
            .toUtc()
            .toIso8601String(),
      });
      status.value = 'Cloud-Datenstand geladen';
    } finally {
      _busy = false;
    }
  }

  /// Prevents a manual sync from restoring cloud data after this device resets.
  Future<void> pauseSynchronizationForFreshStart() async {
    _pausePending = true;
    try {
      while (_busy) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final state = await _readState();
      state['syncPaused'] = true;
      state['dirty'] = true;
      state['lastLocalChangeAt'] = DateTime.now().toUtc().toIso8601String();
      await _writeState(state);
      status.value =
          'Synchronisierung pausiert · neuer lokaler Datenstand bleibt auf diesem Gerät';
    } finally {
      _pausePending = false;
    }
  }

  void dispose() {
    StorageAccess.localDataRevision.removeListener(_changeListener);
    _started = false;
  }
}
