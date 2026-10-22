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
  test('KO byes and sequential stages use production runtime', () {
    const ko = TournamentStage(
      name: 'KO',
      type: 'single_knockout',
      knockoutParticipantCount: 3,
      knockoutBracketSize: 4,
      knockoutByeCount: 1,
      gameFormat: TournamentGameFormat(bestOfLegs: 3),
    );
    expect(estimator.estimate([ko], 4, parameters), 50);
    expect(estimator.preview([ko], 4, parameters)!.totalMatches, 2);
    expect(estimator.preview([ko], 4, parameters)!.minimumMatches, 1);
    expect(estimator.preview([group, ko], 2, parameters)!.minimumMatches, 3);
    expect(estimator.preview([group, ko], 2, parameters)!.totalMatches, 8);
    expect(estimator.estimate([group, ko], 2, parameters), 125);
    expect(estimator.preview([group, ko], 2, parameters)!.matchEndSeconds, [
      1500,
      1500,
      3000,
      3000,
      4500,
      4500,
      6000,
      7500,
    ]);
    expect(estimator.estimate([], 2, parameters), isNull);
  });
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
