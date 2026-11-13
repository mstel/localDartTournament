import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../shared/persistence/app_data_directory.dart';
import '../../../shared/persistence/storage_access.dart';
import 'app_database.dart';
import '../domain/second_screen_widget_placement.dart';
import '../domain/tournament_models.dart';
import '../application/result_entry_performance_trace.dart';

class _TournamentStorageCacheEntry {
  _TournamentStorageCacheEntry({
    required this.lastModified,
    required this.fileLength,
    required this.document,
  });

  final DateTime lastModified;
  final int fileLength;
  final Map<String, dynamic> document;
}

/// Local, account-scoped tournament archive. Supabase synchronization is
/// handled as a complete workspace backup by SupabaseWorkspaceSyncService.
class TournamentStorage {
  TournamentStorage({File? file, LocalAppDatabase? activeDatabase})
    : _file = file,
      _activeDatabase =
          activeDatabase ??
          (file == null
              ? LocalAppDatabase()
              : LocalAppDatabase(baseDirectory: file.parent));

  final File? _file;
  final LocalAppDatabase _activeDatabase;
  // Schema 24 is accepted only after exact verification against its v22 backup.
  static const schemaVersion = 42;
  static const _schemaVersion = schemaVersion;
  static const _maximumDocumentBytes = 128 * 1024 * 1024;

  static final Map<String, _TournamentStorageCacheEntry> _cache = {};

  @visibleForTesting
  static void clearCache([String? path]) {
    if (path != null) {
      _cache.remove(path);
    } else {
      _cache.clear();
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) =>
      StorageAccess.run(action);

  Map<String, dynamic> _cloneDocument(Map<String, dynamic> source) {
    final copy = Map<String, dynamic>.from(source);
    final tournaments = source['tournaments'];
    if (tournaments is List) {
      copy['tournaments'] = [
        for (final item in tournaments)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    return copy;
  }

  Future<Map<String, dynamic>> _readDocument() async {
    final file = await _storageFile();
    if (!await file.exists()) {
      _cache.remove(file.path);
      return {};
    }
    final stat = await file.stat();
    final cached = _cache[file.path];
    if (cached != null &&
        cached.lastModified == stat.modified &&
        cached.fileLength == stat.size) {
      return _cloneDocument(cached.document);
    }

    if (stat.size > _maximumDocumentBytes) {
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

    _cache[file.path] = _TournamentStorageCacheEntry(
      lastModified: stat.modified,
      fileLength: stat.size,
      document: decoded,
    );

    return _cloneDocument(decoded);
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
      final previous = _cache[file.path]?.document ?? await _readDocument();
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
    final stat = await file.stat();

    _cache[file.path] = _TournamentStorageCacheEntry(
      lastModified: stat.modified,
      fileLength: stat.size,
      document: document,
    );
  }

  Future<List<CreatedTournament>> loadTournaments() =>
      _locked(_loadTournamentsUnlocked);

  Future<List<CreatedTournament>> loadTournamentsForRanking(
    String rankingId, {
    DateTime? from,
    DateTime? through,
  }) => _locked(() async {
    final document = await _readDocument();
    if (_migrateLegacyBestPerformances(document)) {
      document.remove('archiveGeneration');
      await _writeDocument(document);
    }
    final tournaments = document['archiveGeneration'] is String
        ? await _ensureRankingYearArchives(
            document,
            rankingId: rankingId,
            from: from,
            through: through,
          )
        : _filterArchiveTournaments(
            [
              for (final item in document['tournaments'] as List? ?? const [])
                if (item is Map<String, dynamic>)
                  CreatedTournament.fromJson(item),
            ],
            rankingId: rankingId,
            from: from,
            through: through,
          );
    final active = (await _activeDatabase.loadActiveTournamentCopies()).where(
      (item) =>
          item.rankingIds.contains(rankingId) &&
          _dateIsWithin(item.effectiveDate, from, through),
    );
    final merged = <String, CreatedTournament>{
      for (final tournament in tournaments) tournament.id: tournament,
    };
    for (final tournament in active) {
      final archived = merged[tournament.id];
      if (tournament.finishedAt != null && archived != null) {
        await _activeDatabase.deleteActiveTournamentCopy(tournament.id);
        continue;
      }
      if (archived == null ||
          !archived.updatedAt.isAfter(tournament.updatedAt)) {
        merged[tournament.id] = tournament;
      }
    }
    return merged.values.toList()..sort(
      (left, right) => left.effectiveDate.compareTo(right.effectiveDate),
    );
  });

  Future<List<CreatedTournament>> _loadTournamentsUnlocked() async {
    final document = await _readDocument();
    if (_migrateLegacyBestPerformances(document)) {
      document.remove('archiveGeneration');
      await _writeDocument(document);
    }
    final tournaments = document['archiveGeneration'] is String
        ? await _ensureRankingYearArchives(document)
        : [
            for (final item in document['tournaments'] as List? ?? const [])
              if (item is Map<String, dynamic>)
                CreatedTournament.fromJson(item),
          ];
    final activeCopies = await _activeDatabase.loadActiveTournamentCopies();
    final merged = <String, CreatedTournament>{
      for (final tournament in tournaments) tournament.id: tournament,
    };
    for (final active in activeCopies) {
      final archived = merged[active.id];
      if (active.finishedAt != null && archived != null) {
        await _activeDatabase.deleteActiveTournamentCopy(active.id);
        continue;
      }
      if (archived == null || !archived.updatedAt.isAfter(active.updatedAt)) {
        merged[active.id] = active;
      }
    }
    return merged.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<CreatedTournament>> _ensureRankingYearArchives(
    Map<String, dynamic> master, {
    String? rankingId,
    DateTime? from,
    DateTime? through,
  }) async {
    final generation = master['archiveGeneration'];
    final indexFile = await _archiveIndexFile();
    if (generation is String && await indexFile.exists()) {
      Object? index;
      try {
        index = jsonDecode(await indexFile.readAsString());
      } on FormatException {
        // A missing or damaged index is rebuilt from the verified master.
      }
      if (await _archiveIndexIsValid(index, generation)) {
        return await _readRankingYearArchives(
          rankingId: rankingId,
          from: from,
          through: through,
        );
      }
    }

    final values = master['tournaments'] as List? ?? const [];
    final legacy = [
      for (final item in values)
        if (item is Map<String, dynamic>) CreatedTournament.fromJson(item),
    ];
    final completed = legacy.where((item) => item.finishedAt != null).toList();
    final unfinished = legacy.where((item) => item.finishedAt == null).toList();
    for (final tournament in unfinished) {
      await _activeDatabase.saveActiveTournamentCopy(tournament);
    }
    final newGeneration = DateTime.now().microsecondsSinceEpoch.toString();
    master
      ..['archiveGeneration'] = newGeneration
      ..['tournaments'] = [
        for (final tournament in completed) tournament.toJson(),
      ];
    await _writeDocument(master);
    await _writeRankingYearArchives(completed, newGeneration);
    return _filterArchiveTournaments(
      completed,
      rankingId: rankingId,
      from: from,
      through: through,
    );
  }

  Future<List<CreatedTournament>> _readRankingYearArchives({
    String? rankingId,
    DateTime? from,
    DateTime? through,
  }) async {
    final directory = await _archiveDirectory();
    if (!await directory.exists()) return const [];
    final result = <CreatedTournament>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('ranking-archive-')) continue;
      if (rankingId != null) {
        final encodedId = base64Url
            .encode(utf8.encode(rankingId))
            .replaceAll('=', '');
        if (!name.startsWith('ranking-archive-$encodedId-')) continue;
      }
      final separator = name.lastIndexOf('-');
      final year = separator < 0
          ? null
          : int.tryParse(name.substring(separator + 1, name.length - 5));
      if (from != null && year != null && year < from.year) continue;
      if (through != null && year != null && year > through.year) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map || decoded['schemaVersion'] != 1) {
        throw FormatException('Ungültiges Ranglistenarchiv: ${entity.path}');
      }
      final values = decoded['tournaments'];
      if (values is! List || values.any((item) => item is! Map)) {
        throw FormatException('Beschädigtes Ranglistenarchiv: ${entity.path}');
      }
      result.addAll([
        for (final item in values)
          CreatedTournament.fromJson(Map<String, dynamic>.from(item as Map)),
      ]);
    }
    final byId = <String, CreatedTournament>{};
    for (final tournament in result) {
      final previous = byId[tournament.id];
      if (previous == null ||
          previous.updatedAt.isBefore(tournament.updatedAt)) {
        byId[tournament.id] = tournament;
      }
    }
    return _filterArchiveTournaments(
      byId.values.toList(),
      rankingId: rankingId,
      from: from,
      through: through,
    );
  }

  List<CreatedTournament> _filterArchiveTournaments(
    Iterable<CreatedTournament> tournaments, {
    String? rankingId,
    DateTime? from,
    DateTime? through,
  }) => [
    for (final tournament in tournaments)
      if ((rankingId == null || tournament.rankingIds.contains(rankingId)) &&
          _dateIsWithin(tournament.effectiveDate, from, through))
        tournament,
  ];

  bool _dateIsWithin(DateTime date, DateTime? from, DateTime? through) {
    final day = DateTime(date.year, date.month, date.day);
    final start = from == null
        ? null
        : DateTime(from.year, from.month, from.day);
    final end = through == null
        ? null
        : DateTime(through.year, through.month, through.day);
    return (start == null || !day.isBefore(start)) &&
        (end == null || !day.isAfter(end));
  }

  Future<void> _writeRankingYearArchives(
    List<CreatedTournament> tournaments,
    String generation,
  ) async {
    final groups = <String, List<CreatedTournament>>{};
    final rankingIds = <String, String>{};
    final years = <String, int>{};
    for (final tournament in tournaments) {
      final rankingId =
          tournament.countsForRanking && tournament.rankingIds.isNotEmpty
          ? tournament.rankingIds.first
          : 'unassigned';
      final year = tournament.effectiveDate.year;
      final key = '$rankingId|$year';
      (groups[key] ??= []).add(tournament);
      rankingIds[key] = rankingId;
      years[key] = year;
    }

    final directory = await _archiveDirectory();
    await directory.create(recursive: true);
    final retainedPaths = <String>{};
    for (final entry in groups.entries) {
      final encodedId = base64Url
          .encode(utf8.encode(rankingIds[entry.key]!))
          .replaceAll('=', '');
      final year = years[entry.key]!;
      final file = File(
        '${directory.path}${Platform.pathSeparator}ranking-archive-$encodedId-$year.json',
      );
      retainedPaths.add(file.path);
      final document = {
        'schemaVersion': 1,
        'generation': generation,
        'rankingId': rankingIds[entry.key],
        'year': year,
        'tournaments': [
          for (final tournament in entry.value) tournament.toJson(),
        ],
      };
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        await compute(_encodeAnyJson, document),
        flush: true,
      );
      await temporary.rename(file.path);
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('ranking-archive-') &&
          entity.path.endsWith('.json') &&
          !retainedPaths.contains(entity.path)) {
        await entity.delete();
      }
    }
    final indexFile = await _archiveIndexFile();
    final temporaryIndex = File('${indexFile.path}.tmp');
    await temporaryIndex.writeAsString(
      jsonEncode({
        'generation': generation,
        'files': [
          for (final path in retainedPaths)
            path.substring(path.lastIndexOf(Platform.pathSeparator) + 1),
        ],
      }),
      flush: true,
    );
    await temporaryIndex.rename(indexFile.path);
  }

  Future<bool> _archiveIndexIsValid(Object? index, String generation) async {
    if (index is! Map ||
        index['generation'] != generation ||
        index['files'] is! List) {
      return false;
    }
    final directory = await _archiveDirectory();
    for (final name in index['files'] as List) {
      if (name is! String ||
          !name.startsWith('ranking-archive-') ||
          !name.endsWith('.json') ||
          name.contains('/') ||
          name.contains('\\') ||
          !await File(
            '${directory.path}${Platform.pathSeparator}$name',
          ).exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _writeArchiveSnapshot(
    List<CreatedTournament> tournaments,
  ) async {
    final generation = DateTime.now().microsecondsSinceEpoch.toString();
    final document = await _readDocument();
    document
      ..['archiveGeneration'] = generation
      ..['tournaments'] = [
        for (final tournament in tournaments.where(
          (item) => item.finishedAt != null,
        ))
          tournament.toJson(),
      ];
    await _writeDocument(document);
    await _writeRankingYearArchives(
      tournaments.where((item) => item.finishedAt != null).toList(),
      generation,
    );
  }

  Future<void> _ensureArchiveLayout() => _locked(() async {
    final master = await _readDocument();
    if (_migrateLegacyBestPerformances(master)) {
      master.remove('archiveGeneration');
      await _writeDocument(master);
    }
    final generation = master['archiveGeneration'];
    final indexFile = await _archiveIndexFile();
    if (generation is String && await indexFile.exists()) {
      Object? index;
      try {
        index = jsonDecode(await indexFile.readAsString());
      } on FormatException {
        // Force a rebuild below.
      }
      if (await _archiveIndexIsValid(index, generation)) return;
    }
    await _ensureRankingYearArchives(master);
  });

  Future<Directory> _archiveDirectory() async {
    final file = await _storageFile();
    return Directory(
      '${file.parent.path}${Platform.pathSeparator}ranking_archives',
    );
  }

  Future<File> _archiveIndexFile() async {
    final directory = await _archiveDirectory();
    return File('${directory.path}${Platform.pathSeparator}archive_index.json');
  }

  bool _migrateLegacyBestPerformances(Object? value) {
    var changed = false;
    if (value is List) {
      for (final item in value) {
        changed = _migrateLegacyBestPerformances(item) || changed;
      }
    } else if (value is Map) {
      if (value['type'] == 'score170' && value.containsKey('playerName')) {
        value['type'] = 'score171Plus';
        value.remove('value');
        changed = true;
      }
      for (final item in value.values) {
        changed = _migrateLegacyBestPerformances(item) || changed;
      }
    }
    return changed;
  }

  Future<void> saveTournament(CreatedTournament tournament) async {
    if (tournament.rankingIds.length > 1) {
      tournament.rankingIds.removeRange(1, tournament.rankingIds.length);
    }
    if (tournament.rankingIds.isEmpty) {
      tournament.countsForRanking = false;
    }
    if (tournament.finishedAt == null) {
      await _locked(() async {
        await ResultEntryPerformanceTrace.measureAsync(
          'archive_layout_check',
          _ensureArchiveLayout,
        );
        final stored = await ResultEntryPerformanceTrace.measureAsync(
          'active_copy_read',
          () => _activeDatabase.loadActiveTournamentCopy(tournament.id),
        );
        if (stored != null && stored.updatedAt.isAfter(tournament.updatedAt)) {
          final incomingLayouts =
              Map<String, List<SecondScreenWidgetPlacement>>.from(
                tournament.secondScreenLayouts,
              );
          tournament.secondScreenLayouts
            ..clear()
            ..addAll(stored.secondScreenLayouts)
            ..addEntries(
              incomingLayouts.entries.where(
                (entry) => !stored.secondScreenLayouts.containsKey(entry.key),
              ),
            );
          tournament.secondScreenActiveLayout =
              stored.secondScreenActiveLayout ??
              tournament.secondScreenActiveLayout;
        }
        await ResultEntryPerformanceTrace.measureAsync(
          'active_copy_write',
          () => _activeDatabase.saveActiveTournamentCopy(tournament),
        );
      });
      return;
    }
    await _locked(() async {
      await _ensureArchiveLayout();
      final tournaments = await _loadTournamentsUnlocked();
      final incomingUpdatedAt = tournament.updatedAt;
      tournament.updatedAt = DateTime.now();
      final index = tournaments.indexWhere((item) => item.id == tournament.id);
      if (index < 0) {
        tournaments.insert(0, tournament);
      } else {
        final stored = tournaments[index];
        if (stored.updatedAt.isAfter(incomingUpdatedAt)) {
          final incomingLayouts =
              Map<String, List<SecondScreenWidgetPlacement>>.from(
                tournament.secondScreenLayouts,
              );
          tournament.secondScreenLayouts
            ..clear()
            ..addAll(stored.secondScreenLayouts)
            ..addEntries(
              incomingLayouts.entries.where(
                (entry) => !stored.secondScreenLayouts.containsKey(entry.key),
              ),
            );
          tournament.secondScreenActiveLayout =
              stored.secondScreenActiveLayout ??
              tournament.secondScreenActiveLayout;
        } else {
          for (final entry in stored.secondScreenLayouts.entries) {
            tournament.secondScreenLayouts.putIfAbsent(
              entry.key,
              () => entry.value,
            );
          }
        }
        tournaments[index] = tournament;
      }
      await _writeArchiveSnapshot(tournaments);
    });
    await _activeDatabase.deleteActiveTournamentCopy(tournament.id);
    StorageAccess.markLocalDataChanged();
  }

  Future<void> saveSecondScreenLayout({
    required CreatedTournament tournament,
    required String name,
    required List<SecondScreenWidgetPlacement>? placements,
    required bool activate,
  }) async {
    await _locked(() async {
      await _ensureArchiveLayout();
      final tournaments = await _loadTournamentsUnlocked();
      final index = tournaments.indexWhere((item) => item.id == tournament.id);
      final latest = index < 0 ? tournament : tournaments[index];

      if (placements == null) {
        latest.secondScreenLayouts.remove(name);
        if (latest.secondScreenActiveLayout == name) {
          latest.secondScreenActiveLayout = null;
        }
      } else {
        latest.secondScreenLayouts[name] =
            List<SecondScreenWidgetPlacement>.from(placements);
        if (activate) latest.secondScreenActiveLayout = name;
      }
      latest.updatedAt = DateTime.now();
      if (index < 0) {
        tournaments.insert(0, latest);
      } else {
        tournaments[index] = latest;
      }

      if (latest.finishedAt == null) {
        await _activeDatabase.saveActiveTournamentCopy(latest);
      } else {
        await _writeArchiveSnapshot(tournaments);
      }

      tournament.secondScreenLayouts
        ..clear()
        ..addAll(
          latest.secondScreenLayouts.map(
            (key, value) => MapEntry(key, List.of(value)),
          ),
        );
      tournament
        ..secondScreenActiveLayout = latest.secondScreenActiveLayout
        ..updatedAt = latest.updatedAt;
    });
    StorageAccess.markLocalDataChanged();
  }

  Future<void> deleteTournament(String id) async {
    await _locked(() async {
      await _ensureArchiveLayout();
      final tournaments = await _loadTournamentsUnlocked();
      tournaments.removeWhere((item) => item.id == id);
      await _writeArchiveSnapshot(tournaments);
    });
    await _activeDatabase.deleteActiveTournamentCopy(id);
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

String _encodeAnyJson(Object? document) => jsonEncode(document);
