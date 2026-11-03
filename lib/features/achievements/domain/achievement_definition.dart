enum AchievementCategory {
  tournamentResults,
  gameplay,
  scoringAndSpecials,
  checkoutAndPrecision,
  performanceAndConsistency,
  activityAndLoyalty,
  rivalriesAndComebacks,
  rankingAwards,
}

extension AchievementCategoryLabel on AchievementCategory {
  String get label => switch (this) {
    AchievementCategory.tournamentResults => 'Turniererfolge',
    AchievementCategory.gameplay => 'Spielbetrieb',
    AchievementCategory.scoringAndSpecials => 'Scoring & Specials',
    AchievementCategory.checkoutAndPrecision => 'Checkout & Präzision',
    AchievementCategory.performanceAndConsistency => 'Leistung & Konstanz',
    AchievementCategory.activityAndLoyalty => 'Aktivität & Treue',
    AchievementCategory.rivalriesAndComebacks => 'Rivalitäten & Comebacks',
    AchievementCategory.rankingAwards => 'Ranglisten-Achievements',
  };
}

enum AchievementMetric {
  tournamentParticipations,
  tournamentWins,
  secondPlaces,
  thirdPlaces,
  fourthPlaces,
  matchWinStreak,
  consecutiveTournamentParticipations,
  tournamentWinStreak,
  legsWon,
  legsLost,
  score180Count,
  firstScore180,
  firstScore171,
  score171Count,
  nineDarterCount,
  bigFish170Count,
  bullseyeFinishCount,
  highFinishCount,
  monthlyCheckoutRate,
  shortLegCount,
  monthlyAverage,
  monthlyScoring,
  consecutiveActiveMonths,
  activeMonthsInYear,
  trainingSessions,
  winsAfterLossStreak,
  eloUpsetWins,
  distinctOpponentsBeaten,
  lossesToSameOpponent,
  rankingGold,
  rankingSilver,
  rankingBronze,
  rankingMvp,
}

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.experiencePoints,
    this.metric,
    this.target = 1,
    this.strictTarget = false,
    this.requiresCompletedRanking = false,
    this.contributesToLevel = true,
    this.completionCategory,
  });

  final String id;
  final String name;
  final String description;
  final AchievementCategory category;
  final int experiencePoints;
  final AchievementMetric? metric;
  final double target;
  final bool strictTarget;
  final bool requiresCompletedRanking;
  final bool contributesToLevel;
  final AchievementCategory? completionCategory;

  bool get isCategoryCompletion => completionCategory != null;

  AchievementDefinition copyWith({double? target}) => AchievementDefinition(
    id: id,
    name: name,
    description: description,
    category: category,
    experiencePoints: experiencePoints,
    metric: metric,
    target: target ?? this.target,
    strictTarget: strictTarget,
    requiresCompletedRanking: requiresCompletedRanking,
    contributesToLevel: contributesToLevel,
    completionCategory: completionCategory,
  );
}

enum AchievementStatus { locked, inProgress, completed }

class AchievementProgress {
  const AchievementProgress({
    required this.definition,
    required this.currentValue,
    required this.status,
    this.unlockedAt,
  });

  final AchievementDefinition definition;
  final double currentValue;
  final AchievementStatus status;
  final DateTime? unlockedAt;

  bool get isCompleted => status == AchievementStatus.completed;

  double get fraction {
    if (definition.target <= 0) return isCompleted ? 1 : 0;
    return (currentValue / definition.target).clamp(0, 1);
  }
}
