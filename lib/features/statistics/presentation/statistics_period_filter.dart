import 'package:flutter/material.dart';
import '../domain/statistics_period.dart';
import 'statistics_date_dialog.dart';

class StatisticsPeriodFilter extends StatefulWidget {
  const StatisticsPeriodFilter({
    super.key,
    required this.onChanged,
    required this.selected,
    this.period,
  });
  final void Function(String, StatisticsPeriod?) onChanged;
  final String selected;
  final StatisticsPeriod? period;

  @override
  State<StatisticsPeriodFilter> createState() => _StatisticsPeriodFilterState();
}

class _StatisticsPeriodFilterState extends State<StatisticsPeriodFilter> {
  Future<void> select(String label) async {
    final now = DateTime.now();
    StatisticsPeriod? period;
    if (label == 'Zeitraum wählen') {
      final range = await showDialog<DateTimeRange>(
        context: context,

        builder: (_) => StatisticsDateDialog(
          initialRange: widget.period == null
              ? null
              : DateTimeRange(
                  start: widget.period!.start,
                  end: widget.period!.endExclusive.subtract(
                    const Duration(microseconds: 1),
                  ),
                ),
        ),
      );
      if (range == null || !mounted) return;
      period = StatisticsPeriod(range.start, range.end);
    } else {
      final start = switch (label) {
        'Heute' => now,
        '7 Tage' => DateTime(now.year, now.month, now.day - 6),
        '30 Tage' => DateTime(now.year, now.month, now.day - 29),
        'Dieser Monat' => DateTime(now.year, now.month),
        'Dieses Jahr' => DateTime(now.year),
        _ => null,
      };
      if (start != null) period = StatisticsPeriod(start, now);
    }
    widget.onChanged(label, period);
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Zeitraum', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final label in const [
                'Gesamt',
                'Heute',
                '7 Tage',
                '30 Tage',
                'Dieser Monat',
                'Dieses Jahr',
                'Zeitraum wählen',
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: widget.selected == label,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => select(label),
                ),
            ],
          ),
          if (widget.period != null)
            Text(
              '${MaterialLocalizations.of(context).formatMediumDate(widget.period!.start)} – ${MaterialLocalizations.of(context).formatMediumDate(widget.period!.endExclusive.subtract(const Duration(microseconds: 1)))}',
            ),
          const SizedBox(height: 8),
          const Text(
            'Gilt für alle Werte und Begegnungen unten. Turnierspiele: Spielende, ersatzweise Start. Ältere Ergebnisse ohne Zeitangabe erscheinen nur unter Gesamt.',
          ),
        ],
      ),
    ),
  );
}
