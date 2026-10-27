import 'package:flutter/material.dart';
import '../../domain/tournament_models.dart';
import '../../application/tournament_timing.dart';

class TournamentSummaryCard extends StatelessWidget {
  const TournamentSummaryCard({
    super.key,
    required this.tournament,
    required this.onOpen,
    required this.onDelete,
    this.onCopy,
  });
  final CreatedTournament tournament;
  final VoidCallback onOpen, onDelete;
  final VoidCallback? onCopy;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = tournament.runStages.length - 1;
    final complete =
        tournament.finishedAt != null ||
        (last >= 0 && tournament.completedStageIndexes.contains(last));
    final status = complete
        ? 'Abgeschlossen'
        : tournament.startedAt != null
        ? 'Läuft'
        : 'Bereit';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      tournament.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Turnieraktionen',
                    onSelected: (action) {
                      switch (action) {
                        case 'copy':
                          onCopy?.call();
                        case 'delete':
                          onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      if (onCopy != null)
                        const PopupMenuItem(
                          value: 'copy',
                          child: ListTile(
                            leading: Icon(Icons.copy_outlined),
                            title: Text('Turnier kopieren'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Turnier löschen'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                tournament.leagueMatch != null
                    ? 'Ligaspiel · ${tournament.leagueMatch!.homePoints}:${tournament.leagueMatch!.awayPoints} Mannschaftspunkte'
                    : '${tournament.players.length} Spieler · ${tournament.stages.length} Etappen',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (tournament.importedArchive == null) ...[
                Builder(
                  builder: (context) {
                    final summary = TournamentTiming.durationSummary(
                      tournament,
                    );
                    if (summary == null || summary.playedMatches == 0) {
                      return const SizedBox.shrink();
                    }
                    String formatDuration(Duration d) {
                      if (d.inHours > 0) {
                        return '${d.inHours}h ${d.inMinutes % 60}m';
                      }
                      return '${d.inMinutes}m';
                    }

                    final matchLabel = summary.playedMatches == 1
                        ? 'Match'
                        : 'Matches';
                    final averageLabel = summary.averageMatchDuration == null
                        ? ''
                        : ' · Ø ${formatDuration(summary.averageMatchDuration!)}';

                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${formatDuration(summary.totalDuration)} · ${summary.playedMatches} $matchLabel$averageLabel',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$status · ${complete ? 'Ergebnisse ansehen' : 'Turnier öffnen'}',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
