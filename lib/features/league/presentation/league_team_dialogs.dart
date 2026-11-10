import 'package:flutter/material.dart';

import '../domain/league_match.dart';

String leaguePlayerStatus(LeagueMatch league, int teamSide, int playerIndex) {
  if (league.activePlayers(teamSide).contains(playerIndex)) return 'Aktiv';
  if (league.substitutions.any(
    (event) =>
        event.teamSide == teamSide && event.outPlayerIndex == playerIndex,
  )) {
    return 'Ausgewechselt';
  }
  return 'Ersatzspieler';
}

Color leaguePlayerStatusColor(
  BuildContext context,
  LeagueMatch league,
  String status,
) {
  if (status == 'Aktiv') return Theme.of(context).colorScheme.primary;
  if (status == 'Ersatzspieler') return Colors.orange.shade800;
  return league.allowReentry
      ? Theme.of(context).colorScheme.onSurface
      : Theme.of(context).colorScheme.error;
}

class LeagueRosterDialog extends StatelessWidget {
  const LeagueRosterDialog({
    super.key,
    required this.league,
    required this.teamSide,
  });

  final LeagueMatch league;
  final int teamSide;

  @override
  Widget build(BuildContext context) {
    final roster = teamSide == 0 ? league.homePlayers : league.awayPlayers;
    final teamName = teamSide == 0 ? league.homeTeam : league.awayTeam;
    return AlertDialog(
      title: Text('Spielerstatus · $teamName'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < roster.length; index++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(roster[index]),
                  trailing: Text(
                    leaguePlayerStatus(league, teamSide, index),
                    style: TextStyle(
                      color: leaguePlayerStatusColor(
                        context,
                        league,
                        leaguePlayerStatus(league, teamSide, index),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

class LeagueTeamPairingsDialog extends StatefulWidget {
  const LeagueTeamPairingsDialog({
    super.key,
    required this.league,
    required this.teamSide,
  });

  final LeagueMatch league;
  final int teamSide;

  @override
  State<LeagueTeamPairingsDialog> createState() =>
      _LeagueTeamPairingsDialogState();
}

class _LeagueTeamPairingsDialogState extends State<LeagueTeamPairingsDialog> {
  late final _pairings = <int, List<int>>{
    for (var index = 0; index < widget.league.games.length; index++)
      if (_isEditableDouble(index)) index: List<int>.from(_playersFor(index)),
  };
  String? _error;

  bool _isEditableDouble(int index) {
    final game = widget.league.games[index];
    return game.isDouble &&
        !game.complete &&
        game.runtime?['startedAt'] == null;
  }

  List<int> _playersFor(int index) => widget.teamSide == 0
      ? widget.league.games[index].home
      : widget.league.games[index].away;

  List<String> get _roster => widget.teamSide == 0
      ? widget.league.homePlayers
      : widget.league.awayPlayers;

  @override
  Widget build(BuildContext context) {
    final teamName = widget.teamSide == 0
        ? widget.league.homeTeam
        : widget.league.awayTeam;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      title: Text('Doppelpartner zuweisen · $teamName'),
      content: SizedBox(
        width: width > 900 ? 680 : width * 0.9,
        child: SingleChildScrollView(
          child: _pairings.isEmpty
              ? const Text('Es gibt keine offenen Doppelbegegnungen.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in _pairings.entries)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Doppel · Spiel ${entry.key + 1}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              for (var slot = 0; slot < 2; slot++)
                                DropdownButtonFormField<int>(
                                  key: ValueKey(
                                    'league-pairing-${widget.teamSide}-${entry.key}-$slot',
                                  ),
                                  initialValue: entry.value[slot],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Spieler ${slot + 1}',
                                  ),
                                  items: [
                                    for (
                                      var player = 0;
                                      player < _roster.length;
                                      player++
                                    )
                                      DropdownMenuItem(
                                        value: player,
                                        child: Text(
                                          '${_roster[player]} · ${leaguePlayerStatus(widget.league, widget.teamSide, player)}',
                                        ),
                                      ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      entry.value[slot] = value;
                                      _error = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _pairings.isEmpty
              ? null
              : () {
                  if (_pairings.values.any(
                    (players) => players.toSet().length != players.length,
                  )) {
                    setState(
                      () => _error =
                          'Für jedes Doppel zwei unterschiedliche Spieler wählen.',
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    for (final entry in _pairings.entries)
                      entry.key: List<int>.from(entry.value),
                  });
                },
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}
