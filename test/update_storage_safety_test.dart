import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:dart_tournament_manager/features/tournaments/data/tournament_storage.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/rankings/domain/local_ranking.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('update_safety');
    file = File('${directory.path}/tournaments.json');
  });
  tearDown(() => directory.delete(recursive: true));

  for (final content in [
    '',
    '[]',
    '{broken',
    '{"schemaVersion":99,"tournaments":[]}',
    '{"schemaVersion":6,"tournaments":[null]}',
  ]) {
    test('invalid or future document is never overwritten: $content', () async {
      await file.writeAsString(content);
      final storage = TournamentStorage(file: file);
      await expectLater(storage.loadTournaments(), throwsFormatException);
      await expectLater(
        storage.saveTournament(_tournament()),
        throwsFormatException,
      );
      expect(await file.readAsString(), content);
    });
  }

  test('migration preserves exact original and subsequent backup', () async {
    const original = '{"schemaVersion":1,"tournaments":[],"custom":"keep"}';
    await file.writeAsString(original);
    final storage = TournamentStorage(file: file);
    await storage.saveTournament(_tournament());
    expect(await File('${file.path}.v1.bak').readAsString(), original);
    final first = await file.readAsString();
    await storage.saveTournament(
      CreatedTournament(
        id: 'new-safety',
        name: 'New safety',
        players: const [],
        stages: const [],
        runStages: const [],
      ),
    );
    expect(await File('${file.path}.bak').readAsString(), first);
    expect(await File('${file.path}.v1.bak').readAsString(), original);
    expect(jsonDecode(await file.readAsString())['custom'], 'keep');
  });

  test(
    'unknown tournament version reports its version and remains untouched',
    () async {
      const content = '{"schemaVersion":25,"tournaments":[]}';
      await file.writeAsString(content);
      final storage = TournamentStorage(file: file);

      try {
        await storage.loadTournaments();
        fail('A future storage version must not be interpreted as supported.');
      } on FormatException catch (error) {
        expect(error.message, contains('Version 25'));
        expect(error.message, contains('1 bis 24'));
      }

      await expectLater(
        storage.saveTournament(_tournament()),
        throwsFormatException,
      );
      expect(await file.readAsString(), content);
    },
  );

  test(
    'schema 24 documents from v1.0.3 remain readable and writable',
    () async {
      final legacyTournament = _tournament().toJson()
        ..['countsForRanking'] = false
        ..['rankingIds'] = ['ranking-1'];
      final current = jsonEncode({
        'schemaVersion': 24,
        'tournaments': [legacyTournament],
        'playerStatistics': {'total': 7},
      });
      await file.writeAsString(current);
      final storage = TournamentStorage(file: file);

      final loaded = await storage.loadTournaments();
      expect(loaded.single.countsForRanking, isFalse);
      expect(loaded.single.rankingIds, ['ranking-1']);
      expect(await file.readAsString(), current);

      await storage.saveTournament(
        CreatedTournament(
          id: 'new-schema-24-record',
          name: 'New schema 24 record',
          players: const [],
          stages: const [],
          runStages: const [],
        ),
      );

      final saved = jsonDecode(await file.readAsString());
      expect(saved['schemaVersion'], 24);
      expect(saved['playerStatistics'], {'total': 7});
      expect((saved['tournaments'] as List).length, 2);
      expect(
        (saved['tournaments'] as List).singleWhere(
          (item) => item['name'] == 'Safety',
        )['countsForRanking'],
        isFalse,
      );
      expect(
        (saved['tournaments'] as List).singleWhere(
          (item) => item['name'] == 'Safety',
        )['rankingIds'],
        ['ranking-1'],
      );
      expect(await File('${file.path}.bak').readAsString(), current);
    },
  );

  test(
    'newer SQLite database is rejected without changing its schema',
    () async {
      final path = '${directory.path}/app_database.sqlite';
      final database = sqlite3.open(path);
      database.execute('PRAGMA user_version = 99');
      database.close();
      await expectLater(
        LocalAppDatabase(baseDirectory: directory).loadPlayerProfiles(),
        throwsStateError,
      );
      final reopened = sqlite3.open(path);
      expect(reopened.select('PRAGMA user_version').first.values.single, 99);
      reopened.close();
    },
  );

  test('SQLite migration creates a readable pre-migration backup', () async {
    final storage = LocalAppDatabase(baseDirectory: directory);
    await storage.loadPlayerProfiles();
    final database = sqlite3.open('${directory.path}/app_database.sqlite');
    database.execute('PRAGMA user_version = 2');
    database.close();
    await storage.loadPlayerProfiles();
    final backup = directory.listSync().whereType<File>().singleWhere(
      (f) => f.path.endsWith('.bak'),
    );
    final old = sqlite3.open(backup.path);
    expect(old.select('PRAGMA user_version').first.values.single, 2);
    old.close();
  });

  test('v9 to v10 migration keeps players, rankings and assignments', () async {
    final path = '${directory.path}/app_database.sqlite';
    final old = sqlite3.open(path);
    old.execute('''
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
        ranking_type TEXT NOT NULL,
        config_json TEXT NOT NULL
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
      CREATE INDEX idx_player_profiles_display_name ON player_profiles(display_name);
      PRAGMA user_version = 9;
    ''');
    old.execute('''INSERT INTO player_profiles(
        id, display_name, created_at
      ) VALUES ('player-1', 'Testspieler', '2026-01-01T00:00:00.000')''');
    old.execute(
      '''INSERT INTO local_rankings(id, name, ranking_type, config_json)
         VALUES (?, ?, ?, ?)''',
      [
        'ranking-1',
        'Vereinsrangliste',
        'elo',
        jsonEncode(
          const LocalRanking(
            id: 'ranking-1',
            name: 'Vereinsrangliste',
            startRating: 1200,
          ).toJson(),
        ),
      ],
    );
    old.execute(
      '''INSERT INTO local_ranking_players(ranking_id, player_profile_id)
         VALUES ('ranking-1', 'player-1')''',
    );
    old.close();

    final storage = LocalAppDatabase(baseDirectory: directory);
    expect(
      (await storage.loadPlayerProfiles()).single.displayName,
      'Testspieler',
    );
    expect((await storage.loadLocalRankings()).single.startRating, 1200);
    expect(await storage.loadRankingPlayerIds('ranking-1'), ['player-1']);

    final migrated = sqlite3.open(path, mode: OpenMode.readOnly);
    expect(migrated.select('PRAGMA user_version').single.values.single, 10);
    expect(
      migrated
          .select('SELECT custom_order FROM local_rankings')
          .single
          .values
          .single,
      0,
    );
    migrated.close();

    final backup = directory.listSync().whereType<File>().singleWhere(
      (candidate) => candidate.path.contains('.v9.'),
    );
    final original = sqlite3.open(backup.path, mode: OpenMode.readOnly);
    expect(original.select('PRAGMA user_version').single.values.single, 9);
    expect(
      original.select('SELECT id FROM player_profiles').single['id'],
      'player-1',
    );
    original.close();
  });
}

CreatedTournament _tournament() => CreatedTournament(
  id: 'safety',
  name: 'Safety',
  players: const [],
  stages: const [],
  runStages: const [],
);
