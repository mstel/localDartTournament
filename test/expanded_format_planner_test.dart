import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/expanded_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/application/configuration_duration_estimator.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_format_planner.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/planning_format_progression.dart';
import 'package:dart_tournament_manager/tournament_workspace.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';

void main() {
  test(
    'target ranking and optional sets/draws preserve all search constraints',
    () async {
      final results = await const ExpandedFormatPlanner().suggest(
        const TournamentPlanningRequest(
          players: 12,
          boards: 4,
          minimumMatchesPerPlayer: 2,
          minimumMinutes: 0,
          maximumMinutes: 1,
          targetMinutes: 240,
          x01Selection: 'variable_301_501',
          checkoutType: 'double_out',
          maximumGroups: 2,
          maximumStages: 4,
          maximumLives: 5,
          requireGroupPhase: true,
          allowDraws: true,
          allowSets: true,
        ),
      );
      expect(results, isNotEmpty);
      final distances = results
          .map((s) => (s.estimatedMinutes - 240).abs())
          .toList();
      expect(distances, [...distances]..sort());
      for (final result in results) {
        expect(result.minimumMatchesPerPlayer, greaterThanOrEqualTo(2));
        expect(result.configurations.length, lessThanOrEqualTo(4));
        for (final stage in result.configurations) {
          if (stage.type != 'groups' || !['round_robin', 'swiss'].contains(stage.groupPlayType)) {
            expect(stage.gameFormat.allowsDraws, isFalse);
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
  final parameters = TournamentPlanningParameters.fromValues({
    PlanningParameter.maximumSuggestions: 64,
  });
  TournamentPlanningRequest request({int stages = 1, bool groups = false}) =>
      TournamentPlanningRequest(
        players: 8,
        boards: 2,
        minimumMatchesPerPlayer: 0,
        minimumMinutes: 0,
        maximumMinutes: 100000,
        x01Selection: '501',
        checkoutType: 'double_out',
        maximumGroups: 2,
        maximumStages: stages,
        maximumLives: 4,
        requireGroupPhase: groups,
      );
  test(
    'all production modes are searched and estimate matches production',
    () async {
      final results = await ExpandedFormatPlanner(
        parameters: parameters,
      ).suggest(request());
      expect(
        results.map((s) => s.configurations.first.type).toSet(),
        containsAll([
          'groups',
          'single_knockout',
          'double_knockout',
          'triple_knockout',
          'kratzer',
        ]),
      );
      expect(
        results
            .where((s) => s.configurations.first.type == 'groups')
            .map((s) => s.configurations.first.groupPlayType),
        containsAll([
          'round_robin',
          'mini_knockout',
          'double_knockout',
          'triple_knockout',
        ]),
      );
      for (final result in results) {
        final estimate = const ConfigurationDurationEstimator().preview(
          result.configurations,
          2,
          parameters,
        )!;
        expect(result.totalMatches, estimate.totalMatches);
        expect(result.estimatedMinutes, estimate.minutes);
      }
    },
  );
  test(
    'multi-stage group requirement, qualification and distance progression',
    () async {
      final results = await ExpandedFormatPlanner(
        parameters: parameters,
      ).suggest(request(stages: 3, groups: true));
      expect(results, isNotEmpty);
      expect(results.any((s) => s.configurations.length == 3), isTrue);
      for (final result in results) {
        final estimate = const ConfigurationDurationEstimator().preview(
          result.configurations,
          2,
          parameters,
        )!;
        expect(result.totalMatches, estimate.totalMatches);
        expect(result.estimatedMinutes, estimate.minutes);
        expect(result.configurations.any((s) => s.type == 'groups'), isTrue);
        final t = CreatedTournament(
          name: 'Finder',
          players: [],
          stages: result.configurations,
          runStages: [],
        );
        final runtime = ProductionTournamentRuntime(t);
        var players = List.generate(
          8,
          (i) => TournamentPlayer.generated(i + 1),
        );
        for (var i = 0; i < t.stages.length; i++) {
          final stage = t.stages[i];
          if (stage.type == 'groups') {
            expect(stage.groupCount, lessThanOrEqualTo(2));
          }
          if (i > 0) {
            expect(
              isPlanningFormatProgressionAllowed(
                t.stages[i - 1].gameFormat,
                stage.gameFormat,
              ),
              isTrue,
            );
          }
          final run = runtime.build(stage, players);
          t.runStages.add(run);
          runtime.activate(i);
          runtime.advance();
          var guard = 0;
          while (runtime.hasOpen(run) && guard++ < 1000) {
            for (final m
                in runtime
                    .matches(run)
                    .where((m) => m.hasPlayers && !m.isResolved)) {
              m.homeLegs = stage.gameFormat.bestOfLegs ~/ 2 + 1;
              m.awayLegs = 0;
            }
            runtime.advance();
          }
          expect(runtime.hasOpen(run), isFalse);
          players = runtime
              .qualifiers(run)
              .take(stage.qualifiedParticipantCount!)
              .toList();
          expect(players.length, stage.qualifiedParticipantCount);
        }
      }
    },
  );

  test(
    'manualQualifiers configures exact qualifiers and knockout byes (e.g. Top 6 for 12 players)',
    () async {
      final results = await const ExpandedFormatPlanner().suggest(
        const TournamentPlanningRequest(
          players: 12,
          boards: 2,
          minimumMatchesPerPlayer: 1,
          minimumMinutes: 0,
          maximumMinutes: 600,
          x01Selection: '501',
          checkoutType: 'double_out',
          maximumGroups: 2,
          maximumStages: 2,
          requireGroupPhase: true,
          preferredFinalStage: 'single_knockout',
          manualQualifiers: 6,
          bestOfLegs: 3,
          lockLegsFormat: true,
        ),
      );
      expect(results, isNotEmpty);
      final top6Plan = results.firstWhere(
        (s) => s.configurations.length == 2 && s.configurations.first.type == 'groups',
      );
      final groupStage = top6Plan.configurations.first;
      final koStage = top6Plan.configurations.last;

      expect(groupStage.qualifiedParticipantCount, 6);
      expect(koStage.knockoutParticipantCount, 6);
      expect(koStage.knockoutBracketSize, 8);
      expect(koStage.knockoutByeCount, 2); // 2 group winners get byes into semifinals!
    },
  );

  test(
    'lockLegsFormat prevents downgrading to Best of 1 and enforces requested Best of Legs',
    () async {
      final results = await const ExpandedFormatPlanner().suggest(
        const TournamentPlanningRequest(
          players: 12,
          boards: 2,
          minimumMatchesPerPlayer: 1,
          minimumMinutes: 0,
          maximumMinutes: 600,
          x01Selection: '501',
          checkoutType: 'double_out',
          maximumGroups: 2,
          maximumStages: 2,
          requireGroupPhase: true,
          bestOfLegs: 3,
          lockLegsFormat: true,
        ),
      );
      expect(results, isNotEmpty);
      for (final result in results) {
        for (final stage in result.configurations) {
          expect(stage.gameFormat.bestOfLegs, 3);
        }
      }
    },
  );
}
