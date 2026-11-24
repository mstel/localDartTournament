import 'package:dart_tournament_manager/features/players/presentation/player_performance_entry_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/performance_snapshot.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabase extends LocalAppDatabase {
  _FakeDatabase({this.initial});

  final PlayerMonthlyPerformance? initial;
  PlayerMonthlyPerformance? saved;
  final List<PerformanceSnapshot> snapshots = [];
  List<DerivedPerformanceMonth> derived = [];

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async {
    final entries = <PlayerMonthlyPerformance>[
      if (saved != null && saved!.playerId == playerId) saved!,
      if (saved == null && initial != null && initial!.playerId == playerId)
        initial!,
    ];
    for (final month in derived) {
      entries.removeWhere(
        (entry) => entry.year == month.year && entry.month == month.month,
      );
      entries.add(
        PlayerMonthlyPerformance(
          playerId: playerId,
          year: month.year,
          month: month.month,
          weightedLegs: month.weightedLegs,
          matches: month.matches,
          scoring: month.scoring,
          average: month.average,
          checkoutRate: month.checkoutRate,
          source: 'scolia_cumulative',
        ),
      );
    }
    return entries;
  }

  @override
  Future<void> savePlayerMonthlyPerformance(
    PlayerMonthlyPerformance performance,
  ) async {
    saved = performance;
  }

  @override
  Future<List<PerformanceSnapshot>> loadPerformanceSnapshots(
    String playerId,
  ) async {
    return List.unmodifiable(snapshots);
  }

  @override
  Future<List<DerivedPerformanceMonth>> savePerformanceSnapshotAndRebuild(
    PerformanceSnapshot snapshot,
  ) async {
    snapshots.removeWhere(
      (entry) => entry.year == snapshot.year && entry.month == snapshot.month,
    );
    snapshots.add(snapshot);
    derived = derivePerformanceMonths(snapshots).months;
    return derived;
  }
}

Future<void> tapSave(WidgetTester tester) async {
  final button = find.byType(FilledButton);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  late PlayerProfile player;

  setUp(() {
    player = PlayerProfile(
      id: 'player-1',
      displayName: 'Testspieler',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime.utc(2026),
      isActive: true,
    );
  });

  Future<void> pumpPage(WidgetTester tester, LocalAppDatabase database) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPerformanceEntryPage(player: player, database: database),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectMonth(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('performance-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectScoliaMode(WidgetTester tester) async {
    await tester.tap(find.text('Scolia kumulativ'));
    await tester.pumpAndSettle();
  }

  testWidgets('monthly performance values can be entered and saved', (
    tester,
  ) async {
    final database = _FakeDatabase();
    await pumpPage(tester, database);

    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '24',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-scoring')),
      '57,4',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-average')),
      '62.1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-checkout')),
      '31,5',
    );
    await tapSave(tester);

    expect(database.saved?.weightedLegs, 24);
    expect(database.saved?.scoring, 57.4);
    expect(database.saved?.average, 62.1);
    expect(database.saved?.checkoutRate, 31.5);
    expect(
      find.textContaining('aus den zugewiesenen Turnieren'),
      findsOneWidget,
    );
  });

  testWidgets('derived match counts are not editable and survive saving', (
    tester,
  ) async {
    final now = DateTime.now();
    final database = _FakeDatabase(
      initial: PlayerMonthlyPerformance(
        playerId: player.id,
        year: now.year,
        month: now.month,
        weightedLegs: 30,
        matches: 9,
        wins: 6,
        losses: 3,
        average: 55,
      ),
    );
    await pumpPage(tester, database);

    expect(find.byKey(const ValueKey('performance-matches')), findsNothing);
    expect(find.byKey(const ValueKey('performance-wins')), findsNothing);
    expect(find.byKey(const ValueKey('performance-losses')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '36',
    );
    await tapSave(tester);

    expect(database.saved?.weightedLegs, 36);
    expect(database.saved?.matches, 9);
    expect(database.saved?.wins, 6);
    expect(database.saved?.losses, 3);
    expect(database.saved?.winRate, closeTo(66.666, 0.001));
  });

  testWidgets('negative or non-integer weighted legs are rejected', (
    tester,
  ) async {
    final database = _FakeDatabase();
    await pumpPage(tester, database);

    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '-1',
    );
    await tapSave(tester);
    expect(database.saved, isNull);
    expect(find.textContaining('nicht negative ganze Zahlen'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '1.5',
    );
    await tapSave(tester);
    expect(database.saved, isNull);
  });

  testWidgets('scolia cumulative snapshots derive the next month', (
    tester,
  ) async {
    final database = _FakeDatabase();
    await pumpPage(tester, database);
    await selectScoliaMode(tester);

    await selectMonth(tester, 'Oktober');
    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '30',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-scolia-matches')),
      '3',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-average')),
      '42',
    );
    await tapSave(tester);

    expect(database.snapshots, hasLength(1));
    expect(
      database.derived.singleWhere((month) => month.month == 10).average,
      closeTo(42, 0.0001),
    );
    await dismissSnackBars(tester);

    await selectMonth(tester, 'November');
    await tester.enterText(
      find.byKey(const ValueKey('performance-weighted-legs')),
      '60',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-scolia-matches')),
      '6',
    );
    await tester.enterText(
      find.byKey(const ValueKey('performance-average')),
      '43',
    );
    await tapSave(tester);

    final november = database.derived.singleWhere((month) => month.month == 11);
    expect(november.weightedLegs, 30);
    expect(november.matches, 3);
    expect(november.average, closeTo(44, 0.0001));
    expect(
      find.textContaining('Monatswert abgeleitet: 30 Legs'),
      findsOneWidget,
    );
  });

  testWidgets(
    'full scolia window asks for the new legs and accepts a correction',
    (tester) async {
      final database = _FakeDatabase();
      await pumpPage(tester, database);
      await selectScoliaMode(tester);

      await selectMonth(tester, 'Oktober');
      await tester.enterText(
        find.byKey(const ValueKey('performance-weighted-legs')),
        '28',
      );
      await tester.enterText(
        find.byKey(const ValueKey('performance-average')),
        '42',
      );
      await tapSave(tester);
      await dismissSnackBars(tester);

      await selectMonth(tester, 'November');
      await tester.enterText(
        find.byKey(const ValueKey('performance-weighted-legs')),
        '78',
      );
      await tester.enterText(
        find.byKey(const ValueKey('performance-average')),
        '${(28 * 42 + 50 * 44) / 78}',
      );
      await tapSave(tester);
      await dismissSnackBars(tester);

      await selectMonth(tester, 'Dezember');
      await tester.enterText(
        find.byKey(const ValueKey('performance-weighted-legs')),
        '100',
      );
      await tester.enterText(
        find.byKey(const ValueKey('performance-average')),
        '${(10 * 42 + 50 * 44 + 40 * 46) / 100}',
      );
      await tapSave(tester);

      expect(
        database.derived.singleWhere((month) => month.month == 12).isEstimated,
        isTrue,
      );
      await dismissSnackBars(tester);
      expect(
        find.byKey(const ValueKey('performance-scolia-window-info')),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final newLegsField = find.byKey(
        const ValueKey('performance-scolia-new-legs'),
      );
      expect(newLegsField, findsOneWidget);
      await tester.enterText(newLegsField, '40');
      await tapSave(tester);

      final december = database.derived.singleWhere(
        (month) => month.month == 12,
      );
      expect(december.weightedLegs, 40);
      expect(december.average, closeTo(46, 0.0001));
      expect(december.isEstimated, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('entry form stays renderable at mobile, tablet and desktop', (
    tester,
  ) async {
    for (final size in [
      const Size(360, 800),
      const Size(800, 600),
      const Size(1440, 900),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(2),
          ),
          child: MaterialApp(
            home: PlayerPerformanceEntryPage(
              player: player,
              database: _FakeDatabase(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('save button has a touch-friendly target on a narrow screen', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = _FakeDatabase();
    await pumpPage(tester, database);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    final button = find.byType(FilledButton);
    expect(button, findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
