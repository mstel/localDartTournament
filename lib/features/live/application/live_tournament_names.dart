import '../../tournaments/data/app_database.dart';
import '../../tournaments/domain/tournament_models.dart';

/// Spectator-facing names are always "Vorname Nachnameinitial.".
///
/// This intentionally ignores nicknames and the stored compactName, because
/// both may contain a nickname or a full last name.
String livePlayerName(
  TournamentPlayer? player, {
  Map<String, PlayerProfile> profiles = const {},
}) {
  if (player == null) return 'Offen';
  if (player.isTeam) {
    return player.individuals
        .map((member) => livePlayerName(member, profiles: profiles))
        .join(' & ');
  }

  final profile = player.profileId == null
      ? null
      : profiles[player.profileId];
  if (profile != null) {
    final firstName = profile.firstName.trim();
    final lastName = profile.lastName.trim();
    if (firstName.isEmpty) return lastName.isEmpty ? 'Spieler' : lastName;
    return lastName.isEmpty ? firstName : '$firstName ${lastName[0]}.';
  }

  // Generated placeholders have no real surname; keep the readable label.
  if (player.isGenerated) return player.name;

  final cleaned = player.name
      .trim()
      .replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '')
      .trim();
  final parts = cleaned.split(RegExp(r'\s+'));
  if (parts.length < 2) return cleaned;
  final firstName = parts.first;
  final lastName = parts.last;
  return lastName.isEmpty ? firstName : '$firstName ${lastName[0]}.';
}
