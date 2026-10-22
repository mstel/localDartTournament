import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../domain/local_statistics.dart';
import 'widgets/player_elo_comparison_chart.dart';

class PlayerComparisonPage extends StatefulWidget {
  const PlayerComparisonPage({
    super.key,
    LocalAppDatabase? database,
    TournamentStorage? tournamentStorage,
  }) : _database = database,
       _tournamentStorage = tournamentStorage;

  final LocalAppDatabase? _database;
  final TournamentStorage? _tournamentStorage;

  @override
  State<PlayerComparisonPage> createState() => _PlayerComparisonPageState();
}

class _PlayerComparisonPageState extends State<PlayerComparisonPage> {
  late final LocalAppDatabase _database =
      widget._database ?? LocalAppDatabase();
  late final TournamentStorage _tournamentStorage =
      widget._tournamentStorage ?? TournamentStorage();
  late final Future<(List<PlayerProfile>, List<LocalRanking>)> _options =
      _loadOptions();
  String? _leftId;
  String? _rightId;
  String? _rankingId;
  Future<(LocalPlayerStatistics, LocalPlayerStatistics, LocalEloSnapshot?)>?
  _comparison;

  Future<(LocalPlayerStatistics, LocalPlayerStatistics, LocalEloSnapshot?)>
  _loadComparison(String leftId, String rightId, LocalRanking? ranking) async {
    final statsService = LocalStatisticsService(
      database: _database,
      storage: _tournamentStorage,
    );
    final leftStats = await statsService.forPlayers({leftId});
    final rightStats = await statsService.forPlayers({rightId});
    final snapshot = ranking == null
        ? null
        : await LocalRankingEloService(
            database: _database,
            tournamentStorage: _tournamentStorage,
          ).calculate(ranking);
    return (leftStats, rightStats, snapshot);
  }

  Future<(List<PlayerProfile>, List<LocalRanking>)> _loadOptions() async {
    final players = await _database.loadPlayerProfiles();
    final rankings = await _database.loadLocalRankings();
    return (players, rankings);
  }

  void _updateSelection({
    required String leftId,
    required String rightId,
    required LocalRanking? ranking,
  }) {
    setState(() {
      _leftId = leftId;
      _rightId = rightId;
      _rankingId = ranking?.id;
      _comparison = _loadComparison(leftId, rightId, ranking);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spieler vergleichen')),
    body: FutureBuilder<(List<PlayerProfile>, List<LocalRanking>)>(
      future: _options,
      builder: (context, optionsSnapshot) {
        if (optionsSnapshot.hasError) {
          return const Center(
            child: Text('Spieler und Ranglisten konnten nicht geladen werden.'),
          );
        }
        final options = optionsSnapshot.data;
        if (options == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final (players, rankings) = options;
        if (players.length < 2) {
          return const AdaptiveContentList(
            children: [
              Text('Zum Vergleichen werden mindestens zwei Spieler benötigt.'),
            ],
          );
        }
        final leftId = players.any((player) => player.id == _leftId)
            ? _leftId!
            : players.first.id;
        final rightId = players.any((player) => player.id == _rightId)
            ? _rightId!
            : players.firstWhere((player) => player.id != leftId).id;
        final eloRankings = rankings
            .where((ranking) => ranking.type == RankingType.elo)
            .toList();
        final ranking = eloRankings.isEmpty
            ? null
            : eloRankings.firstWhere(
                (item) => item.id == _rankingId,
                orElse: () => eloRankings.first,
              );
        if (_comparison == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _comparison == null) {
              _updateSelection(
                leftId: leftId,
                rightId: rightId,
                ranking: ranking,
              );
            }
          });
        }
        final left = players.firstWhere((player) => player.id == leftId);
        final right = players.firstWhere((player) => player.id == rightId);
        return AdaptiveContentList(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final selectors = [
                  _playerSelector(
                    label: 'Links',
                    value: leftId,
                    excludedPlayerId: rightId,
                    players: players,
                    onChanged: (value) => _updateSelection(
                      leftId: value,
                      rightId: rightId,
                      ranking: ranking,
                    ),
                  ),
                  _playerSelector(
                    label: 'Rechts',
                    value: rightId,
                    excludedPlayerId: leftId,
                    players: players,
                    onChanged: (value) => _updateSelection(
                      leftId: leftId,
                      rightId: value,
                      ranking: ranking,
                    ),
                  ),
                ];
                return wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: selectors[0]),
                          const SizedBox(width: 16),
                          Expanded(child: selectors[1]),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          selectors[0],
                          const SizedBox(height: 12),
                          selectors[1],
                        ],
                      );
              },
            ),
            if (eloRankings.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: ranking?.id,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Elo-Rangliste für den Verlauf',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final item in eloRankings)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  final selected = eloRankings.firstWhere(
                    (item) => item.id == value,
                  );
                  _updateSelection(
                    leftId: leftId,
                    rightId: rightId,
                    ranking: selected,
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            if (_comparison case final future?)
              FutureBuilder<
                (
                  LocalPlayerStatistics,
                  LocalPlayerStatistics,
                  LocalEloSnapshot?,
                )
              >(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Der Spieler-Vergleich konnte nicht geladen werden.',
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final (leftStats, rightStats, elo) = data;
                  final colors = Theme.of(context).colorScheme;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _playerSummary(
                              left.displayName,
                              leftStats,
                              colors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _playerSummary(
                              right.displayName,
                              rightStats,
                              colors.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Elo-Entwicklung${ranking == null ? '' : ' · ${ranking.name}'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (elo == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Für den Verlauf muss eine Elo-Rangliste ausgewählt sein.',
                          ),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _legend(left.displayName, colors.primary),
                            _legend(right.displayName, colors.tertiary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        PlayerEloComparisonChart(
                          left: elo.history[left.id] ?? const [],
                          right: elo.history[right.id] ?? const [],
                          leftColor: colors.primary,
                          rightColor: colors.tertiary,
                          gridColor: colors.outlineVariant,
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        );
      },
    ),
  );

  Widget _playerSelector({
    required String label,
    required String value,
    required String excludedPlayerId,
    required List<PlayerProfile> players,
    required ValueChanged<String> onChanged,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('player-comparison-$label'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'Spieler $label',
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final player in players)
        if (player.id != excludedPlayerId)
          DropdownMenuItem(value: player.id, child: Text(player.displayName)),
    ],
    onChanged: (id) {
      if (id != null) onChanged(id);
    },
  );

  Widget _playerSummary(
    String name,
    LocalPlayerStatistics stats,
    Color accent,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('${stats.matches} Spiele · ${stats.wins} Siege'),
          Text('${stats.legWinRate.toStringAsFixed(1)} % Legquote'),
          Text('${stats.tournaments} Turniere · ${stats.tournamentWins} Siege'),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (stats.matchWinRate / 100).clamp(0.0, 1.0),
            color: accent,
            minHeight: 8,
          ),
        ],
      ),
    ),
  );

  Widget _legend(String name, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 18, height: 4, color: color),
      const SizedBox(width: 8),
      Text(name),
    ],
  );
}
