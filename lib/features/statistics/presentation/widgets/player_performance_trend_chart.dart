import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/player_monthly_performance.dart';

class PlayerPerformanceTrendChart extends StatelessWidget {
  const PlayerPerformanceTrendChart({
    super.key,
    required this.entries,
    required this.year,
  });

  final List<PlayerMonthlyPerformance> entries;
  final int? year;

  static const _series = [
    (label: 'Scoring', color: Color(0xFF4FC3F7)),
    (label: 'Average', color: Color(0xFFFFB74D)),
    (label: 'Checkout Quote', color: Color(0xFF81C784)),
  ];

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final years = year == null
        ? entries.map((entry) => entry.year).toSet().toList()
        : [year!];
    years.sort((left, right) => right.compareTo(left));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Performance-Entwicklung',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Die Linien zeigen den Monatsverlauf je Kennzahl normiert auf deren eigenen Wertebereich; die Tabelle nennt die Originalwerte.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final item in _series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 18, height: 3, color: item.color),
                  const SizedBox(width: 6),
                  Text(item.label),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final chartYear in years)
          _yearChart(
            context,
            chartYear,
            entries.where((entry) => entry.year == chartYear).toList(),
          ),
      ],
    );
  }

  Widget _yearChart(
    BuildContext context,
    int chartYear,
    List<PlayerMonthlyPerformance> entries,
  ) {
    final byMonth = {for (final entry in entries) entry.month: entry};
    final data = [for (var month = 1; month <= 12; month++) byMonth[month]];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$chartYear', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _PerformanceChartPainter(
                  entries: data,
                  colors: [for (final item in _series) item.color],
                  textColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  gridColor: Theme.of(context).colorScheme.outlineVariant,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                horizontalMargin: 8,
                columns: const [
                  DataColumn(label: Text('Monat')),
                  DataColumn(label: Text('Scoring')),
                  DataColumn(label: Text('Average')),
                  DataColumn(label: Text('Checkout Quote')),
                ],
                rows: [
                  for (var month = 1; month <= 12; month++)
                    DataRow(
                      cells: [
                        DataCell(Text(_monthName(month))),
                        DataCell(Text(_format(data[month - 1]?.scoring))),
                        DataCell(Text(_format(data[month - 1]?.average))),
                        DataCell(
                          Text(
                            data[month - 1]?.checkoutRate == null
                                ? '–'
                                : '${data[month - 1]!.checkoutRate!.toStringAsFixed(1)} %',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _format(double? value) => value?.toStringAsFixed(1) ?? '–';

  static String _monthName(int month) => const [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ][month - 1];
}

class _PerformanceChartPainter extends CustomPainter {
  const _PerformanceChartPainter({
    required this.entries,
    required this.colors,
    required this.textColor,
    required this.gridColor,
  });

  final List<PlayerMonthlyPerformance?> entries;
  final List<Color> colors;
  final Color textColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 22.0;
    final graph = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    for (var line = 0; line <= 4; line++) {
      final y = graph.top + graph.height * line / 4;
      canvas.drawLine(Offset(graph.left, y), Offset(graph.right, y), gridPaint);
    }
    final monthPaint = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (var month = 1; month <= 12; month++) {
      final x = graph.left + graph.width * (month - 1) / 11;
      monthPaint.text = TextSpan(
        text: PlayerPerformanceTrendChart._monthName(month),
        style: TextStyle(color: textColor, fontSize: 10),
      );
      monthPaint.layout();
      monthPaint.paint(
        canvas,
        Offset(x - monthPaint.width / 2, graph.bottom + 5),
      );
    }

    for (var series = 0; series < colors.length; series++) {
      final values = [
        for (final entry in entries)
          switch (series) {
            0 => entry?.scoring,
            1 => entry?.average,
            _ => entry?.checkoutRate,
          },
      ];
      final present = values.whereType<double>().toList();
      if (present.isEmpty) continue;
      final maximum = present.reduce(math.max);
      final minimum = present.reduce(math.min);
      final range = maximum - minimum;
      final path = Path();
      var hasStarted = false;
      for (var index = 0; index < values.length; index++) {
        final value = values[index];
        if (value == null) {
          hasStarted = false;
          continue;
        }
        final x = graph.left + graph.width * index / 11;
        final normalized = range == 0 ? 0.5 : (value - minimum) / range;
        final point = Offset(x, graph.bottom - normalized * graph.height);
        if (hasStarted) {
          path.lineTo(point.dx, point.dy);
        } else {
          path.moveTo(point.dx, point.dy);
          hasStarted = true;
        }
        canvas.drawCircle(point, 3.5, Paint()..color = colors[series]);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors[series]
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PerformanceChartPainter oldDelegate) =>
      entries != oldDelegate.entries ||
      colors != oldDelegate.colors ||
      textColor != oldDelegate.textColor ||
      gridColor != oldDelegate.gridColor;
}
