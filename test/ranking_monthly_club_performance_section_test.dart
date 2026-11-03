import 'package:dart_tournament_manager/features/rankings/application/ranking_year_review_service.dart';
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
        month: 1,
        weightedLegs: 40,
        scoring: 49,
        average: 87.1,
        checkoutRate: 43.4,
      ),
      RankingMonthlyClubPerformance(
        month: 2,
        weightedLegs: 100,
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

      expect(find.text('Vereinsentwicklung pro Monat'), findsOneWidget);
      expect(find.text('40 Legs'), findsOneWidget);
      expect(find.text('Scoring: 49.0'), findsOneWidget);
      expect(find.text('Average: 87.1'), findsOneWidget);
      expect(find.text('Checkout-Quote: 43.4 %'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
