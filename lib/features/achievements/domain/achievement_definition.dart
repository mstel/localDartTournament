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
    description: target == null || target == this.target
        ? description
        : _descriptionForTarget(description, this.target, target),
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

String _descriptionForTarget(
  String description,
  double previousTarget,
  double nextTarget,
) {
  final replacement = nextTarget == nextTarget.roundToDouble()
      ? nextTarget.toInt().toString()
      : nextTarget.toString();
  final candidates = [
    _formatTarget(previousTarget),
    ...?_germanTargetWords[previousTarget.round()],
  ];
  for (final candidate in candidates.toSet()) {
    final escaped = RegExp.escape(candidate);
    final match = RegExp(
      '(^|[^\\p{L}\\p{N}])$escaped(?=[^\\p{L}\\p{N}]|\$)',
      caseSensitive: false,
      unicode: true,
    ).firstMatch(description);
    if (match == null) continue;
    return description.replaceRange(
      match.start,
      match.end,
      '${match.group(1)}$replacement',
    );
  }
  return description;
}

String _formatTarget(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

const _germanTargetWords = <int, List<String>>{
  1: ['ein', 'eine', 'einen', 'einem', 'einer', 'eines'],
  2: ['zwei'],
  3: ['drei'],
  4: ['vier'],
  5: ['fünf'],
  6: ['sechs'],
  7: ['sieben'],
  8: ['acht'],
  9: ['neun'],
  10: ['zehn'],
  11: ['elf'],
  12: ['zwölf'],
  20: ['zwanzig'],
  25: ['fünfundzwanzig'],
  40: ['vierzig'],
  50: ['fünfzig'],
  100: ['hundert'],
};

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
