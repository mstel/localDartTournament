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
  static const _schemaVersion = 24;

  Future<T> _locked<T>(Future<T> Function() action) =>
      StorageAccess.run(action);

  Future<Map<String, dynamic>> _readDocument() async {
    final file = await _storageFile();
    if (!await file.exists()) return {};
    final content = await file.readAsString();
    final decoded = content.length >= 256 * 1024
        ? await compute(jsonDecode, content)
        : jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger Turnierspeicher');
    }
    final version = decoded['schemaVersion'] ?? 1;
    if (version is! int || version < 1 || version > _schemaVersion) {
      throw const FormatException(
        'Nicht unterstützte Speicherversion. Bitte App aktualisieren.',
      );
    }
    final tournaments = decoded['tournaments'];
    if (tournaments != null &&
        (tournaments is! List ||
            tournaments.any((item) => item is! Map<String, dynamic>))) {
      throw const FormatException('Beschädigte Turnierliste');
    }
    return decoded;
  }

  Future<void> _writeDocument(Map<String, dynamic> document) async {
    final file = await _storageFile();
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      final previous = await _readDocument();
      await file.copy('${file.path}.bak');
      final version = previous['schemaVersion'] ?? 1;
      final migrationBackup = File('${file.path}.v$version.bak');
      if (version < _schemaVersion && !await migrationBackup.exists()) {
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
