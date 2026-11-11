import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/statistics/presentation/live_tournament_statistics_section.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    testWidgets('live tournament statistics at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final tournament = CreatedTournament(
        name: 'Laufendes Turnier',
        players: [],
        stages: [],
        runStages: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LiveTournamentStatisticsSection(tournament: tournament),
            ),
          ),
        ),
      );
      expect(find.text('Turnierstatistik'), findsOneWidget);
      expect(
        find.text(
          'Noch keine abgeschlossenen Begegnungen mit menschlichen Teilnehmern.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
