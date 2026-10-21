import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  final planner = TournamentFormatPlanner(
    parameters: TournamentPlanningParameters.fromValues({
      PlanningParameter.minutes501DoubleOut: 10,
      PlanningParameter.boardIdleMinutes: 0,
    }),
  );
  TournamentPlanningRequest request(int min, int max) =>
      TournamentPlanningRequest(
        players: 3,
        boards: 1,
        minimumMatchesPerPlayer: 2,
        minimumMinutes: min,
        maximumMinutes: max,
        x01Selection: '501',
        checkoutType: 'double_out',
        maximumGroups: 1,
      );
  test(
    'automatically proposes different best-of lengths matching the time window',
    () {
      final suggestions = planner.suggestFormats(request(70, 180));
      expect(suggestions.map((s) => s.format.bestOfLegs), [7, 5, 3]);
      expect(suggestions.every((s) => !s.isClosestAlternative), isTrue);
      expect(suggestions.map((s) => s.estimatedMinutes), [165, 120, 75]);
    },
  );
  test(
    'short window chooses Bo1 and impossible window returns marked alternatives',
    () {
      expect(
        planner.suggestFormats(request(0, 40)).single.format.bestOfLegs,
        1,
      );
      final alternatives = planner.suggestFormats(request(1, 2));
      expect(alternatives, isNotEmpty);
      expect(alternatives.every((s) => s.isClosestAlternative), isTrue);
    },
  );
}
