import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/tournaments/application/configuration_duration_estimator.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_planning_parameters.dart';

void main() {
  const estimator = ConfigurationDurationEstimator();
  const parameters = TournamentPlanningParameters();
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
    expect(estimator.preview([group], 4, parameters)!.totalMatches, 6);
    final before = group.toJson();
    final one = estimator.estimate([group], 1, parameters)!;
    final two = estimator.estimate([group], 2, parameters)!;
    expect(one, 75);
    expect(two, 38);
    expect(estimator.preview([group], 2, parameters)!.matchEndSeconds, [
      750,
      750,
      1500,
      1500,
      2250,
      2250,
    ]);
    expect(group.toJson(), before);
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
    expect(estimator.estimate([longer], 1, parameters), 120);
    expect(estimator.estimate([repeat], 1, parameters), 150);
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
    expect(estimator.estimate([ko], 4, parameters), 49);
    expect(estimator.preview([ko], 4, parameters)!.totalMatches, 2);
    expect(estimator.preview([ko], 4, parameters)!.minimumMatches, 1);
    expect(estimator.preview([group, ko], 2, parameters)!.minimumMatches, 3);
    expect(estimator.preview([group, ko], 2, parameters)!.totalMatches, 8);
    expect(estimator.estimate([group, ko], 2, parameters), 71);
    expect(estimator.preview([group, ko], 2, parameters)!.matchEndSeconds, [
      750,
      750,
      1500,
      1500,
      2250,
      2250,
      3000,
      3990,
    ]);
    expect(estimator.estimate([], 2, parameters), isNull);
  });
}
