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
  final _visibleSeries = <int>{0, 1, 2};
  bool _showTrendCurves = false;

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
        const Text(
          'Die Kennzahlen sind jeweils auf ihren eigenen Wertebereich normiert. '
          'Für Originalwerte Monat oder Datenpunkt auswählen.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (
              var index = 0;
              index < PlayerPerformanceTrendChart.series.length;
              index++
            )
              _SeriesToggle(
                label: PlayerPerformanceTrendChart.series[index].label,
                color: PlayerPerformanceTrendChart.series[index].color,
                selected: _visibleSeries.contains(index),
                onTap: () => setState(() {
                  if (_visibleSeries.contains(index)) {
                    _visibleSeries.remove(index);
                  } else {
                    _visibleSeries.add(index);
                  }
                }),
              ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Switch(
                  value: _showTrendCurves,
                  onChanged: (value) =>
                      setState(() => _showTrendCurves = value),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 220,
                  child: Text('Trendkurven anzeigen', softWrap: true),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final chartYear in years)
          _YearPerformanceChart(
            key: ValueKey('performance-chart-$chartYear'),
            year: chartYear,
            entries: widget.entries
                .where((entry) => entry.year == chartYear)
                .toList(),
            visibleSeries: _visibleSeries.toSet(),
            showTrendCurves: _showTrendCurves,
          ),
      ],
    );
  }
}

class _SeriesToggle extends StatelessWidget {
  const _SeriesToggle({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$label ${selected ? "anzeigen" : "ausgeblendet"}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 3,
                color: selected ? color : color.withValues(alpha: 0.3),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  softWrap: true,
                  style: TextStyle(
                    color: selected
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    decoration: selected ? null : TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _YearPerformanceChart extends StatefulWidget {
  const _YearPerformanceChart({
    super.key,
    required this.year,
    required this.entries,
    required this.visibleSeries,
    required this.showTrendCurves,
  });

  final int year;
  final List<PlayerMonthlyPerformance> entries;
  final Set<int> visibleSeries;
  final bool showTrendCurves;

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
              '${widget.year}',
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
                          visibleSeries: widget.visibleSeries,
                          showTrendCurves: widget.showTrendCurves,
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
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _DataPointDetails(entry: selected),
              ),
          ],
        ),
      ),
    );
  }

  void _selectAt(double dx, double width, int firstMonth, int lastMonth) {
    const graphLeft = 30.0;
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

class _DataPointDetails extends StatelessWidget {
  const _DataPointDetails({required this.entry});

  final PlayerMonthlyPerformance entry;

  @override
  Widget build(BuildContext context) {
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
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '$month ${entry.year}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text('Partien: ${entry.matches}'),
            Text('Gewertete Legs: ${entry.weightedLegs}'),
            Text('Scoring: ${_format(entry.scoring)}'),
            Text('Average: ${_format(entry.average)}'),
            Text(
              'Checkout Quote: ${entry.checkoutRate == null ? "–" : "${_format(entry.checkoutRate)} %"}',
            ),
          ],
        ),
      ),
    );
  }

  String _format(double? value) => value?.toStringAsFixed(1) ?? '–';
}

class _PerformanceChartPainter extends CustomPainter {
  const _PerformanceChartPainter({
    required this.entries,
    required this.firstMonth,
    required this.visibleSeries,
    required this.showTrendCurves,
    required this.textColor,
    required this.gridColor,
  });

  final List<PlayerMonthlyPerformance?> entries;
  final int firstMonth;
  final Set<int> visibleSeries;
  final bool showTrendCurves;
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
    if (graph.width <= 0 || graph.height <= 0) return;
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

    for (final series in visibleSeries) {
      final color = PlayerPerformanceTrendChart.series[series].color;
      final values = [for (final entry in entries) _value(entry, series)];
      final present = [
        for (var index = 0; index < values.length; index++)
          if (values[index] != null) (index, values[index]!),
      ];
      if (present.isEmpty) continue;
      final minimum = present.map((point) => point.$2).reduce(math.min);
      final maximum = present.map((point) => point.$2).reduce(math.max);
      final range = maximum - minimum;
      Offset point(int index, double value) {
        final x = monthCount == 1
            ? graph.center.dx
            : graph.left + graph.width * index / (monthCount - 1);
        final normalized = range == 0
            ? 0.5
            : ((value - minimum) / range).clamp(0.0, 1.0);
        return Offset(x, graph.bottom - normalized * graph.height);
      }

      final path = Path();
      Offset? previousPoint;
      for (final item in present) {
        final currentPoint = point(item.$1, item.$2);
        if (previousPoint == null) {
          path.moveTo(currentPoint.dx, currentPoint.dy);
        } else {
          path.lineTo(currentPoint.dx, currentPoint.dy);
        }
        previousPoint = currentPoint;
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
      if (showTrendCurves && present.length > 1) {
        final trend = _trendPath(present, point);
        final dashPaint = Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke;
        for (final metric in trend.computeMetrics()) {
          for (var distance = 0.0; distance < metric.length; distance += 9) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 5, metric.length),
              ),
              dashPaint,
            );
          }
        }
      }
    }
  }

  Path _trendPath(
    List<(int, double)> points,
    Offset Function(int, double) toPoint,
  ) {
    final meanX =
        points.fold<double>(0, (sum, point) => sum + point.$1) / points.length;
    final meanY =
        points.fold<double>(0, (sum, point) => sum + point.$2) / points.length;
    var numerator = 0.0;
    var denominator = 0.0;
    for (final item in points) {
      numerator += (item.$1 - meanX) * (item.$2 - meanY);
      denominator += math.pow(item.$1 - meanX, 2);
    }
    if (denominator == 0) return Path();
    final slope = numerator / denominator;
    final minimumX = points.first.$1;
    final maximumX = points.last.$1;
    final minimum = points.map((item) => item.$2).reduce(math.min);
    final maximum = points.map((item) => item.$2).reduce(math.max);
    double fittedValue(int x) {
      return (meanY + slope * (x - meanX)).clamp(minimum, maximum);
    }

    final start = toPoint(minimumX, fittedValue(minimumX));
    final end = toPoint(maximumX, fittedValue(maximumX));
    return Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
  }

  double? _value(PlayerMonthlyPerformance? entry, int series) =>
      switch (series) {
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
      visibleSeries != oldDelegate.visibleSeries ||
      showTrendCurves != oldDelegate.showTrendCurves ||
      textColor != oldDelegate.textColor ||
      firstMonth != oldDelegate.firstMonth ||
      gridColor != oldDelegate.gridColor;
}
