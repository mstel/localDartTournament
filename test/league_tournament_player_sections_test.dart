import 'package:dart_tournament_manager/features/league/domain/league_match.dart';
import 'package:dart_tournament_manager/features/league/presentation/league_tournament_player_sections.dart';
import 'package:dart_tournament_manager/features/tournaments/domain/tournament_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('separates same-named players by league team', (tester) async {
    const homePlayer = TournamentPlayer(
      profileId: 'home-marvin',
      name: 'Marvin',
      isGenerated: false,
    );
    const awayPlayer = TournamentPlayer(
      profileId: 'away-marvin',
      name: 'Marvin',
      isGenerated: false,
    );
    final league = LeagueMatch.adjusted(
      homeTeam: 'Heim',
      awayTeam: 'Gast',
      homePlayers: const ['Marvin'],
      awayPlayers: const ['Marvin'],
      singlesPerPlayer: 1,
      doublesCount: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LeagueTournamentPlayerSections(
            leagueMatch: league,
            players: const [homePlayer, awayPlayer],
            playerTileBuilder: (player) => ListTile(
              title: Text(player.name),
              subtitle: Text(player.profileId!),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Heimteam · Heim'), findsOneWidget);
    expect(find.text('Gastteam · Gast'), findsOneWidget);
    await tester.tap(find.text('Heimteam · Heim'));
    await tester.pumpAndSettle();
    expect(find.text('home-marvin'), findsOneWidget);
    expect(find.text('away-marvin'), findsNothing);

    await tester.tap(find.text('Gastteam · Gast'));
    await tester.pumpAndSettle();
    expect(find.text('home-marvin'), findsOneWidget);
    expect(find.text('away-marvin'), findsOneWidget);
  });
}
