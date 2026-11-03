import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CreatedTournament tournament({bool? showNotifications}) => CreatedTournament(
    name: 'Testturnier',
    players: const [],
    stages: const [],
    runStages: const [],
    showAchievementNotifications: showNotifications ?? true,
  );

  test(
    'achievement notifications default to enabled for old tournament data',
    () {
      final oldData = tournament().toJson()
        ..remove('showAchievementNotifications');
      final restored = CreatedTournament.fromJson(oldData);

      expect(restored.showAchievementNotifications, isTrue);
    },
  );

  test('achievement notification setting is persisted', () {
    final original = tournament(showNotifications: false);
    final restored = CreatedTournament.fromJson(original.toJson());

    expect(restored.showAchievementNotifications, isFalse);
  });

  test('achievement notices on matches survive tournament serialization', () {
    final original = CreatedTournament(
      name: 'Testturnier',
      players: const [],
      stages: const [],
      runStages: [
        GroupTournamentRunStage(
          name: 'Gruppenphase',
          groupPlayType: 'round_robin',
          groups: [
            TournamentGroup(
              name: 'Gruppe A',
              playType: 'round_robin',
              players: const [],
              matches: [
                GroupMatch(
                  round: 1,
                  achievementNotifications: const [
                    TournamentAchievementNotice(
                      playerProfileId: 'player-1',
                      playerName: 'Alex',
                      achievementName: 'Maximum',
                      explanation: 'Du hast eine 180 geworfen.',
                      rankingName: 'Saison 2026',
                    ),
                  ],
                ),
              ],
            ),
          ],
          qualificationPlan: null,
          tieBreakers: const [],
        ),
      ],
    );
    final restored = CreatedTournament.fromJson(original.toJson());
    final match = (restored.runStages.single as GroupTournamentRunStage)
        .groups
        .single
        .matches
        .single;

    expect(match.achievementNotifications.single.achievementName, 'Maximum');
    expect(
      match.achievementNotifications.single.explanation,
      'Du hast eine 180 geworfen.',
    );
  });

  test('matches can collect achievement notices at runtime', () {
    final match = GroupMatch(round: 1);
    match.achievementNotifications.add(
      const TournamentAchievementNotice(
        playerProfileId: 'player-1',
        playerName: 'Alex',
        achievementName: 'Maximum',
        explanation: 'Du hast eine 180 geworfen.',
        rankingName: 'Saison 2026',
      ),
    );

    expect(match.achievementNotifications, hasLength(1));
  });
}
