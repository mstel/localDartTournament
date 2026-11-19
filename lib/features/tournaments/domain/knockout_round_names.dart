import 'tournament_models.dart';

String knockoutRoundName(int index, int totalRounds) =>
    switch (totalRounds - index) {
      1 => 'Finale',
      2 => 'Halbfinale',
      3 => 'Viertelfinale',
      4 => 'Achtelfinale',
      _ => 'Runde ${index + 1}',
    };

/// Spaltenüberschrift für Turnierbäume und Spielpläne.
///
/// Das Platzierungsspiel um Platz 3 gehört fachlich zur Finalrunde und wird
/// deshalb gemeinsam mit dem Finale ausgewiesen.
String knockoutRoundColumnTitle(
  List<GroupMatch> roundMatches,
  int roundIndex,
  int totalRounds,
) {
  if (roundMatches.isNotEmpty &&
      roundMatches.every((match) => match.placementKey != null)) {
    return roundMatches.any((match) => match.label == 'Spiel um Platz 3')
        ? 'Finale / Spiel um Platz 3'
        : 'Platzierung';
  }
  return knockoutRoundName(roundIndex, totalRounds);
}

String _section(GroupMatch match) {
  final label = match.label ?? '';
  if (label.contains('Grand Final') ||
      label.contains('Reset') ||
      label.contains('Triple-KO Finalrunde')) {
    return 'Finale';
  }
  final losses = int.tryParse(label.split(' ').first);
  if (losses != null && losses >= 2 && label.contains('Niederlagen')) {
    return 'Loser-Bracket $losses';
  }
  if (label.startsWith('1 Niederlage') || label.startsWith('Losers')) {
    return 'Loser-Bracket';
  }
  return 'Winner-Bracket';
}

/// Presentation only: runtime labels remain stable for bracket propagation.
String knockoutMatchName(GroupMatch match, Iterable<GroupMatch> matches) {
  if (match.placementKey != null) return match.label ?? 'Platzierung';
  if (match.isDecider || (match.label?.contains('Platz ') ?? false)) {
    return match.label ?? 'Decider';
  }
  final section = _section(match);
  if (section == 'Finale') {
    return 'Finale';
  }
  final rounds =
      matches
          .where(
            (m) =>
                !m.isDecider &&
                !(m.label?.contains('Platz ') ?? false) &&
                _section(m) == section,
          )
          .map((m) => m.round)
          .toSet()
          .toList()
        ..sort();
  final name = knockoutRoundName(rounds.indexOf(match.round), rounds.length);
  return section == 'Winner-Bracket' ? name : '$section · $name';
}

String stageMatchName(TournamentRunStage stage, GroupMatch match) {
  if (stage is KnockoutTournamentRunStage) {
    return knockoutMatchName(match, stage.matches);
  }
  if (stage is GroupTournamentRunStage) {
    for (final group in stage.groups) {
      final all = [
        ...group.matches,
        ...group.knockoutRounds.expand((r) => r),
        ...group.placementMatches,
      ];
      if (all.contains(match) &&
          !['round_robin', 'swiss'].contains(group.playType)) {
        return knockoutMatchName(match, all);
      }
    }
  }
  return match.label ?? 'Runde ${match.round % 1000}';
}
