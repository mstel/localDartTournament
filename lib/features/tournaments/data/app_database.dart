import '../../../shared/persistence/storage_access.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:path/path.dart' as path;
import '../../../shared/persistence/app_data_directory.dart';
import 'package:sqlite3/sqlite3.dart';

import '../domain/tournament_models.dart';
import '../../rankings/domain/local_ranking.dart';

class LocalAppDatabase {
  LocalAppDatabase({Directory? baseDirectory}) : _baseDirectory = baseDirectory;

  static const schemaVersion = 10;

  final Directory? _baseDirectory;

  /// Uses the same restore lock and migration backups as other app data.
  Future<T> withDatabase<T>(Future<T> Function(Database) action) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          return await action(database);
        } finally {
          database.close();
        }
      });

  Future<List<PlayerProfile>> loadPlayerProfiles() async {
    return StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        final rows = database.select('''
        SELECT id, display_name, country, city, darts_setup_json,
               created_at, is_active
        FROM player_profiles
        WHERE is_active = 1
        ORDER BY display_name COLLATE NOCASE
      ''');
        return [for (final row in rows) PlayerProfile.fromRow(row)];
      } finally {
        database.close();
      }
    });
  }

  Future<List<LocalRanking>> loadLocalRankings() => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      return [
        for (final row in database.select(
          '''SELECT config_json FROM local_rankings
             ORDER BY custom_order, name COLLATE NOCASE, id''',
        ))
          LocalRanking.fromJson(
            Map<String, Object?>.from(jsonDecode(row['config_json'] as String) as Map),
          ),
      ];
    } finally {
      database.close();
    }
  });

  Future<void> saveLocalRanking(LocalRanking ranking) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      database.execute(
        '''INSERT INTO local_rankings(id, name, ranking_type, config_json)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET name=excluded.name,
             ranking_type=excluded.ranking_type, config_json=excluded.config_json''',
        [ranking.id, ranking.name.trim(), ranking.type.name, jsonEncode(ranking.toJson())],
      );
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<void> deleteLocalRanking(String rankingId) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      database.execute('DELETE FROM local_rankings WHERE id = ?', [rankingId]);
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<List<String>> loadRankingPlayerIds(String rankingId) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          return [
            for (final row in database.select(
              'SELECT player_profile_id FROM local_ranking_players WHERE ranking_id = ? ORDER BY player_profile_id',
              [rankingId],
            ))
              row['player_profile_id'] as String,
          ];
        } finally {
          database.close();
        }
      });

  Future<List<LocalRanking>> loadRankingsForPlayer(String playerId) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          return [
            for (final row in database.select(
              '''SELECT r.config_json FROM local_rankings r
                 JOIN local_ranking_players p ON p.ranking_id = r.id
                 WHERE p.player_profile_id = ? ORDER BY r.name COLLATE NOCASE''',
              [playerId],
            ))
              LocalRanking.fromJson(
                Map<String, Object?>.from(jsonDecode(row['config_json'] as String) as Map),
              ),
          ];
        } finally {
          database.close();
        }
      });

  Future<void> setRankingPlayers(String rankingId, Iterable<String> playerIds) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          database.execute('BEGIN');
          try {
            database.execute(
              'DELETE FROM local_ranking_players WHERE ranking_id = ?',
              [rankingId],
            );
            for (final playerId in playerIds.toSet()) {
              database.execute(
                '''INSERT INTO local_ranking_players(ranking_id, player_profile_id)
                   SELECT ?, id FROM player_profiles WHERE id = ? AND is_active = 1''',
                [rankingId, playerId],
              );
            }
            database.execute('COMMIT');
            StorageAccess.markLocalDataChanged();
          } catch (_) {
            database.execute('ROLLBACK');
            rethrow;
          }
        } finally {
          database.close();
        }
      });

  Future<List<Map<String, Object?>>> loadChallongePlayerLinks({String source = 'challonge'}) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          return [
            for (final row in database.select(
              'SELECT challonge_name, player_profile_id FROM challonge_player_links WHERE source = ? ORDER BY challonge_name COLLATE NOCASE',
              [source],
            ))
              {'challongeName': row['challonge_name'], 'playerProfileId': row['player_profile_id']},
          ];
        } finally { database.close(); }
      });

  Future<void> saveChallongePlayerLink(String name, String playerId, {String source = 'challonge'}) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          database.execute(
            '''INSERT INTO challonge_player_links(source, normalized_name, challonge_name, player_profile_id)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(source, normalized_name) DO UPDATE SET challonge_name=excluded.challonge_name, player_profile_id=excluded.player_profile_id''',
            [source, name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '), name.trim(), playerId],
          );
          StorageAccess.markLocalDataChanged();
        } finally { database.close(); }
      });

  Future<void> deleteChallongePlayerLink(String name, {String source = 'challonge'}) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          database.execute('DELETE FROM challonge_player_links WHERE source = ? AND normalized_name = ?',
            [source, name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')]);
          StorageAccess.markLocalDataChanged();
        } finally { database.close(); }
      });

  Future<List<TournamentPlayer>> loadTournamentPlayers() async {
    return StorageAccess.run(() async {
      final profiles = await loadPlayerProfiles();
      return [
        for (final profile in profiles)
          TournamentPlayer(
            profileId: profile.id,
            name: profile.displayName,
            isGenerated: false,
          ),
      ];
    });
  }

  Future<File> databaseFile() => _databaseFile();

  Future<PlayerProfile> createPlayerProfile({
    required String displayName,
    String country = '',
    String city = '',
    String dartsSetupJson = '',
  }) async {
    return StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        final now = DateTime.now();
        final profile = PlayerProfile(
          id: _newId(),
          displayName: displayName.trim(),
          country: country.trim(),
          city: city.trim(),
          dartsSetupJson: dartsSetupJson.trim(),
          createdAt: now,
          isActive: true,
        );
        database.execute(
          '''
        INSERT INTO player_profiles (
          id, display_name, country, city, darts_setup_json,
          created_at, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            profile.id,
            profile.displayName,
            profile.country,
            profile.city,
            profile.dartsSetupJson,
            profile.createdAt.toIso8601String(),
            1,
          ],
        );
        StorageAccess.markLocalDataChanged();
        return profile;
      } finally {
        database.close();
      }
    });
  }

  Future<void> updatePlayerProfile(PlayerProfile profile) async {
    return StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        database.execute(
          '''
        UPDATE player_profiles
        SET display_name = ?, country = ?, city = ?, darts_setup_json = ?
        WHERE id = ?
        ''',
          [
            profile.displayName.trim(),
            profile.country.trim(),
            profile.city.trim(),
            profile.dartsSetupJson.trim(),
            profile.id,
          ],
        );
        StorageAccess.markLocalDataChanged();
      } finally {
        database.close();
      }
    });
  }

  Future<void> deactivatePlayerProfile(String id) async {
    return StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        database.execute(
          'UPDATE player_profiles SET is_active = 0 WHERE id = ?',
          [id],
        );
        StorageAccess.markLocalDataChanged();
      } finally {
        database.close();
      }
    });
  }

  Future<Database> _openDatabase() async {
    final file = await _databaseFile();
    await file.parent.create(recursive: true);
    final database = sqlite3.open(file.path);
    database.execute('PRAGMA foreign_keys = ON');
    try {
      final version = _currentSchemaVersion(database);
      if (version > schemaVersion) {
        throw StateError(
          'Lokale Datenbank-Version $version wird nicht unterstützt '
          '(maximal $schemaVersion). Die Datei wurde nicht verändert. '
          'Bitte mit einer App-Version öffnen, die dieses Format unterstützt.',
        );
      }
      if (version > 0 && version < schemaVersion) {
        final backup =
            '${file.path}.v$version.${DateTime.now().microsecondsSinceEpoch}.bak';
        database.execute('VACUUM INTO ?', [backup]);
      }
      _migrate(database);
      return database;
    } catch (_) {
      database.close();
      rethrow;
    }
  }

  void _migrate(Database database) {
    final currentVersion = _currentSchemaVersion(database);
    if (currentVersion >= schemaVersion) {
      return;
    }

    database.execute('PRAGMA foreign_keys = OFF');
    database.execute('BEGIN');
    try {
      if (currentVersion == schemaVersion - 1) {
        database.execute(
          'ALTER TABLE local_rankings ADD COLUMN custom_order INTEGER NOT NULL DEFAULT 0',
        );
        final rankings = database.select(
          'SELECT id FROM local_rankings ORDER BY name COLLATE NOCASE, id',
        );
        for (var index = 0; index < rankings.length; index++) {
          database.execute(
            'UPDATE local_rankings SET custom_order = ? WHERE id = ?',
            [index, rankings[index]['id']],
          );
        }
      } else {
        if (currentVersion > 0) {
          final oldTables = database.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          );
          for (final row in oldTables) {
            final name = (row['name'] as String).replaceAll('"', '""');
            database.execute('DROP TABLE IF EXISTS "$name"');
          }
        }
        _createSchema(database);
      }
      database.execute('PRAGMA user_version = $schemaVersion');
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      database.execute('PRAGMA foreign_keys = ON');
    }
  }

  int _currentSchemaVersion(Database database) {
    final result = database.select('PRAGMA user_version');
    if (result.isEmpty || result.first.isEmpty) {
      return 0;
    }
    return result.first.values.first as int? ?? 0;
  }

  void _createSchema(Database database) {
    database.execute('''
      CREATE TABLE player_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        darts_setup_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      );

      CREATE TABLE local_rankings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        ranking_type TEXT NOT NULL CHECK (ranking_type IN ('elo', 'series')),
        config_json TEXT NOT NULL,
        custom_order INTEGER NOT NULL DEFAULT 0
      );

      CREATE TABLE local_ranking_players (
        ranking_id TEXT NOT NULL REFERENCES local_rankings(id) ON DELETE CASCADE,
        player_profile_id TEXT NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
        PRIMARY KEY (ranking_id, player_profile_id)
      );

      CREATE TABLE challonge_player_links (
        source TEXT NOT NULL,
        normalized_name TEXT NOT NULL,
        challonge_name TEXT NOT NULL,
        player_profile_id TEXT NOT NULL REFERENCES player_profiles(id) ON DELETE CASCADE,
        PRIMARY KEY(source, normalized_name)
      );

      CREATE INDEX idx_player_profiles_display_name
        ON player_profiles(display_name);
    ''');
  }

  Future<File> _databaseFile() async {
    final directory = _baseDirectory ?? await _defaultBaseDirectory();
    return File(path.join(directory.path, 'app_database.sqlite'));
  }

  Future<Directory> _defaultBaseDirectory() => appDataDirectory();

  String _newId() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final randomPart = Random().nextInt(1 << 32).toRadixString(16);
    return '$timestamp-$randomPart';
  }
}

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.displayName,
    required this.country,
    required this.city,
    required this.dartsSetupJson,
    required this.createdAt,
    required this.isActive,
  });

  factory PlayerProfile.fromRow(Row row) {
    return PlayerProfile(
      id: row['id'] as String? ?? '',
      displayName: row['display_name'] as String? ?? '',
      country: row['country'] as String? ?? '',
      city: row['city'] as String? ?? '',
      dartsSetupJson: row['darts_setup_json'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isActive: (row['is_active'] as int? ?? 1) == 1,
    );
  }

  final String id;
  final String displayName;
  final String country;
  final String city;
  final String dartsSetupJson;
  final DateTime createdAt;
  final bool isActive;

  Map<String, dynamic> get _metadata {
    final trimmed = dartsSetupJson.trim();
    if (trimmed.startsWith('{')) {
      try {
        return Map<String, dynamic>.from(jsonDecode(trimmed) as Map);
      } catch (_) {}
    }
    return const {};
  }

  String get nickname => _metadata['nickname'] as String? ?? '';
  String get birthdate => _metadata['birthdate'] as String? ?? '';
  String get scoliaId => _metadata['scoliaId'] as String? ?? '';
  String get autodartsName => _metadata['autodartsName'] as String? ?? '';
  String get threeKDartsId => _metadata['threeKDartsId'] as String? ?? '';

  static String encodeMetadata({
    String nickname = '',
    String birthdate = '',
    String scoliaId = '',
    String autodartsName = '',
    String threeKDartsId = '',
  }) {
    return jsonEncode({
      if (nickname.trim().isNotEmpty) 'nickname': nickname.trim(),
      if (birthdate.trim().isNotEmpty) 'birthdate': birthdate.trim(),
      if (scoliaId.trim().isNotEmpty) 'scoliaId': scoliaId.trim(),
      if (autodartsName.trim().isNotEmpty) 'autodartsName': autodartsName.trim(),
      if (threeKDartsId.trim().isNotEmpty) 'threeKDartsId': threeKDartsId.trim(),
    });
  }

  PlayerProfile copyWith({
    String? displayName,
    String? country,
    String? city,
    String? dartsSetupJson,
  }) {
    return PlayerProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      country: country ?? this.country,
      city: city ?? this.city,
      dartsSetupJson: dartsSetupJson ?? this.dartsSetupJson,
      createdAt: createdAt,
      isActive: isActive,
    );
  }
}
