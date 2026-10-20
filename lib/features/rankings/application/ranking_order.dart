import '../domain/local_ranking.dart';

enum RankingSortMode { startYearDescending, alphabetical, custom }

extension RankingSortModeLabel on RankingSortMode {
  String get label => switch (this) {
    RankingSortMode.startYearDescending => 'Startjahr absteigend',
    RankingSortMode.alphabetical => 'Alphabetisch',
    RankingSortMode.custom => 'Benutzerdefiniert',
  };
}

List<LocalRanking> sortRankings(
  Iterable<LocalRanking> rankings,
  RankingSortMode mode,
) {
  final result = rankings.toList();
  result.sort((left, right) {
    final comparison = switch (mode) {
      RankingSortMode.startYearDescending => _compareStartYears(left, right),
      RankingSortMode.alphabetical => _compareNames(left, right),
      RankingSortMode.custom => left.customOrder.compareTo(right.customOrder),
    };
    return comparison == 0 ? _compareNames(left, right) : comparison;
  });
  return result;
}

int _compareStartYears(LocalRanking left, LocalRanking right) {
  final leftYear = left.validFromDate?.year ?? left.validFromYear;
  final rightYear = right.validFromDate?.year ?? right.validFromYear;
  if (leftYear == null) return rightYear == null ? 0 : 1;
  if (rightYear == null) return -1;
  return rightYear.compareTo(leftYear);
}

int _compareNames(LocalRanking left, LocalRanking right) {
  final nameComparison = left.name.toLowerCase().compareTo(
    right.name.toLowerCase(),
  );
  return nameComparison == 0 ? left.id.compareTo(right.id) : nameComparison;
}
