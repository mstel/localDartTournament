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

/// Keeps one private complete workspace per authenticated Supabase account.
/// Local edits are uploaded after a short debounce; a newer remote snapshot is
/// pulled when the local account workspace has no unpushed edits.
class SupabaseWorkspaceSyncService {
  static final instance = SupabaseWorkspaceSyncService._();
  static const _localOnlyPreview = bool.fromEnvironment(
    'LOCAL_ONLY_PREVIEW',
    defaultValue: false,
  );

  SupabaseWorkspaceSyncService._()
    : _repository = SupabaseBackupRepository(),
      _debounce = const Duration(seconds: 3);

  SupabaseWorkspaceSyncService({
    SupabaseBackupRepository? repository,
    Duration debounce = const Duration(seconds: 3),
  }) : _repository = repository ?? SupabaseBackupRepository(),
       _debounce = debounce;

  static final status = ValueNotifier<String>('Lokale Daten sind bereit');
  final SupabaseBackupRepository _repository;
  final Duration _debounce;
  Timer? _timer;
  bool _busy = false;
  bool _syncRequestedWhileBusy = false;
  bool _pausePending = false;
  bool _started = false;
  late final VoidCallback _changeListener = _onLocalChange;

  void start() {
    if (_started) return;
    _started = true;
    StorageAccess.localDataRevision.addListener(_changeListener);
    unawaited(_prepareAndSynchronize());
  }

  Future<void> activateAccount(String? accountId) async {
    if (accountId == null || _localOnlyPreview) return;
    final accountDirectory = await appDataDirectory();
    final stateFile = File(
      path.join(accountDirectory.path, 'supabase_sync_state.json'),
    );
    final localWorkspaceExists =
        await File(path.join(accountDirectory.path, 'tournaments.json'))
            .exists() ||
        await File(path.join(accountDirectory.path, 'app_database.sqlite'))
            .exists();
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
        status.value = 'Automatische Synchronisierung wieder aktiviert';
      }
      return;
    }
    if (await ownerMarker.exists()) return;
    // Claim the old local-only workspace once. Do not seed another Supabase
    // account from the same legacy data directory.
    if (await _repository.hasBackup()) {
      await ownerMarker.parent.create(recursive: true);
      await ownerMarker.writeAsString(accountId, flush: true);
      return;
    }
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
      status.value = 'Bisherige lokale Daten dem Supabase-Konto zugeordnet';
    }
    // The state file is account-scoped; creating it here also makes a later
    // sync distinguish this account from the legacy local-only store.
    if (!await stateFile.exists()) await _writeState({'dirty': copied});
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

  Future<void> _prepareAndSynchronize() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) await activateAccount(user.id);
      await synchronize();
    } catch (error) {
      status.value = 'Synchronisierung wartet auf Verbindung: $error';
    }
  }

  void _onLocalChange() {
    unawaited(_markDirtyAndResumeIfReady());
    _schedule(_debounce);
  }

  Future<void> _markDirtyAndResumeIfReady() async {
    await _setDirty(true);
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
    status.value = 'Automatische Synchronisierung wieder aktiviert';
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

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(synchronize()));
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
      status.value = 'Lokaler Testmodus · automatische Cloud-Synchronisierung ist deaktiviert';
      return;
    }
    if (_pausePending) return;
    if (_busy) {
      _syncRequestedWhileBusy = true;
      return;
    }
    try {
      if (Supabase.instance.client.auth.currentUser == null) {
        status.value = 'Nicht angemeldet · lokal gespeichert';
        return;
      }
    } catch (_) {
      return;
    }
    _busy = true;
    try {
      final state = await _readState();
      if (state['syncPaused'] == true) {
        status.value = 'Synchronisierung pausiert · neuer lokaler Datenstand bleibt auf diesem Gerät';
        return;
      }
      if (!await _repository.hasBackup()) {
        await _push(state);
        return;
      }
      final remote = await _repository.download(await BackupService.create());
      final lastSynced = DateTime.tryParse('${state['lastSyncedAt'] ?? ''}');
      final remoteIsNewer =
          lastSynced == null || remote.createdAt.isAfter(lastSynced);
      if (state['dirty'] == true) {
        if (remoteIsNewer) {
          status.value =
              'Cloud und dieses Gerät haben Änderungen · Abgleich erforderlich';
          return;
        }
        await _push(state);
        return;
      }
      if (remoteIsNewer) {
        status.value = 'Lade neueren Datenstand aus Supabase …';
        await (await BackupService.create()).restore(remote, restartApp: false);
        await _writeState({
          'dirty': false,
          'lastSyncedAt': remote.createdAt.toUtc().toIso8601String(),
        });
        status.value = 'Aktueller Datenstand aus Supabase geladen';
      } else {
        status.value = 'Mit Supabase synchronisiert';
      }
    } catch (error) {
      status.value = 'Synchronisierung wartet auf Verbindung: $error';
    } finally {
      _busy = false;
      if (_syncRequestedWhileBusy && !_pausePending) {
        _syncRequestedWhileBusy = false;
        _schedule(_debounce);
      }
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

  Future<void> _push(Map<String, dynamic> state) async {
    status.value = 'Sichere Änderungen in Supabase …';
    final timestamp = await _repository.upload(await BackupService.create());
    await _writeState({
      'dirty': false,
      'lastSyncedAt': timestamp.toUtc().toIso8601String(),
    });
    status.value = 'Mit Supabase synchronisiert';
  }

  /// User-confirmed resolution for simultaneous offline changes.
  Future<void> uploadLocalVersion() async {
    if (_pausePending) return;
    if (_busy) return;
    _busy = true;
    try {
      final state = await _readState();
      state.remove('syncPaused');
      state['dirty'] = true;
      await _writeState(state);
      await _push(state);
    } finally {
      _busy = false;
    }
  }

  /// User-confirmed resolution that replaces the local account workspace.
  Future<void> downloadRemoteVersion() async {
    if (_pausePending) return;
    if (_busy) return;
    _busy = true;
    try {
      final backups = await BackupService.create();
      final remote = await _repository.download(backups);
      await backups.restore(remote, restartApp: false);
      await _writeState({
        'dirty': false,
        'lastSyncedAt': remote.createdAt.toUtc().toIso8601String(),
      });
      status.value = 'Cloud-Datenstand geladen';
    } finally {
      _busy = false;
    }
  }

  /// Pauses every automatic cloud operation before this device is reset.
  Future<void> pauseSynchronizationForFreshStart() async {
    _pausePending = true;
    _timer?.cancel();
    try {
      while (_busy) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      final state = await _readState();
      state['syncPaused'] = true;
      state['dirty'] = true;
      state['lastLocalChangeAt'] = DateTime.now().toUtc().toIso8601String();
      await _writeState(state);
      status.value = 'Synchronisierung pausiert · neuer lokaler Datenstand bleibt auf diesem Gerät';
    } finally {
      _pausePending = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    StorageAccess.localDataRevision.removeListener(_changeListener);
    _started = false;
  }
}
