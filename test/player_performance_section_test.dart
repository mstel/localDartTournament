import 'package:dart_tournament_manager/features/statistics/domain/player_monthly_performance.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/widgets/player_performance_section.dart';
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
      expect(find.text('Ausgewertet: 100 gewertete Legs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });
}
