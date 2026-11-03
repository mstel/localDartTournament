enum BestPerformanceType {
  bigFish170,
  score171Plus,
  score180,
  highFinish,
  bullseyeFinish,
  shortLeg,
  // Keep old in-memory callers source-compatible; persisted score170 is migrated.
  score170,
}

class BestPerformance {
  const BestPerformance({
    required this.type,
    required this.playerName,
    this.playerProfileId,
    this.value,
    this.details,
  });

  final BestPerformanceType type;
  final String playerName;
  final String? playerProfileId;
  final int? value;
  final String? details;

  BestPerformanceType get normalizedType => type == BestPerformanceType.score170
      ? BestPerformanceType.score171Plus
      : type;

  String get label => switch (normalizedType) {
    BestPerformanceType.bigFish170 => '170 (Big Fish)',
    BestPerformanceType.score171Plus => '171+',
    BestPerformanceType.score180 => '180+',
    BestPerformanceType.highFinish => 'High Finish',
    BestPerformanceType.bullseyeFinish => 'Bullseye Finish',
    BestPerformanceType.shortLeg => 'Shortleg',
    BestPerformanceType.score170 => '171+',
  };

  factory BestPerformance.fromJson(Map<String, dynamic> json) {
    final legacy170Plus = json['type'] == 'score170';
    return BestPerformance(
      type: legacy170Plus
          ? BestPerformanceType.score171Plus
          : BestPerformanceType.values.firstWhere(
              (type) => type.name == json['type'],
              orElse: () => BestPerformanceType.score180,
            ),
      playerName: json['playerName'] as String? ?? '',
      playerProfileId: json['playerProfileId'] as String?,
      value: legacy170Plus ? null : json['value'] as int?,
      details: json['details'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': normalizedType.name,
    'playerName': playerName,
    if (playerProfileId != null) 'playerProfileId': playerProfileId,
    if (value != null) 'value': value,
    if (details != null) 'details': details,
  };
}
