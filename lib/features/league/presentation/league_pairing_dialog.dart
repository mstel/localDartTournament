import 'package:flutter/material.dart';
import '../domain/league_match.dart';

class LeaguePairingDialog extends StatefulWidget {
  const LeaguePairingDialog({
    super.key,
    required this.league,
    required this.index,
  });
  final LeagueMatch league;
  final int index;
  @override
  State<LeaguePairingDialog> createState() => _LeaguePairingDialogState();
}

class _LeaguePairingDialogState extends State<LeaguePairingDialog> {
  late final _home = [...widget.league.games[widget.index].home];
  late final _away = [...widget.league.games[widget.index].away];
  String? _error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Aufstellung bearbeiten'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final side in [0, 1])
              for (var slot = 0; slot < _home.length; slot++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    initialValue: (side == 0 ? _home : _away)[slot],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '${side == 0 ? 'Heim' : 'Gast'} ${slot + 1}',
                    ),
                    items: [
                      for (
                        var p = 0;
                        p <
                            (side == 0
                                    ? widget.league.homePlayers
                                    : widget.league.awayPlayers)
                                .length;
                        p++
                      )
                        DropdownMenuItem(
                          value: p,
                          child: Text(
                            (side == 0
                                ? widget.league.homePlayers
                                : widget.league.awayPlayers)[p],
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        (side == 0 ? _home : _away)[slot] = value;
                      }
                    },
                  ),
                ),
            if (_error != null) Text(_error!),
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
        onPressed: () {
          if (_home.toSet().length != _home.length ||
              _away.toSet().length != _away.length) {
            setState(
              () =>
                  _error = 'Im Doppel zwei unterschiedliche Teilnehmer wählen.',
            );
            return;
          }
          widget.league.games[widget.index].home = _home;
          widget.league.games[widget.index].away = _away;
          Navigator.pop(context, true);
        },
        child: const Text('Übernehmen'),
      ),
    ],
  );
}
