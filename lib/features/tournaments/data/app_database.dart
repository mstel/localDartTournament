import '../../../shared/persistence/storage_access.dart';

import 'dart:convert';
import 'dart:math';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../../shared/persistence/app_data_directory.dart';

import 'package:sqlite3/sqlite3.dart';

import '../domain/tournament_models.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../statistics/domain/monthly_player_performance.dart';
import '../../statistics/domain/player_monthly_performance.dart';

class LocalAppDatabase {
  LocalAppDatabase({Directory? baseDirectory}) : _baseDirectory = baseDirectory;

  static const schemaVersion = 16;

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
        SELECT id, display_name, last_name, country, city, darts_setup_json,
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

  Future<List<MonthlyPlayerPerformance>> loadMonthlyPlayerPerformances(
    Set<String> playerProfileIds, {
    int? year,
  }) async {
    if (playerProfileIds.isEmpty) return const [];
    return StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        final ids = playerProfileIds.toList()..sort();
        final placeholders = List.filled(ids.length, '?').join(', ');
        final rows = database.select(
          '''SELECT player_profile_id, source_player_name, month,
                    three_dart_average, first_nine_average,
                    checkout_percentage, legs, matches
             FROM monthly_player_statistics
             WHERE player_profile_id IN ($placeholders)
             ${year == null ? '' : 'AND substr(month, 1, 4) = ?'}
             ORDER BY month DESC, source_player_name COLLATE NOCASE''',
          [...ids, if (year != null) year.toString()],
        );
        return [
          for (final row in rows)
            MonthlyPlayerPerformance.fromRow(Map<String, Object?>.from(row)),
        ];
      } finally {
        database.close();
      }
    });
  }

  Future<void> saveMonthlyPlayerPerformances(
    List<MonthlyPlayerPerformance> records,
  ) async {
    if (records.isEmpty) return;
    final keys = <String>{};
    for (final record in records) {
      if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(record.month) ||
          record.playerProfileId.isEmpty ||
          record.sourcePlayerName.trim().isEmpty ||
          !record.threeDartAverage.isFinite ||
          record.threeDartAverage < 0 ||
          !record.firstNineAverage.isFinite ||
          record.firstNineAverage < 0 ||
          (record.checkoutPercentage != null &&
              (!record.checkoutPercentage!.isFinite ||
                  record.checkoutPercentage! < 0 ||
                  record.checkoutPercentage! > 100)) ||
          record.legs < 0 ||
          record.matches < 0) {
        throw ArgumentError('Ungültiger Monatsstatistik-Datensatz.');
      }
      if (!keys.add('${record.playerProfileId}|${record.month}')) {
        throw ArgumentError(
          'Teilnehmer und Monat dürfen im Import nur einmal vorkommen.',
        );
      }
    }

    await StorageAccess.run(() async {
      final database = await _openDatabase();
      try {
        database.execute('BEGIN');
        try {
          for (final record in records) {
            final profile = database.select(
              'SELECT is_active FROM player_profiles WHERE id = ?',
              [record.playerProfileId],
            );
            if (profile.isEmpty || profile.single['is_active'] != 1) {
              throw StateError(
                'Ein zugeordneter Teilnehmer ist nicht mehr aktiv.',
              );
            }
            database.execute(
              '''INSERT INTO monthly_player_statistics(
                   player_profile_id, source_player_name, month,
                   three_dart_average, first_nine_average,
                   checkout_percentage, legs, matches
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(player_profile_id, month) DO UPDATE SET
                   source_player_name = excluded.source_player_name,
                   three_dart_average = excluded.three_dart_average,
                   first_nine_average = excluded.first_nine_average,
                   checkout_percentage = excluded.checkout_percentage,
                   legs = excluded.legs,
                   matches = excluded.matches''',
              [
                record.playerProfileId,
                record.sourcePlayerName.trim(),
                record.month,
                record.threeDartAverage,
                record.firstNineAverage,
                record.checkoutPercentage,
                record.legs,
                record.matches,
              ],
            );
          }
          database.execute('COMMIT');
        } catch (_) {
          database.execute('ROLLBACK');
          rethrow;
        }
        StorageAccess.markLocalDataChanged();
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
          '''SELECT config_json, custom_order FROM local_rankings
             ORDER BY custom_order, name COLLATE NOCASE, id''',
        ))
          LocalRanking.fromJson(
            Map<String, Object?>.from(
              jsonDecode(row['config_json'] as String) as Map,
            ),
          ).copyWith(customOrder: row['custom_order'] as int? ?? 0),
      ];
    } finally {
      database.close();
    }
  });

  Future<Map<String, Map<String, Object?>>> loadRankingAchievementProgress(
    String rankingId,
    String playerProfileId,
  ) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      final rows = database.select(
        '''SELECT achievement_id, current_value, alternative_current_value,
                  target_value, alternative_target_value, status,
                  unlocked_at, explanation, is_final, source_hash
           FROM ranking_achievement_progress
           WHERE ranking_id = ? AND player_profile_id = ?''',
        [rankingId, playerProfileId],
      );
      return {
        for (final row in rows)
          row['achievement_id'] as String: Map<String, Object?>.from(row),
      };
    } finally {
      database.close();
    }
  });

  Future<void> saveRankingAchievementProgress({
    required String rankingId,
    required String playerProfileId,
    required Iterable<Map<String, Object?>> progress,
  }) => StorageAccess.run(() async {
    final entries = progress.toList();
    final database = await _openDatabase();
    var changed = false;
    try {
      database.execute('BEGIN');
      try {
        for (final item in entries) {
          database.execute(
            '''INSERT INTO ranking_achievement_progress(
                 ranking_id, player_profile_id, achievement_id,
                 current_value, target_value, status, unlocked_at,
                 explanation, is_final, source_hash,
                 alternative_current_value, alternative_target_value
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
               ON CONFLICT(ranking_id, player_profile_id, achievement_id)
               DO UPDATE SET
                 current_value = excluded.current_value,
                 alternative_current_value = excluded.alternative_current_value,
                 target_value = excluded.target_value,
                 alternative_target_value = excluded.alternative_target_value,
                 status = excluded.status,
                 unlocked_at = excluded.unlocked_at,
                 explanation = excluded.explanation,
                 is_final = excluded.is_final,
                 source_hash = excluded.source_hash
               WHERE current_value IS NOT excluded.current_value
                  OR target_value IS NOT excluded.target_value
                  OR alternative_current_value IS NOT excluded.alternative_current_value
                  OR alternative_target_value IS NOT excluded.alternative_target_value
                  OR status IS NOT excluded.status
                  OR unlocked_at IS NOT excluded.unlocked_at
                  OR explanation IS NOT excluded.explanation
                  OR is_final IS NOT excluded.is_final
                  OR source_hash IS NOT excluded.source_hash''',
            [
              rankingId,
              playerProfileId,
              item['achievement_id'],
              item['current_value'],
              item['target_value'],
              item['status'],
              item['unlocked_at'],
              item['explanation'],
              item['is_final'],
              item['source_hash'],
              item['alternative_current_value'] ?? 0,
              item['alternative_target_value'] ?? 0,
            ],
          );
          changed =
              (database.select('SELECT changes() AS changed').first['changed']
                      as int) >
                  0 ||
              changed;
        }
        database.execute('COMMIT');
        if (changed) StorageAccess.markLocalDataChanged();
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
    } finally {
      database.close();
    }
  });

  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      final rows = database.select(
        '''SELECT player_profile_id, year, month, weighted_legs,
                  scoring, average, checkout_rate
           FROM player_monthly_performance
           WHERE player_profile_id = ?${year == null ? '' : ' AND year = ?'}
           ORDER BY year, month''',
        year == null ? [playerId] : [playerId, year],
      );
      return [
        for (final row in rows)
          PlayerMonthlyPerformance.fromRow(Map<String, Object?>.from(row)),
      ];
    } finally {
      database.close();
    }
  });

  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformanceForPlayers(
    Set<String> playerIds, {
    int? year,
  }) => StorageAccess.run(() async {
    if (playerIds.isEmpty) return const [];
    final database = await _openDatabase();
    try {
      final ids = playerIds.toList()..sort();
      final performances = <PlayerMonthlyPerformance>[];
      for (var start = 0; start < ids.length; start += 900) {
        final batch = ids.skip(start).take(900).toList();
        final rows = database.select(
          '''SELECT player_profile_id, year, month, weighted_legs,
                    scoring, average, checkout_rate
             FROM player_monthly_performance
             WHERE player_profile_id IN (${List.filled(batch.length, '?').join(',')})
             ${year == null ? '' : 'AND year = ?'}
             ORDER BY year, month, player_profile_id''',
          [...batch, ?year],
        );
        performances.addAll(
          rows.map(
            (row) => PlayerMonthlyPerformance.fromRow(
              Map<String, Object?>.from(row),
            ),
          ),
        );
      }
      return performances;
    } finally {
      database.close();
    }
  });

  Future<void> savePlayerMonthlyPerformance(
    PlayerMonthlyPerformance performance,
  ) => StorageAccess.run(() async {
    if (performance.month < 1 ||
        performance.month > 12 ||
        performance.weightedLegs < 0 ||
        performance.scoring != null &&
            (!performance.scoring!.isFinite || performance.scoring! < 0) ||
        performance.average != null &&
            (!performance.average!.isFinite || performance.average! < 0) ||
        performance.checkoutRate != null &&
            (!performance.checkoutRate!.isFinite ||
                performance.checkoutRate! < 0 ||
                performance.checkoutRate! > 100)) {
      throw ArgumentError('Performance-Daten sind ungültig.');
    }
    final database = await _openDatabase();
    try {
      database.execute(
        '''INSERT INTO player_monthly_performance(
             player_profile_id, year, month, weighted_legs,
             scoring, average, checkout_rate
           ) VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(player_profile_id, year, month) DO UPDATE SET
             weighted_legs = excluded.weighted_legs,
             scoring = excluded.scoring,
             average = excluded.average,
             checkout_rate = excluded.checkout_rate''',
        [
          performance.playerId,
          performance.year,
          performance.month,
          performance.weightedLegs,
          performance.scoring,
          performance.average,
          performance.checkoutRate,
        ],
      );
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<void> saveLocalRanking(
    LocalRanking ranking,
  ) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      final existing = database.select(
        'SELECT custom_order FROM local_rankings WHERE id = ?',
        [ranking.id],
      );
      final customOrder = existing.isNotEmpty
          ? existing.first['custom_order'] as int
          : database
                    .select(
                      'SELECT COALESCE(MAX(custom_order), -1) + 1 AS next_order FROM local_rankings',
                    )
                    .first['next_order']
                as int;
      database.execute('BEGIN');
      try {
        if (ranking.isDefaultForStatistics) {
          for (final row in database.select(
            'SELECT id, config_json FROM local_rankings WHERE id != ?',
            [ranking.id],
          )) {
            final config = LocalRanking.fromJson(
              Map<String, Object?>.from(
                jsonDecode(row['config_json'] as String) as Map,
              ),
            );
            if (config.isDefaultForStatistics) {
              database.execute(
                'UPDATE local_rankings SET config_json = ? WHERE id = ?',
                [
                  jsonEncode(
                    config.copyWith(isDefaultForStatistics: false).toJson(),
                  ),
                  row['id'],
                ],
              );
            }
          }
        }
        database.execute(
          '''INSERT INTO local_rankings(
               id, name, ranking_type, config_json, custom_order
             )
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name,
               ranking_type=excluded.ranking_type, config_json=excluded.config_json''',
          [
            ranking.id,
            ranking.name.trim(),
            ranking.type.name,
            jsonEncode(ranking.toJson()),
            customOrder,
          ],
        );
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<List<CreatedTournament>>
  loadActiveTournamentCopies() => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      return [
        for (final row in database.select(
          'SELECT tournament_json FROM active_tournament_copies ORDER BY updated_at DESC',
        ))
          CreatedTournament.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(row['tournament_json'] as String) as Map,
            ),
          ),
      ];
    } finally {
      database.close();
    }
  });

  Future<CreatedTournament?> loadActiveTournamentCopy(String id) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          final rows = database.select(
            'SELECT tournament_json FROM active_tournament_copies WHERE id = ?',
            [id],
          );
          if (rows.isEmpty) return null;
          return CreatedTournament.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(rows.single['tournament_json'] as String) as Map,
            ),
          );
        } finally {
          database.close();
        }
      });

  Future<void> saveActiveTournamentCopy(
    CreatedTournament tournament,
  ) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      final now = DateTime.now();
      tournament.updatedAt = now;
      database.execute(
        '''INSERT INTO active_tournament_copies(id, tournament_json, updated_at)
               VALUES (?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                 tournament_json = excluded.tournament_json,
                 updated_at = excluded.updated_at''',
        [tournament.id, jsonEncode(tournament.toJson()), now.toIso8601String()],
      );
    } finally {
      database.close();
    }
    StorageAccess.markLocalDataChanged();
  });

  Future<void> deleteActiveTournamentCopy(String id) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          database.execute(
            'DELETE FROM active_tournament_copies WHERE id = ?',
            [id],
          );
        } finally {
          database.close();
        }
      });

  Future<void> clearActiveTournamentCopies() => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      database.execute('DELETE FROM active_tournament_copies');
    } finally {
      database.close();
    }
    StorageAccess.markLocalDataChanged();
  });

  Future<void> deleteLocalRanking(String rankingId) =>
      StorageAccess.run(() async {
        final database = await _openDatabase();
        try {
          database.execute('DELETE FROM local_rankings WHERE id = ?', [
            rankingId,
          ]);
          StorageAccess.markLocalDataChanged();
        } finally {
          database.close();
        }
      });

  Future<void> saveLocalRankingOrder(
    List<String> rankingIds,
  ) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      final storedIds = {
        for (final row in database.select('SELECT id FROM local_rankings'))
          row['id'] as String,
      };
      if (storedIds.length != rankingIds.length ||
          storedIds.length != rankingIds.toSet().length ||
          !storedIds.containsAll(rankingIds)) {
        throw ArgumentError(
          'Die benutzerdefinierte Reihenfolge muss jede Rangliste genau einmal enthalten.',
        );
      }

      database.execute('BEGIN');
      try {
        for (var index = 0; index < rankingIds.length; index++) {
          database.execute(
            'UPDATE local_rankings SET custom_order = ? WHERE id = ?',
            [index, rankingIds[index]],
          );
        }
        database.execute('COMMIT');
      } catch (_) {
        database.execute('ROLLBACK');
        rethrow;
      }
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<List<String>> loadRankingPlayerIds(
    String rankingId,
  ) => StorageAccess.run(() async {
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
                Map<String, Object?>.from(
                  jsonDecode(row['config_json'] as String) as Map,
                ),
              ),
          ];
        } finally {
          database.close();
        }
      });

  Future<void> setRankingPlayers(
    String rankingId,
    Iterable<String> playerIds,
  ) => StorageAccess.run(() async {
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

  Future<List<Map<String, Object?>>> loadChallongePlayerLinks({
    String source = 'challonge',
  }) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      return [
        for (final row in database.select(
          'SELECT challonge_name, player_profile_id FROM challonge_player_links WHERE source = ? ORDER BY challonge_name COLLATE NOCASE',
          [source],
        ))
          {
            'challongeName': row['challonge_name'],
            'playerProfileId': row['player_profile_id'],
          },
      ];
    } finally {
      database.close();
    }
  });

  Future<void> saveChallongePlayerLink(
    String name,
    String playerId, {
    String source = 'challonge',
  }) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      database.execute(
        '''INSERT INTO challonge_player_links(source, normalized_name, challonge_name, player_profile_id)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(source, normalized_name) DO UPDATE SET challonge_name=excluded.challonge_name, player_profile_id=excluded.player_profile_id''',
        [
          source,
          name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
          name.trim(),
          playerId,
        ],
      );
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
  });

  Future<void> deleteChallongePlayerLink(
    String name, {
    String source = 'challonge',
  }) => StorageAccess.run(() async {
    final database = await _openDatabase();
    try {
      database.execute(
        'DELETE FROM challonge_player_links WHERE source = ? AND normalized_name = ?',
        [source, name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')],
      );
      StorageAccess.markLocalDataChanged();
    } finally {
      database.close();
    }
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
            compactName: profile.compactDisplayName,
          ),
      ];
    });
  }

  Future<File> databaseFile() => _databaseFile();

  Future<PlayerProfile> createPlayerProfile({
    String? displayName,
    String? firstName,
    String lastName = '',
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
          firstName: (firstName ?? displayName ?? '').trim(),
          lastName: lastName.trim(),
          country: country.trim(),
          city: city.trim(),
          dartsSetupJson: dartsSetupJson.trim(),
          createdAt: now,
          isActive: true,
        );
        database.execute(
          '''
        INSERT INTO player_profiles (
          id, display_name, last_name, country, city, darts_setup_json,
          created_at, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            profile.id,
            profile.firstName,
            profile.lastName,
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
        SET display_name = ?, last_name = ?, country = ?, city = ?,
            darts_setup_json = ?
        WHERE id = ?
        ''',
          [
            profile.firstName.trim(),
            profile.lastName.trim(),
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
      if (version > 0 && version < 9) {
        throw StateError(
          'Lokale Datenbank-Version $version kann nicht sicher migriert werden. '
          'Die Datei wurde nicht verändert. Bitte erstelle eine Kopie der '
          'Datenbank und öffne sie mit einer passenden App-Version.',
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
      if (currentVersion == 15) {
        _createActiveTournamentCopiesTable(database);
      } else if (currentVersion == 14) {
        _createRankingAchievementProgressTable(database);
      } else if (currentVersion == 13) {
        _createRankingAchievementProgressTable(database);
        _createMonthlyPlayerStatisticsTable(database);
      } else if (currentVersion == 12) {
        _createRankingAchievementProgressTable(database);
        _createMonthlyPlayerStatisticsTable(database);
      } else if (currentVersion == 11) {
        _createPlayerMonthlyPerformanceTable(database);
        _createRankingAchievementProgressTable(database);
        _createMonthlyPlayerStatisticsTable(database);
      } else if (currentVersion == 10) {
        database.execute(
          "ALTER TABLE player_profiles ADD COLUMN last_name TEXT NOT NULL DEFAULT ''",
        );
        _createPlayerMonthlyPerformanceTable(database);
        _createRankingAchievementProgressTable(database);
        _createMonthlyPlayerStatisticsTable(database);
      } else if (currentVersion == 9) {
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
        database.execute(
          "ALTER TABLE player_profiles ADD COLUMN last_name TEXT NOT NULL DEFAULT ''",
        );
        _createPlayerMonthlyPerformanceTable(database);
        _createRankingAchievementProgressTable(database);
        _createMonthlyPlayerStatisticsTable(database);
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
      _createActiveTournamentCopiesTable(database);
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
        last_name TEXT NOT NULL DEFAULT '',
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
    _createPlayerMonthlyPerformanceTable(database);
    _createRankingAchievementProgressTable(database);
    _createMonthlyPlayerStatisticsTable(database);
    _createActiveTournamentCopiesTable(database);
  }

  void _createActiveTournamentCopiesTable(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS active_tournament_copies (
        id TEXT PRIMARY KEY,
        tournament_json TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_active_tournament_copies_updated
        ON active_tournament_copies(updated_at);
    ''');
  }

  void _createMonthlyPlayerStatisticsTable(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS monthly_player_statistics (
        player_profile_id TEXT NOT NULL
          REFERENCES player_profiles(id) ON DELETE CASCADE,
        source_player_name TEXT NOT NULL,
        month TEXT NOT NULL CHECK (
          length(month) = 7 AND
          substr(month, 1, 4) GLOB '[0-9][0-9][0-9][0-9]' AND
          substr(month, 6, 2) GLOB '[0-9][0-9]' AND
          CAST(substr(month, 6, 2) AS INTEGER) BETWEEN 1 AND 12
        ),
        three_dart_average REAL NOT NULL CHECK (three_dart_average >= 0),
        first_nine_average REAL NOT NULL CHECK (first_nine_average >= 0),
        checkout_percentage REAL CHECK (
          checkout_percentage IS NULL OR
          checkout_percentage BETWEEN 0 AND 100
        ),
        legs INTEGER NOT NULL CHECK (legs >= 0),
        matches INTEGER NOT NULL CHECK (matches >= 0),
        PRIMARY KEY (player_profile_id, month)
      );
      CREATE INDEX IF NOT EXISTS idx_monthly_player_statistics_month
        ON monthly_player_statistics(month);
    ''');
  }

  void _createPlayerMonthlyPerformanceTable(Database database) {
    database.execute('''
      CREATE TABLE player_monthly_performance (
        player_profile_id TEXT NOT NULL
          REFERENCES player_profiles(id) ON DELETE CASCADE,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
        weighted_legs INTEGER NOT NULL CHECK (weighted_legs >= 0),
        scoring REAL,
        average REAL,
        checkout_rate REAL CHECK (
          checkout_rate IS NULL OR checkout_rate BETWEEN 0 AND 100
        ),
        PRIMARY KEY (player_profile_id, year, month)
      )
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

  void _createRankingAchievementProgressTable(Database database) {
    database.execute('''
      CREATE TABLE IF NOT EXISTS ranking_achievement_progress (
        ranking_id TEXT NOT NULL
          REFERENCES local_rankings(id) ON DELETE CASCADE,
        player_profile_id TEXT NOT NULL
          REFERENCES player_profiles(id) ON DELETE CASCADE,
        achievement_id TEXT NOT NULL,
        current_value REAL NOT NULL CHECK (current_value >= 0),
        alternative_current_value REAL NOT NULL DEFAULT 0
          CHECK (alternative_current_value >= 0),
        target_value REAL NOT NULL CHECK (target_value >= 0),
        alternative_target_value REAL NOT NULL DEFAULT 0
          CHECK (alternative_target_value >= 0),
        status TEXT NOT NULL
          CHECK (status IN ('locked', 'inProgress', 'completed')),
        unlocked_at TEXT,
        explanation TEXT NOT NULL DEFAULT '',
        is_final INTEGER NOT NULL DEFAULT 0 CHECK (is_final IN (0, 1)),
        source_hash TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (ranking_id, player_profile_id, achievement_id)
      );

      CREATE INDEX IF NOT EXISTS idx_ranking_achievement_player
        ON ranking_achievement_progress(player_profile_id, ranking_id);
    ''');
    final columns = database
        .select('PRAGMA table_info(ranking_achievement_progress)')
        .map((row) => row['name'] as String)
        .toSet();
    if (!columns.contains('alternative_current_value')) {
      database.execute(
        'ALTER TABLE ranking_achievement_progress '
        'ADD COLUMN alternative_current_value REAL NOT NULL DEFAULT 0',
      );
    }
    if (!columns.contains('alternative_target_value')) {
      database.execute(
        'ALTER TABLE ranking_achievement_progress '
        'ADD COLUMN alternative_target_value REAL NOT NULL DEFAULT 0',
      );
    }
  }
}

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    String? displayName,
    String? firstName,
    this.lastName = '',
    required this.country,
    required this.city,
    required this.dartsSetupJson,
    required this.createdAt,
    required this.isActive,
  }) : firstName = firstName ?? displayName ?? '';

  factory PlayerProfile.fromRow(Row row) {
    return PlayerProfile(
      id: row['id'] as String? ?? '',
      firstName: row['display_name'] as String? ?? '',
      lastName: row['last_name'] as String? ?? '',
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
  final String firstName;
  final String lastName;
  String get displayName =>
      [firstName, lastName].where((part) => part.trim().isNotEmpty).join(' ');
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
  String get compactDisplayName {
    if (nickname.trim().isNotEmpty) return nickname.trim();
    if (lastName.trim().isEmpty) return firstName;
    return '$firstName ${lastName.trim()[0]}.';
  }

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
      if (autodartsName.trim().isNotEmpty)
        'autodartsName': autodartsName.trim(),
      if (threeKDartsId.trim().isNotEmpty)
        'threeKDartsId': threeKDartsId.trim(),
    });
  }

  PlayerProfile copyWith({
    String? displayName,
    String? firstName,
    String? lastName,
    String? country,
    String? city,
    String? dartsSetupJson,
  }) {
    return PlayerProfile(
      id: id,
      firstName: firstName ?? displayName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      country: country ?? this.country,
      city: city ?? this.city,
      dartsSetupJson: dartsSetupJson ?? this.dartsSetupJson,
      createdAt: createdAt,
      isActive: isActive,
    );
  }
}
