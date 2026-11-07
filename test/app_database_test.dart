import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dart_tournament_manager/features/achievements/application/ranking_achievement_service.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/local_player_statistics_page.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/shared/persistence/storage_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'schema 14 migration restores achievement progress and player refresh',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          'dart_achievement_progress_schema_14_test_',
        ),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );

      const ranking = LocalRanking(
        id: 'ranking',
        name: 'Rangliste',
        type: RankingType.series,
        achievementsEnabled: true,
      );
      final file = File('${directory.path}/app_database.sqlite');
      final oldDatabase = sqlite3.open(file.path);
      oldDatabase.execute('''
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
          ranking_type TEXT NOT NULL,
          config_json TEXT NOT NULL,
          custom_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE local_ranking_players (
          ranking_id TEXT NOT NULL,
          player_profile_id TEXT NOT NULL,
          PRIMARY KEY (ranking_id, player_profile_id)
        );
        CREATE TABLE player_monthly_performance (
          player_profile_id TEXT NOT NULL,
          year INTEGER NOT NULL,
          month INTEGER NOT NULL,
          weighted_legs INTEGER NOT NULL,
          scoring REAL,
          average REAL,
          checkout_rate REAL,
          PRIMARY KEY (player_profile_id, year, month)
        );
        CREATE TABLE monthly_player_statistics (
          player_profile_id TEXT NOT NULL,
          source_player_name TEXT NOT NULL,
          month TEXT NOT NULL,
          three_dart_average REAL NOT NULL,
          first_nine_average REAL NOT NULL,
          checkout_percentage REAL,
          legs INTEGER NOT NULL,
          matches INTEGER NOT NULL,
          PRIMARY KEY (player_profile_id, month)
        );
        CREATE TABLE ranking_achievement_progress (
          ranking_id TEXT NOT NULL,
          player_profile_id TEXT NOT NULL,
          achievement_id TEXT NOT NULL,
          current_value REAL NOT NULL,
          target_value REAL NOT NULL,
          status TEXT NOT NULL,
          unlocked_at TEXT,
          explanation TEXT NOT NULL DEFAULT '',
          is_final INTEGER NOT NULL DEFAULT 0,
          source_hash TEXT NOT NULL DEFAULT '',
          PRIMARY KEY (ranking_id, player_profile_id, achievement_id)
        );
        INSERT INTO player_profiles(id, display_name, created_at)
          VALUES ('player-1', 'Testspieler', '2026-01-01T00:00:00.000');
        INSERT INTO local_rankings(
          id, name, ranking_type, config_json, custom_order
        ) VALUES (
          'ranking', 'Rangliste', 'series',
          '${jsonEncode(ranking.toJson())}', 0
        );
        INSERT INTO local_ranking_players(ranking_id, player_profile_id)
          VALUES ('ranking', 'player-1');
        INSERT INTO ranking_achievement_progress(
          ranking_id, player_profile_id, achievement_id,
          current_value, target_value, status, explanation
        ) VALUES (
          'ranking', 'player-1', 'first_tournament_win',
          0, 1, 'locked', 'Noch kein Turniersieg.'
        );
        INSERT INTO monthly_player_statistics(
          player_profile_id, source_player_name, month,
          three_dart_average, first_nine_average, checkout_percentage,
          legs, matches
        ) VALUES (
          'player-1', 'Testspieler', '2026-01',
          55, 60, 25, 12, 4
        );
        PRAGMA user_version = 14;
      ''');
      oldDatabase.close();

      final legacyDatabase = sqlite3.open(file.path, mode: OpenMode.readOnly);
      expect(
        legacyDatabase.select('PRAGMA user_version').single.values.single,
        14,
      );
      expect(
        () => legacyDatabase.select(
          'SELECT alternative_current_value FROM ranking_achievement_progress',
        ),
        throwsA(isA<SqliteException>()),
      );
      legacyDatabase.close();

      final database = LocalAppDatabase(baseDirectory: directory);
      await tester.pumpWidget(
        MaterialApp(
          home: LocalPlayerStatisticsPage(
            name: 'Testspieler',
            profileIds: const {'player-1'},
            database: database,
            tournamentStorage: TournamentStorage(
              file: File('${directory.path}/tournaments.json'),
            ),
          ),
        ),
      );
      for (
        var attempt = 0;
        attempt < 20 && find.text('Spiele gespielt').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        find.text('Statistiken konnten nicht geladen werden.'),
        findsNothing,
      );
      expect(find.text('Spiele gespielt'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final (
        profiles,
        monthlyStatistics,
        stored,
        refreshed,
      ) = (await tester.runAsync(() async {
        final profiles = await database.loadPlayerProfiles();
        final monthlyStatistics = await database.loadMonthlyPlayerPerformances({
          'player-1',
        });
        final stored = await database.loadRankingAchievementProgress(
          ranking.id,
          'player-1',
        );
        final refreshed = await RankingAchievementService(database: database)
            .refreshPlayer(
              ranking: ranking,
              playerProfileId: 'player-1',
              tournaments: const [],
            );
        return (profiles, monthlyStatistics, stored, refreshed);
      }))!;
      expect(profiles.single.id, 'player-1');
      expect(monthlyStatistics, hasLength(1));
      expect(monthlyStatistics.single.threeDartAverage, 55);
      expect(stored['first_tournament_win']!['alternative_current_value'], 0);
      expect(stored['first_tournament_win']!['alternative_target_value'], 0);
      expect(
        refreshed.evaluation.progress['first_tournament_win']!.currentValue,
        0,
      );

      final migrated = sqlite3.open(file.path, mode: OpenMode.readOnly);
      expect(
        migrated.select('PRAGMA user_version').single.values.single,
        LocalAppDatabase.schemaVersion,
      );
      expect(
        migrated
            .select(
              '''SELECT alternative_current_value, alternative_target_value
                 FROM ranking_achievement_progress
                 WHERE ranking_id = 'ranking' AND player_profile_id = 'player-1'
                   AND achievement_id = 'first_tournament_win' ''',
            )
            .single
            .values
            .toList(),
        [0.0, 0.0],
      );
      migrated.close();
    },
  );

  test(
    'saving unchanged achievement progress does not mark local data dirty',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dart_achievement_progress_revision_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = LocalAppDatabase(baseDirectory: directory);
      final player = await database.createPlayerProfile(displayName: 'Spieler');
      const ranking = LocalRanking(id: 'ranking', name: 'Rangliste');
      await database.saveLocalRanking(ranking);
      final progress = [
        {
          'achievement_id': 'first_match',
          'current_value': 1.0,
          'target_value': 1.0,
          'status': 'completed',
          'unlocked_at': '2026-11-04T10:00:00.000Z',
          'explanation': 'Erster Erfolg',
          'is_final': 1,
          'source_hash': 'source',
        },
      ];

      final beforeInsert = StorageAccess.localDataRevision.value;
      await database.saveRankingAchievementProgress(
        rankingId: ranking.id,
        playerProfileId: player.id,
        progress: progress,
      );
      final afterInsert = StorageAccess.localDataRevision.value;
      expect(afterInsert, beforeInsert + 1);

      await database.saveRankingAchievementProgress(
        rankingId: ranking.id,
        playerProfileId: player.id,
        progress: progress,
      );
      expect(StorageAccess.localDataRevision.value, afterInsert);
    },
  );

  test(
    'monthly performance is loaded and updated by player and month',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dart_player_monthly_performance_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = LocalAppDatabase(baseDirectory: directory);
      final player = await database.createPlayerProfile(
        displayName: 'Monatsspieler',
      );
      final entry = PlayerMonthlyPerformance(
        playerId: player.id,
        year: 2026,
        month: 5,
        weightedLegs: 18,
        scoring: 57.4,
        average: 62.1,
        checkoutRate: 31.5,
      );

      await database.savePlayerMonthlyPerformance(entry);
      var entries = await database.loadPlayerMonthlyPerformance(
        player.id,
        year: 2026,
      );
      expect(entries, hasLength(1));
      expect(entries.single.periodKey, entry.periodKey);
      expect(entries.single.weightedLegs, entry.weightedLegs);
      expect(entries.single.scoring, entry.scoring);
      expect(entries.single.average, entry.average);
      expect(entries.single.checkoutRate, entry.checkoutRate);

      await database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: player.id,
          year: 2026,
          month: 5,
          weightedLegs: 24,
          scoring: null,
          average: 65,
          checkoutRate: 35,
        ),
      );
      entries = await database.loadPlayerMonthlyPerformance(player.id);
      expect(entries, hasLength(1));
      expect(entries.single.weightedLegs, 24);
      expect(entries.single.scoring, isNull);
      expect(entries.single.average, 65);
    },
  );

  test(
    'monthly performance can be loaded for multiple players and a year',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dart_player_monthly_performance_batch_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final database = LocalAppDatabase(baseDirectory: directory);
      final firstPlayer = await database.createPlayerProfile(
        displayName: 'Spieler Eins',
      );
      final secondPlayer = await database.createPlayerProfile(
        displayName: 'Spieler Zwei',
      );
      await database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: firstPlayer.id,
          year: 2026,
          month: 3,
          weightedLegs: 10,
          average: 88,
        ),
      );
      await database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: secondPlayer.id,
          year: 2025,
          month: 8,
          weightedLegs: 12,
          average: 92,
        ),
      );

      final currentYear = await database.loadPlayerMonthlyPerformanceForPlayers(
        {firstPlayer.id, secondPlayer.id},
        year: 2026,
      );
      final allYears = await database.loadPlayerMonthlyPerformanceForPlayers({
        firstPlayer.id,
        secondPlayer.id,
      });

      expect(currentYear, hasLength(1));
      expect(currentYear.single.playerId, firstPlayer.id);
      expect(allYears, hasLength(2));
    },
  );

  test('starts with an empty player catalog', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_tournament_manager_database_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);

    final databaseFile = await database.databaseFile();
    final profiles = await database.loadPlayerProfiles();
    final players = await database.loadTournamentPlayers();

    expect(databaseFile.path.endsWith('app_database.sqlite'), isTrue);
    expect(databaseFile.existsSync(), isTrue);
    expect(profiles, isEmpty);
    expect(players, isEmpty);
  });

  test('creates, updates and deactivates player profiles', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_tournament_manager_database_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);

    final created = await database.createPlayerProfile(
      displayName: 'Max Mustermann',
      country: 'Deutschland',
      city: 'Berlin',
      dartsSetupJson: '23g Steeldart',
    );

    var profiles = await database.loadPlayerProfiles();
    expect(
      profiles.where((profile) => profile.displayName == 'Max Mustermann'),
      hasLength(1),
    );

    await database.updatePlayerProfile(
      created.copyWith(
        displayName: 'Max Power',
        city: 'Hamburg',
        dartsSetupJson: '24g Steeldart',
      ),
    );

    profiles = await database.loadPlayerProfiles();
    final updated = profiles.singleWhere((profile) => profile.id == created.id);
    expect(updated.displayName, 'Max Power');
    expect(updated.city, 'Hamburg');
    expect(updated.dartsSetupJson, '24g Steeldart');

    await database.deactivatePlayerProfile(created.id);

    profiles = await database.loadPlayerProfiles();
    expect(profiles.any((profile) => profile.id == created.id), isFalse);
  });

  test('stores surnames and provides full and compact player names', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_tournament_manager_player_names_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = LocalAppDatabase(baseDirectory: directory);
    final profile = await database.createPlayerProfile(
      firstName: 'Max',
      lastName: 'Mustermann',
      dartsSetupJson: PlayerProfile.encodeMetadata(nickname: 'The Dart'),
    );

    expect(profile.displayName, 'Max Mustermann');
    expect(profile.compactDisplayName, 'The Dart');
    expect(profile.copyWith(dartsSetupJson: '{}').compactDisplayName, 'Max M.');

    final loaded = (await database.loadPlayerProfiles()).single;
    expect(loaded.firstName, 'Max');
    expect(loaded.lastName, 'Mustermann');
    expect(loaded.displayName, 'Max Mustermann');
    expect(loaded.compactDisplayName, 'The Dart');
    final tournamentPlayer = (await database.loadTournamentPlayers()).single;
    expect(tournamentPlayer.name, 'Max Mustermann');
    expect(tournamentPlayer.shortDisplayName, 'The Dart');
  });

  test('stores local rankings and their assigned player profiles', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_local_rankings_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(baseDirectory: directory);
    final player = await database.createPlayerProfile(
      displayName: 'Vereinsdart',
    );
    const ranking = LocalRanking(
      id: 'dc-unzenberg-2026',
      name: 'DC Unzenberg 2026',
      startRating: 1200,
      newPlayerK: 30,
      matchesBeforeNormal: 12,
    );

    await database.saveLocalRanking(ranking);
    await database.setRankingPlayers(ranking.id, [player.id]);

    expect((await database.loadLocalRankings()).single.startRating, 1200);
    expect(await database.loadRankingPlayerIds(ranking.id), [player.id]);
    expect(
      (await database.loadRankingsForPlayer(player.id)).single.name,
      'DC Unzenberg 2026',
    );

    await database.deleteLocalRanking(ranking.id);
    expect(await database.loadRankingPlayerIds(ranking.id), isEmpty);
  });

  test('keeps only one ranking marked as the statistics default', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_local_ranking_default_test_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final database = LocalAppDatabase(baseDirectory: directory);

    await database.saveLocalRanking(
      const LocalRanking(
        id: 'first',
        name: 'First',
        isDefaultForStatistics: true,
      ),
    );
    await database.saveLocalRanking(
      const LocalRanking(
        id: 'second',
        name: 'Second',
        isDefaultForStatistics: true,
      ),
    );

    final rankings = await database.loadLocalRankings();
    expect(
      rankings
          .where((ranking) => ranking.isDefaultForStatistics)
          .map((r) => r.id),
      ['second'],
    );
  });

  test('migrates existing rankings and persists their custom order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_local_rankings_order_migration_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/app_database.sqlite');
    final oldDatabase = sqlite3.open(file.path);
    oldDatabase.execute('''
      CREATE TABLE player_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        darts_setup_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    oldDatabase.execute('''
      CREATE TABLE local_rankings (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        ranking_type TEXT NOT NULL CHECK (ranking_type IN ('elo', 'series')),
        config_json TEXT NOT NULL
      )
    ''');
    for (final ranking in [
      const LocalRanking(id: 'z', name: 'Z Rangliste', startRating: 1250),
      const LocalRanking(id: 'a', name: 'A Rangliste', startRating: 1150),
    ]) {
      oldDatabase.execute('INSERT INTO local_rankings VALUES (?, ?, ?, ?)', [
        ranking.id,
        ranking.name,
        ranking.type.name,
        jsonEncode(ranking.toJson()),
      ]);
    }
    oldDatabase.execute('PRAGMA user_version = 9');
    oldDatabase.close();

    final database = LocalAppDatabase(baseDirectory: directory);
    var rankings = await database.loadLocalRankings();
    expect(rankings.map((ranking) => ranking.name), [
      'A Rangliste',
      'Z Rangliste',
    ]);
    expect(rankings.map((ranking) => ranking.customOrder), [0, 1]);
    expect(rankings.map((ranking) => ranking.startRating), [1150, 1250]);

    await database.saveLocalRankingOrder(['z', 'a']);
    rankings = await LocalAppDatabase(
      baseDirectory: directory,
    ).loadLocalRankings();
    expect(rankings.map((ranking) => ranking.id), ['z', 'a']);
    expect(rankings.map((ranking) => ranking.customOrder), [0, 1]);
  });

  test('adds surname column to schema 10 without changing player data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_player_surname_migration_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/app_database.sqlite');
    final oldDatabase = sqlite3.open(file.path);
    oldDatabase.execute('''
      CREATE TABLE player_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        darts_setup_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    oldDatabase.execute(
      "INSERT INTO player_profiles (id, display_name, created_at) "
      "VALUES ('legacy', 'Max Mustermann', '2026-01-01T00:00:00.000')",
    );
    oldDatabase.execute('PRAGMA user_version = 10');
    oldDatabase.close();

    final profiles = await LocalAppDatabase(
      baseDirectory: directory,
    ).loadPlayerProfiles();

    expect(profiles.single.displayName, 'Max Mustermann');
    expect(profiles.single.lastName, isEmpty);
    expect(
      directory.listSync().whereType<File>().any(
        (candidate) => candidate.path.contains('.v10.'),
      ),
      isTrue,
    );
    final migrated = sqlite3.open(file.path, mode: OpenMode.readOnly);
    expect(
      migrated.select('PRAGMA user_version').single.values.single,
      LocalAppDatabase.schemaVersion,
    );
    expect(
      migrated.select(
        "SELECT name FROM sqlite_master WHERE name = 'monthly_player_statistics'",
      ),
      hasLength(1),
    );
    expect(
      migrated.select(
        "SELECT name FROM sqlite_master WHERE name = 'player_monthly_performance'",
      ),
      hasLength(1),
    );
    migrated.close();
  });

  test('adds monthly player statistics to schema 11', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_monthly_statistics_migration_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/app_database.sqlite');
    final oldDatabase = sqlite3.open(file.path);
    oldDatabase.execute('''
      CREATE TABLE player_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        last_name TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        darts_setup_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    oldDatabase.execute(
      "INSERT INTO player_profiles(id, display_name, created_at) "
      "VALUES ('player-1', 'Testspieler', '2026-01-01T00:00:00.000')",
    );
    oldDatabase.execute('PRAGMA user_version = 11');
    oldDatabase.close();

    final database = LocalAppDatabase(baseDirectory: directory);
    expect(await database.loadMonthlyPlayerPerformances({'player-1'}), isEmpty);
    final migrated = sqlite3.open(file.path, mode: OpenMode.readOnly);
    expect(
      migrated.select('PRAGMA user_version').single.values.single,
      LocalAppDatabase.schemaVersion,
    );
    expect(
      migrated.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'monthly_player_statistics'",
      ),
      hasLength(1),
    );
    expect(
      migrated.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'player_monthly_performance'",
      ),
      hasLength(1),
    );
    migrated.close();
  });

  test(
    'schema 13 migration preserves prior monthly performance data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dart_monthly_statistics_schema_13_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      final file = File('${directory.path}/app_database.sqlite');
      final oldDatabase = sqlite3.open(file.path);
      oldDatabase.execute('''
      CREATE TABLE player_profiles (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        last_name TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        city TEXT NOT NULL DEFAULT '',
        darts_setup_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE player_monthly_performance (
        player_profile_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        weighted_legs INTEGER NOT NULL,
        scoring REAL,
        average REAL,
        checkout_rate REAL,
        PRIMARY KEY(player_profile_id, year, month)
      );
      INSERT INTO player_profiles(id, display_name, created_at)
        VALUES ('player-1', 'Testspieler', '2026-01-01T00:00:00.000');
      INSERT INTO player_monthly_performance(
        player_profile_id, year, month, weighted_legs, scoring, average
      ) VALUES ('player-1', 2026, 1, 12, 42.5, 65.2);
      PRAGMA user_version = 13;
    ''');
      oldDatabase.close();

      final database = LocalAppDatabase(baseDirectory: directory);
      expect(
        await database.loadMonthlyPlayerPerformances({'player-1'}),
        isEmpty,
      );

      final migrated = sqlite3.open(file.path, mode: OpenMode.readOnly);
      expect(
        migrated.select('PRAGMA user_version').single.values.single,
        LocalAppDatabase.schemaVersion,
      );
      expect(
        migrated
            .select('''SELECT weighted_legs, scoring, average
               FROM player_monthly_performance
               WHERE player_profile_id = 'player-1' AND year = 2026 AND month = 1''')
            .single
            .values
            .toList(),
        [12, 42.5, 65.2],
      );
      expect(
        migrated.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name = 'monthly_player_statistics'",
        ),
        hasLength(1),
      );
      migrated.close();
    },
  );

  test('rejects unknown old SQLite schema without changing its data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'dart_local_database_unknown_schema_test_',
    );
    addTearDown(() => directory.delete(recursive: true));

    final file = File('${directory.path}/app_database.sqlite');
    final old = sqlite3.open(file.path);
    old.execute('CREATE TABLE legacy_data (value TEXT NOT NULL)');
    old.execute("INSERT INTO legacy_data VALUES ('keep')");
    old.execute('PRAGMA user_version = 2');
    old.close();
    final originalBytes = await file.readAsBytes();

    await expectLater(
      LocalAppDatabase(baseDirectory: directory).loadPlayerProfiles(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('kann nicht sicher migriert werden'),
        ),
      ),
    );

    expect(await file.readAsBytes(), originalBytes);
    expect(directory.listSync().whereType<File>(), hasLength(1));
    final unchanged = sqlite3.open(file.path, mode: OpenMode.readOnly);
    expect(unchanged.select('PRAGMA user_version').single.values.single, 2);
    expect(
      unchanged.select('SELECT value FROM legacy_data').single['value'],
      'keep',
    );
    unchanged.close();
  });

  test('keeps player profile id in tournament player json', () {
    const player = TournamentPlayer(
      profileId: 'profile-1',
      name: 'Anna Check',
      isGenerated: false,
      compactName: 'Ace',
    );

    final restored = TournamentPlayer.fromJson(player.toJson());

    expect(restored.profileId, 'profile-1');
    expect(restored.name, 'Anna Check');
    expect(restored.shortDisplayName, 'Ace');
    expect(restored.isGenerated, isFalse);
  });
}
