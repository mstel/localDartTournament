import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/planning_suggestion_card.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/models/match_result.dart';

void main() {
  testWidgets(
    'suggestion card displays both stage formats and time calculations',
    (tester) async {
      final suggestion = const TournamentFormatPlanner()
          .suggestFormats(
            const TournamentPlanningRequest(
              players: 13,
              boards: 4,
              minimumMatchesPerPlayer: 3,
              minimumMinutes: 120,
              maximumMinutes: 360,
              maximumGroups: 3,
              x01Selection: 'variable_301_501',
              checkoutType: 'double_out',
            ),
          )
          .firstWhere((s) => s.stages.length == 2);
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanningSuggestionCard(
                suggestion: suggestion,
                onSelected: () => selected = true,
              ),
            ),
          ),
        ),
      );
      for (final stage in suggestion.stages) {
        expect(
          find.text('${stage.label}: ${stage.format.label}'),
          findsOneWidget,
        );
      }
      expect(
        find.textContaining(
          'Gruppen: ${suggestion.duration!.groupSlots} Zeitblöcke',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'KO: ${suggestion.duration!.knockoutSlots} Zeitblöcke',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(suggestion.title));
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('set result entry records sets separately from aggregate legs', (
    tester,
  ) async {
    MatchResult? result;
    final match = GroupMatch(
      round: 1,
      homePlayer: TournamentPlayer.generated(1),
      awayPlayer: TournamentPlayer.generated(2),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<MatchResult>(
                  context: context,
                  builder: (_) => ResultDialog(
                    match: match,
                    format: const TournamentGameFormat(
                      bestOfSets: 3,
                      bestOfLegs: 5,
                    ),
                  ),
                );
              },
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.enterText(
        find.byKey(ValueKey('set-result-$i')),
        ['2', '1', '6', '7'][i],
      );
    }
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result?.homeSets, 2);
    expect(result?.awaySets, 1);
    expect(result?.homeLegs, 6);
    expect(result?.awayLegs, 7);
    expect(tester.takeException(), isNull);
  });
}
