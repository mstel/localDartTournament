import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/brackets/knockout_seeding_mode_label.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show KnockoutBracketView;

void main() {
  group('knockoutSeedingModeLabel', () {
    test('uses the shared German labels for every seeding mode', () {
      expect(
        knockoutSeedingModeLabel('cross'),
        'Gruppenplatzierung - Feste Kreuzpaarungen',
      );
      expect(
        knockoutSeedingModeLabel('random_cross'),
        'Gruppenplatzierung - Zufällige Kreuzpaarungen',
      );
      expect(
        knockoutSeedingModeLabel('elo'),
        'Leistungsbasierte Setzliste (ELO)',
      );
      expect(knockoutSeedingModeLabel('manual'), 'Manuelle Paarungszuordnung');
      expect(
        knockoutSeedingModeLabel('random'),
        'Zufallsauslosung beim Turnierstart',
      );
      expect(
        knockoutSeedingModeLabel('unknown'),
        'Gruppenplatzierung - Feste Kreuzpaarungen',
      );
    });

    test('reads the mode from the matching planning stage', () {
      const runStage = KnockoutTournamentRunStage(name: 'KO', rounds: []);
      final tournament = CreatedTournament(
        name: 'Turnier',
        players: const [],
        stages: const [
          TournamentStage(
            name: 'KO',
            type: 'knockout',
            knockoutSeedingMode: 'elo',
          ),
        ],
        runStages: const [runStage],
      );

      expect(
        knockoutSeedingModeLabelForStage(tournament, runStage),
        'Leistungsbasierte Setzliste (ELO)',
      );
      expect(knockoutSeedingModeLabelForStage(null, runStage), isNull);
    });
  });

  group('KnockoutBracketView draw-method caption', () {
    const stage = KnockoutTournamentRunStage(name: 'KO', rounds: []);
    Future<void> onEditResult(GroupMatch match) async {}

    Widget buildView({String? drawMethodLabel}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KnockoutBracketView(
            stage: stage,
            qualifyingRank: 1,
            onEditResult: onEditResult,
            canEditResults: false,
            drawMethodLabel: drawMethodLabel,
          ),
        ),
      ),
    );

    testWidgets('is hidden when no label is provided', (tester) async {
      await tester.pumpWidget(buildView());

      expect(find.textContaining('Auslosungsmethode:'), findsNothing);
    });

    testWidgets('is shown below the tree when a label is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildView(drawMethodLabel: knockoutSeedingModeLabel('random')),
      );

      expect(
        find.text('Auslosungsmethode: Zufallsauslosung beim Turnierstart'),
        findsOneWidget,
      );
    });

    testWidgets('does not overflow inside bounded bracket areas', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 320,
              child: KnockoutBracketView(
                stage: stage,
                qualifyingRank: 1,
                onEditResult: onEditResult,
                canEditResults: false,
                drawMethodLabel: knockoutSeedingModeLabel('elo'),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.text('Auslosungsmethode: Leistungsbasierte Setzliste (ELO)'),
        findsOneWidget,
      );
    });
  });
}
