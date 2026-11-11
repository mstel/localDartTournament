import 'package:flutter/material.dart';
import '../../../league/domain/league_match.dart';
import '../../domain/tournament_models.dart';
import '../../domain/tournament_winner.dart';
import '../../application/tournament_timing.dart';

class TournamentSummaryCard extends StatelessWidget {
  const TournamentSummaryCard({
    super.key,
    required this.tournament,
    required this.onOpen,
    required this.onDelete,
    this.onEditEndTime,
    this.onQuickEdit,
    this.onCopy,
    this.onConvert,
  });
  final CreatedTournament tournament;
  final VoidCallback onOpen, onDelete;
  final VoidCallback? onEditEndTime;
  final VoidCallback? onQuickEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onConvert;
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
    final league = tournament.leagueMatch;
    final typeLabel = league != null
        ? league.variant == LeagueMatchVariant.traditional
              ? 'Ligaspiel'
              : 'Angepasstes Freundschafts-/Ligaspiel'
        : tournament.countsForRanking && tournament.rankingIds.isNotEmpty
        ? 'Ranglistenturnier'
        : 'Normales Turnier';
    final winnerName = _winnerName(tournament, complete);
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
                        case 'quickEdit':
                          onQuickEdit?.call();
                          break;
                        case 'copy':
                          onCopy?.call();
                          break;
                        case 'endTime':
                          onEditEndTime?.call();
                          break;
                        case 'convert':
                          onConvert?.call();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      if (onQuickEdit != null)
                        const PopupMenuItem(
                          value: 'quickEdit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Schnell bearbeiten'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
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
                      if (complete && onEditEndTime != null)
                        const PopupMenuItem(
                          value: 'endTime',
                          child: ListTile(
                            leading: Icon(Icons.edit_calendar_outlined),
                            title: Text('Enddatum festlegen'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      if (onConvert != null)
                        const PopupMenuItem(
                          value: 'convert',
                          child: ListTile(
                            leading: Icon(Icons.transform_outlined),
                            title: Text('Zu Dart-Turnier konvertieren'),
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
                typeLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    Text(
                      _formatTournamentDate(
                        tournament.tournamentDate ?? tournament.createdAt,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                league != null
                    ? '${league.homePoints}:${league.awayPoints} Mannschaftspunkte'
                    : '${tournament.players.length} Teilnehmer · ${tournament.stages.length} Phasen',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (winnerName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Sieger: $winnerName',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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

  String _formatTournamentDate(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  String? _winnerName(CreatedTournament tournament, bool complete) {
    if (!complete) return null;
    final league = tournament.leagueMatch;
    if (league != null) {
      if (!league.complete || league.homePoints == league.awayPoints) {
        return null;
      }
      return league.homePoints > league.awayPoints
          ? league.homeTeam
          : league.awayTeam;
    }
    return TournamentWinner.name(tournament);
  }
}
