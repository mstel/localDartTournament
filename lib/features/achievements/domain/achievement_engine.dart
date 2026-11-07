import 'achievement_catalog.dart';
import 'achievement_definition.dart';

class AchievementEvaluation {
  const AchievementEvaluation({
    required this.progress,
    required this.totalExperiencePoints,
    required this.levelEligibleExperiencePoints,
    required this.level,
    required this.levelStartExperiencePoints,
    this.nextLevelExperiencePoints,
  });

  final Map<String, AchievementProgress> progress;
  final int totalExperiencePoints;
  final int levelEligibleExperiencePoints;
  final int level;
  final int levelStartExperiencePoints;
  final int? nextLevelExperiencePoints;

  int? get experiencePointsToNextLevel => nextLevelExperiencePoints == null
      ? null
      : nextLevelExperiencePoints! - levelEligibleExperiencePoints;

  double get levelProgress {
    final next = nextLevelExperiencePoints;
    if (next == null) return 1;
    final span = next - levelStartExperiencePoints;
    if (span <= 0) return 1;
    return ((levelEligibleExperiencePoints - levelStartExperiencePoints) / span)
        .clamp(0, 1);
  }
}

class AchievementEngine {
  const AchievementEngine();

  AchievementEvaluation evaluate({
    required Map<AchievementMetric, double> values,
    required bool rankingCompleted,
    List<AchievementDefinition> definitions = AchievementCatalog.definitions,
    Set<String> permanentlyUnlocked = const {},
    Map<String, DateTime> unlockedAt = const {},
  }) {
    final progress = <String, AchievementProgress>{};
    for (final definition in definitions) {
      if (definition.isCategoryCompletion) continue;
      final metricValue = (values[definition.metric] ?? 0)
          .clamp(0, double.infinity)
          .toDouble();
      final isPreserved = permanentlyUnlocked.contains(definition.id);
      final current = isPreserved && metricValue < definition.target
          ? definition.target
          : metricValue;
      final alternativeMetricValue = definition.alternativeMetric == null
          ? 0.0
          : (values[definition.alternativeMetric] ?? 0)
                .clamp(0, double.infinity)
                .toDouble();
      final alternativeTarget = definition.alternativeTarget;
      final alternativeCurrent =
          isPreserved &&
              alternativeTarget != null &&
              alternativeMetricValue < alternativeTarget
          ? alternativeTarget
          : alternativeMetricValue;
      final eligible = !definition.requiresCompletedRanking || rankingCompleted;
      final reached =
          (definition.strictTarget
              ? current > definition.target
              : current >= definition.target) ||
          (alternativeTarget != null &&
              (definition.strictTarget
                  ? alternativeCurrent > alternativeTarget
                  : alternativeCurrent >= alternativeTarget));
      final completed = isPreserved || (eligible && reached);
      final status = completed
          ? AchievementStatus.completed
          : current > 0 || alternativeCurrent > 0
          ? AchievementStatus.inProgress
          : AchievementStatus.locked;
      progress[definition.id] = AchievementProgress(
        definition: definition,
        currentValue: current,
        alternativeCurrentValue: alternativeCurrent,
        status: status,
        unlockedAt: unlockedAt[definition.id],
      );
    }

    for (final definition in definitions.where(
      (item) => item.isCategoryCompletion,
    )) {
      final categoryProgress = progress.values
          .where(
            (item) => item.definition.category == definition.completionCategory,
          )
          .toList();
      final achievedCount = categoryProgress
          .where((item) => item.isCompleted)
          .length;
      final allComplete =
          categoryProgress.isNotEmpty &&
          achievedCount == categoryProgress.length;
      final completed =
          allComplete || permanentlyUnlocked.contains(definition.id);
      final current = completed ? 1.0 : 0.0;
      progress[definition.id] = AchievementProgress(
        definition: definition,
        currentValue: current,
        status: completed
            ? AchievementStatus.completed
            : current > 0
            ? AchievementStatus.inProgress
            : AchievementStatus.locked,
        unlockedAt: unlockedAt[definition.id],
      );
    }

    var totalExperiencePoints = 0;
    var levelEligibleExperiencePoints = 0;
    for (final item in progress.values) {
      if (!item.isCompleted) continue;
      totalExperiencePoints += item.definition.experiencePoints;
      if (item.definition.contributesToLevel) {
        levelEligibleExperiencePoints += item.definition.experiencePoints;
      }
    }

    final thresholds = AchievementCatalog.levelThresholds;
    var level = 1;
    for (var index = 1; index < thresholds.length; index++) {
      if (levelEligibleExperiencePoints < thresholds[index]) break;
      level = index + 1;
    }
    final levelIndex = level - 1;
    return AchievementEvaluation(
      progress: progress,
      totalExperiencePoints: totalExperiencePoints,
      levelEligibleExperiencePoints: levelEligibleExperiencePoints,
      level: level,
      levelStartExperiencePoints: thresholds[levelIndex],
      nextLevelExperiencePoints: level == thresholds.length
          ? null
          : thresholds[level],
    );
  }
}
