import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/configuration_duration_estimator.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  const estimator = ConfigurationDurationEstimator();
  final parameters = TournamentPlanningParameters.fromValues({
    PlanningParameter.minutes501DoubleOut: 10,
    PlanningParameter.boardIdleMinutes: 0,
  });
  const group = TournamentStage(
    name: 'Liga',
    type: 'groups',
    groupSizes: [4],
    groupCount: 1,
    gameFormat: TournamentGameFormat(bestOfLegs: 3),
  );
  TournamentStage swissGroup(int players, {int bestOfLegs = 3}) =>
      TournamentStage(
        name: 'Swiss',
        type: 'groups',
        groupSizes: [players],
        groupCount: 1,
        groupPlayType: 'swiss',
        groupPlayTypes: const ['swiss'],
        groupRoundRobinRepeats: const [1],
        gameFormat: TournamentGameFormat(bestOfLegs: bestOfLegs),
      );

  test('boards affect duration without modifying configuration', () {
    final summary = estimator.preview([group], 1, parameters)!;
    expect(summary.totalMatches, 6);
    expect(summary.minimumMatches, 3);
    expect(summary.minimumMinutes, 150);
    expect(estimator.preview([group], 2, parameters)!.minimumMinutes, 75);
    expect(estimator.preview([group], 4, parameters)!.totalMatches, 6);
    final before = group.toJson();
    final one = estimator.estimate([group], 1, parameters)!;
    final two = estimator.estimate([group], 2, parameters)!;
    expect(one, 150);
    expect(two, 75);
    expect(estimator.preview([group], 2, parameters)!.matchEndSeconds, [
      1500,
      1500,
      3000,
      3000,
      4500,
      4500,
    ]);
    expect(group.toJson(), before);
  });
  test('default board idle time is counted between concurrent group waves', () {
    const defaults = TournamentPlanningParameters();

    final oneBoard = estimator.preview([group], 1, defaults)!;
    final twoBoards = estimator.preview([group], 2, defaults)!;

    expect(oneBoard.minutes, 95);
    expect(oneBoard.waitMinutes, 20);
    expect(twoBoards.minutes, 46);
    expect(twoBoards.waitMinutes, 8);
  });
  test('formats and repeats affect estimates', () {
    final longer = TournamentStage.fromJson({
      ...group.toJson(),
      'gameFormat': const TournamentGameFormat(bestOfLegs: 5).toJson(),
    });
    final repeat = TournamentStage.fromJson({
      ...group.toJson(),
      'groupRoundRobinRepeats': [2],
    });
    expect(estimator.estimate([longer], 1, parameters), 240);
    expect(estimator.estimate([repeat], 1, parameters), 300);
    expect(estimator.preview([repeat], 1, parameters)!.minimumMatches, 6);
    expect(estimator.preview([repeat], 1, parameters)!.totalMatches, 12);
  });
  test(
    'Swiss rounds estimate full match distance and partial-board waiting',
    () {
      final swissParameters = TournamentPlanningParameters.fromValues({
        PlanningParameter.minutes501DoubleOut: 10,
        PlanningParameter.boardIdleMinutes: 4,
        PlanningParameter.swissRoundWaitMinutes: 0,
      });
      final fiveMatchesOnFourBoards = estimator.preview(
        [swissGroup(10)],
        4,
        swissParameters,
      )!;
      expect(fiveMatchesOnFourBoards.totalMatches, 5);
      expect(fiveMatchesOnFourBoards.minimumMatches, 1);
      expect(fiveMatchesOnFourBoards.minutes, 68);
      expect(fiveMatchesOnFourBoards.waitMinutes, 8);

      final eightMatchesOnFourBoards = estimator.preview(
        [swissGroup(16)],
        4,
        swissParameters,
      )!;
      expect(eightMatchesOnFourBoards.totalMatches, 8);
      expect(eightMatchesOnFourBoards.minutes, 64);
      expect(eightMatchesOnFourBoards.waitMinutes, 4);

      final bestOfFive = estimator.preview(
        [swissGroup(10, bestOfLegs: 5)],
        4,
        swissParameters,
      )!;
      expect(bestOfFive.minutes, 108);
    },
  );
  test('KO byes and sequential stages use production runtime', () {
    const ko = TournamentStage(
      name: 'KO',
      type: 'single_knockout',
      knockoutParticipantCount: 3,
      knockoutBracketSize: 4,
      knockoutByeCount: 1,
      gameFormat: TournamentGameFormat(bestOfLegs: 3),
    );
    expect(estimator.estimate([ko], 4, parameters), 60);
    expect(estimator.preview([ko], 4, parameters)!.totalMatches, 2);
    expect(estimator.preview([ko], 4, parameters)!.minimumMatches, 1);
    expect(estimator.preview([group, ko], 2, parameters)!.minimumMatches, 3);
    expect(estimator.preview([group, ko], 2, parameters)!.totalMatches, 8);
    expect(estimator.estimate([group, ko], 2, parameters), 135);
    expect(estimator.preview([group, ko], 2, parameters)!.matchEndSeconds, [
      1500,
      1500,
      3000,
      3000,
      4500,
      4500,
      6300,
      8100,
    ]);
    expect(estimator.estimate([], 2, parameters), isNull);
  });
  test(
    'KO rounds use full-distance match durations and wait for each round',
    () {
      const knockout = TournamentStage(
        name: 'KO',
        type: 'single_knockout',
        knockoutParticipantCount: 8,
        gameFormat: TournamentGameFormat(bestOfLegs: 5),
      );
      final withBoardChange = TournamentPlanningParameters.fromValues({
        PlanningParameter.minutes501DoubleOut: 10,
        PlanningParameter.boardIdleMinutes: 4,
      });

      final estimate = estimator.preview([knockout], 4, withBoardChange)!;

      expect(estimate.minutes, 158);
      expect(estimate.matchEndSeconds, [
        3000,
        3000,
        3000,
        3000,
        6240,
        6240,
        9480,
      ]);
    },
  );
  test('variable elimination uses a match-count lower bound for duration', () {
    const doubleKo = TournamentStage(
      name: 'Double KO',
      type: 'double_knockout',
      knockoutParticipantCount: 4,
      knockoutBracketSize: 4,
      knockoutLives: 2,
      gameFormat: TournamentGameFormat(bestOfLegs: 3),
    );

    final oneBoard = estimator.preview([doubleKo], 1, parameters)!;
    final twoBoards = estimator.preview([doubleKo], 2, parameters)!;

    expect(oneBoard.variableMatches, isTrue);
    expect(oneBoard.minimumMinutes, 75);
    expect(twoBoards.minimumMinutes, 50);
    expect(oneBoard.minimumMinutes, lessThanOrEqualTo(oneBoard.minutes));
    expect(twoBoards.minimumMinutes, lessThanOrEqualTo(twoBoards.minutes));
  });
}
