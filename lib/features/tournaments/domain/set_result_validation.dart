import 'tournament_models.dart';

/// A normal legs match ends as soon as a player reaches the legs-to-win
/// threshold. Even formats may also end tied after every leg is played.
bool isValidLegResult(
  TournamentGameFormat format, {
  required int homeLegs,
  required int awayLegs,
}) {
  if (homeLegs < 0 || awayLegs < 0) return false;
  final legsToWin = format.bestOfLegs ~/ 2 + 1;
  if (homeLegs > legsToWin || awayLegs > legsToWin) return false;
  if (homeLegs == awayLegs) {
    return format.allowsDraws && homeLegs * 2 == format.bestOfLegs;
  }
  return (homeLegs == legsToWin && awayLegs < legsToWin) ||
      (awayLegs == legsToWin && homeLegs < legsToWin);
}

/// Aggregate legs must be attainable from the reported set wins.
bool isValidSetResult(
  TournamentGameFormat format, {
  required int homeSets,
  required int awaySets,
  required int homeLegs,
  required int awayLegs,
}) {
  final setsToWin = format.bestOfSets ~/ 2 + 1;
  final legsToWin = format.bestOfLegs ~/ 2 + 1;
  if (homeSets < 0 ||
      awaySets < 0 ||
      !((homeSets == setsToWin && awaySets < setsToWin) ||
          (awaySets == setsToWin && homeSets < setsToWin))) {
    return false;
  }
  bool attainable(int legs, int won, int lost) =>
      legs >= won * legsToWin &&
      legs <= won * legsToWin + lost * (legsToWin - 1);
  return attainable(homeLegs, homeSets, awaySets) &&
      attainable(awayLegs, awaySets, homeSets);
}
