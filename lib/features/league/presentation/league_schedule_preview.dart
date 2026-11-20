import 'package:flutter/material.dart';

/// Kompakte Vorschau des angepassten Ligaspielplans, bevor das Turnier
/// angelegt wird. Die Reihenfolge entspricht [LeagueMatch.adjusted].
class AdjustedLeagueSchedulePreview extends StatelessWidget {
  const AdjustedLeagueSchedulePreview({
    super.key,
    required this.homePlayers,
    required this.awayPlayers,
    required this.starterCount,
    required this.singlesPerPlayer,
    required this.doublesCount,
  });

  final List<String> homePlayers;
  final List<String> awayPlayers;
  final int starterCount;
  final int singlesPerPlayer;
  final int doublesCount;

  @override
  Widget build(BuildContext context) {
    final fixtures = _fixtures();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Spielplan-Vorschau',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (fixtures.isEmpty)
          const Text(
            'Noch keine Begegnungen. Bitte Stammspieler und Einzelanzahl prüfen.',
          )
        else
          for (final fixture in fixtures)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 28, child: Text('${fixture.number}.')),
                  Expanded(child: Text(fixture.label)),
                ],
              ),
            ),
      ],
    );
  }

  List<({int number, String label})> _fixtures() {
    final starters = starterCount < 0 ? 0 : starterCount;
    final rounds = singlesPerPlayer < 0 ? 0 : singlesPerPlayer;
    final doubles = doublesCount < 0 ? 0 : doublesCount;
    if (starters == 0) return const [];

    final fixtures = <({int number, String label})>[];
    var number = 0;

    for (var round = 0; round < rounds; round++) {
      for (var player = 0; player < starters; player++) {
        fixtures.add((
          number: ++number,
          label:
              'Runde ${round + 1} · ${_player(homePlayers, player)} gegen '
              '${_player(awayPlayers, (player + round) % starters)}',
        ));
      }
    }
    for (var pair = 0; pair < doubles; pair++) {
      final first = pair * 2;
      final second = first + 1;
      fixtures.add((
        number: ++number,
        label:
            'Doppel ${pair + 1} · ${_player(homePlayers, first)} / '
            '${_player(homePlayers, second)} gegen '
            '${_player(awayPlayers, first)} / ${_player(awayPlayers, second)}',
      ));
    }
    return fixtures;
  }

  String _player(List<String> roster, int index) {
    final name = index < roster.length ? roster[index].trim() : '';
    return name.isEmpty ? 'Platz ${index + 1}' : name;
  }
}
