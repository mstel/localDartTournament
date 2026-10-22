import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/result_entry.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/models/match_result.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime, TournamentFormatPlannerDialog;

void main() {
  test('even lengths use minimum winning legs and capped maximum', () {
    expect(PlanningDuration.estimatedLegs(2), 2);
    expect(PlanningDuration.estimatedLegs(4), 3.5);
    expect(PlanningDuration.estimatedLegs(6), 5);
    expect(PlanningDuration.estimatedLegs(100), 75.5);
  });
  test('draws give one point each and count as completed matches', () {
    final a = TournamentPlayer.generated(1), b = TournamentPlayer.generated(2);
    final match = GroupMatch(
      round: 1,
      homePlayer: a,
      awayPlayer: b,
      homeLegs: 2,
      awayLegs: 2,
    );
    final runtime = ProductionTournamentRuntime(
      CreatedTournament(
        name: 'Draw',
        players: [a, b],
        stages: [],
        runStages: [],
      ),
    );
    final table = runtime.standings(
      TournamentGroup(
        name: 'A',
        playType: 'round_robin',
        players: [a, b],
        matches: [match],
      ),
      defaultGroupTieBreakers,
    );
    expect(match.isResolved, isTrue);
    expect(match.winner, isNull);
    for (final row in table) {
      expect(row.points, 1);
      expect(row.draws, 1);
      expect(row.played, 1);
    }
    expect(
      TournamentGameFormat.fromJson(
        const TournamentGameFormat(bestOfLegs: 4).toJson(),
      ).allowsDraws,
      isTrue,
    );
  });
  test(
    'finder opt-in adds even groups but never even knockout or set formats',
    () {
      final planner = TournamentFormatPlanner(
        parameters: TournamentPlanningParameters.fromValues({
          PlanningParameter.maximumSuggestions: 64,
        }),
      );
      TournamentPlanningRequest request(bool draws) =>
          TournamentPlanningRequest(
            players: 8,
            boards: 2,
            minimumMatchesPerPlayer: 2,
            minimumMinutes: 60,
            maximumMinutes: 240,
            x01Selection: '501',
            checkoutType: 'double_out',
            allowDraws: draws,
            allowSets: true,
          );
      expect(
        planner
            .suggestFormats(request(false))
            .expand((s) => s.stages)
            .every((s) => s.format.bestOfLegs.isOdd),
        isTrue,
      );
      final options = planner.suggestFormats(request(true));
      expect(options.any((s) => s.stages.first.format.allowsDraws), isTrue);
      for (final stage in options.expand((s) => s.stages)) {
        if (stage.type != 'groups' || stage.format.bestOfSets > 1) {
          expect(stage.format.bestOfLegs.isOdd, isTrue);
        }
      }
    },
  );
  testWidgets('finder draw switch starts off and can be enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: TournamentFormatPlannerDialog()),
    );
    final rules = find.ancestor(
      of: find.text('Spielregeln'),
      matching: find.byType(ExpansionTile),
    );
    await tester.ensureVisible(rules);
    await tester.tap(rules);
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('planner-allow-draws'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });
  testWidgets('selects the initial zero when a result field is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ResultDialog(
                  match: GroupMatch(
                    round: 1,
                    homePlayer: TournamentPlayer.generated(1),
                    awayPlayer: TournamentPlayer.generated(2),
                  ),
                ),
              ),
              child: const Text('Öffnen'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
    final homeField = find.byKey(const ValueKey('home-legs-field'));
    await tester.tap(homeField);

    final controller = tester.widget<TextField>(homeField).controller!;
    expect(controller.text, '0');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
  });

  testWidgets('Bo4 accepts 2:2 but rejects unfinished 1:1', (tester) async {
    MatchResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<MatchResult>(
                  context: context,
                  builder: (_) => ResultDialog(
                    match: GroupMatch(
                      round: 1,
                      homePlayer: TournamentPlayer.generated(1),
                      awayPlayer: TournamentPlayer.generated(2),
                    ),
                    format: const TournamentGameFormat(bestOfLegs: 4),
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
    for (final key in ['home-legs-field', 'away-legs-field']) {
      await tester.enterText(find.byKey(ValueKey(key)), '1');
    }
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.byType(AlertDialog), findsOneWidget);
    for (final key in ['home-legs-field', 'away-legs-field']) {
      await tester.enterText(find.byKey(ValueKey(key)), '2');
    }
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result?.homeLegs, 2);
    expect(result?.awayLegs, 2);
  });
}
