import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_duration.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/set_result_validation.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart'
    show ProductionTournamentRuntime;

void main() {
  final planner = TournamentFormatPlanner(
    parameters: TournamentPlanningParameters.fromValues({
      PlanningParameter.maximumSuggestions: 64,
    }),
  );
  TournamentPlanningRequest request(String score) => TournamentPlanningRequest(
    players: 13,
    boards: 4,
    minimumMatchesPerPlayer: 3,
    minimumMinutes: 120,
    maximumMinutes: 360,
    maximumGroups: 3,
    x01Selection: score,
    checkoutType: 'double_in_out',
    allowSets: true,
  );

  test(
    'finder proposes independently varied stages with sets, legs and scores',
    () {
      final suggestions = planner.suggestFormats(request('variable_301_501'));
      final multi = suggestions.where((s) => s.stages.length == 2).toList();
      expect(multi, isNotEmpty);
      expect(
        multi.any(
          (s) =>
              s.stages.first.format.x01Score != s.stages.last.format.x01Score,
        ),
        isTrue,
      );
      expect(
        multi.any(
          (s) =>
              s.stages.first.format.bestOfLegs !=
              s.stages.last.format.bestOfLegs,
        ),
        isTrue,
      );
      expect(
        multi.any(
          (s) =>
              s.stages.first.format.bestOfSets !=
              s.stages.last.format.bestOfSets,
        ),
        isTrue,
      );
      for (final s in multi) {
        final d = s.duration!;
        expect(
          d.matchMinutes,
          planner.estimatedMatchMinutes(s.stages.first.format),
        );
        expect(
          d.knockoutMatchMinutes,
          planner.estimatedMatchMinutes(s.stages.last.format),
        );
        expect(d.totalMinutes, d.groupMinutes + d.knockoutMinutes);
        expect(s.stages.every((stage) => stage.format.doubleIn), isTrue);
      }
    },
  );

  test('fixed score remains fixed for every proposed stage', () {
    expect(
      planner
          .suggestFormats(request('501'))
          .expand((s) => s.stages)
          .every((s) => s.format.x01Score == 501),
      isTrue,
    );
  });

  test('default short list includes different stage formats', () {
    final suggestions = const TournamentFormatPlanner().suggestFormats(
      request('variable_301_501'),
    );
    expect(
      suggestions.any(
        (s) =>
            s.stages.length > 1 &&
            s.stages.first.format.label != s.stages.last.format.label,
      ),
      isTrue,
    );
  });

  test('set estimate multiplies average sets by average legs per set', () {
    expect(
      PlanningDuration.estimatedMatchLegs(
        const TournamentGameFormat(bestOfSets: 3, bestOfLegs: 3),
      ),
      6.25,
    );
    expect(
      PlanningDuration.estimatedMatchLegs(
        const TournamentGameFormat(bestOfSets: 5, bestOfLegs: 3),
      ),
      10,
    );
    expect(TournamentGameFormat.fromJson({'bestOfLegs': 5}).bestOfSets, 1);
    const f = TournamentGameFormat(x01Score: 301, bestOfSets: 3, bestOfLegs: 5);
    expect(TournamentGameFormat.fromJson(f.toJson()).toJson(), f.toJson());
  });

  test(
    'set winner determines advancement and points even with fewer total legs',
    () {
      final home = TournamentPlayer.generated(1),
          away = TournamentPlayer.generated(2);
      final match = GroupMatch(
        round: 1,
        homePlayer: home,
        awayPlayer: away,
        homeSets: 2,
        awaySets: 1,
        homeLegs: 6,
        awayLegs: 7,
      );
      const format = TournamentGameFormat(bestOfSets: 3, bestOfLegs: 5);
      expect(
        isValidSetResult(
          format,
          homeSets: 2,
          awaySets: 1,
          homeLegs: 6,
          awayLegs: 7,
        ),
        isTrue,
      );
      expect(
        isValidSetResult(
          format,
          homeSets: 2,
          awaySets: 1,
          homeLegs: 3,
          awayLegs: 7,
        ),
        isFalse,
      );
      expect(match.winner, home);
      final restored = GroupMatch.fromJson(match.toJson());
      expect(restored.winner?.name, home.name);
      final runtime = ProductionTournamentRuntime(
        CreatedTournament(
          name: 'Sets',
          players: [home, away],
          stages: [],
          runStages: [],
        ),
      );
      final standings = runtime.standings(
        TournamentGroup(
          name: 'A',
          playType: 'round_robin',
          players: [home, away],
          matches: [match],
        ),
        defaultGroupTieBreakers,
      );
      expect(standings.first.player, home);
      expect(standings.first.points, 3);
      expect(standings.first.legsFor, 6);
      expect(standings.first.legsAgainst, 7);
    },
  );
}
