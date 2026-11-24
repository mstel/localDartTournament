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
