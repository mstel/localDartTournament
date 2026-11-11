import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../../../shared/widgets/sport_metric_grid.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../tournaments/application/tournament_timing.dart';
import '../domain/tournament_player_statistics.dart';
import 'widgets/tournament_player_summary_card.dart';

/// Rebuilt from current results so edits and removed results are reflected.
class LiveTournamentStatisticsSection extends StatefulWidget {
  const LiveTournamentStatisticsSection({super.key, required this.tournament});
  final CreatedTournament tournament;
  @override
  State<LiveTournamentStatisticsSection> createState() =>
      _LiveTournamentStatisticsSectionState();
}

class _LiveTournamentStatisticsSectionState
    extends State<LiveTournamentStatisticsSection>
    with AutomaticKeepAliveClientMixin {
  int _sort = 0;
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = const TournamentStatisticsCalculator().calculate([
      widget.tournament,
    ]);
    final completedMatches = TournamentTiming.matches(
      widget.tournament,
    ).where((match) => match.hasResult).length;
    final visible =
        rows.where((r) => r.name.toLowerCase().contains(_query)).toList()
          ..sort((a, b) {
            final order = switch (_sort) {
              1 => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              _ => b.wins.compareTo(a.wins),
            };
            return order != 0 ? order : a.name.compareTo(b.name);
          });
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Turnierstatistik',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text('Aktueller Stand über alle Phasen'),
            const SizedBox(height: 16),
            SportMetricGrid(
              metrics: [
                SportMetric(
                  'Begegnungen',
                  '$completedMatches',
                  Icons.check_circle_outline,
                ),
                SportMetric(
                  'Teilnehmer',
                  '${rows.length}',
                  Icons.groups_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 16),
            ...[
              if (rows.isEmpty)
                const Text(
                  'Noch keine abgeschlossenen Begegnungen mit menschlichen Teilnehmern.',
                )
              else ...[
                AdaptiveTileLayout(
                  minTileWidth: 360,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        labelText: 'Teilnehmer suchen',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey(_sort),
                      initialValue: _sort,
                      isExpanded: true,
                      itemHeight: null,
                      decoration: const InputDecoration(
                        labelText: 'Sortierung',
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Siege')),
                        DropdownMenuItem(value: 1, child: Text('Name')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _sort = value);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty) const Text('Keine passenden Teilnehmer.'),
                AdaptiveTileLayout(
                  minTileWidth: 360,
                  children: [
                    for (final row in visible)
                      TournamentPlayerSummaryCard(row: row),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 16),
            const Text(
              'Die Übersicht basiert auf gespeicherten Turnierergebnissen.',
            ),
          ],
        ),
      ),
    );
  }
}
