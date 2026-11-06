import 'package:flutter/material.dart';

import '../../domain/player_monthly_performance.dart';
import 'player_performance_trend_chart.dart';

class PerformanceStatisticsDetailSection extends StatefulWidget {
  const PerformanceStatisticsDetailSection({super.key, required this.entries});

  final List<PlayerMonthlyPerformance> entries;

  @override
  State<PerformanceStatisticsDetailSection> createState() =>
      _PerformanceStatisticsDetailSectionState();
}

class _PerformanceStatisticsDetailSectionState
    extends State<PerformanceStatisticsDetailSection> {
  int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final years = {
      DateTime.now().year,
      ...widget.entries.map((entry) => entry.year),
    }.toList()..sort((left, right) => right.compareTo(left));
    final entries =
        widget.entries.where((entry) => entry.year == _year).toList()
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
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: DropdownButtonFormField<int>(
                initialValue: _year,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Jahr',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
                items: [
                  for (final year in years)
                    DropdownMenuItem(value: year, child: Text('$year')),
                ],
                onChanged: (year) {
                  if (year != null) setState(() => _year = year);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Für dieses Jahr sind keine Performance-Daten erfasst.',
              ),
            )
          else ...[
            PlayerPerformanceTrendChart(
              entries: entries,
              year: _year,
              title: 'Performance-Entwicklung',
            ),
            const Divider(),
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
