import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/player_performance_trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('separate metric charts show data point details', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerPerformanceTrendChart(
              year: 2026,
              entries: const [
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: 2026,
                  month: 2,
                  matches: 4,
                  weightedLegs: 12,
                  scoring: 50,
                  average: 80,
                  checkoutRate: 40,
                ),
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: 2026,
                  month: 4,
                  matches: 7,
                  weightedLegs: 20,
                  scoring: 60,
                  average: 90,
                  checkoutRate: 50,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scoring · 2026'), findsOneWidget);
    expect(find.text('Average · 2026'), findsOneWidget);
    expect(find.text('Checkout Quote · 2026'), findsOneWidget);
    final chart = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 180,
    );
    final firstChart = chart.first;
    final topLeft = tester.getTopLeft(firstChart);
    final chartSize = tester.getSize(firstChart);
    final monthFourX = topLeft.dx + chartSize.width - 8;
    await tester.tapAt(Offset(monthFourX, topLeft.dy + 60));
    await tester.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);
    expect(find.text('Partien: 7'), findsOneWidget);
    expect(find.text('Gewertete Legs: 20'), findsOneWidget);
    expect(find.text('Scoring: 60.0'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip).first).message,
      contains('Partien: 7'),
    );
    expect(tester.takeException(), isNull);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('chart starts and ends at months with data', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlayerPerformanceTrendChart(
              year: 2026,
              entries: const [
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: 2026,
                  month: 7,
                  matches: 3,
                  weightedLegs: 9,
                  scoring: 50,
                  average: 80,
                  checkoutRate: 40,
                ),
                PlayerMonthlyPerformance(
                  playerId: 'player',
                  year: 2026,
                  month: 9,
                  matches: 5,
                  weightedLegs: 15,
                  scoring: 60,
                  average: 90,
                  checkoutRate: 50,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 180,
    );
    final firstChart = chart.first;
    final topLeft = tester.getTopLeft(firstChart);
    final chartSize = tester.getSize(firstChart);
    await tester.tapAt(
      Offset(topLeft.dx + chartSize.width - 8, topLeft.dy + 60),
    );
    await tester.pumpAndSettle();

    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Partien: 5'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip).first).message,
      contains('Partien: 5'),
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
    'chart remains responsive at mobile, tablet, desktop and 200% text',
    (tester) async {
      final entries = [
        for (final month in [1, 4, 8])
          PlayerMonthlyPerformance(
            playerId: 'player',
            year: DateTime.now().year,
            month: month,
            matches: month,
            weightedLegs: month * 4,
            scoring: 45 + month.toDouble(),
            average: 75 + month.toDouble(),
            checkoutRate: 30 + month.toDouble(),
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
                body: SingleChildScrollView(
                  child: PlayerPerformanceTrendChart(
                    year: DateTime.now().year,
                    entries: entries,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}
