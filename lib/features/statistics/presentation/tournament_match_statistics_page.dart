import 'package:flutter/material.dart';
import '../../../shared/widgets/adaptive_content.dart';
import '../domain/best_performance.dart';
import '../../tournaments/domain/tournament_models.dart';
import '../../rankings/application/tournament_match_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';

/// Read-only details derived from the statistics saved with this match.
class TournamentMatchStatisticsPage extends StatefulWidget {
  const TournamentMatchStatisticsPage({
    super.key,
    required this.match,
    this.tournament,
  });
  final GroupMatch match;
  final CreatedTournament? tournament;

  @override
  State<TournamentMatchStatisticsPage> createState() =>
      _TournamentMatchStatisticsPageState();
}

class _TournamentMatchStatisticsPageState
    extends State<TournamentMatchStatisticsPage> {
  late final Future<List<TournamentMatchEloChange>>? _eloChanges =
      _loadEloChanges();

  Future<List<TournamentMatchEloChange>>? _loadEloChanges() {
    final tournament = widget.tournament;
    if (tournament == null ||
        !tournament.countsForRanking ||
        tournament.rankingIds.isEmpty) {
      return null;
    }
    return TournamentMatchEloService().calculate(tournament).then((changes) {
      final key = const LocalEloCalculator().matchKey(tournament, widget.match);
      return key == null ? const [] : changes[key] ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final sides = [match.homePlayer, match.awayPlayer];
    final duration = match.startedAt != null && match.finishedAt != null
        ? match.finishedAt!.difference(match.startedAt!)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Spielstatistik')),
      body: AdaptiveContentList(
        children: [
          Text(
            '${sides[0]?.name ?? 'Offen'} gegen ${sides[1]?.name ?? 'Offen'}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Ergebnis: ${match.homeScore}:${match.awayScore}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (match.homeSets != null)
            Text('Legs: ${match.homeLegs}:${match.awayLegs}'),
          if (duration != null && !duration.isNegative)
            Text(
              'Spieldauer: ${duration.inMinutes} min ${duration.inSeconds % 60} s',
            ),
          if (_eloChanges != null)
            FutureBuilder<List<TournamentMatchEloChange>>(
              future: _eloChanges,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Ranglistenänderungen konnten nicht geladen werden.',
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'Elo-Änderungen',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final change in snapshot.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(change.rankingName),
                        subtitle: Text(
                          '${sides[0]?.name ?? 'Offen'}: ${_formatDelta(change.homeDelta)} · '
                          '${sides[1]?.name ?? 'Offen'}: ${_formatDelta(change.awayDelta)}',
                        ),
                      ),
                  ],
                );
              },
            ),
          if (match.bestPerformances.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Bestleistungen',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final performance in match.bestPerformances)
              Card(
                child: ListTile(
                  leading: Icon(switch (performance.type) {
                    BestPerformanceType.bigFish170 ||
                    BestPerformanceType.score171Plus ||
                    BestPerformanceType.score170 ||
                    BestPerformanceType.score180 => Icons.bolt,
                    BestPerformanceType.highFinish => Icons.flag_outlined,
                    BestPerformanceType.bullseyeFinish => Icons.gps_fixed,
                    BestPerformanceType.shortLeg => Icons.timer_outlined,
                  }),
                  title: Text(
                    '${performance.playerName} · ${performance.label}',
                  ),
                  trailing: performance.value == null
                      ? (performance.details == null
                            ? null
                            : Text(performance.details!))
                      : Text('${performance.value}'),
                ),
              ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDelta(int? delta) {
    if (delta == null) return 'nicht berücksichtigt';
    return delta > 0 ? '+$delta Elo' : '$delta Elo';
  }
}

class MatchStatisticsTapTarget extends StatelessWidget {
  const MatchStatisticsTapTarget({
    super.key,
    required this.match,
    required this.child,
    this.tournament,
  });
  final GroupMatch match;
  final Widget child;
  final CreatedTournament? tournament;
  static void open(
    BuildContext context,
    GroupMatch match, {
    CreatedTournament? tournament,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          TournamentMatchStatisticsPage(match: match, tournament: tournament),
    ),
  );
  @override
  Widget build(BuildContext context) =>
      !match.hasResult || !match.hasPlayers || match.isAnnulled
      ? child
      : Tooltip(
          message: 'Spielstatistik öffnen',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => open(context, match, tournament: tournament),
              child: child,
            ),
          ),
        );
}
