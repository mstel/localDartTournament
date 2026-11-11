import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/tournament_schedule_pdf_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CreatedTournament _tournament(TournamentRunStage? stage) => CreatedTournament(
  name: 'Testturnier',
  players: const [],
  stages: const [],
  runStages: stage == null ? const [] : [stage],
);

void main() {
  testWidgets('Swiss and Kratzer schedule exports are disabled with a reason', (
    tester,
  ) async {
    final swiss = GroupTournamentRunStage(
      name: 'Swiss',
      groupPlayType: 'swiss',
      groups: [],
      qualificationPlan: null,
      tieBreakers: const [],
    );
    final kratzer = KnockoutTournamentRunStage(
      name: 'Kratzer',
      rounds: const [],
      isKratzer: true,
    );

    for (final stage in [swiss, kratzer]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TournamentSchedulePdfButton(tournament: _tournament(stage)),
          ),
        ),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'Druck / Exportfunktionen des Spielplans für diesen Modus deaktiviert',
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('supported tournament schedules expose the print action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TournamentSchedulePdfButton(tournament: _tournament(null)),
        ),
      ),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
