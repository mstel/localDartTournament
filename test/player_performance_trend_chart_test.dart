import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/player_performance_trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('chart supports series toggles and data point details', (
    tester,
  ) async {
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

    expect(find.text('Trendkurven anzeigen'), findsOneWidget);
    final chart = find.byWidgetPredicate(
      (widget) => widget is SizedBox && widget.height == 180,
    );
    final topLeft = tester.getTopLeft(chart);
    final chartSize = tester.getSize(chart);
    final monthFourX = topLeft.dx + 30 + (chartSize.width - 38) * 3 / 11;
    await tester.tapAt(Offset(monthFourX, topLeft.dy + 60));
    await tester.pumpAndSettle();
    expect(find.text('April 2026'), findsOneWidget);
    expect(find.text('Partien: 7'), findsOneWidget);
    expect(find.text('Gewertete Legs: 20'), findsOneWidget);
    expect(find.text('Scoring: 60.0'), findsOneWidget);

    await tester.tap(find.text('Scoring').first);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Scoring').first).style?.decoration,
      TextDecoration.lineThrough,
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

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
