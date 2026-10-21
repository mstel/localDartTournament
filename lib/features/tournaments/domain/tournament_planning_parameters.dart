enum PlanningParameter {
  swissRoundWaitMinutes(
    'Swiss-Zeitplanung',
    'Reserve je Rundenwechsel (Warten / Auslosung)',
    5,
    0,
    120,
  ),
  maximumGroups('Turnieraufbau', 'Maximale Gruppenzahl', 4, 1, 64),
  qualifiersPerGroup('Turnieraufbau', 'Qualifikation je Gruppe', 2, 1, 64),
  maximumSuggestions('Turnieraufbau', 'Anzahl Vorschläge', 3, 1, 64),
  minutes301DoubleOut('Minuten pro Leg', '301 · Double Out', 3, 1, 120),
  minutes501DoubleOut('Minuten pro Leg', '501 · Double Out', 5, 1, 120),
  minutes301SingleOut('Minuten pro Leg', '301 · Single Out', 2, 1, 120),
  minutes501SingleOut('Minuten pro Leg', '501 · Single Out', 4, 1, 120),
  boardIdleMinutes(
    'Pausen / Boardwechsel',
    'Leerstand Minuten/Board',
    4,
    0,
    120,
  ),
  fallbackSingleOutMinutes(
    'Minuten pro Leg',
    'Andere Punktzahlen · Single Out',
    7,
    1,
    120,
  ),
  fallbackOtherMinutes(
    'Minuten pro Leg',
    'Sonstige Kombinationen (auch Master Out)',
    10,
    1,
    120,
  ),
  missingMatchPenalty(
    'Bewertung (Strafpunkte)',
    'Je fehlendem Mindestspiel pro Spieler',
    10000,
    0,
    1000000,
  ),
  timeWindowPenalty(
    'Bewertung (Strafpunkte)',
    'Je Minute außerhalb des Zeitfensters',
    10,
    0,
    1000000,
  ),
  targetDurationPenalty(
    'Bewertung (Strafpunkte)',
    'Je Minute Abstand zur maximalen Dauer',
    1,
    0,
    1000000,
  );

  const PlanningParameter(
    this.category,
    this.label,
    this.defaultValue,
    this.minimum,
    this.maximum,
  );
  final String category;
  final String label;
  final int defaultValue;
  final int minimum;
  final int maximum;

  bool accepts(int value) => value >= minimum && value <= maximum;
}

/// Immutable, validated values shared by settings and the planning engine.
class TournamentPlanningParameters {
  const TournamentPlanningParameters() : _values = const {};

  TournamentPlanningParameters.fromValues(Map<PlanningParameter, int> values)
    : _values = Map.unmodifiable(values) {
    for (final entry in values.entries) {
      if (!entry.key.accepts(entry.value)) {
        throw ArgumentError.value(entry.value, entry.key.name);
      }
    }
  }

  factory TournamentPlanningParameters.fromJson(Map<String, dynamic> json) {
    return TournamentPlanningParameters.fromValues({
      for (final parameter in PlanningParameter.values)
        parameter: switch (json[parameter.name]) {
          final int value when parameter.accepts(value) => value,
          _ => parameter.defaultValue,
        },
    });
  }

  final Map<PlanningParameter, int> _values;
  int value(PlanningParameter parameter) =>
      _values[parameter] ?? parameter.defaultValue;
  Map<String, dynamic> toJson() => {
    for (final parameter in PlanningParameter.values)
      parameter.name: value(parameter),
  };
  int get maximumGroups => value(PlanningParameter.maximumGroups);
  int get qualifiersPerGroup => value(PlanningParameter.qualifiersPerGroup);
  int get maximumSuggestions => value(PlanningParameter.maximumSuggestions);
  int get minutes301DoubleOut => value(PlanningParameter.minutes301DoubleOut);
  int get minutes501DoubleOut => value(PlanningParameter.minutes501DoubleOut);
  int get minutes301SingleOut => value(PlanningParameter.minutes301SingleOut);
  int get minutes501SingleOut => value(PlanningParameter.minutes501SingleOut);
  int get boardIdleMinutes => value(PlanningParameter.boardIdleMinutes);
  int get fallbackSingleOutMinutes =>
      value(PlanningParameter.fallbackSingleOutMinutes);
  int get fallbackOtherMinutes => value(PlanningParameter.fallbackOtherMinutes);
  int get missingMatchPenalty => value(PlanningParameter.missingMatchPenalty);
  int get timeWindowPenalty => value(PlanningParameter.timeWindowPenalty);
  int get targetDurationPenalty =>
      value(PlanningParameter.targetDurationPenalty);
}
