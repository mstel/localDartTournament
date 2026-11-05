import 'package:dart_tournament_manager/features/players/presentation/player_performance_entry_page.dart';
import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/tournaments/data/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDatabase extends LocalAppDatabase {
  PlayerMonthlyPerformance? saved;

  @override
  Future<List<PlayerMonthlyPerformance>> loadPlayerMonthlyPerformance(
    String playerId, {
    int? year,
  }) async => [
    if (saved case final entry? when entry.playerId == playerId)
      entry,
  ];

  @override
  Future<void> savePlayerMonthlyPerformance(
    PlayerMonthlyPerformance performance,
  ) async {
    saved = performance;
  }
}

void main() {
  testWidgets('monthly performance values can be entered and saved', (
    tester,
  ) async {
    final database = _FakeDatabase();
    final player = PlayerProfile(
      id: 'player-1',
      displayName: 'Testspieler',
      country: '',
      city: '',
      dartsSetupJson: '',
      createdAt: DateTime.utc(2026),
      isActive: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPerformanceEntryPage(player: player, database: database),
      ),
    );
    await tester.pumpAndSettle();

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
    await tester.tap(find.text('Monatswerte speichern'));
    await tester.pumpAndSettle();

    expect(database.saved?.weightedLegs, 24);
    expect(database.saved?.scoring, 57.4);
    expect(database.saved?.average, 62.1);
    expect(database.saved?.checkoutRate, 31.5);
  });
}
