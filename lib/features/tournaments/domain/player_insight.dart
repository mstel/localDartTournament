enum PlayerInsightType {
  hotStreak,
  coldStreak,
  risingStar,
  momentum,
  unstoppable,
  backOnTrack,
  consistent,
  bogeyOpponent,
  rival,
  sweetRevenge,
  giantKiller,
  lastLegStanding,
  underdog,
  titleDefender,
  eloClimber,
}

extension PlayerInsightTypeLabel on PlayerInsightType {
  String get label => switch (this) {
    PlayerInsightType.hotStreak => 'Hot Streak',
    PlayerInsightType.coldStreak => 'Cold Streak',
    PlayerInsightType.risingStar => 'Rising Star',
    PlayerInsightType.momentum => 'Momentum',
    PlayerInsightType.unstoppable => 'Unstoppable',
    PlayerInsightType.backOnTrack => 'Back on Track',
    PlayerInsightType.consistent => 'Consistent',
    PlayerInsightType.bogeyOpponent => 'Angstgegner',
    PlayerInsightType.rival => 'Rivalen',
    PlayerInsightType.sweetRevenge => 'Rache ist süß',
    PlayerInsightType.giantKiller => 'Giant Slayer',
    PlayerInsightType.lastLegStanding => 'Decider',
    PlayerInsightType.underdog => 'Underdog',
    PlayerInsightType.titleDefender => 'Titelverteidiger',
    PlayerInsightType.eloClimber => 'ELO Climber',
  };
}

class PlayerInsight {
  const PlayerInsight({
    required this.type,
    required this.playerId,
    required this.explanation,
    this.rivalId,
  });

  final PlayerInsightType type;
  final String playerId;
  final String? rivalId;
  final String explanation;
}
