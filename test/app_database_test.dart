import 'dart:io';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    );

    final restored = TournamentPlayer.fromJson(player.toJson());

    expect(restored.profileId, 'profile-1');
    expect(restored.name, 'Anna Check');
    expect(restored.isGenerated, isFalse);
  });
}
