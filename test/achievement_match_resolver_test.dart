import 'package:dart_tournament_manager/features/achievements/application/achievement_match_resolver.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const player = TournamentPlayer(
    profileId: 'player-1',
    name: 'Spieler Eins',
    isGenerated: false,
  );
  const opponent = TournamentPlayer(
    profileId: 'player-2',
    name: 'Spieler Zwei',
    isGenerated: false,
  );
  const resolver = AchievementMatchResolver();

  test('a loss unlock is attached to the match that crossed the threshold', () {
    final loss = GroupMatch(
      homePlayer: player,
      awayPlayer: opponent,
      round: 1,
      homeLegs: 0,
      awayLegs: 3,
      finishedAt: DateTime(2026, 8, 1, 18),
    );
    final laterWin = GroupMatch(
      homePlayer: player,
      awayPlayer: opponent,
      round: 2,
      homeLegs: 3,
      awayLegs: 1,
      finishedAt: DateTime(2026, 8, 1, 19),
    );

    expect(
      resolver.resolve(
        playerProfileId: player.profileId!,
        unlockedAt: loss.finishedAt,
        matches: [laterWin, loss],
        tournamentDate: DateTime(2026, 8, 1),
      ),
      same(loss),
    );
  });

  test(
    'a prior tournament achievement can surface on the next event match',
    () {
      final firstMatch = GroupMatch(
        homePlayer: player,
        awayPlayer: opponent,
        round: 1,
        homeLegs: 3,
        awayLegs: 0,
        finishedAt: DateTime(2026, 8, 8, 18),
      );
      final unlockedAt = DateTime(2026, 8, 1, 20);

      expect(
        resolver.resolve(
          playerProfileId: player.profileId!,
          unlockedAt: unlockedAt,
          matches: [firstMatch],
          tournamentDate: DateTime(2026, 8, 8),
        ),
        same(firstMatch),
      );
    },
  );

  test('tournament-completion achievements attach to the latest match', () {
    final lastMatch = GroupMatch(
      homePlayer: player,
      awayPlayer: opponent,
      round: 3,
      homeLegs: 3,
      awayLegs: 2,
      finishedAt: DateTime(2026, 8, 1, 18),
    );

    expect(
      resolver.resolve(
        playerProfileId: player.profileId!,
        unlockedAt: DateTime(2026, 8, 1, 19),
        matches: [lastMatch],
        tournamentDate: DateTime(2026, 8, 1),
        tournamentFinishedAt: DateTime(2026, 8, 1, 19),
      ),
      same(lastMatch),
    );
  });
}
