import 'package:dart_tournament_manager/features/players/presentation/player_performance_entry_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabase extends LocalAppDatabase {
  _FakeDatabase({this.initial});

  final PlayerMonthlyPerformance? initial;
  PlayerMonthlyPerformance? saved;

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async {
    final entry = saved ?? initial;
    return [if (entry != null && entry.playerId == playerId) entry];
  }

  @override
  Future<void> savePlayerMonthlyPerformance(
    PlayerMonthlyPerformance performance,
  ) async {
    saved = performance;
  }
}

Future<void> tapSave(WidgetTester tester) async {
  final button = find.byType(FilledButton);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
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
