import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'backup_service.dart';
import '../../tournaments/data/tournament_storage.dart';

/// Lossless logical snapshot used by Supabase's content-addressed backup.
/// Completed tournament records remain individually available, so profile
/// statistics can continue to derive from the same full match history.
class IncrementalWorkspaceArchive {
  IncrementalWorkspaceArchive._({
    required this.objects,
    required this.tournamentOrder,
    required this.absentStores,
  });

  static const appName = 'dart-tournament-incremental-backup';
  static const version = 1;
  static const tournamentsRootKey = 'tournaments-root';
  static const tournamentPrefix = 'tournament:';
  static const storePrefix = 'store:';

  final Map<String, Uint8List> objects;
  final List<String> tournamentOrder;
  final Set<String> absentStores;

  factory IncrementalWorkspaceArchive.fromStoreFiles(
    Map<String, Uint8List?> files,
  ) {
    if (files.length != BackupService.names.length ||
        !files.keys.toSet().containsAll(BackupService.names)) {
      throw const FormatException('Unvollständige lokale Speicherdateien.');
    }
    final objects = <String, Uint8List>{};
    final absentStores = <String>{};
    final tournamentBytes = files['tournaments.json'];
    Map<String, dynamic> root = {
      'schemaVersion': TournamentStorage.schemaVersion,
    };
    var tournaments = <Map<String, dynamic>>[];
    if (tournamentBytes != null) {
      final decoded = jsonDecode(utf8.decode(tournamentBytes));
      if (decoded is! Map<String, dynamic> || decoded['tournaments'] is! List) {
        throw const FormatException('Turnierarchiv ist ungültig.');
      }
      root = Map<String, dynamic>.from(decoded)
        ..remove('tournaments')
        ..remove('archiveGeneration');
      final seenIds = <String>{};
      for (final value in decoded['tournaments'] as List) {
        if (value is! Map<String, dynamic> || value['id'] is! String) {
          throw const FormatException('Turnierdatensatz hat keine gültige ID.');
        }
        final tournament = Map<String, dynamic>.from(value);
        final id = tournament['id'] as String;
        if (id.isEmpty || !seenIds.add(id)) {
          throw const FormatException('Turnier-IDs müssen eindeutig sein.');
        }
        tournaments.add(tournament);
        objects['$tournamentPrefix$id'] = _jsonBytes(tournament);
      }
    }
    objects[tournamentsRootKey] = _jsonBytes(root);
    for (final name in BackupService.names.where(
      (name) => name != 'tournaments.json',
    )) {
      final bytes = files[name];
      if (bytes == null) {
        absentStores.add(name);
      } else {
        objects['$storePrefix$name'] = Uint8List.fromList(bytes);
      }
    }
    return IncrementalWorkspaceArchive._(
      objects: objects,
      tournamentOrder: [
        for (final tournament in tournaments) tournament['id'] as String,
      ],
      absentStores: absentStores,
    );
  }

  factory IncrementalWorkspaceArchive.fromManifest(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['app'] != appName ||
        value['version'] != version ||
        value['createdAt'] is! String ||
        DateTime.tryParse(value['createdAt'] as String) == null ||
        value['objects'] is! Map ||
        value['tournamentOrder'] is! List ||
        value['absentStores'] is! List) {
      throw const FormatException('Ungültiges Delta-Backup-Manifest.');
    }
    final order = (value['tournamentOrder'] as List).cast<String>();
    if (order.toSet().length != order.length) {
      throw const FormatException('Turnier-Reihenfolge ist ungültig.');
    }
    final absentStores = (value['absentStores'] as List).cast<String>().toSet();
    if (absentStores.any(
      (name) =>
          !BackupService.names.contains(name) || name == 'tournaments.json',
    )) {
      throw const FormatException('Unbekannte Speicherdatei im Manifest.');
    }
    final entries = value['objects'] as Map;
    final objects = <String, Uint8List>{};
    for (final entry in entries.entries) {
      if (entry.key is! String ||
          entry.value is! Map ||
          (entry.value as Map)['sha256'] is! String ||
          (entry.value as Map)['path'] is! String) {
        throw const FormatException('Ungültiger Manifest-Eintrag.');
      }
      objects[entry.key as String] = Uint8List(0);
    }
    final tournamentKeys = objects.keys
        .where((key) => key.startsWith(tournamentPrefix))
        .map((key) => key.substring(tournamentPrefix.length))
        .toSet();
    if (tournamentKeys.length != order.length ||
        !tournamentKeys.containsAll(order) ||
        !objects.containsKey(tournamentsRootKey) ||
        objects.keys.any((key) {
          if (key == tournamentsRootKey || key.startsWith(tournamentPrefix)) {
            return false;
          }
          if (!key.startsWith(storePrefix)) return true;
          final name = key.substring(storePrefix.length);
          return !BackupService.names.contains(name) ||
              name == 'tournaments.json' ||
              absentStores.contains(name);
        })) {
      throw const FormatException(
        'Manifest enthält keinen vollständigen Stand.',
      );
    }
    for (final name in BackupService.names.where(
      (name) => name != 'tournaments.json',
    )) {
      if (!absentStores.contains(name) &&
          !objects.containsKey('$storePrefix$name')) {
        throw FormatException('Manifest enthält die Datei $name nicht.');
      }
    }
    return IncrementalWorkspaceArchive._(
      objects: objects,
      tournamentOrder: order,
      absentStores: absentStores,
    );
  }

  Map<String, Object?> toManifest(Map<String, String> objectPaths) => {
    'app': appName,
    'version': version,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'tournamentOrder': tournamentOrder,
    'absentStores': absentStores.toList()..sort(),
    'objects': {
      for (final entry in objects.entries)
        entry.key: {
          'sha256': sha256.convert(entry.value).toString(),
          'path': objectPaths[entry.key],
        },
    },
  };

  Set<String> changedObjectKeys(
    Map<String, dynamic>? previousManifest, {
    required String objectPathPrefix,
  }) {
    final previous = previousManifest?['objects'];
    final previousObjects = previous is Map
        ? previous
        : const <Object?, Object?>{};
    return {
      for (final entry in objects.entries)
        if (!_matchesPreviousObject(entry, previousObjects, objectPathPrefix))
          entry.key,
    };
  }

  bool _matchesPreviousObject(
    MapEntry<String, Uint8List> entry,
    Map previous,
    String objectPathPrefix,
  ) {
    final old = previous[entry.key];
    if (old is! Map) return false;
    final digest = sha256.convert(entry.value).toString();
    final path = old['path'];
    return old['sha256'] == digest && path == '$objectPathPrefix/$digest.bin';
  }

  Map<String, Uint8List?> toStoreFiles() {
    final rootBytes = objects[tournamentsRootKey];
    if (rootBytes == null) {
      throw const FormatException('Turnier-Stammdaten fehlen im Manifest.');
    }
    final decodedRoot = jsonDecode(utf8.decode(rootBytes));
    if (decodedRoot is! Map<String, dynamic>) {
      throw const FormatException('Turnier-Stammdaten sind ungültig.');
    }
    final tournamentById = <String, Map<String, dynamic>>{};
    for (final id in tournamentOrder) {
      final bytes = objects['$tournamentPrefix$id'];
      if (bytes == null) {
        throw FormatException('Turnierdaten fehlen: $id');
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> || decoded['id'] != id) {
        throw FormatException('Turnierdaten sind beschädigt: $id');
      }
      tournamentById[id] = decoded;
    }
    final root = Map<String, dynamic>.from(
      decodedRoot,
    )..['tournaments'] = [for (final id in tournamentOrder) tournamentById[id]];
    final result = <String, Uint8List?>{
      'tournaments.json': _jsonBytes(root),
      for (final name in BackupService.names.where(
        (name) => name != 'tournaments.json',
      ))
        name: absentStores.contains(name) ? null : objects['$storePrefix$name'],
    };
    if (result.values.where((value) => value != null).length < 2) {
      throw const FormatException('Delta-Backup enthält zu wenige Dateien.');
    }
    return result;
  }

  static Uint8List _jsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));
}
