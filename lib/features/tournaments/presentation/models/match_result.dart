import '../../../statistics/domain/best_performance.dart';
import '../../domain/tournament_models.dart';

class MatchResult {
  const MatchResult({
    required this.homeLegs,
    required this.awayLegs,
    this.isAnnulled = false,
    this.homeSets,
    this.awaySets,
    this.bestPerformances = const [],
    this.scratchedPlayer,
    this.kratzerBonusLives = const [],
  });

  const MatchResult.annulled()
    : homeLegs = null,
      homeSets = null,
      awaySets = null,
      awayLegs = null,
      isAnnulled = true,
      bestPerformances = const [],
      scratchedPlayer = null,
      kratzerBonusLives = const [];

  const MatchResult.cleared()
    : homeLegs = null,
      homeSets = null,
      awaySets = null,
      awayLegs = null,
      isAnnulled = false,
      bestPerformances = const [],
      scratchedPlayer = null,
      kratzerBonusLives = const [];

  const MatchResult.kratzer(
    this.scratchedPlayer, {
    this.kratzerBonusLives = const [],
  }) : homeLegs = null,
       awayLegs = null,
       homeSets = null,
       awaySets = null,
       isAnnulled = false,
       bestPerformances = const [];

  final int? homeLegs;
  final int? awayLegs;
  final int? homeSets;
  final int? awaySets;
  final bool isAnnulled;
  final List<BestPerformance> bestPerformances;
  final TournamentPlayer? scratchedPlayer;
  final List<KratzerBonusLife> kratzerBonusLives;
}
