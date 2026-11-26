/// Canonical schedule modes of the tournament director.
///
/// The app offers exactly three combinations to normal tournaments:
///
/// * `Fest – Gruppenbasiert` (`fixed_schedule` + `group`)
/// * `Fest – Turnierweit` (`fixed_schedule` + `global`)
/// * `Dynamisch` (`dynamic`, always tournament-wide)
///
/// Legacy `dynamic + group` data is migrated to plain dynamic on read. League
/// and friendship tournaments keep their own `directorMultiBoardAssignmentBehavior`
/// and are intentionally not normalised here.
class DirectorScheduleModes {
  const DirectorScheduleModes._();

  static const fixedSchedule = 'fixed_schedule';
  static const dynamicMode = 'dynamic';
  static const group = 'group';
  static const global = 'global';

  static String playOrderMode(Object? value) => switch (value) {
    'fixed_order' || fixedSchedule => fixedSchedule,
    _ => dynamicMode,
  };

  static String schedulingStrategy(Object? value, String playOrderMode) {
    final normalized = (value as String?)?.trim().toLowerCase() == global
        ? global
        : group;
    return playOrderMode == dynamicMode ? global : normalized;
  }

  static bool isKnockoutStageType(String type) =>
      type == 'single_knockout' ||
      type == 'double_knockout' ||
      type == 'triple_knockout' ||
      type == 'kratzer';

  /// KO-Phasen haben keine Gruppen, auf die Boards fest verteilt werden
  /// könnten. Dort ist nur die turnierweite Zuweisung zulässig.
  static bool allowsGroupBoardAssignment(String stageType) =>
      !isKnockoutStageType(stageType);

  /// Normalisiert die Boardzuweisung für die aktive Phase. Beim Wechsel in
  /// eine KO-Phase wird `group` deshalb automatisch auf `global` korrigiert.
  static String strategyForStage(
    Object? value,
    String playOrderMode,
    String stageType,
  ) {
    final strategy = schedulingStrategy(value, playOrderMode);
    if (strategy == group && !allowsGroupBoardAssignment(stageType)) {
      return global;
    }
    return strategy;
  }

  /// Normalises a persisted pair without allocating a new map when possible.
  static Map<String, dynamic> normalizeJson(Map<String, dynamic> json) {
    final mode = playOrderMode(json['directorPlayOrderMode']);
    final strategy = schedulingStrategy(
      json['directorSchedulingStrategy'],
      mode,
    );
    final normalized = <String, dynamic>{...json};
    normalized['directorPlayOrderMode'] = mode;
    normalized['directorSchedulingStrategy'] = strategy;
    return normalized;
  }
}
