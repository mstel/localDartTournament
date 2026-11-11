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

  bool get hasThreshold => switch (this) {
    PlayerInsightType.hotStreak ||
    PlayerInsightType.coldStreak ||
    PlayerInsightType.risingStar ||
    PlayerInsightType.unstoppable ||
    PlayerInsightType.backOnTrack ||
    PlayerInsightType.bogeyOpponent ||
    PlayerInsightType.rival ||
    PlayerInsightType.sweetRevenge ||
    PlayerInsightType.giantKiller ||
    PlayerInsightType.lastLegStanding ||
    PlayerInsightType.eloClimber => true,
    PlayerInsightType.momentum ||
    PlayerInsightType.consistent ||
    PlayerInsightType.underdog ||
    PlayerInsightType.titleDefender => false,
  };

  int get minimumThreshold => switch (this) {
    PlayerInsightType.hotStreak ||
    PlayerInsightType.coldStreak ||
    PlayerInsightType.unstoppable ||
    PlayerInsightType.backOnTrack ||
    PlayerInsightType.bogeyOpponent ||
    PlayerInsightType.rival ||
    PlayerInsightType.sweetRevenge ||
    PlayerInsightType.lastLegStanding => 2,
    _ => 1,
  };

  int get maximumThreshold => switch (this) {
    PlayerInsightType.hotStreak => 4,
    PlayerInsightType.bogeyOpponent => 10,
    PlayerInsightType.rival || PlayerInsightType.lastLegStanding => 5,
    PlayerInsightType.unstoppable => 999,
    PlayerInsightType.giantKiller => 99999,
    PlayerInsightType.eloClimber => 99999,
    _ => 999,
  };

  String get thresholdLabel => switch (this) {
    PlayerInsightType.hotStreak => 'Gewonnene Matches in Folge',
    PlayerInsightType.coldStreak => 'Verlorene Matches in Folge',
    PlayerInsightType.risingStar => 'Average-Steigerung zum Vormonat',
    PlayerInsightType.unstoppable => 'Gewonnene Matches in Folge',
    PlayerInsightType.backOnTrack => 'Vorherige Niederlagen in Folge',
    PlayerInsightType.bogeyOpponent => 'Verlorene Duelle unter den letzten 10',
    PlayerInsightType.rival => 'Gewonnene Duelle unter den letzten 10',
    PlayerInsightType.sweetRevenge =>
      'Vorherige Niederlagen gegen denselben Gegner',
    PlayerInsightType.giantKiller => 'ELO-Rückstand vor dem Match',
    PlayerInsightType.lastLegStanding => 'Decider unter den letzten 5 Matches',
    PlayerInsightType.eloClimber => 'ELO-Zuwachs der letzten 30 Tage',
    _ => '',
  };

  String get thresholdUnit => switch (this) {
    PlayerInsightType.risingStar => 'Punkte',
    PlayerInsightType.giantKiller ||
    PlayerInsightType.eloClimber => 'ELO-Punkte',
    _ => 'Matches',
  };

  String conditionDescription(int threshold) => switch (this) {
    PlayerInsightType.hotStreak =>
      'Die letzten $threshold Matches wurden hintereinander gewonnen. Ab 5 Siegen zeigt die App stattdessen „Unstoppable“.',
    PlayerInsightType.coldStreak =>
      'Die letzten $threshold Matches wurden hintereinander verloren.',
    PlayerInsightType.risingStar =>
      'Der Average ist mindestens um $threshold Punkte höher als im Vormonat. Für beide Monate sind jeweils mindestens 10 Legs nötig.',
    PlayerInsightType.momentum =>
      'Die erste abgeschlossene Partie dieses Turniers wurde gewonnen. Das ist eine Ja/Nein-Bedingung ohne Schwellenwert.',
    PlayerInsightType.unstoppable =>
      'Mindestens $threshold Matches in Folge wurden gewonnen.',
    PlayerInsightType.backOnTrack =>
      'Nach mindestens $threshold Niederlagen in Folge wurde wieder ein Match gewonnen.',
    PlayerInsightType.consistent =>
      'Die letzten 5 abgeschlossenen Matches wechselten durchgehend zwischen Sieg und Niederlage.',
    PlayerInsightType.bogeyOpponent =>
      'Mindestens $threshold der letzten 10 direkten Duelle gegen denselben Gegner wurden verloren.',
    PlayerInsightType.rival =>
      'Von den letzten 10 direkten Duellen gegen denselben Gegner wurden zwischen $threshold und ${10 - threshold} gewonnen.',
    PlayerInsightType.sweetRevenge =>
      'Ein Gegner wurde besiegt, nachdem zuvor mindestens $threshold direkte Duelle in Folge gegen ihn verloren wurden.',
    PlayerInsightType.giantKiller =>
      'Ein Gegner mit mindestens $threshold ELO-Punkten mehr wurde geschlagen.',
    PlayerInsightType.lastLegStanding =>
      'Mindestens $threshold der letzten 5 Matches wurden im entscheidenden letzten Leg gewonnen.',
    PlayerInsightType.underdog =>
      'Teilnehmer im unteren Drittel der ELO-Rangliste des Teilnehmerfelds haben eine positive Matchbilanz.',
    PlayerInsightType.titleDefender =>
      'Der Sieger der vorherigen Ausgabe desselben Turniers nimmt wieder teil.',
    PlayerInsightType.eloClimber =>
      'Der höchste ELO-Zuwachs der letzten 30 Tage ist mindestens $threshold Punkte hoch.',
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
