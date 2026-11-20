import 'package:dart_tournament_manager/features/rankings/application/tournament_match_elo_service.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:dart_tournament_manager/features/tournaments/presentation/widgets/run/recent_match_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GroupMatch match() {
    final home = TournamentPlayer(
      profileId: 'home',
      name: 'Alex',
      isGenerated: false,
    );
    final away = TournamentPlayer(
      profileId: 'away',
      name: 'Ben',
      isGenerated: false,
    );
    return GroupMatch(
      homePlayer: home,
      awayPlayer: away,
      round: 1,
      homeLegs: 2,
      awayLegs: 0,
    );
  }

  CreatedTournament tournament() => CreatedTournament(
    name: 'Testturnier',
    players: const [],
    stages: const [],
    runStages: const [],
  );

  testWidgets(
    'shows the real projected delta and ratings for a hypothetical change',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentMatchResultLogEntry(
              tournament: tournament(),
              match: match(),
              eloChanges: const [
                TournamentMatchEloChange(
                  rankingName: 'Vereinsrangliste',
                  homeDelta: 13,
                  awayDelta: -13,
                  homeRatingBefore: 1000,
                  homeRatingAfter: 1013,
                  awayRatingBefore: 1000,
                  awayRatingAfter: 987,
                  homeHypothetical: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('+13 Elo (1000 → 1013) (hypothetisch)'), findsOneWidget);
      expect(find.text('-13 Elo (1000 → 987)'), findsOneWidget);
      expect(find.text('0 Elo (1000 → 1000)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing projections do not show a fabricated zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentMatchResultLogEntry(
            tournament: tournament(),
            match: match(),
            eloChanges: const [
              TournamentMatchEloChange(
                rankingName: 'Vereinsrangliste',
                homeDelta: null,
                awayDelta: null,
                homeHypothetical: true,
                awayHypothetical: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('0 Elo (1000 → 1000)'), findsNothing);
    expect(find.textContaining('(hypothetisch)'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
