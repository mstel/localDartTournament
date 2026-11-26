import 'dart:io';

import 'package:dart_tournament_manager/features/statistics/domain/performance_snapshot.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Directory> _tempDirectory() =>
    Directory.systemTemp.createTemp('performance_snapshot_test_');

PerformanceSnapshot _snapshot(
  String playerId,
  int year,
  int month,
  int legs, {
  required double average,
}) {
  return PerformanceSnapshot.create(
    id: '$playerId-$year-$month',
    playerId: playerId,
    year: year,
    month: month,
    windowLegs: legs,
    matches: legs ~/ 10,
    average: average,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('cumulative snapshots derive months and allow corrections', (
    tester,
  ) async {
    final directory = (await tester.runAsync(_tempDirectory))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final database = LocalAppDatabase(baseDirectory: directory);
    final profile = (await tester.runAsync(
      () => database.createPlayerProfile(displayName: 'Testspieler'),
    ))!;

    await tester.runAsync(
      () => database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: profile.id,
          year: 2026,
          month: 9,
          weightedLegs: 12,
          average: 55,
        ),
      ),
    );

    await tester.runAsync(
      () => database.savePerformanceSnapshotAndRebuild(
        _snapshot(profile.id, 2026, 10, 30, average: 42),
      ),
    );
    await tester.runAsync(
      () => database.savePerformanceSnapshotAndRebuild(
        _snapshot(profile.id, 2026, 11, 60, average: 43),
      ),
    );

    final snapshots = (await tester.runAsync(
      () => database.loadPerformanceSnapshots(profile.id),
    ))!;
    expect(snapshots, hasLength(2));
    expect(snapshots.first.averageTotal, closeTo(1260, 0.0001));
    expect(snapshots.last.averageTotal, closeTo(2580, 0.0001));

    final entries = (await tester.runAsync(
      () => database.loadPlayerMonthlyPerformance(profile.id),
    ))!;
    expect(entries, hasLength(3));
    final september = entries.firstWhere((entry) => entry.month == 9);
    expect(september.average, 55);
    expect(september.source, 'manual');
    final october = entries.firstWhere((entry) => entry.month == 10);
    expect(october.average, 42);
    expect(october.source, 'scolia_cumulative');
    final november = entries.firstWhere((entry) => entry.month == 11);
    expect(november.weightedLegs, 30);
    expect(november.average, closeTo(44, 0.0001));
    expect(november.source, 'scolia_cumulative');

    await tester.runAsync(
      () => database.savePerformanceSnapshotAndRebuild(
        _snapshot(profile.id, 2026, 10, 30, average: 43),
      ),
    );
    final corrected = (await tester.runAsync(
      () => database.loadPlayerMonthlyPerformance(profile.id),
    ))!;
    expect(
      corrected.firstWhere((entry) => entry.month == 11).average,
      closeTo(43, 0.0001),
    );
  });

  testWidgets('deleting a snapshot rebuilds the remaining derived months', (
    tester,
  ) async {
    final directory = (await tester.runAsync(_tempDirectory))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final database = LocalAppDatabase(baseDirectory: directory);
    final profile = (await tester.runAsync(
      () => database.createPlayerProfile(displayName: 'Testspieler'),
    ))!;

    await tester.runAsync(
      () => database.savePlayerMonthlyPerformance(
        PlayerMonthlyPerformance(
          playerId: profile.id,
          year: 2026,
          month: 9,
          weightedLegs: 12,
          average: 55,
        ),
      ),
    );
    await tester.runAsync(
      () => database.savePerformanceSnapshotAndRebuild(
        _snapshot(profile.id, 2026, 10, 30, average: 42),
      ),
    );
    await tester.runAsync(
      () => database.savePerformanceSnapshotAndRebuild(
        _snapshot(profile.id, 2026, 11, 60, average: 43),
      ),
    );

    await tester.runAsync(
      () => database.deletePerformanceSnapshotAndRebuild(
        playerId: profile.id,
        year: 2026,
        month: 10,
      ),
    );

    final snapshots = (await tester.runAsync(
      () => database.loadPerformanceSnapshots(profile.id),
    ))!;
    expect(snapshots.map((entry) => entry.month), [11]);

    final entries = (await tester.runAsync(
      () => database.loadPlayerMonthlyPerformance(profile.id),
    ))!;
    expect(entries.map((entry) => entry.month), [9, 11]);
    final september = entries.firstWhere((entry) => entry.month == 9);
    expect(september.source, 'manual');
    expect(september.average, 55);
    final november = entries.firstWhere((entry) => entry.month == 11);
    expect(november.source, 'scolia_cumulative');
    expect(november.weightedLegs, 60);
    expect(november.average, 43);
  });

  testWidgets('schema 17 migration adds snapshot storage without data loss', (
    tester,
  ) async {
    final directory = (await tester.runAsync(_tempDirectory))!;
    addTearDown(() => tester.runAsync(() => directory.delete(recursive: true)));
    final file = File('${directory.path}/app_database.sqlite');
    final legacy = sqlite3.open(file.path);
    legacy.execute('''
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
      CREATE TABLE player_monthly_performance (
        player_profile_id TEXT NOT NULL,
        year INTEGER NOT NULL,
        month INTEGER NOT NULL,
        weighted_legs INTEGER NOT NULL,
        matches INTEGER NOT NULL DEFAULT 0,
        wins INTEGER NOT NULL DEFAULT 0,
        losses INTEGER NOT NULL DEFAULT 0,
        scoring REAL,
        average REAL,
        checkout_rate REAL,
        PRIMARY KEY (player_profile_id, year, month)
      );
      INSERT INTO player_profiles(id, display_name, created_at)
        VALUES ('player-1', 'Testspieler', '2026-01-01T00:00:00.000');
      INSERT INTO player_monthly_performance(player_profile_id, year, month, weighted_legs, average)
        VALUES ('player-1', 2026, 9, 20, 55);
      PRAGMA user_version = 17;
    ''');
    legacy.close();

    final database = LocalAppDatabase(baseDirectory: directory);
    final entries = (await tester.runAsync(
      () => database.loadPlayerMonthlyPerformance('player-1'),
    ))!;
    expect(entries.single.average, 55);
    expect(entries.single.source, 'manual');
    expect(
      await tester.runAsync(
        () => database.loadPerformanceSnapshots('player-1'),
      ),
      isEmpty,
    );
    final version = (await tester.runAsync(() async {
      final raw = sqlite3.open(file.path);
      final value = raw.select('PRAGMA user_version').single.values.single;
      raw.close();
      return value;
    }))!;
    expect(version, LocalAppDatabase.schemaVersion);
  });
}
