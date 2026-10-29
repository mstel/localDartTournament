class TournamentFlowPrioritySettings {
  const TournamentFlowPrioritySettings({
    this.playerMatchDeficitThreshold = 2,
    this.groupMatchDeficitThreshold = 3,
    this.usePercentageForGroups = false,
  });

  static const minimumThreshold = 1;
  final int playerMatchDeficitThreshold;
  final int groupMatchDeficitThreshold;
  final bool usePercentageForGroups;

  TournamentFlowPrioritySettings copyWith({
    int? playerMatchDeficitThreshold,
    int? groupMatchDeficitThreshold,
    bool? usePercentageForGroups,
  }) => TournamentFlowPrioritySettings(
    playerMatchDeficitThreshold:
        playerMatchDeficitThreshold ?? this.playerMatchDeficitThreshold,
    groupMatchDeficitThreshold:
        groupMatchDeficitThreshold ?? this.groupMatchDeficitThreshold,
    usePercentageForGroups:
        usePercentageForGroups ?? this.usePercentageForGroups,
  );

  bool get isValid =>
      playerMatchDeficitThreshold >= minimumThreshold &&
      groupMatchDeficitThreshold >= minimumThreshold;

  @override
  bool operator ==(Object other) =>
      other is TournamentFlowPrioritySettings &&
      other.playerMatchDeficitThreshold == playerMatchDeficitThreshold &&
      other.groupMatchDeficitThreshold == groupMatchDeficitThreshold &&
      other.usePercentageForGroups == usePercentageForGroups;

  @override
  int get hashCode => Object.hash(
    playerMatchDeficitThreshold,
    groupMatchDeficitThreshold,
    usePercentageForGroups,
  );
}
