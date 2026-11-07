import 'dart:math' as math;

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
  shutoutMatchWins,
  legsWonAgainstSameOpponent,
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
  consecutiveWinsAgainstLowerElo,
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
    this.parameterLabel,
    this.parameterTarget,
    this.alternativeDescription,
    this.alternativeMetric,
    this.alternativeTarget,
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
  final String? parameterLabel;
  final double? parameterTarget;
  final String? alternativeDescription;
  final AchievementMetric? alternativeMetric;
  final double? alternativeTarget;
  final bool strictTarget;
  final bool requiresCompletedRanking;
  final bool contributesToLevel;
  final AchievementCategory? completionCategory;

  bool get isCategoryCompletion => completionCategory != null;

  AchievementDefinition copyWith({
    double? target,
    double? parameterTarget,
    double? alternativeTarget,
  }) {
    var nextAlternativeDescription = alternativeDescription;
    if (alternativeTarget != null &&
        alternativeTarget != this.alternativeTarget &&
        nextAlternativeDescription != null &&
        this.alternativeTarget != null) {
      nextAlternativeDescription = _descriptionForTarget(
        nextAlternativeDescription,
        this.alternativeTarget!,
        alternativeTarget,
      );
    }
    if (parameterTarget != null &&
        parameterTarget != this.parameterTarget &&
        nextAlternativeDescription != null &&
        this.parameterTarget != null) {
      nextAlternativeDescription = _descriptionForTarget(
        nextAlternativeDescription,
        this.parameterTarget!,
        parameterTarget,
      );
    }
    return AchievementDefinition(
      id: id,
      name: name,
      description: parameterTarget != null && this.parameterTarget != null
          ? _descriptionForTarget(
              description,
              this.parameterTarget!,
              parameterTarget,
            )
          : target == null || target == this.target
          ? description
          : _descriptionForTarget(description, this.target, target),
      alternativeDescription: nextAlternativeDescription,
      category: category,
      experiencePoints: experiencePoints,
      metric: metric,
      target: target ?? this.target,
      parameterLabel: parameterLabel,
      parameterTarget: parameterTarget ?? this.parameterTarget,
      alternativeTarget: alternativeTarget ?? this.alternativeTarget,
      alternativeMetric: alternativeMetric,
      strictTarget: strictTarget,
      requiresCompletedRanking: requiresCompletedRanking,
      contributesToLevel: contributesToLevel,
      completionCategory: completionCategory,
    );
  }
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
    this.alternativeCurrentValue = 0,
    required this.status,
    this.unlockedAt,
  });

  final AchievementDefinition definition;
  final double currentValue;
  final double alternativeCurrentValue;
  final AchievementStatus status;
  final DateTime? unlockedAt;

  bool get isCompleted => status == AchievementStatus.completed;

  double get fraction {
    final primary = definition.target <= 0
        ? (isCompleted ? 1.0 : 0.0)
        : (currentValue / definition.target).clamp(0, 1).toDouble();
    final alternativeTarget = definition.alternativeTarget;
    if (alternativeTarget == null || alternativeTarget <= 0) return primary;
    return math
        .max(primary, (alternativeCurrentValue / alternativeTarget).clamp(0, 1))
        .toDouble();
  }
}
