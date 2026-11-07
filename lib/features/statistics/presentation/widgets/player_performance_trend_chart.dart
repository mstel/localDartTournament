import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/player_monthly_performance.dart';

class PlayerPerformanceTrendChart extends StatefulWidget {
  const PlayerPerformanceTrendChart({
    super.key,
    required this.entries,
    required this.year,
    this.title = 'Performance-Entwicklung',
  });

  final List<PlayerMonthlyPerformance> entries;
  final int? year;
  final String title;

  static const series = [
    (label: 'Scoring', color: Color(0xFF4FC3F7)),
    (label: 'Average', color: Color(0xFFFFB74D)),
    (label: 'Checkout Quote', color: Color(0xFF81C784)),
  ];

  @override
  State<PlayerPerformanceTrendChart> createState() =>
      _PlayerPerformanceTrendChartState();
}

class _PlayerPerformanceTrendChartState
    extends State<PlayerPerformanceTrendChart> {
  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();
    final years = widget.year == null
        ? widget.entries.map((entry) => entry.year).toSet().toList()
        : [widget.year!];
    years.sort((left, right) => right.compareTo(left));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final chartYear in years)
          for (
            var series = 0;
            series < PlayerPerformanceTrendChart.series.length;
            series++
          )
            _YearPerformanceChart(
              key: ValueKey('performance-chart-$chartYear-$series'),
              year: chartYear,
              series: series,
              entries: widget.entries
                  .where((entry) => entry.year == chartYear)
                  .toList(),
            ),
      ],
    );
  }
}

class _YearPerformanceChart extends StatefulWidget {
  const _YearPerformanceChart({
    super.key,
    required this.year,
    required this.series,
    required this.entries,
  });

  final int year;
  final int series;
  final List<PlayerMonthlyPerformance> entries;

  @override
  State<_YearPerformanceChart> createState() => _YearPerformanceChartState();
}

class _YearPerformanceChartState extends State<_YearPerformanceChart> {
  int? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final entries = [...widget.entries]
      ..sort((left, right) => left.month.compareTo(right.month));
    if (entries.isEmpty) return const SizedBox.shrink();
    final firstMonth = entries.first.month;
    final lastMonth = entries.last.month;
    final byMonth = {for (final entry in entries) entry.month: entry};
    final data = [
      for (var month = firstMonth; month <= lastMonth; month++) byMonth[month],
    ];
    final selected = _selectedMonth == null ? null : byMonth[_selectedMonth!];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${PlayerPerformanceTrendChart.series[widget.series].label} · ${widget.year}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: LayoutBuilder(
                builder: (context, constraints) => Tooltip(
                  message: selected == null
                      ? ''
                      : _performanceTooltipText(selected),
                  child: MouseRegion(
                    onHover: (event) => _selectAt(
                      event.localPosition.dx,
                      constraints.maxWidth,
                      firstMonth,
                      lastMonth,
                    ),
                    onExit: (_) {
                      if (_selectedMonth != null) {
                        setState(() => _selectedMonth = null);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (event) => _selectAt(
                        event.localPosition.dx,
                        constraints.maxWidth,
                        firstMonth,
                        lastMonth,
                      ),
                      child: CustomPaint(
                        painter: _PerformanceChartPainter(
                          entries: data,
                          firstMonth: firstMonth,
                          series: widget.series,
                          color: PlayerPerformanceTrendChart
                              .series[widget.series]
                              .color,
                          textColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                          gridColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAt(double dx, double width, int firstMonth, int lastMonth) {
    const graphLeft = 48.0;
    const graphRight = 8.0;
    final graphWidth = width - graphLeft - graphRight;
    if (graphWidth <= 0 || dx < graphLeft || dx > width - graphRight) return;
    final monthCount = lastMonth - firstMonth + 1;
    final index = monthCount == 1
        ? 0
        : (((dx - graphLeft) / graphWidth) * (monthCount - 1)).round().clamp(
            0,
            monthCount - 1,
          );
    final selectedMonth = firstMonth + index;
    final hasData = widget.entries.any((entry) => entry.month == selectedMonth);
    final nextSelectedMonth = hasData ? selectedMonth : null;
    if (_selectedMonth != nextSelectedMonth) {
      setState(() => _selectedMonth = nextSelectedMonth);
    }
  }
}

String _performanceTooltipText(PlayerMonthlyPerformance entry) {
  final month = const [
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
  ][entry.month - 1];
  String format(double? value) => value?.toStringAsFixed(1) ?? '–';
  return [
    '$month ${entry.year}',
    'Partien: ${entry.matches}',
    'Gewertete Legs: ${entry.weightedLegs}',
    'Scoring: ${format(entry.scoring)}',
    'Average: ${format(entry.average)}',
    'Checkout Quote: ${entry.checkoutRate == null ? "–" : "${format(entry.checkoutRate)} %"}',
  ].join('\n');
}

class _PerformanceChartPainter extends CustomPainter {
  const _PerformanceChartPainter({
    required this.entries,
    required this.firstMonth,
    required this.series,
    required this.color,
    required this.textColor,
    required this.gridColor,
  });

  final List<PlayerMonthlyPerformance?> entries;
  final int firstMonth;
  final int series;
  final Color color;
  final Color textColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    const right = 8.0;
    const top = 12.0;
    const bottom = 24.0;
    final graph = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    if (graph.width <= 0 || graph.height <= 0) return;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.7;
    final values = [for (final entry in entries) _value(entry)];
    final present = [
      for (var index = 0; index < values.length; index++)
        if (values[index] != null) (index, values[index]!),
    ];
    if (present.isEmpty) return;
    final minimum = present.map((point) => point.$2).reduce(math.min);
    final maximum = present.map((point) => point.$2).reduce(math.max);
    final range = maximum - minimum;
    final padding = range == 0
        ? math.max(maximum.abs() * 0.1, 1.0).toDouble()
        : range * 0.1;
    final axisMinimum = math.max(0.0, minimum - padding).toDouble();
    final axisMaximum = maximum + padding;
    final axisRange = axisMaximum - axisMinimum;
    final axisLabel = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );
    for (var line = 0; line <= 4; line++) {
      final fraction = line / 4;
      final y = graph.top + graph.height * fraction;
      canvas.drawLine(Offset(graph.left, y), Offset(graph.right, y), gridPaint);
      final value = axisMaximum - axisRange * fraction;
      axisLabel.text = TextSpan(
        text: value.toStringAsFixed(series == 2 ? 0 : 1),
        style: TextStyle(color: textColor, fontSize: 10),
      );
      axisLabel.layout(maxWidth: left - 6);
      axisLabel.paint(canvas, Offset(0, y - axisLabel.height / 2));
    }
    final monthPaint = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    final monthCount = entries.length;
    for (var index = 0; index < monthCount; index++) {
      final month = firstMonth + index;
      final x = monthCount == 1
          ? graph.center.dx
          : graph.left + graph.width * index / (monthCount - 1);
      monthPaint.text = TextSpan(
        text: _monthName(month),
        style: TextStyle(color: textColor, fontSize: 10),
      );
      monthPaint.layout();
      monthPaint.paint(
        canvas,
        Offset(x - monthPaint.width / 2, graph.bottom + 5),
      );
    }

    Offset point(int index, double value) {
      final x = monthCount == 1
          ? graph.center.dx
          : graph.left + graph.width * index / (monthCount - 1);
      final normalized = axisRange == 0
          ? 0.5
          : ((value - axisMinimum) / axisRange).clamp(0.0, 1.0).toDouble();
      return Offset(x, graph.bottom - normalized * graph.height);
    }

    final path = Path();
    for (final (index, value) in present) {
      final currentPoint = point(index, value);
      if (index == present.first.$1) {
        path.moveTo(currentPoint.dx, currentPoint.dy);
      } else {
        path.lineTo(currentPoint.dx, currentPoint.dy);
      }
      canvas.drawCircle(currentPoint, 3.5, Paint()..color = color);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  double? _value(PlayerMonthlyPerformance? entry) => switch (series) {
    0 => entry?.scoring,
    1 => entry?.average,
    _ => entry?.checkoutRate,
  };

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

  @override
  bool shouldRepaint(covariant _PerformanceChartPainter oldDelegate) =>
      entries != oldDelegate.entries ||
      series != oldDelegate.series ||
      color != oldDelegate.color ||
      textColor != oldDelegate.textColor ||
      firstMonth != oldDelegate.firstMonth ||
      gridColor != oldDelegate.gridColor;
}
