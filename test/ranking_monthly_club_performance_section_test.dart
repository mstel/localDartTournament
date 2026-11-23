import 'package:dart_tournament_manager/features/rankings/application/ranking_year_review_service.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/player_performance_trend_chart.dart';
import 'package:dart_tournament_manager/features/rankings/presentation/widgets/ranking_monthly_club_performance_section.dart';
import 'package:dart_tournament_manager/shared/widgets/adaptive_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('club performance adapts to narrow layouts and large text', (
    tester,
  ) async {
    const monthlyPerformance = [
      RankingMonthlyClubPerformance(
        year: 2026,
        month: 1,
        weightedLegs: 40,
        matches: 10,
        wins: 7,
        losses: 3,
        scoring: 49,
        average: 87.1,
        checkoutRate: 43.4,
      ),
      RankingMonthlyClubPerformance(
        year: 2026,
        month: 2,
        weightedLegs: 100,
        matches: 20,
        wins: 12,
        losses: 8,
        scoring: 60,
        average: 95,
        checkoutRate: 50,
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
                children: const [
                  RankingMonthlyClubPerformanceSection(
                    monthlyPerformance: monthlyPerformance,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gesamt-Performance pro Monat'), findsOneWidget);
      expect(find.textContaining('2026'), findsNWidgets(4));
      expect(find.text('Siegesrate · 2026'), findsOneWidget);
      final chart = tester.widget<PlayerPerformanceTrendChart>(
        find.byType(PlayerPerformanceTrendChart),
      );
      expect(chart.entries.map((entry) => entry.wins), [7, 12]);
      expect(chart.entries.map((entry) => entry.losses), [3, 8]);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
