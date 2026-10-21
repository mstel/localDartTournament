import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  final planner = TournamentFormatPlanner(
    parameters: TournamentPlanningParameters.fromValues({
      PlanningParameter.minutes501DoubleOut: 10,
      PlanningParameter.boardIdleMinutes: 0,
    }),
  );
  test('automatic finder includes Bo101 for a matching time window', () {
    final suggestions = planner.suggestFormats(
      const TournamentPlanningRequest(
        requireGroupPhase: true,
        players: 3,
        boards: 1,
        minimumMatchesPerPlayer: 1,
        minimumMinutes: 2280,
        maximumMinutes: 2280,
        x01Selection: '501',
        checkoutType: 'double_out',
        maximumGroups: 1,
      ),
    );
    expect(suggestions.single.format.bestOfLegs, 101);
    expect(suggestions.single.estimatedMinutes, 2280);
    expect(PlanningDuration.estimatedLegs(101), 76);
    expect(PlanningDuration.estimatedLegs(21), 16);
    expect(PlanningDuration.estimatedLegs(100), 75.5);
  });
  test(
    'uses midpoint of minimum and maximum without rounding individual matches',
    () {
      expect(PlanningDuration.estimatedLegs(3), 2.5);
      expect(PlanningDuration.estimatedLegs(5), 4);
      expect(PlanningDuration.estimatedLegs(7), 5.5);
      expect(PlanningDuration.estimatedLegs(1), 1);
      for (final bestOf in [3, 5, 7, 21, 101]) {
        final suggestion = planner
            .suggest(
              TournamentPlanningRequest(
                requireGroupPhase: true,
                players: 3,
                boards: 1,
                minimumMatchesPerPlayer: 0,
                minimumMinutes: 0,
                maximumMinutes: 10000,
                x01Selection: '501',
                checkoutType: 'double_out',
                maximumGroups: 1,
                bestOfLegs: bestOf,
              ),
            )
            .single;
        expect(suggestion.format.bestOfLegs, bestOf);
        expect(
          suggestion.estimatedMinutes,
          (30 * ((bestOf ~/ 2 + 1 + bestOf) / 2)).ceil(),
        );
      }
    },
  );
}
