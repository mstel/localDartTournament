import 'engines/board_scheduling_engine.dart';
import 'engines/tournament_engine.dart';
import 'tournament_models.dart';

/// Estimates a flexible round-robin order with equally long matches.
/// Board capacity and each group's player availability both limit throughput.
/// Knockout rounds remain sequential because they depend on prior results.
class PlanningDuration {
  const PlanningDuration({
    required this.groupSlots,
    required this.knockoutSlots,
    required this.matchMinutes,
    this.boardIdleMinutes = 0,
    num? knockoutMatchMinutes,
  }) : knockoutMatchMinutes = knockoutMatchMinutes ?? matchMinutes;
  final int groupSlots;
  final int knockoutSlots;
  final num matchMinutes;
  final num knockoutMatchMinutes;
  final num boardIdleMinutes;
  int get _knockoutSwitches => groupSlots > 0
      ? knockoutSlots
      : knockoutSlots > 0
      ? knockoutSlots - 1
      : 0;
  // Avoid rounding floating-point residues above whole minutes up again.
  int get groupMinutes =>
      (groupSlots * matchMinutes +
              (groupSlots > 0 ? groupSlots - 1 : 0) * boardIdleMinutes -
              1e-9)
          .ceil();
  int get knockoutMinutes =>
      (knockoutSlots * knockoutMatchMinutes +
              _knockoutSwitches * boardIdleMinutes -
              1e-9)
          .ceil();
  int get totalMinutes => groupMinutes + knockoutMinutes;

  static double estimatedLegs(int bestOfLegs) {
    if (bestOfLegs < 1) {
      throw ArgumentError.value(bestOfLegs, 'bestOfLegs');
    }
    final minimum = bestOfLegs ~/ 2 + 1;
    return (minimum + bestOfLegs) / 2;
  }

  static double estimatedMatchLegs(TournamentGameFormat format) =>
      estimatedLegs(format.bestOfLegs) * estimatedLegs(format.bestOfSets);

  factory PlanningDuration.calculate({
    required List<int> groupSizes,
    required int qualifiers,
    required int boards,
    required num matchMinutes,
    String strategy = 'global',
    num? knockoutMatchMinutes,
    num boardIdleMinutes = 0,
  }) {
    if (boards < 1 ||
        matchMinutes < 1 ||
        (knockoutMatchMinutes ?? matchMinutes) < 1 ||
        boardIdleMinutes < 0) {
      throw ArgumentError('Positive boards and match duration required');
    }
    final groupEntries = <PlayEntry>[];
    for (var group = 0; group < groupSizes.length; group++) {
      final players = [
        for (var player = 0; player < groupSizes[group]; player++)
          TournamentPlayer(name: 'G$group-P$player', isGenerated: true),
      ];
      for (final match in tournamentEngine.buildRoundRobinMatches(players)) {
        groupEntries.add(PlayEntry(match, 0, 'G$group', 'G$group'));
      }
    }
    final assignments = const BoardSchedulingEngine().schedule(
      all: groupEntries,
      ready: groupEntries,
      boardCount: boards,
      strategy: strategy,
    );
    final groupSlots = assignments.isEmpty ? 0 : assignments.last.block + 1;
    var knockoutSlots = 0;
    if (qualifiers > 1) {
      var bracket = 1;
      while (bracket < qualifiers) {
        bracket *= 2;
      }
      // Only actual first-round matches count; byes need no board time.
      knockoutSlots += _knockoutRoundSlots(qualifiers - bracket ~/ 2, boards);
      for (var matches = bracket ~/ 4; matches >= 1; matches ~/= 2) {
        knockoutSlots += _knockoutRoundSlots(matches, boards);
      }
    }
    return PlanningDuration(
      groupSlots: groupSlots,
      knockoutSlots: knockoutSlots,
      matchMinutes: matchMinutes,
      knockoutMatchMinutes: knockoutMatchMinutes,
      boardIdleMinutes: boardIdleMinutes,
    );
  }
}

int _knockoutRoundSlots(int matches, int boards) {
  final entries = [
    for (var index = 0; index < matches; index++)
      PlayEntry(
        GroupMatch(
          homePlayer: TournamentPlayer.generated(index * 2 + 1),
          awayPlayer: TournamentPlayer.generated(index * 2 + 2),
          round: 1,
        ),
        0,
        'KO',
      ),
  ];
  final schedule = const BoardSchedulingEngine().schedule(
    all: entries,
    ready: entries,
    boardCount: boards,
  );
  return schedule.isEmpty ? 0 : schedule.last.block + 1;
}
