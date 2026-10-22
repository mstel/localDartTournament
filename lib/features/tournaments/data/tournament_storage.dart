import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../shared/persistence/app_data_directory.dart';
import '../../../shared/persistence/storage_access.dart';
import '../domain/tournament_models.dart';

/// Local, account-scoped tournament archive. Supabase synchronization is
/// handled as a complete workspace backup by SupabaseWorkspaceSyncService.
class TournamentStorage {
  TournamentStorage({File? file}) : _file = file;

  final File? _file;
  // Schema 24 is accepted only after exact verification against its v22 backup.
  static const _schemaVersion = 26;
  static const _maximumDocumentBytes = 128 * 1024 * 1024;

  Future<T> _locked<T>(Future<T> Function() action) =>
      StorageAccess.run(action);

  Future<Map<String, dynamic>> _readDocument() async {
    final file = await _storageFile();
    if (!await file.exists()) return {};
    if (await file.length() > _maximumDocumentBytes) {
      throw const FormatException(
        'Turnierspeicher überschreitet die maximale Dateigröße. '
        'Die Originaldatei wurde nicht verändert.',
      );
    }
    final content = await file.readAsString();
    final decoded = content.length >= 256 * 1024
        ? await compute(jsonDecode, content)
        : jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger Turnierspeicher');
    }
    final version = decoded['schemaVersion'] ?? 1;
    if (version is! int || version < 1 || version > _schemaVersion) {
      throw FormatException(
        'Turnierspeicher-Version $version wird nicht unterstützt '
        '(unterstützt werden 1 bis $_schemaVersion). '
        'Die Datei wurde nicht verändert. '
        'Bitte mit einer App-Version öffnen, die dieses Format unterstützt.',
      );
    }
    if (version == 24) {
      await _verifySchema24Backup(file, decoded);
    }
    final tournaments = decoded['tournaments'];
    if (tournaments != null &&
        (tournaments is! List ||
            tournaments.any((item) => item is! Map<String, dynamic>))) {
      throw const FormatException('Beschädigte Turnierliste');
    }
    return decoded;
  }

  Future<void> _verifySchema24Backup(
    File file,
    Map<String, dynamic> document,
  ) async {
    final backup = File('${file.path}.v22.bak');
    if (!await backup.exists()) {
      throw FormatException(
        'Turnierspeicher-Version 24 kann nur mit passender '
        'tournaments.json.v22.bak gelesen werden. Die Sicherung fehlt am '
        'erwarteten Speicherort: ${backup.path}. '
        'Die Originaldatei wurde nicht verändert.',
      );
    }
    if (await backup.length() > _maximumDocumentBytes) {
      throw const FormatException(
        'Die v22-Sicherung überschreitet die maximale Dateigröße. '
        'Die Originaldatei wurde nicht verändert.',
      );
    }

    dynamic backupDocument;
    try {
      backupDocument = jsonDecode(await backup.readAsString());
    } on FormatException {
      throw const FormatException(
        'Die v22-Sicherung ist kein gültiges JSON. '
        'Die Originaldatei wurde nicht verändert.',
      );
    }
    if (backupDocument is! Map<String, dynamic> ||
        backupDocument['schemaVersion'] != 22) {
      throw const FormatException(
        'Die vorhandene Sicherung ist keine gültige Turnierspeicher-Version 22. '
        'Die Originaldatei wurde nicht verändert.',
      );
    }

    final currentComparable = Map<String, dynamic>.from(document)
      ..remove('schemaVersion');
    final backupComparable = Map<String, dynamic>.from(backupDocument)
      ..remove('schemaVersion');
    if (!_sameJsonValue(currentComparable, backupComparable)) {
      throw const FormatException(
        'Turnierspeicher-Version 24 stimmt nicht exakt mit der '
        'v22-Sicherung überein. Es wurden keine Daten verändert.',
      );
    }
  }

  bool _sameJsonValue(Object? left, Object? right) {
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

  Future<void> _writeDocument(Map<String, dynamic> document) async {
    final file = await _storageFile();
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      final previous = await _readDocument();
      await file.copy('${file.path}.bak');
      final version = previous['schemaVersion'] ?? 1;
      final migrationBackup = File('${file.path}.v$version.bak');
      if (version != _schemaVersion && !await migrationBackup.exists()) {
        await file.copy(migrationBackup.path);
      }
    }
    document['schemaVersion'] = _schemaVersion;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      await compute(_encodeTournamentDocument, document),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<List<CreatedTournament>> loadTournaments() =>
      _locked(_loadTournamentsUnlocked);

  Future<List<CreatedTournament>> _loadTournamentsUnlocked() async {
    final document = await _readDocument();
    final values = document['tournaments'] as List? ?? const [];
    return [
      for (final item in values)
        if (item is Map<String, dynamic>) CreatedTournament.fromJson(item),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> saveTournament(CreatedTournament tournament) async {
    await _locked(() async {
      final tournaments = await _loadTournamentsUnlocked();
      tournament.updatedAt = DateTime.now();
      final index = tournaments.indexWhere((item) => item.id == tournament.id);
      if (index < 0) {
        tournaments.insert(0, tournament);
      } else {
        tournaments[index] = tournament;
      }
      final document = await _readDocument();
      document['tournaments'] = tournaments
          .map((item) => item.toJson())
          .toList();
      await _writeDocument(document);
    });
    StorageAccess.markLocalDataChanged();
  }

  Future<void> deleteTournament(String id) async {
    await _locked(() async {
      final tournaments = await _loadTournamentsUnlocked();
      tournaments.removeWhere((item) => item.id == id);
      final document = await _readDocument();
      document['tournaments'] = tournaments
          .map((item) => item.toJson())
          .toList();
      await _writeDocument(document);
    });
    StorageAccess.markLocalDataChanged();
  }

  Future<File> storageFile() => _storageFile();

  Future<File> _storageFile() async {
    if (_file != null) return _file;
    final directory = await appDataDirectory();
    return File('${directory.path}${Platform.pathSeparator}tournaments.json');
  }
}

String _encodeTournamentDocument(Map<String, dynamic> document) =>
    jsonEncode(document);
