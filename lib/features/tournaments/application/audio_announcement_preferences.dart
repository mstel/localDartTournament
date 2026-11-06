import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../domain/tournament_models.dart';

enum AnnouncementNameFormat { fullName, firstNameLastInitial }

class AudioAnnouncementPreferences {
  const AudioAnnouncementPreferences({
    this.nameFormat = AnnouncementNameFormat.fullName,
    this.speakNicknameWhenAvailable = false,
    this.readAlternativeRecommendations = false,
    this.alternativeRecommendationCount = 1,
  });

  final AnnouncementNameFormat nameFormat;
  final bool speakNicknameWhenAvailable;
  final bool readAlternativeRecommendations;
  final int alternativeRecommendationCount;

  AudioAnnouncementPreferences copyWith({
    AnnouncementNameFormat? nameFormat,
    bool? speakNicknameWhenAvailable,
    bool? readAlternativeRecommendations,
    int? alternativeRecommendationCount,
  }) => AudioAnnouncementPreferences(
    nameFormat: nameFormat ?? this.nameFormat,
    speakNicknameWhenAvailable:
        speakNicknameWhenAvailable ?? this.speakNicknameWhenAvailable,
    readAlternativeRecommendations:
        readAlternativeRecommendations ?? this.readAlternativeRecommendations,
    alternativeRecommendationCount:
        alternativeRecommendationCount ?? this.alternativeRecommendationCount,
  );
}

class AudioAnnouncementPreferencesStorage {
  static const _nameFormatKey = 'audio_announcement_name_format';
  static const _nicknameKey = 'audio_announcement_speak_nickname';
  static const _readAlternativesKey = 'audio_announcement_read_alternatives';
  static const _altCountKey = 'audio_announcement_alt_count';

  Future<AudioAnnouncementPreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedFormat = preferences.getString(_nameFormatKey);
    final altCount = preferences.getInt(_altCountKey) ?? 1;
    return AudioAnnouncementPreferences(
      nameFormat: AnnouncementNameFormat.values.firstWhere(
        (format) => format.name == storedFormat,
        orElse: () => AnnouncementNameFormat.fullName,
      ),
      speakNicknameWhenAvailable: preferences.getBool(_nicknameKey) ?? false,
      readAlternativeRecommendations:
          preferences.getBool(_readAlternativesKey) ?? false,
      alternativeRecommendationCount: altCount.clamp(1, 3),
    );
  }

  Future<void> save(AudioAnnouncementPreferences value) async {
    final preferences = await SharedPreferences.getInstance();
    final formatSaved = await preferences.setString(
      _nameFormatKey,
      value.nameFormat.name,
    );
    final nicknameSaved = await preferences.setBool(
      _nicknameKey,
      value.speakNicknameWhenAvailable,
    );
    final readAlternativesSaved = await preferences.setBool(
      _readAlternativesKey,
      value.readAlternativeRecommendations,
    );
    final altCountSaved = await preferences.setInt(
      _altCountKey,
      value.alternativeRecommendationCount.clamp(1, 3),
    );
    if (!formatSaved ||
        !nicknameSaved ||
        !readAlternativesSaved ||
        !altCountSaved) {
      throw StateError(
        'Ton-Modus-Einstellungen konnten nicht gespeichert werden.',
      );
    }
  }
}

String spokenMatchLabel(
  GroupMatch match,
  AudioAnnouncementPreferences preferences,
  Map<String, PlayerProfile> profiles,
) {
  String playerName(TournamentPlayer? player) {
    if (player == null) return 'Offen';
    if (player.isTeam) {
      return player.individuals
          .map((member) => playerName(member))
          .join(' und ');
    }
    final profile = player.profileId == null
        ? null
        : profiles[player.profileId];
    if (preferences.speakNicknameWhenAvailable &&
        profile?.nickname.trim().isNotEmpty == true) {
      return profile!.nickname.trim();
    }
    if (profile == null && player.isGenerated) return player.name;
    if (preferences.nameFormat == AnnouncementNameFormat.fullName) {
      return profile?.displayName ?? player.name;
    }
    final firstName = profile?.firstName.trim() ?? '';
    final lastName = profile?.lastName.trim() ?? '';
    if (firstName.isNotEmpty) {
      return lastName.isEmpty ? firstName : '$firstName ${lastName[0]}.';
    }
    final parts = player.name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return player.name;
    return '${parts.first} ${parts.last[0]}.';
  }

  return '${playerName(match.homePlayer)} gegen ${playerName(match.awayPlayer)}';
}
