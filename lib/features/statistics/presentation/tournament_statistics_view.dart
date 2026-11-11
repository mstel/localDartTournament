import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../domain/tournament_player_statistics.dart';

class TournamentStatisticsView extends StatelessWidget {
  const TournamentStatisticsView({
    super.key,
    required this.rows,
    this.title = 'Teilnehmerstatistiken',
    this.description =
        'Aus lokal gespeicherten Turnier- und Teilnehmerergebnissen.',
  });
  final List<TournamentPlayerStatistics> rows;
  final String description;
  final String title;
  @override
  Widget build(BuildContext context) => AdaptiveContentList(
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      Text(description),
      const SizedBox(height: 16),
      if (rows.isEmpty)
        const Text('Noch keine abgeschlossenen Begegnungen gespeichert.'),
      for (final row in rows) TournamentStatisticsCard(row: row),
    ],
  );
}

class TournamentStatisticsCard extends StatelessWidget {
  const TournamentStatisticsCard({
    super.key,
    required this.row,
    this.playerName,
  });
  final TournamentPlayerStatistics row;
  final String? playerName;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            playerName ?? row.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '${row.tournaments.length} Turniere · ${row.matches} Begegnungen',
          ),
          Text(
            '${row.wins} Siege · ${row.draws} Unentschieden · ${row.losses} Niederlagen',
          ),
          Text(
            'Gewonnene / verlorene Legs: ${row.legsFor} / ${row.legsAgainst}',
          ),
        ],
      ),
    ),
  );
}
