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
  late final Future<(List<PlayerProfile>, List<LocalRanking>, List<int>)>
  _options = _loadOptions();
  String? _leftId;
  String? _rightId;
  String? _rankingId = 'all';
  int? _selectedYear;
  Future<(LocalPlayerStatistics, LocalPlayerStatistics, LocalEloSnapshot?)>?
  _comparison;

  Future<(LocalPlayerStatistics, LocalPlayerStatistics, LocalEloSnapshot?)>
  _loadComparison(
    String leftId,
    String rightId,
    LocalRanking? ranking, {
    int? year,
  }) async {
    final statsService = LocalStatisticsService(
      database: _database,
      storage: _tournamentStorage,
    );
    final tournaments = await _tournamentStorage.loadTournaments();
    final filteredTournaments = tournaments.where((t) {
      if (ranking != null) {
        if (!t.countsForRanking || !t.rankingIds.contains(ranking.id)) {
          return false;
        }
      }
      if (year != null) {
        final date = (t.finishedAt ?? t.createdAt).toLocal();
        if (date.year != year) {
          return false;
        }
      }
      return true;
    }).toList();

    final leftStats = await statsService.forPlayersFromTournaments({
      leftId,
    }, filteredTournaments);
    final rightStats = await statsService.forPlayersFromTournaments({
      rightId,
    }, filteredTournaments);
    final snapshot = ranking == null
        ? null
        : await LocalRankingEloService(
            database: _database,
            tournamentStorage: _tournamentStorage,
          ).calculate(ranking, tournaments: filteredTournaments);
    return (leftStats, rightStats, snapshot);
  }

  Future<(List<PlayerProfile>, List<LocalRanking>, List<int>)>
  _loadOptions() async {
    final players = await _database.loadPlayerProfiles();
    final rankings = await _database.loadLocalRankings();
    final tournaments = await _tournamentStorage.loadTournaments();
    final years =
        tournaments
            .map((t) => (t.finishedAt ?? t.createdAt).toLocal().year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    return (players, rankings, years);
  }

  void _updateSelection({
    required String leftId,
    required String rightId,
    required LocalRanking? ranking,
    required int? year,
  }) {
    setState(() {
      _leftId = leftId;
      _rightId = rightId;
      _rankingId = ranking?.id ?? 'all';
      _selectedYear = year;
      _comparison = _loadComparison(leftId, rightId, ranking, year: year);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Spieler vergleichen')),
    body: FutureBuilder<(List<PlayerProfile>, List<LocalRanking>, List<int>)>(
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
        final (players, rankings, years) = options;
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
        final ranking = (_rankingId == null || _rankingId == 'all')
            ? null
            : eloRankings.where((item) => item.id == _rankingId).firstOrNull;

        if (_comparison == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _comparison == null) {
              _updateSelection(
                leftId: leftId,
                rightId: rightId,
                ranking: ranking,
                year: _selectedYear,
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
                      year: _selectedYear,
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
                      year: _selectedYear,
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
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final rankingFilter = DropdownButtonFormField<String>(
                  initialValue: _rankingId ?? 'all',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Elo-Rangliste',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('Alle Ranglisten'),
                    ),
                    for (final item in eloRankings)
                      DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                  ],
                  onChanged: (value) {
                    final selected = (value == null || value == 'all')
                        ? null
                        : eloRankings
                              .where((item) => item.id == value)
                              .firstOrNull;
                    _updateSelection(
                      leftId: leftId,
                      rightId: rightId,
                      ranking: selected,
                      year: _selectedYear,
                    );
                  },
                );

                final yearFilter = DropdownButtonFormField<int?>(
                  initialValue: _selectedYear,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Zeitraum',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Gesamter Zeitraum'),
                    ),
                    for (final y in years)
                      DropdownMenuItem<int?>(value: y, child: Text('$y')),
                  ],
                  onChanged: (value) {
                    _updateSelection(
                      leftId: leftId,
                      rightId: rightId,
                      ranking: ranking,
                      year: value,
                    );
                  },
                );

                return wide
                    ? Row(
                        children: [
                          Expanded(child: rankingFilter),
                          const SizedBox(width: 16),
                          Expanded(child: yearFilter),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          rankingFilter,
                          const SizedBox(height: 12),
                          yearFilter,
                        ],
                      );
              },
            ),
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
                        'Spielervergleich · ${ranking?.name ?? 'Alle Ranglisten'}${_selectedYear == null ? '' : ' ($_selectedYear)'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          border: TableBorder(
                            verticalInside: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
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
                              label: SizedBox(
                                width: 210,
                                child: Text(
                                  'Kategorie',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
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
                                  DataCell(
                                    SizedBox(
                                      width: 210,
                                      child: Text(
                                        row.category,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(row.right)),
                                ],
                              ),
                          ],
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
      rows[0] = (category: 'Elo aktuell', left: '-', right: '-');
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

    return rows;
  }

  String _performanceCategory(BestPerformanceType type) => switch (type) {
    BestPerformanceType.score170 => '170+ Aufnahmen',
    BestPerformanceType.score180 => '180er',
    BestPerformanceType.highFinish => 'High Finishes',
    BestPerformanceType.shortLeg => 'Shortlegs',
  };
}
