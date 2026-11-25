class TournamentFlowPrioritySettings {
  const TournamentFlowPrioritySettings({
    this.playerMatchDeficitThreshold = 2,
    this.groupMatchDeficitThreshold = 3,
    this.usePercentageForGroups = false,
    this.enabled = true,
  });

  static const minimumThreshold = 1;
  final int playerMatchDeficitThreshold;
  final int groupMatchDeficitThreshold;
  final bool usePercentageForGroups;
  final bool enabled;

  TournamentFlowPrioritySettings copyWith({
    int? playerMatchDeficitThreshold,
    int? groupMatchDeficitThreshold,
    bool? usePercentageForGroups,
    bool? enabled,
  }) => TournamentFlowPrioritySettings(
    playerMatchDeficitThreshold:
        playerMatchDeficitThreshold ?? this.playerMatchDeficitThreshold,
    groupMatchDeficitThreshold:
        groupMatchDeficitThreshold ?? this.groupMatchDeficitThreshold,
    usePercentageForGroups:
        usePercentageForGroups ?? this.usePercentageForGroups,
    enabled: enabled ?? this.enabled,
  );

  bool get isValid =>
      playerMatchDeficitThreshold >= minimumThreshold &&
      groupMatchDeficitThreshold >= minimumThreshold;

  @override
  bool operator ==(Object other) =>
      other is TournamentFlowPrioritySettings &&
      other.playerMatchDeficitThreshold == playerMatchDeficitThreshold &&
      other.groupMatchDeficitThreshold == groupMatchDeficitThreshold &&
      other.usePercentageForGroups == usePercentageForGroups &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(
    playerMatchDeficitThreshold,
    groupMatchDeficitThreshold,
    usePercentageForGroups,
    enabled,
  );
}
