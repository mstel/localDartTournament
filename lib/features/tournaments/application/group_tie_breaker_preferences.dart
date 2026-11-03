import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tournament_models.dart';

class GroupTieBreakerPreferences {
  static const key = 'tournaments.v1.group_tie_breakers';
  static const previousDefault = [
    'points',
    'headToHead',
    'legDifference',
    'legsFor',
  ];

  Future<List<String>> load() async {
    final stored = (await SharedPreferences.getInstance()).getStringList(key);
    if (stored == null || !_isValid(stored)) {
      return List<String>.from(defaultGroupTieBreakers);
    }
    if (_matches(stored, previousDefault)) {
      final migrated = List<String>.from(defaultGroupTieBreakers);
      await save(migrated);
      return migrated;
    }
    return stored;
  }

  Future<void> save(List<String> tieBreakers) async {
    if (!_isValid(tieBreakers)) {
      throw ArgumentError.value(
        tieBreakers,
        'tieBreakers',
        'Muss alle Gruppen-Tie-Breaker genau einmal enthalten.',
      );
    }
    if (!await (await SharedPreferences.getInstance()).setStringList(
      key,
      tieBreakers,
    )) {
      throw StateError(
        'Tie-Breaker-Reihenfolge konnte nicht gespeichert werden.',
      );
    }
  }

  bool _isValid(List<String> tieBreakers) =>
      tieBreakers.length == defaultGroupTieBreakers.length &&
      tieBreakers.toSet().length == defaultGroupTieBreakers.length &&
      tieBreakers.every(defaultGroupTieBreakers.contains);

  bool _matches(List<String> first, List<String> second) =>
      first.length == second.length &&
      first.asMap().entries.every((entry) => entry.value == second[entry.key]);
}
