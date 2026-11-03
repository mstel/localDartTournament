import 'package:flutter/material.dart';

import '../../tournaments/domain/tournament_models.dart';
import '../domain/league_match.dart';

class LeagueTournamentPlayerSections extends StatelessWidget {
  const LeagueTournamentPlayerSections({
    super.key,
    required this.leagueMatch,
    required this.players,
    required this.playerTileBuilder,
  });

  final LeagueMatch leagueMatch;
  final List<TournamentPlayer> players;
  final Widget Function(TournamentPlayer player) playerTileBuilder;

  @override
  Widget build(BuildContext context) {
    final homeCount = leagueMatch.homePlayers.length;
    final homePlayers = players.take(homeCount).toList();
    final awayPlayers = players
        .skip(homeCount)
        .take(leagueMatch.awayPlayers.length)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _teamSection(
          title: 'Heimteam · ${leagueMatch.homeTeam}',
          players: homePlayers,
          playerTileBuilder: playerTileBuilder,
        ),
        _teamSection(
          title: 'Gastteam · ${leagueMatch.awayTeam}',
          players: awayPlayers,
          playerTileBuilder: playerTileBuilder,
        ),
      ],
    );
  }

  Widget _teamSection({
    required String title,
    required List<TournamentPlayer> players,
    required Widget Function(TournamentPlayer player) playerTileBuilder,
  }) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.people_alt_outlined),
      title: Text(title),
      subtitle: Text('${players.length} Spieler'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [for (final player in players) playerTileBuilder(player)],
    ),
  );
}
