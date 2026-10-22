class TournamentDurationRange {
  const TournamentDurationRange._();

  static String formatDuration(Duration duration) =>
      formatMinutes(duration.inMinutes);

  static String formatMinutes(int minutes) =>
      '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

  static String actualDurationLabel(Duration duration) =>
      'Tatsächliche Turnierdauer: ${formatDuration(duration)}';

  static String estimatedDurationLabel({
    required int minimumMinutes,
    required int maximumMinutes,
  }) {
    final averageMinutes = ((minimumMinutes + maximumMinutes) / 2).round();
    return 'Geschätzte Turnierdauer: ${formatMinutes(averageMinutes)} '
        '(${formatMinutes(minimumMinutes)}–${formatMinutes(maximumMinutes)})';
  }

  static ({int minimumMinutes, int maximumMinutes}) forEstimate({
    required int estimatedMinutes,
    required Iterable<({int bestOfLegs, int matchCount})> matches,
  }) {
    var estimatedLegs = 0.0;
    var minimumLegs = 0.0;
    var maximumLegs = 0.0;
    for (final match in matches) {
      if (match.matchCount <= 0 || match.bestOfLegs < 1) continue;
      final minimum = match.bestOfLegs ~/ 2 + 1;
      estimatedLegs += match.matchCount * (minimum + match.bestOfLegs) / 2;
      minimumLegs += match.matchCount * minimum;
      maximumLegs += match.matchCount * match.bestOfLegs;
    }

    if (estimatedLegs == 0) {
      return (
        minimumMinutes: estimatedMinutes,
        maximumMinutes: estimatedMinutes,
      );
    }

    return (
      minimumMinutes: (estimatedMinutes * minimumLegs / estimatedLegs).round(),
      maximumMinutes: (estimatedMinutes * maximumLegs / estimatedLegs).round(),
    );
  }
}
