import 'package:flutter_test/flutter_test.dart';
import 'package:dart_tournament_manager/features/achievements/domain/achievement_catalog.dart';
import 'package:dart_tournament_manager/features/achievements/domain/achievement_definition.dart';
import 'package:dart_tournament_manager/features/achievements/domain/achievement_engine.dart';

Map<AchievementMetric, double> _valuesForAllAchievements({
  bool includeRankingAwards = true,
}) {
  final values = <AchievementMetric, double>{};
  for (final definition in AchievementCatalog.definitions) {
    final metric = definition.metric;
    if (metric == null) continue;
    if (!includeRankingAwards &&
        definition.category == AchievementCategory.rankingAwards) {
      continue;
    }
    final value = values[metric] ?? 0;
    final requiredValue = definition.strictTarget
        ? definition.target + 0.01
        : definition.target;
    if (requiredValue > value) values[metric] = requiredValue;
  }
  return values;
}

void main() {
  const engine = AchievementEngine();

  test('catalog XP totals match the level 10 specification', () {
    expect(AchievementCatalog.levelThresholds, [
      0,
      100,
      250,
      450,
      700,
      1000,
      1350,
      1800,
      2250,
      2700,
    ]);
    expect(AchievementCatalog.levelEligibleExperiencePoints, greaterThan(2700));
    expect(
      AchievementCatalog.allExperiencePoints -
          AchievementCatalog.levelEligibleExperiencePoints,
      675,
    );
  });

  test('one metric can unlock multiple stages with their own XP', () {
    final result = engine.evaluate(
      values: {AchievementMetric.legsWon: 50},
      rankingCompleted: false,
    );

    expect(result.progress['legs_won_10']!.isCompleted, isTrue);
    expect(result.progress['legs_won_25']!.isCompleted, isTrue);
    expect(result.progress['legs_won_50']!.isCompleted, isTrue);
    expect(result.progress['legs_won_100']!.isCompleted, isFalse);
    expect(result.totalExperiencePoints, 39);
  });

  test('ranking-specific thresholds drive evaluation dynamically', () {
    final definitions = AchievementCatalog.withTargets({
      'legs_won_10': 3,
      'legs_won_25': 7,
    });
    final result = engine.evaluate(
      values: {AchievementMetric.legsWon: 5},
      rankingCompleted: false,
      definitions: definitions,
    );

    expect(result.progress['legs_won_10']!.definition.target, 3);
    expect(result.progress['legs_won_10']!.isCompleted, isTrue);
    expect(result.progress['legs_won_25']!.definition.target, 7);
    expect(result.progress['legs_won_25']!.isCompleted, isFalse);
  });

  test(
    'checkout-rate achievements require strictly more than their target',
    () {
      final atThreshold = engine.evaluate(
        values: {AchievementMetric.monthlyCheckoutRate: 20},
        rankingCompleted: false,
      );
      final aboveThreshold = engine.evaluate(
        values: {AchievementMetric.monthlyCheckoutRate: 20.1},
        rankingCompleted: false,
      );

      expect(atThreshold.progress['checkout_rate_20']!.isCompleted, isFalse);
      expect(aboveThreshold.progress['checkout_rate_20']!.isCompleted, isTrue);
    },
  );

  test('ranking awards stay locked until completion and remain permanent', () {
    final liveResult = engine.evaluate(
      values: {AchievementMetric.rankingGold: 1},
      rankingCompleted: false,
    );
    expect(liveResult.progress['ranking_gold']!.isCompleted, isFalse);
    expect(liveResult.totalExperiencePoints, 0);

    final completedResult = engine.evaluate(
      values: {AchievementMetric.rankingGold: 1},
      rankingCompleted: true,
    );
    expect(completedResult.progress['ranking_gold']!.isCompleted, isTrue);

    final correctedResult = engine.evaluate(
      values: const {},
      rankingCompleted: true,
      permanentlyUnlocked: const {'ranking_gold'},
    );
    expect(correctedResult.progress['ranking_gold']!.isCompleted, isTrue);
    expect(correctedResult.totalExperiencePoints, 50);
  });

  test('special XP does not advance levels but is still accumulated', () {
    final regularResult = engine.evaluate(
      values: _valuesForAllAchievements(includeRankingAwards: false),
      rankingCompleted: false,
    );
    expect(
      regularResult.levelEligibleExperiencePoints,
      AchievementCatalog.levelEligibleExperiencePoints,
    );
    expect(regularResult.level, 10);
    expect(regularResult.nextLevelExperiencePoints, isNull);

    final allResult = engine.evaluate(
      values: _valuesForAllAchievements(),
      rankingCompleted: true,
    );
    expect(
      allResult.levelEligibleExperiencePoints,
      AchievementCatalog.levelEligibleExperiencePoints,
    );
    expect(
      allResult.totalExperiencePoints,
      AchievementCatalog.allExperiencePoints,
    );
    expect(allResult.level, 10);
  });

  test('level 10 is reachable without placement-series achievements', () {
    final values = _valuesForAllAchievements(includeRankingAwards: false)
      ..[AchievementMetric.tournamentWins] = 1
      ..[AchievementMetric.secondPlaces] = 0
      ..[AchievementMetric.thirdPlaces] = 0
      ..[AchievementMetric.fourthPlaces] = 0;
    final result = engine.evaluate(values: values, rankingCompleted: false);

    expect(result.progress['tournament_wins_3']!.isCompleted, isFalse);
    expect(result.progress['second_places_3']!.isCompleted, isFalse);
    expect(result.progress['third_places_3']!.isCompleted, isFalse);
    expect(result.progress['fourth_places_5']!.isCompleted, isFalse);
    expect(result.level, 10);
  });

  test('placement series use shared 2, 3 and 5 stage rewards', () {
    const seriesIds = [
      ['tournament_wins_3', 'tournament_wins_5', 'tournament_wins_7'],
      ['second_places_3', 'second_places_5', 'second_places_7'],
      ['third_places_3', 'third_places_5', 'third_places_7'],
      ['fourth_places_5', 'fourth_places_10', 'fourth_places_25'],
    ];
    for (var stage = 0; stage < 3; stage++) {
      final definitions = [
        for (final ids in seriesIds)
          AchievementCatalog.definitions.singleWhere(
            (definition) => definition.id == ids[stage],
          ),
      ];
      expect(
        definitions.map((definition) => definition.target),
        everyElement([2.0, 3.0, 5.0][stage]),
      );
      expect(
        definitions.map((definition) => definition.experiencePoints),
        everyElement([20, 30, 50][stage]),
      );
    }
  });
}
