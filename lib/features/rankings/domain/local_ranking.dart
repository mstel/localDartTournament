enum RankingType { elo, series }

class LocalRanking {
  const LocalRanking({
    required this.id,
    required this.name,
    this.type = RankingType.elo,
    this.startRating = 1000,
    this.newPlayerK = 25,
    this.normalPlayerK = 15,
    this.proPlayerK = 10,
    this.matchesBeforeNormal = 10,
    this.proRatingThreshold = 2400,
    this.participationPoints = 1,
    this.setWinPoints = 1,
    this.firstPlacePoints = 10,
    this.secondPlacePoints = 6,
    this.thirdPlacePoints = 3,
    this.bestPerformancePoints = 1,
    this.validFromYear,
    this.validToYear,
    this.validFromDate,
    this.validToDate,
    this.enableTiers = false,
    this.requireMinimumParticipations = false,
    this.minimumParticipations = 1,
    this.allowDecayBelowStartRating = false,
    this.absenceDecayEnabled = false,
    this.absenceDecayPoints = 5,
    this.inactivityDecayEnabled = false,
    this.inactivityGraceTournaments = 3,
    this.inactivityDecayPoints = 5,
    this.isDefaultForStatistics = false,
    this.customOrder = 0,
  });

  final String id;
  final String name;
  final RankingType type;
  final int startRating;
  final int newPlayerK;
  final int normalPlayerK;
  final int proPlayerK;
  final int matchesBeforeNormal;
  final int proRatingThreshold;
  final int participationPoints;
  final int setWinPoints;
  final int firstPlacePoints;
  final int secondPlacePoints;
  final int thirdPlacePoints;
  final int bestPerformancePoints;
  final int? validFromYear;
  final int? validToYear;
  final DateTime? validFromDate;
  final DateTime? validToDate;
  final bool enableTiers;
  final bool requireMinimumParticipations;
  final int minimumParticipations;
  final bool allowDecayBelowStartRating;
  final bool absenceDecayEnabled;
  final int absenceDecayPoints;
  final bool inactivityDecayEnabled;
  final int inactivityGraceTournaments;
  final int inactivityDecayPoints;
  final bool isDefaultForStatistics;
  final int customOrder;

  bool includesTournamentYear(int year) =>
      (validFromYear == null || year >= validFromYear!) &&
      (validToYear == null || year <= validToYear!);

  bool includesTournamentDate(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final from =
        validFromDate ??
        (validFromYear == null ? null : DateTime(validFromYear!, 1, 1));
    final to =
        validToDate ??
        (validToYear == null ? null : DateTime(validToYear!, 12, 31));
    return (from == null || !day.isBefore(from)) &&
        (to == null || !day.isAfter(to));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'startRating': startRating,
    'newPlayerK': newPlayerK,
    'normalPlayerK': normalPlayerK,
    'proPlayerK': proPlayerK,
    'matchesBeforeNormal': matchesBeforeNormal,
    'proRatingThreshold': proRatingThreshold,
    'participationPoints': participationPoints,
    'setWinPoints': setWinPoints,
    'firstPlacePoints': firstPlacePoints,
    'secondPlacePoints': secondPlacePoints,
    'thirdPlacePoints': thirdPlacePoints,
    'bestPerformancePoints': bestPerformancePoints,
    'validFromYear': validFromYear,
    'validToYear': validToYear,
    'validFromDate': validFromDate?.toIso8601String(),
    'validToDate': validToDate?.toIso8601String(),
    'enableTiers': enableTiers,
    'requireMinimumParticipations': requireMinimumParticipations,
    'minimumParticipations': minimumParticipations,
    'allowDecayBelowStartRating': allowDecayBelowStartRating,
    'absenceDecayEnabled': absenceDecayEnabled,
    'absenceDecayPoints': absenceDecayPoints,
    'inactivityDecayEnabled': inactivityDecayEnabled,
    'inactivityGraceTournaments': inactivityGraceTournaments,
    'inactivityDecayPoints': inactivityDecayPoints,
    'isDefaultForStatistics': isDefaultForStatistics,
  };

  factory LocalRanking.fromJson(Map<String, Object?> json) => LocalRanking(
    id: json['id'] as String,
    name: json['name'] as String,
    type: RankingType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => RankingType.elo,
    ),
    startRating: json['startRating'] as int? ?? 1000,
    newPlayerK: json['newPlayerK'] as int? ?? 25,
    normalPlayerK: json['normalPlayerK'] as int? ?? 15,
    proPlayerK: json['proPlayerK'] as int? ?? 10,
    matchesBeforeNormal: json['matchesBeforeNormal'] as int? ?? 10,
    proRatingThreshold: json['proRatingThreshold'] as int? ?? 2400,
    participationPoints: json['participationPoints'] as int? ?? 1,
    setWinPoints: json['setWinPoints'] as int? ?? 1,
    firstPlacePoints: json['firstPlacePoints'] as int? ?? 10,
    secondPlacePoints: json['secondPlacePoints'] as int? ?? 6,
    thirdPlacePoints: json['thirdPlacePoints'] as int? ?? 3,
    bestPerformancePoints: json['bestPerformancePoints'] as int? ?? 1,
    validFromYear: json['validFromYear'] as int?,
    validToYear: json['validToYear'] as int?,
    validFromDate: DateTime.tryParse(json['validFromDate'] as String? ?? ''),
    validToDate: DateTime.tryParse(json['validToDate'] as String? ?? ''),
    enableTiers: json['enableTiers'] as bool? ?? false,
    requireMinimumParticipations:
        json['requireMinimumParticipations'] as bool? ?? false,
    minimumParticipations: json['minimumParticipations'] as int? ?? 1,
    allowDecayBelowStartRating:
        json['allowDecayBelowStartRating'] as bool? ?? false,
    absenceDecayEnabled: json['absenceDecayEnabled'] as bool? ?? false,
    absenceDecayPoints: json['absenceDecayPoints'] as int? ?? 5,
    inactivityDecayEnabled: json['inactivityDecayEnabled'] as bool? ?? false,
    inactivityGraceTournaments: json['inactivityGraceTournaments'] as int? ?? 3,
    inactivityDecayPoints: json['inactivityDecayPoints'] as int? ?? 5,
    isDefaultForStatistics: json['isDefaultForStatistics'] as bool? ?? false,
  );

  LocalRanking copyWith({
    String? id,
    String? name,
    RankingType? type,
    int? startRating,
    int? newPlayerK,
    int? normalPlayerK,
    int? proPlayerK,
    int? matchesBeforeNormal,
    int? proRatingThreshold,
    int? participationPoints,
    int? setWinPoints,
    int? firstPlacePoints,
    int? secondPlacePoints,
    int? thirdPlacePoints,
    int? bestPerformancePoints,
    int? validFromYear,
    int? validToYear,
    DateTime? validFromDate,
    DateTime? validToDate,
    bool? enableTiers,
    bool? requireMinimumParticipations,
    int? minimumParticipations,
    bool? allowDecayBelowStartRating,
    bool? absenceDecayEnabled,
    int? absenceDecayPoints,
    bool? inactivityDecayEnabled,
    int? inactivityGraceTournaments,
    int? inactivityDecayPoints,
    bool? isDefaultForStatistics,
    int? customOrder,
  }) => LocalRanking(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    startRating: startRating ?? this.startRating,
    newPlayerK: newPlayerK ?? this.newPlayerK,
    normalPlayerK: normalPlayerK ?? this.normalPlayerK,
    proPlayerK: proPlayerK ?? this.proPlayerK,
    matchesBeforeNormal: matchesBeforeNormal ?? this.matchesBeforeNormal,
    proRatingThreshold: proRatingThreshold ?? this.proRatingThreshold,
    participationPoints: participationPoints ?? this.participationPoints,
    setWinPoints: setWinPoints ?? this.setWinPoints,
    firstPlacePoints: firstPlacePoints ?? this.firstPlacePoints,
    secondPlacePoints: secondPlacePoints ?? this.secondPlacePoints,
    thirdPlacePoints: thirdPlacePoints ?? this.thirdPlacePoints,
    bestPerformancePoints: bestPerformancePoints ?? this.bestPerformancePoints,
    validFromYear: validFromYear ?? this.validFromYear,
    validToYear: validToYear ?? this.validToYear,
    validFromDate: validFromDate ?? this.validFromDate,
    validToDate: validToDate ?? this.validToDate,
    enableTiers: enableTiers ?? this.enableTiers,
    requireMinimumParticipations:
        requireMinimumParticipations ?? this.requireMinimumParticipations,
    minimumParticipations: minimumParticipations ?? this.minimumParticipations,
    allowDecayBelowStartRating:
        allowDecayBelowStartRating ?? this.allowDecayBelowStartRating,
    absenceDecayEnabled: absenceDecayEnabled ?? this.absenceDecayEnabled,
    absenceDecayPoints: absenceDecayPoints ?? this.absenceDecayPoints,
    inactivityDecayEnabled:
        inactivityDecayEnabled ?? this.inactivityDecayEnabled,
    inactivityGraceTournaments:
        inactivityGraceTournaments ?? this.inactivityGraceTournaments,
    inactivityDecayPoints: inactivityDecayPoints ?? this.inactivityDecayPoints,
    isDefaultForStatistics:
        isDefaultForStatistics ?? this.isDefaultForStatistics,
    customOrder: customOrder ?? this.customOrder,
  );
}
