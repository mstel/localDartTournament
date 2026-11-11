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
          context: context,
          teamSide: 0,
          title: 'Heimteam · ${leagueMatch.homeTeam}',
          players: homePlayers,
          playerTileBuilder: playerTileBuilder,
        ),
        _teamSection(
          context: context,
          teamSide: 1,
          title: 'Gastteam · ${leagueMatch.awayTeam}',
          players: awayPlayers,
          playerTileBuilder: playerTileBuilder,
        ),
      ],
    );
  }

  Widget _teamSection({
    required BuildContext context,
    required int teamSide,
    required String title,
    required List<TournamentPlayer> players,
    required Widget Function(TournamentPlayer player) playerTileBuilder,
  }) {
    final active = leagueMatch.activePlayers(teamSide).toSet();
    final substitutions = leagueMatch.substitutions
        .where((event) => event.teamSide == teamSide)
        .toList();
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.people_alt_outlined),
        title: Text(title),
        subtitle: Text('${players.length} Teilnehmer'),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (var index = 0; index < players.length; index++) ...[
            playerTileBuilder(players[index]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(left: 72, bottom: 8),
                child: _playerStatus(context, index, active, substitutions),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _playerStatus(
    BuildContext context,
    int playerIndex,
    Set<int> active,
    List<LeagueSubstitution> substitutions,
  ) {
    final wasSubstitutedOut = substitutions.any(
      (event) => event.outPlayerIndex == playerIndex,
    );
    final status = active.contains(playerIndex)
        ? 'Aktiv'
        : wasSubstitutedOut
        ? 'Ausgewechselt'
        : 'Ersatzspieler';
    final Color color;
    if (status == 'Ersatzspieler') {
      color = Colors.orange.shade800;
    } else if (status == 'Ausgewechselt') {
      color = leagueMatch.allowReentry
          ? Theme.of(context).colorScheme.onSurface
          : Theme.of(context).colorScheme.error;
    } else {
      color = Theme.of(context).colorScheme.primary;
    }
    if (status == 'Ausgewechselt' && leagueMatch.allowReentry) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(status, style: const TextStyle(color: Colors.white)),
        ),
      );
    }
    return Text(status, style: TextStyle(color: color));
  }
}
