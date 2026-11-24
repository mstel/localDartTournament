import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../tournaments/domain/director_schedule_modes.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/domain/tournament_settings.dart';

class DirectorAudioDefaults {
  const DirectorAudioDefaults({
    this.soundModeEnabled = false,
    this.nameFormat = AnnouncementNameFormat.fullName,
    this.speakNicknameWhenAvailable = false,
    this.readAlternativeRecommendations = false,
    this.alternativeRecommendationCount = 3,
  });

  final bool soundModeEnabled;
  final AnnouncementNameFormat nameFormat;
  final bool speakNicknameWhenAvailable;
  final bool readAlternativeRecommendations;
  final int alternativeRecommendationCount;

  static const defaults = DirectorAudioDefaults();

  DirectorAudioDefaults copyWith({
    bool? soundModeEnabled,
    AnnouncementNameFormat? nameFormat,
    bool? speakNicknameWhenAvailable,
    bool? readAlternativeRecommendations,
    int? alternativeRecommendationCount,
  }) => DirectorAudioDefaults(
    soundModeEnabled: soundModeEnabled ?? this.soundModeEnabled,
    nameFormat: nameFormat ?? this.nameFormat,
    speakNicknameWhenAvailable:
        speakNicknameWhenAvailable ?? this.speakNicknameWhenAvailable,
    readAlternativeRecommendations:
        readAlternativeRecommendations ?? this.readAlternativeRecommendations,
    alternativeRecommendationCount:
        alternativeRecommendationCount ?? this.alternativeRecommendationCount,
  );

  factory DirectorAudioDefaults.fromJson(Map<String, dynamic> json) =>
      DirectorAudioDefaults(
        soundModeEnabled: json['soundModeEnabled'] as bool? ?? false,
        nameFormat: AnnouncementNameFormat.values.firstWhere(
          (format) => format.name == json['nameFormat'],
          orElse: () => AnnouncementNameFormat.fullName,
        ),
        speakNicknameWhenAvailable:
            json['speakNicknameWhenAvailable'] as bool? ?? false,
        readAlternativeRecommendations:
            json['readAlternativeRecommendations'] as bool? ?? false,
        alternativeRecommendationCount:
            ((json['alternativeRecommendationCount'] as num?)?.toInt() ?? 3)
                .clamp(0, 3),
      );

  Map<String, dynamic> toJson() => {
    'soundModeEnabled': soundModeEnabled,
    'nameFormat': nameFormat.name,
    'speakNicknameWhenAvailable': speakNicknameWhenAvailable,
    'readAlternativeRecommendations': readAlternativeRecommendations,
    'alternativeRecommendationCount': alternativeRecommendationCount,
  };

  TournamentSettings applyTo(TournamentSettings settings) => settings.copyWith(
    soundModeEnabled: soundModeEnabled,
    announcementNameFormat: nameFormat,
    speakNicknameWhenAvailable: speakNicknameWhenAvailable,
    readAlternativeRecommendations: readAlternativeRecommendations,
    alternativeRecommendationCount: alternativeRecommendationCount,
  );
}

class DirectorModeDefaults {
  const DirectorModeDefaults({
    this.tournamentsEnabled = true,
    this.tournamentScheduleMode = 'fixed_schedule',
    this.tournamentBoardAssignment = 'group',
    this.tournamentAudio = DirectorAudioDefaults.defaults,
    this.tournamentPlayerInsights = false,
    this.leagueScheduleMode = 'fixed_schedule',
    this.leagueSuggestionMode = 'assigned',
    this.leagueAudio = DirectorAudioDefaults.defaults,
  });

  final bool tournamentsEnabled;
  final String tournamentScheduleMode;
  final String tournamentBoardAssignment;
  final DirectorAudioDefaults tournamentAudio;
  final bool tournamentPlayerInsights;
  final String leagueScheduleMode;
  final String leagueSuggestionMode;
  final DirectorAudioDefaults leagueAudio;

  static const defaults = DirectorModeDefaults();
  static const schemaVersion = 1;

  DirectorModeDefaults copyWith({
    bool? tournamentsEnabled,
    String? tournamentScheduleMode,
    String? tournamentBoardAssignment,
    DirectorAudioDefaults? tournamentAudio,
    bool? tournamentPlayerInsights,
    String? leagueScheduleMode,
    String? leagueSuggestionMode,
    DirectorAudioDefaults? leagueAudio,
  }) => DirectorModeDefaults(
    tournamentsEnabled: tournamentsEnabled ?? this.tournamentsEnabled,
    tournamentScheduleMode:
        tournamentScheduleMode ?? this.tournamentScheduleMode,
    tournamentBoardAssignment:
        tournamentBoardAssignment ?? this.tournamentBoardAssignment,
    tournamentAudio: tournamentAudio ?? this.tournamentAudio,
    tournamentPlayerInsights:
        tournamentPlayerInsights ?? this.tournamentPlayerInsights,
    leagueScheduleMode: leagueScheduleMode ?? this.leagueScheduleMode,
    leagueSuggestionMode: leagueSuggestionMode ?? this.leagueSuggestionMode,
    leagueAudio: leagueAudio ?? this.leagueAudio,
  );

  factory DirectorModeDefaults.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version != null && version != schemaVersion) {
      throw FormatException(
        'Turnierleiter-Standardwerte-Version $version wird nicht unterstützt.',
      );
    }
    final tournament = Map<String, dynamic>.from(
      json['tournaments'] as Map? ?? const {},
    );
    final league = Map<String, dynamic>.from(
      json['league'] as Map? ?? const {},
    );
    final scheduleMode = DirectorScheduleModes.playOrderMode(
      tournament['scheduleMode'],
    );
    return DirectorModeDefaults(
      tournamentsEnabled: tournament['enabled'] as bool? ?? true,
      tournamentScheduleMode: scheduleMode,
      tournamentBoardAssignment: DirectorScheduleModes.schedulingStrategy(
        tournament['boardAssignment'],
        scheduleMode,
      ),
      tournamentAudio: DirectorAudioDefaults.fromJson(
        Map<String, dynamic>.from(tournament['audio'] as Map? ?? const {}),
      ),
      tournamentPlayerInsights: tournament['playerInsights'] as bool? ?? false,
      leagueScheduleMode: _oneOf(league['scheduleMode'], const [
        'fixed_schedule',
        'dynamic',
      ], 'fixed_schedule'),
      leagueSuggestionMode: _oneOf(league['suggestionMode'], const [
        'mirror',
        'assigned',
      ], 'assigned'),
      leagueAudio: DirectorAudioDefaults.fromJson(
        Map<String, dynamic>.from(league['audio'] as Map? ?? const {}),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'tournaments': {
      'enabled': tournamentsEnabled,
      'scheduleMode': tournamentScheduleMode,
      'boardAssignment': tournamentBoardAssignment,
      'audio': tournamentAudio.toJson(),
      'playerInsights': tournamentPlayerInsights,
    },
    'league': {
      'scheduleMode': leagueScheduleMode,
      'suggestionMode': leagueSuggestionMode,
      'audio': leagueAudio.toJson(),
    },
  };

  /// Applies the defaults to a newly created regular tournament.
  CreatedTournament applyToTournament(CreatedTournament tournament) {
    tournament
      ..directorModeEnabled = tournamentsEnabled
      ..directorPlayOrderMode = tournamentScheduleMode
      ..directorSchedulingStrategy = DirectorScheduleModes.schedulingStrategy(
        tournamentBoardAssignment,
        tournamentScheduleMode,
      )
      ..showPlayerInsights = tournamentPlayerInsights
      ..tournamentSettings = tournamentAudio.applyTo(
        tournament.tournamentSettings,
      );
    return tournament;
  }

  /// Applies the defaults to a newly created league/friendly match. The
  /// director mode is always forced on for this mode.
  CreatedTournament applyToLeagueMatch(CreatedTournament tournament) {
    tournament
      ..directorModeEnabled = true
      ..directorPlayOrderMode = leagueScheduleMode
      ..directorMultiBoardAssignmentBehavior = leagueSuggestionMode
      ..tournamentSettings = leagueAudio.applyTo(tournament.tournamentSettings);
    return tournament;
  }

  static String _oneOf(Object? value, List<String> allowed, String fallback) =>
      allowed.contains(value) ? value! as String : fallback;
}

class DirectorModeDefaultsStorage {
  const DirectorModeDefaultsStorage();

  static const _key = 'director_mode_defaults_v1';

  Future<DirectorModeDefaults> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_key);
      if (raw == null || raw.trim().isEmpty) {
        return DirectorModeDefaults.defaults;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return DirectorModeDefaults.defaults;
      return DirectorModeDefaults.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return DirectorModeDefaults.defaults;
    }
  }

  Future<void> save(DirectorModeDefaults value) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_key, jsonEncode(value.toJson()));
    if (!saved) {
      throw StateError(
        'Turnierleiter-Standardwerte konnten nicht gespeichert werden.',
      );
    }
  }
}
