enum AnnouncementNameFormat { fullName, firstNameLastInitial }

class TournamentSettings {
  const TournamentSettings({
    this.priorityHintsEnabled = true,
    this.playerMatchDeficitThreshold = 2,
    this.groupMatchDeficitThreshold = 3,
    this.usePercentageForGroups = false,
    this.soundModeEnabled = false,
    this.announceHintsAudibly = false,
    this.idleBoardSoundEnabled = false,
    this.idleBoardSoundStartMinutes = 1,
    this.idleBoardSoundRepeatMinutes = 1,
    this.readAlternativeRecommendations = false,
    this.alternativeRecommendationCount = 3,
    this.announcementNameFormat = AnnouncementNameFormat.fullName,
    this.speakNicknameWhenAvailable = false,
    this.liveVisible = false,
  });

  static const schemaVersion = 1;
  static const minimumThreshold = 1;
  static const maximumThreshold = 999;

  final int playerMatchDeficitThreshold;
  final bool priorityHintsEnabled;
  final int groupMatchDeficitThreshold;
  final bool usePercentageForGroups;
  final bool soundModeEnabled;
  final bool announceHintsAudibly;
  final bool idleBoardSoundEnabled;
  final int idleBoardSoundStartMinutes;
  final int idleBoardSoundRepeatMinutes;
  final bool readAlternativeRecommendations;
  final int alternativeRecommendationCount;
  final AnnouncementNameFormat announcementNameFormat;
  final bool speakNicknameWhenAvailable;

  /// Publishes a slim spectator view of the running tournament. Additive to
  /// schema version 1 so older app versions can still read tournaments.
  final bool liveVisible;

  bool get isValid =>
      playerMatchDeficitThreshold >= minimumThreshold &&
      playerMatchDeficitThreshold <= maximumThreshold &&
      groupMatchDeficitThreshold >= minimumThreshold &&
      groupMatchDeficitThreshold <= maximumThreshold &&
      idleBoardSoundStartMinutes >= 1 &&
      idleBoardSoundStartMinutes <= 5 &&
      idleBoardSoundRepeatMinutes >= 1 &&
      idleBoardSoundRepeatMinutes <= 5 &&
      alternativeRecommendationCount >= 0 &&
      alternativeRecommendationCount <= 3;

  TournamentSettings copyWith({
    int? playerMatchDeficitThreshold,
    bool? priorityHintsEnabled,
    int? groupMatchDeficitThreshold,
    bool? usePercentageForGroups,
    bool? soundModeEnabled,
    bool? announceHintsAudibly,
    bool? idleBoardSoundEnabled,
    int? idleBoardSoundStartMinutes,
    int? idleBoardSoundRepeatMinutes,
    bool? readAlternativeRecommendations,
    int? alternativeRecommendationCount,
    AnnouncementNameFormat? announcementNameFormat,
    bool? speakNicknameWhenAvailable,
    bool? liveVisible,
  }) => TournamentSettings(
    playerMatchDeficitThreshold:
        playerMatchDeficitThreshold ?? this.playerMatchDeficitThreshold,
    priorityHintsEnabled: priorityHintsEnabled ?? this.priorityHintsEnabled,
    groupMatchDeficitThreshold:
        groupMatchDeficitThreshold ?? this.groupMatchDeficitThreshold,
    usePercentageForGroups:
        usePercentageForGroups ?? this.usePercentageForGroups,
    soundModeEnabled: soundModeEnabled ?? this.soundModeEnabled,
    announceHintsAudibly: announceHintsAudibly ?? this.announceHintsAudibly,
    idleBoardSoundEnabled: idleBoardSoundEnabled ?? this.idleBoardSoundEnabled,
    idleBoardSoundStartMinutes:
        idleBoardSoundStartMinutes ?? this.idleBoardSoundStartMinutes,
    idleBoardSoundRepeatMinutes:
        idleBoardSoundRepeatMinutes ?? this.idleBoardSoundRepeatMinutes,
    readAlternativeRecommendations:
        readAlternativeRecommendations ?? this.readAlternativeRecommendations,
    alternativeRecommendationCount:
        alternativeRecommendationCount ?? this.alternativeRecommendationCount,
    announcementNameFormat:
        announcementNameFormat ?? this.announcementNameFormat,
    speakNicknameWhenAvailable:
        speakNicknameWhenAvailable ?? this.speakNicknameWhenAvailable,
    liveVisible: liveVisible ?? this.liveVisible,
  );

  factory TournamentSettings.fromJson(
    Map<String, dynamic> json, {
    bool defaultPriorityHintsEnabled = true,
  }) {
    final storedNameFormat = json['announcementNameFormat'];
    final settings = TournamentSettings(
      playerMatchDeficitThreshold: _boundedInt(
        json['playerMatchDeficitThreshold'],
        fallback: 2,
        minimum: minimumThreshold,
        maximum: maximumThreshold,
      ),
      priorityHintsEnabled:
          json['priorityHintsEnabled'] as bool? ??
          defaultPriorityHintsEnabled,
      groupMatchDeficitThreshold: _boundedInt(
        json['groupMatchDeficitThreshold'],
        fallback: 3,
        minimum: minimumThreshold,
        maximum: maximumThreshold,
      ),
      usePercentageForGroups: json['usePercentageForGroups'] as bool? ?? false,
      soundModeEnabled: json['soundModeEnabled'] as bool? ?? false,
      announceHintsAudibly: json['announceHintsAudibly'] as bool? ?? false,
      idleBoardSoundEnabled: json['idleBoardSoundEnabled'] as bool? ?? false,
      idleBoardSoundStartMinutes: _boundedInt(
        json['idleBoardSoundStartMinutes'],
        fallback: 1,
        minimum: 1,
        maximum: 5,
      ),
      idleBoardSoundRepeatMinutes: _boundedInt(
        json['idleBoardSoundRepeatMinutes'],
        fallback: 1,
        minimum: 1,
        maximum: 5,
      ),
      readAlternativeRecommendations:
          json['readAlternativeRecommendations'] as bool? ?? false,
      alternativeRecommendationCount: _boundedInt(
        json['alternativeRecommendationCount'],
        fallback: 3,
        minimum: 0,
        maximum: 3,
      ),
      announcementNameFormat: AnnouncementNameFormat.values.firstWhere(
        (format) => format.name == storedNameFormat,
        orElse: () => AnnouncementNameFormat.fullName,
      ),
      speakNicknameWhenAvailable:
          json['speakNicknameWhenAvailable'] as bool? ?? false,
      liveVisible: json['liveVisible'] as bool? ?? false,
    );
    if (json['version'] != null && json['version'] != schemaVersion) {
      throw FormatException(
        'Turniereinstellungen-Version ${json['version']} wird nicht unterstützt.',
      );
    }
    return settings;
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'playerMatchDeficitThreshold': playerMatchDeficitThreshold,
    'priorityHintsEnabled': priorityHintsEnabled,
    'groupMatchDeficitThreshold': groupMatchDeficitThreshold,
    'usePercentageForGroups': usePercentageForGroups,
    'soundModeEnabled': soundModeEnabled,
    'announceHintsAudibly': announceHintsAudibly,
    'idleBoardSoundEnabled': idleBoardSoundEnabled,
    'idleBoardSoundStartMinutes': idleBoardSoundStartMinutes,
    'idleBoardSoundRepeatMinutes': idleBoardSoundRepeatMinutes,
    'readAlternativeRecommendations': readAlternativeRecommendations,
    'alternativeRecommendationCount': alternativeRecommendationCount,
    'announcementNameFormat': announcementNameFormat.name,
    'speakNicknameWhenAvailable': speakNicknameWhenAvailable,
    if (liveVisible) 'liveVisible': true,
  };

  static int _boundedInt(
    Object? value, {
    required int fallback,
    required int minimum,
    required int maximum,
  }) {
    final parsed = value is int ? value : int.tryParse('$value') ?? fallback;
    return parsed.clamp(minimum, maximum);
  }

  @override
  bool operator ==(Object other) =>
      other is TournamentSettings &&
      other.playerMatchDeficitThreshold == playerMatchDeficitThreshold &&
      other.priorityHintsEnabled == priorityHintsEnabled &&
      other.groupMatchDeficitThreshold == groupMatchDeficitThreshold &&
      other.usePercentageForGroups == usePercentageForGroups &&
      other.soundModeEnabled == soundModeEnabled &&
      other.announceHintsAudibly == announceHintsAudibly &&
      other.idleBoardSoundEnabled == idleBoardSoundEnabled &&
      other.idleBoardSoundStartMinutes == idleBoardSoundStartMinutes &&
      other.idleBoardSoundRepeatMinutes == idleBoardSoundRepeatMinutes &&
      other.readAlternativeRecommendations == readAlternativeRecommendations &&
      other.alternativeRecommendationCount == alternativeRecommendationCount &&
      other.announcementNameFormat == announcementNameFormat &&
      other.speakNicknameWhenAvailable == speakNicknameWhenAvailable &&
      other.liveVisible == liveVisible;

  @override
  int get hashCode => Object.hash(
    playerMatchDeficitThreshold,
    priorityHintsEnabled,
    groupMatchDeficitThreshold,
    usePercentageForGroups,
    soundModeEnabled,
    announceHintsAudibly,
    idleBoardSoundEnabled,
    idleBoardSoundStartMinutes,
    idleBoardSoundRepeatMinutes,
    readAlternativeRecommendations,
    alternativeRecommendationCount,
    announcementNameFormat,
    speakNicknameWhenAvailable,
    liveVisible,
  );
}
