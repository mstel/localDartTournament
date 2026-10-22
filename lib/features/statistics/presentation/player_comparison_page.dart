import 'package:flutter/material.dart';

import '../../../shared/widgets/adaptive_content.dart';
import '../../rankings/application/local_ranking_elo_service.dart';
import '../../rankings/domain/local_elo_calculator.dart';
import '../../rankings/domain/local_ranking.dart';
import '../../tournaments/data/app_database.dart';
import '../../tournaments/data/tournament_storage.dart';
import '../domain/best_performance.dart';
import '../domain/local_statistics.dart';

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
                  final rows = _comparisonRows(
                    leftStats: leftStats,
                    rightStats: rightStats,
                    leftId: left.id,
                    rightId: right.id,
                    elo: elo,
                    ranking: ranking,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Spielervergleich${ranking == null ? '' : ' · ${ranking.name}'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            DataColumn(
                              label: Text(
                                left.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const DataColumn(
                              label: Text(
                                'Kategorie',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                right.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          rows: [
                            for (final row in rows)
                              DataRow(
                                cells: [
                                  DataCell(Text(row.left)),
                                  DataCell(Text(row.category)),
                                  DataCell(Text(row.right)),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (elo == null && eloRankings.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Für den Elo-Verlauf muss eine Elo-Rangliste angelegt sein.',
                          ),
                        ),
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

  List<({String category, String left, String right})> _comparisonRows({
    required LocalPlayerStatistics leftStats,
    required LocalPlayerStatistics rightStats,
    required String leftId,
    required String rightId,
    required LocalEloSnapshot? elo,
    required LocalRanking? ranking,
  }) {
    String percent(double value) => '${value.toStringAsFixed(1)} %';
    final rows = <({String category, String left, String right})>[
      (category: 'Elo aktuell', left: '', right: ''),
      (
        category: 'Spiele',
        left: '${leftStats.matches}',
        right: '${rightStats.matches}',
      ),
      (
        category: 'Siege',
        left: '${leftStats.wins}',
        right: '${rightStats.wins}',
      ),
      (
        category: 'Niederlagen',
        left: '${leftStats.losses}',
        right: '${rightStats.losses}',
      ),
      (
        category: 'Unentschieden',
        left: '${leftStats.draws}',
        right: '${rightStats.draws}',
      ),
      (
        category: 'Siegquote',
        left: percent(leftStats.matchWinRate),
        right: percent(rightStats.matchWinRate),
      ),
      (
        category: 'Turniere',
        left: '${leftStats.tournaments}',
        right: '${rightStats.tournaments}',
      ),
      (
        category: 'Turniersiege',
        left: '${leftStats.tournamentWins}',
        right: '${rightStats.tournamentWins}',
      ),
      (
        category: 'Legs gewonnen / verloren',
        left: '${leftStats.legsWon} / ${leftStats.legsLost}',
        right: '${rightStats.legsWon} / ${rightStats.legsLost}',
      ),
      (
        category: 'Legquote',
        left: percent(leftStats.legWinRate),
        right: percent(rightStats.legWinRate),
      ),
      (
        category: 'Sets gewonnen / verloren',
        left: '${leftStats.setsWon} / ${leftStats.setsLost}',
        right: '${rightStats.setsWon} / ${rightStats.setsLost}',
      ),
      for (final type in BestPerformanceType.values)
        (
          category: _performanceCategory(type),
          left:
              '${leftStats.bestPerformances.where((item) => item.type == type).length}',
          right:
              '${rightStats.bestPerformances.where((item) => item.type == type).length}',
        ),
    ];
    if (ranking == null) {
      rows[0] = (category: 'Elo aktuell', left: '–', right: '–');
      return rows;
    }

    final entries = {
      for (final player in elo?.entries ?? const <LocalEloPlayer>[])
        player.id: player.rating,
    };
    rows[0] = (
      category: 'Elo aktuell · ${ranking.name}',
      left: '${entries[leftId] ?? ranking.startRating}',
      right: '${entries[rightId] ?? ranking.startRating}',
    );

    final leftHistory = elo?.history[leftId] ?? const [];
    final rightHistory = elo?.history[rightId] ?? const [];
    final historyByKey = <String, Map<String, LocalEloHistoryItem>>{};
    for (final (playerId, history) in [
      (leftId, leftHistory),
      (rightId, rightHistory),
    ]) {
      for (final item in history) {
        final key = '${item.tournamentId}:${item.matchIndex}';
        historyByKey.putIfAbsent(key, () => {})[playerId] = item;
      }
    }
    final eventKeys = historyByKey.keys.toList()
      ..sort((left, right) {
        final leftItem = historyByKey[left]!.values.first;
        final rightItem = historyByKey[right]!.values.first;
        final date = leftItem.playedAt.compareTo(rightItem.playedAt);
        return date == 0 ? left.compareTo(right) : date;
      });
    for (final key in eventKeys) {
      final event = historyByKey[key]!;
      final item = event.values.first;
      final date =
          '${item.playedAt.day.toString().padLeft(2, '0')}.'
          '${item.playedAt.month.toString().padLeft(2, '0')}.'
          '${item.playedAt.year}';
      rows.add((
        category: 'Elo-Verlauf · ${item.tournamentName} · $date',
        left: event[leftId] == null ? '–' : '${event[leftId]!.ratingAfter}',
        right: event[rightId] == null ? '–' : '${event[rightId]!.ratingAfter}',
      ));
    }
    return rows;
  }

  String _performanceCategory(BestPerformanceType type) => switch (type) {
    BestPerformanceType.score170 => '170+ Aufnahmen',
    BestPerformanceType.score180 => '180er',
    BestPerformanceType.highFinish => 'High Finishes',
    BestPerformanceType.shortLeg => 'Shortlegs',
  };
}
