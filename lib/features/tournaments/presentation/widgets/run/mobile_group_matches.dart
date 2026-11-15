import 'round_match_list.dart';
import 'package:flutter/material.dart';
import '../../../domain/tournament_models.dart';
import 'result_entry.dart';

/// The mobile group view puts playable matches ahead of optional detail tables.
class MobileGroupMatches extends StatelessWidget {
  const MobileGroupMatches({
    super.key,
    required this.group,
    this.matches,
    required this.table,
    required this.onEditResult,
    required this.canEditResults,
  });
  final TournamentGroup group;
  final List<GroupMatch>? matches;
  final Widget table;
  final void Function(GroupMatch) onEditResult;
  final bool canEditResults;

  @override
  Widget build(BuildContext context) {
    final orderedMatches = matches ?? group.matches;
    final pending = orderedMatches.where((match) => !match.isResolved).toList();
    final finished = orderedMatches.where((match) => match.isResolved).toList();
    final swiss = group.playType == 'swiss';
    final playedCount = finished.where((m) => m.hasPlayers).length;
    final openCount = swiss
        ? (group.players.length ~/ 2) *
                  group.matches.map((m) => m.round).toSet().length -
              playedCount
        : pending.length;
    Widget tile(GroupMatch match) => MatchResultTile(
      match: match,
      onEditResult: onEditResult,
      canEditResult: canEditResults,
      leadingLabel: match.isDecider ? match.label : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(group.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '$openCount offen · ${swiss ? playedCount : finished.length} abgeschlossen${swiss ? ' · ${finished.where((m) => !m.hasPlayers).length} Freilose' : ''}',
        ),
        const SizedBox(height: 12),
        if (pending.isNotEmpty) ...[
          Text(
            'Offene Begegnungen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RoundMatchList(
            key: ValueKey(group),
            rounds: [
              for (final round
                  in (orderedMatches.map((m) => m.round).toSet().toList()
                    ..sort()))
                orderedMatches.where((m) => m.round == round).toList(),
            ],
            labels: [
              for (final round
                  in (orderedMatches.map((m) => m.round).toSet().toList()
                    ..sort()))
                'Runde $round',
            ],
            openOnly: true,
            onEditResult: onEditResult,
            canEditResults: canEditResults,
          ),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Alle Begegnungen dieser Gruppe sind abgeschlossen.'),
          ),
        Card(
          child: ExpansionTile(
            key: PageStorageKey('table-${group.name}'),
            maintainState: true,
            title: const Text('Tabelle & Weiterkommen'),
            leading: const Icon(Icons.leaderboard_outlined),
            childrenPadding: const EdgeInsets.all(12),
            children: [
              const Text(
                'Für weitere Spalten die Tabelle seitlich verschieben.',
              ),
              const SizedBox(height: 8),
              table,
            ],
          ),
        ),
        if (finished.isNotEmpty)
          Card(
            child: ExpansionTile(
              key: PageStorageKey('finished-${group.name}'),
              maintainState: true,
              title: Text('Abgeschlossene Begegnungen (${finished.length})'),
              leading: const Icon(Icons.check_circle_outline),
              childrenPadding: const EdgeInsets.all(12),
              children: [for (final match in finished) tile(match)],
            ),
          ),
      ],
    );
  }
}
