import 'dart:convert';
import 'dart:io';

import '../../../shared/persistence/app_data_directory.dart';
import '../../../shared/persistence/storage_access.dart';
import '../domain/tournament_models.dart';

/// Warum eine Turnier-Version im lokalen Papierkorb liegt.
enum TournamentTrashReason {
  completion('Turnierabschluss'),
  replaced('Neue Fassung'),
  deleted('Gelöscht'),
  reopened('Wieder geöffnet'),
  reset('Zurückgesetzt'),
  staleActiveCopy('Veralteter Zwischenstand');

  const TournamentTrashReason(this.label);

  final String label;

  static TournamentTrashReason fromName(String? name) =>
      TournamentTrashReason.values.firstWhere(
        (reason) => reason.name == name,
        orElse: () => TournamentTrashReason.replaced,
      );
}

/// Eine wiederherstellbare, versionierte Turnier-Version.
class TrashedTournament {
  const TrashedTournament({
    required this.entryId,
    required this.tournamentId,
    required this.name,
    required this.savedAt,
    required this.reason,
    required this.tournamentJson,
    this.note,
  });

  final String entryId;
  final String tournamentId;
  final String name;
  final DateTime savedAt;
  final TournamentTrashReason reason;
  final Map<String, dynamic> tournamentJson;
  final String? note;

  CreatedTournament toTournament() => CreatedTournament.fromJson(tournamentJson);

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'tournamentId': tournamentId,
    'name': name,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'reason': reason.name,
    'tournament': tournamentJson,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  factory TrashedTournament.fromJson(Map<String, dynamic> json) {
    final tournament = json['tournament'];
    if (tournament is! Map<String, dynamic>) {
      throw const FormatException('Papierkorb-Eintrag enthält kein Turnier.');
    }
    return TrashedTournament(
      entryId: json['entryId'] as String? ?? '',
      tournamentId: json['tournamentId'] as String? ?? '',
      name: json['name'] as String? ?? 'Turnier',
      savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      reason: TournamentTrashReason.fromName(json['reason'] as String?),
      tournamentJson: tournament,
      note: json['note'] as String?,
    );
  }
}

/// Lokaler Papierkorb für Turnier-Versionen.
///
/// Der Papierkorb ist bewusst unabhängig von der einmaligen `.bak`-Datei und
/// von benutzergetriggerten Vollsicherungen. Jeder Abschluss, jede bewusste
/// Löschung und jede destruktive Korrektur erzeugt hier eine wiederherstellbare
/// Kopie. Alte Einträge werden begrenzt, damit die Datei nicht unendlich wächst.
class TournamentTrash {
  TournamentTrash({File? file, DateTime Function()? now})
    : _file = file,
      _now = now ?? DateTime.now;

  final File? _file;
  final DateTime Function() _now;

  static const schemaVersion = 1;
  static const maxEntriesPerVersion = 5;
  static const maxEntries = 100;
  static const Duration maxAge = Duration(days: 30);

  Future<File> storageFile() async {
    final file = _file;
    if (file != null) return file;
    final directory = await appDataDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}tournament_trash.json',
    );
  }

  Future<List<TrashedTournament>> list() =>
      StorageAccess.run(_readEntriesUnlocked);

  Future<TrashedTournament> put(
    CreatedTournament tournament, {
    required TournamentTrashReason reason,
    String? note,
  }) =>
      StorageAccess.run(
        () => putUnlocked(tournament, reason: reason, note: note),
      );

  /// Schreibt ohne eigenen Storage-Lease. Wird von [TournamentStorage] innerhalb
  /// dessen bestehender Sperre verwendet, damit verschachtelte Aufrufe nicht
  /// auf sich selbst warten können.
  Future<TrashedTournament> putUnlocked(
    CreatedTournament tournament, {
    required TournamentTrashReason reason,
    String? note,
  }) async {
    final entries = await _readEntriesUnlocked();
    final now = _now();
    final entry = TrashedTournament(
      entryId: '${tournament.id}-${reason.name}-${now.microsecondsSinceEpoch}',
      tournamentId: tournament.id,
      name: tournament.name,
      savedAt: now,
      reason: reason,
      tournamentJson: CreatedTournament.fromJson(tournament.toJson()).toJson(),
      note: note,
    );
    entries.removeWhere((item) => now.difference(item.savedAt) > maxAge);
    entries.insert(0, entry);
    final byVersion = <String, List<TrashedTournament>>{};
    for (final item in entries) {
      final key = '${item.tournamentId}|${item.reason.name}';
      (byVersion[key] ??= []).add(item);
    }
    final retainedIds = <String>{};
    for (final items in byVersion.values) {
      items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      retainedIds.addAll(
        items.take(maxEntriesPerVersion).map((item) => item.entryId),
      );
    }
    entries.removeWhere((item) => !retainedIds.contains(item.entryId));
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    final kept = entries.take(maxEntries).toList();
    await _writeEntriesUnlocked(kept);
    StorageAccess.markLocalDataChanged();
    return entry;
  }

  /// Entfernt einen Eintrag, ohne das Turnier wiederherzustellen.
  Future<bool> remove(String entryId) => StorageAccess.run(() async {
    final entries = await _readEntriesUnlocked();
    final before = entries.length;
    entries.removeWhere((item) => item.entryId == entryId);
    final removed = before - entries.length;
    if (removed > 0) {
      await _writeEntriesUnlocked(entries);
      StorageAccess.markLocalDataChanged();
    }
    return removed > 0;
  });

  Future<int> clear() => StorageAccess.run(() async {
    final count = (await _readEntriesUnlocked()).length;
    await _writeEntriesUnlocked(const []);
    if (count > 0) StorageAccess.markLocalDataChanged();
    return count;
  });

  Future<List<TrashedTournament>> _readEntriesUnlocked() async {
    final file = await storageFile();
    if (!await file.exists()) return <TrashedTournament>[];
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger lokaler Papierkorb.');
    }
    final version = decoded['schemaVersion'] ?? 1;
    if (version != schemaVersion) {
      throw FormatException(
        'Papierkorb-Version $version wird nicht unterstützt.',
      );
    }
    final values = decoded['entries'];
    if (values is! List) {
      throw const FormatException('Beschädigter lokaler Papierkorb.');
    }
    final entries = <TrashedTournament>[];
    for (final item in values) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Beschädigter Papierkorb-Eintrag.');
      }
      entries.add(TrashedTournament.fromJson(item));
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }

  Future<void> _writeEntriesUnlocked(List<TrashedTournament> entries) async {
    final file = await storageFile();
    await file.parent.create(recursive: true);
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
    }
    final document = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'entries': [for (final entry in entries) entry.toJson()],
    };
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(document), flush: true);
    await temporary.rename(file.path);
  }
}
