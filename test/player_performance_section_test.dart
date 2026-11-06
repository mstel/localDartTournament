import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/player_performance_section.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/performance_statistics_detail_section.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders performance for responsive sizes and large text', (
    tester,
  ) async {
    const performance = [
      PlayerMonthlyPerformance(
        playerId: 'player',
        year: 2000,
        month: 2,
        weightedLegs: 30,
        scoring: 50,
        average: 50,
        checkoutRate: 40,
      ),
      PlayerMonthlyPerformance(
        playerId: 'player',
        year: 2000,
        month: 1,
        weightedLegs: 70,
        scoring: 40,
        average: 40,
        checkoutRate: 30,
      ),
    ];

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
            home: Scaffold(
              body: AdaptiveContentList(
                children: [PlayerPerformanceSection(performance: performance)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Performance (gesamt)'), findsOneWidget);
      expect(find.text('Aktuelle Form: letzte 100 Legs'), findsOneWidget);
      expect(find.text('Ausgewertet: 100 gewertete Legs'), findsNothing);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('short current form adjusts its heading to available legs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerPerformanceSection(
            performance: [
              PlayerMonthlyPerformance(
                playerId: 'player',
                year: DateTime.now().year - 1,
                month: 4,
                weightedLegs: 64,
                scoring: 55,
                average: 80,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Aktuelle Form: letzte 64 Legs'), findsOneWidget);
    expect(find.textContaining('Ausgewertet:'), findsNothing);
  });

  testWidgets('monthly detail defaults to this year and shows annual totals', (
    tester,
  ) async {
    final year = DateTime.now().year;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PerformanceStatisticsDetailSection(
              entries: [
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: year,
                  month: 9,
                  matches: 5,
                  weightedLegs: 16,
                  scoring: 60,
                  average: 45,
                ),
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: year - 1,
                  month: 2,
                  matches: 3,
                  weightedLegs: 10,
                  scoring: 50,
                  average: 40,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Performance Statistiken im Detail'));
    await tester.pumpAndSettle();

    expect(find.text('September'), findsOneWidget);
    expect(find.text('Jahresschnitt und Summen'), findsOneWidget);
    expect(find.text('Partien: 5'), findsOneWidget);
    expect(find.text('Gewertete Legs: 16'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Jahresschnitt und Summen')).dy,
      lessThan(tester.getTopLeft(find.byType(DataTable)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('monthly detail heading wraps on a narrow large-text layout', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: PerformanceStatisticsDetailSection(entries: const []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find.text('Performance Statistiken im Detail'),
    );
    expect(title.maxLines, 2);
    expect(title.softWrap, isTrue);
    expect(tester.takeException(), isNull);
  });
}
