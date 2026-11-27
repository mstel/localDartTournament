import 'package:flutter/material.dart';

import '../../domain/player_spider_metrics.dart';
import '../../domain/player_monthly_performance.dart';
import 'player_performance_trend_chart.dart';
import 'player_spider_chart.dart';

class PerformanceStatisticsDetailSection extends StatefulWidget {
  const PerformanceStatisticsDetailSection({
    super.key,
    required this.entries,
    this.allEntries,
    this.spiderBuilder,
  });

  final List<PlayerMonthlyPerformance> entries;
  final List<PlayerMonthlyPerformance>? allEntries;
  final Future<PlayerSpiderComparison> Function(
    List<PlayerMonthlyPerformance> yearEntries,
  )?
  spiderBuilder;

  @override
  State<PerformanceStatisticsDetailSection> createState() =>
      _PerformanceStatisticsDetailSectionState();
}

class _PerformanceStatisticsDetailSectionState
    extends State<PerformanceStatisticsDetailSection> {
  int _year = DateTime.now().year;
  Future<PlayerSpiderComparison>? _spiderFuture;

  @override
  void initState() {
    super.initState();
    _refreshSpider();
  }

  @override
  void didUpdateWidget(covariant PerformanceStatisticsDetailSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries ||
        oldWidget.spiderBuilder != widget.spiderBuilder) {
      _refreshSpider();
    }
  }

  void _refreshSpider() {
    if (widget.spiderBuilder == null) return;
    final entries =
        widget.entries.where((entry) => entry.year == _year).toList()
          ..sort((left, right) => left.month.compareTo(right.month));
    _spiderFuture = widget.spiderBuilder!(entries);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.allEntries ?? widget.entries;
    final years = {
      DateTime.now().year,
      ...source.map((entry) => entry.year),
    }.toList()..sort((left, right) => right.compareTo(left));
    final entries =
        source.where((entry) => entry.year == _year).toList()
          ..sort((left, right) => left.month.compareTo(right.month));
    final summary = summarizeMonthlyPerformance(entries);
    final matches = entries.fold<int>(
      0,
      (total, entry) => total + entry.matches,
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(
          'Performance Statistiken im Detail',
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 2,
          softWrap: true,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Jahr', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    items: [
                      for (final year in years)
                        DropdownMenuItem(value: year, child: Text('$year')),
                    ],
                    onChanged: (year) {
                      if (year != null) {
                        setState(() {
                          _year = year;
                          _refreshSpider();
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (widget.spiderBuilder != null) ...[
            FutureBuilder<PlayerSpiderComparison>(
              future: _spiderFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final spider = snapshot.data;
                if (spider == null) {
                  return const SizedBox.shrink();
                }
                final hasPlayerData = entries.isNotEmpty;
                return PlayerSpiderChart(
                  title: 'Leistungsprofil',
                  subtitle: hasPlayerData
                      ? 'Außenkante: Vereinsmaximum, Mitte: Vereinsdurchschnitt'
                      : 'Keine Daten im ausgewählten Zeitraum – Vereinsdurchschnitt angezeigt',
                  metrics: [
                    for (var i = 0; i < PlayerSpiderValues.labels.length; i++)
                      PlayerSpiderMetric(
                        label: PlayerSpiderValues.labels[i],
                        value: hasPlayerData ? spider.player.toList()[i] : 0,
                        maxValue: spider.clubMax.toList()[i],
                        averageValue: spider.clubAverage.toList()[i],
                        normalizedValue: hasPlayerData
                            ? _normalizedSpiderValue(spider, i)
                            : 0,
                        normalizedAverage: _normalizedSpiderAverage(spider, i),
                        valueText: hasPlayerData ? null : '–',
                        averageText: _spiderValueText(
                          spider.clubAverage.toList()[i],
                          i,
                        ),
                        maxText: _spiderValueText(spider.clubMax.toList()[i], i),
                      ),
                  ],
                  playerColor: Theme.of(context).colorScheme.primary,
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          PlayerPerformanceTrendChart(
            entries: entries,
            year: _year,
            title: 'Performance-Entwicklung',
          ),
          if (entries.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Für dieses Jahr sind keine Performance-Daten erfasst.',
                ),
              ),
            )
          else ...[
            const Divider(),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Partien, Gewonnen, Verloren und Siegesrate stammen aus den '
                'zugewiesenen Turnieren und ihren Ergebnissen.',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Jahresschnitt und Summen',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _AnnualValue(label: 'Partien', value: '$matches'),
                _AnnualValue(label: 'Gewonnen', value: '${summary.wins}'),
                _AnnualValue(label: 'Verloren', value: '${summary.losses}'),
                _AnnualValue(
                  label: 'Siegesrate',
                  value: '${_format(summary.winRate)} %',
                ),
                _AnnualValue(
                  label: 'Gewertete Legs',
                  value: '${summary.weightedLegs}',
                ),
                _AnnualValue(
                  label: 'Scoring Ø',
                  value: _format(summary.scoring),
                ),
                _AnnualValue(
                  label: 'Average Ø',
                  value: _format(summary.average),
                ),
                _AnnualValue(
                  label: 'Checkout Ø',
                  value: summary.checkoutRate == null
                      ? '–'
                      : '${_format(summary.checkoutRate)} %',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Monat')),
                  DataColumn(label: Text('Scoring'), numeric: true),
                  DataColumn(label: Text('Average'), numeric: true),
                  DataColumn(label: Text('Checkout'), numeric: true),
                  DataColumn(label: Text('Partien'), numeric: true),
                  DataColumn(label: Text('Gewonnen'), numeric: true),
                  DataColumn(label: Text('Verloren'), numeric: true),
                  DataColumn(label: Text('Siegesrate %'), numeric: true),
                  DataColumn(label: Text('Legs'), numeric: true),
                ],
                rows: [
                  for (final entry in entries)
                    DataRow(
                      cells: [
                        DataCell(Text(_monthName(entry.month))),
                        DataCell(Text(_format(entry.scoring))),
                        DataCell(Text(_format(entry.average))),
                        DataCell(
                          Text(
                            entry.checkoutRate == null
                                ? '–'
                                : '${_format(entry.checkoutRate)} %',
                          ),
                        ),
                        DataCell(Text('${entry.matches}')),
                        DataCell(Text('${entry.wins}')),
                        DataCell(Text('${entry.losses}')),
                        DataCell(Text('${_format(entry.winRate)} %')),
                        DataCell(Text('${entry.weightedLegs}')),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _normalizedSpiderValue(PlayerSpiderComparison spider, int index) {
    final value = spider.player.toList()[index];
    final max = spider.clubMax.toList()[index];
    if (index == 4) return PlayerSpiderComparison.normalizeWinRate(value);
    if (index == 3) {
      final cap = PlayerSpiderComparison.bestPerformancesScaleCap(
        spider.clubAverage.bestPerformances,
      );
      return (value / cap).clamp(0.0, 1.0);
    }
    if (max <= 0) return 0;
    return (value / max).clamp(0.0, 1.0);
  }

  double _normalizedSpiderAverage(PlayerSpiderComparison spider, int index) {
    final value = spider.clubAverage.toList()[index];
    final max = spider.clubMax.toList()[index];
    if (index == 4) return PlayerSpiderComparison.normalizeWinRate(value);
    if (index == 3) {
      final cap = PlayerSpiderComparison.bestPerformancesScaleCap(
        spider.clubAverage.bestPerformances,
      );
      return (value / cap).clamp(0.0, 1.0);
    }
    if (max <= 0) return 0;
    return (value / max).clamp(0.0, 1.0);
  }

  String _spiderValueText(double value, int index) {
    if (index == 2 || index == 4) return '${value.toStringAsFixed(1)} %';
    if (index == 3) {
      return value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(1);
  }

  String _format(double? value) => value?.toStringAsFixed(1) ?? '–';

  String _monthName(int month) => const [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ][month - 1];
}

class _AnnualValue extends StatelessWidget {
  const _AnnualValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
}
