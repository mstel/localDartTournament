import 'dart:convert';

/// Versioned, persisted state of the "Dynamisch + turnierweit optimiert"
/// waiting list.
///
/// Only the fixed preview is stored. The optimised remainder is recalculated
/// from the current tournament state whenever it is read.
class GlobalWaitlistState {
  GlobalWaitlistState({
    this.schemaVersion = currentSchemaVersion,
    int? fixedCount,
    Map<int, List<String>>? fixedKeysByStage,
  }) : fixedCount = (fixedCount ?? defaultFixedCount).clamp(1, 12),
       _fixedKeysByStage = {
         for (final entry in (fixedKeysByStage ?? const {}).entries)
           entry.key: List<String>.unmodifiable(entry.value),
       };

  static const currentSchemaVersion = 1;
  static const defaultFixedCount = 4;

  final int schemaVersion;
  int fixedCount;
  final Map<int, List<String>> _fixedKeysByStage;

  factory GlobalWaitlistState.fromJson(Object? value) {
    if (value is! Map) return GlobalWaitlistState();
    final json = Map<String, dynamic>.from(value);
    final version = json['schemaVersion'] as int? ?? 0;
    if (version < 1 || version > currentSchemaVersion) {
      return GlobalWaitlistState();
    }
    final rawStages = json['stages'];
    final stages = <int, List<String>>{};
    if (rawStages is Map) {
      for (final entry in rawStages.entries) {
        final stage = int.tryParse(entry.key.toString());
        if (stage == null || entry.value is! List) continue;
        stages[stage] = entry.value.whereType<String>().toList();
      }
    }
    return GlobalWaitlistState(
      schemaVersion: version,
      fixedCount: json['fixedCount'] as int?,
      fixedKeysByStage: stages,
    );
  }

  List<String> fixedKeys(int stage) =>
      List<String>.unmodifiable(_fixedKeysByStage[stage] ?? const <String>[]);

  void setFixedKeys(int stage, List<String> keys) {
    if (keys.isEmpty) {
      _fixedKeysByStage.remove(stage);
      return;
    }
    _fixedKeysByStage[stage] = List<String>.unmodifiable(keys);
  }

  void clear() => _fixedKeysByStage.clear();

  bool get hasPersistedData =>
      fixedCount != defaultFixedCount ||
      _fixedKeysByStage.values.any((keys) => keys.isNotEmpty);

  GlobalWaitlistState copy() => GlobalWaitlistState.fromJson(toJson());

  Map<String, dynamic> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'fixedCount': fixedCount,
    'stages': {
      for (final entry in _fixedKeysByStage.entries)
        entry.key.toString(): entry.value,
    },
  };

  @override
  String toString() => jsonEncode(toJson());
}
