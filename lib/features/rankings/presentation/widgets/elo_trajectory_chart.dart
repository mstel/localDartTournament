import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

class EloTrajectoryPoint {
  const EloTrajectoryPoint({
    required this.playedAt,
    required this.tournamentName,
    required this.rating,
    required this.delta,
    this.breakdown = const [],
  });

  final DateTime playedAt;
  final String tournamentName;
  final int rating;
  final int delta;
  final List<String> breakdown;
}

class EloTrajectoryChart extends StatefulWidget {
  const EloTrajectoryChart({
    super.key,
    required this.points,
    required this.color,
    required this.gridColor,
  });

  final List<EloTrajectoryPoint> points;
  final Color color;
  final Color gridColor;

  @override
  State<EloTrajectoryChart> createState() => _EloTrajectoryChartState();
}

class _EloTrajectoryChartState extends State<EloTrajectoryChart> {
  final ScrollController _scrollController = ScrollController();
  int? _selectedIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectPoint(double x, double width, int firstYear, int monthCount) {
    if (widget.points.isEmpty) return;
    const padding = 12.0;
    final plotWidth = math.max(width - padding * 2, 1).toDouble();
    final targetMonth =
        ((x - padding) / plotWidth).clamp(0.0, 1.0) * monthCount;
    var index = 0;
    var distance = double.infinity;
    for (var candidate = 0; candidate < widget.points.length; candidate++) {
      final candidateMonth = _monthPosition(
        widget.points[candidate].playedAt,
        firstYear,
      );
      final candidateDistance = (candidateMonth - targetMonth).abs();
      if (candidateDistance <= distance) {
        index = candidate;
        distance = candidateDistance;
      }
    }
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (widget.points.isEmpty) return const SizedBox.shrink();
      final years = widget.points.map((point) => point.playedAt.year);
      final firstYear = years.reduce(
        (left, right) => left < right ? left : right,
      );
      final lastYear = years.reduce(
        (left, right) => left > right ? left : right,
      );
      final monthCount = (lastYear - firstYear + 1) * 12;
      final textScaler = MediaQuery.textScalerOf(context);
      final monthWidth = math.max(44.0, 32 * textScaler.scale(1));
      final chartWidth = math
          .max(constraints.maxWidth, monthCount * monthWidth)
          .toDouble();
      final selected = _selectedIndex;
      final point = selected == null ? null : widget.points[selected];
      final pointX = point == null
          ? 0.0
          : 12.0 +
                (chartWidth - 24) *
                    _monthPosition(point.playedAt, firstYear) /
                    monthCount;
      final tooltipWidth = math.min(chartWidth, 240.0);
      final tooltipLeft = point == null
          ? 0.0
          : (pointX - tooltipWidth / 2)
                .clamp(0.0, chartWidth - tooltipWidth)
                .toDouble();
      return Semantics(
        label:
            'Interaktive Elo-Entwicklung mit Monatsachse Januar bis Dezember',
        value: point == null
            ? 'Punkt auswählen, um Turnier und Wertungsänderung anzuzeigen'
            : [
                '${point.tournamentName}, ${point.rating} Elo, '
                    '${point.delta >= 0 ? '+' : ''}${point.delta}',
                ...point.breakdown,
              ].join(', '),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: chartWidth > constraints.maxWidth,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: MouseRegion(
                onHover: (event) => _selectPoint(
                  event.localPosition.dx,
                  chartWidth,
                  firstYear,
                  monthCount,
                ),
                onExit: (_) => setState(() => _selectedIndex = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => _selectPoint(
                    details.localPosition.dx,
                    chartWidth,
                    firstYear,
                    monthCount,
                  ),
                  child: SizedBox(
                    width: chartWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 196,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _EloTrajectoryPainter(
                                    points: widget.points,
                                    firstYear: firstYear,
                                    monthCount: monthCount,
                                    selectedIndex: selected,
                                    color: widget.color,
                                    gridColor: widget.gridColor,
                                    textColor: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    textScaler: textScaler,
                                  ),
                                ),
                              ),
                              if (point != null)
                                Positioned(
                                  top: 0,
                                  left: tooltipLeft,
                                  width: tooltipWidth,
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.inverseSurface,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          [
                                            '${point.playedAt.day}.${point.playedAt.month}.${point.playedAt.year} · ${point.tournamentName}',
                                            '${point.rating} Elo (${point.delta >= 0 ? '+' : ''}${point.delta})',
                                            ...point.breakdown,
                                          ].join('\n'),
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onInverseSurface,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

double _monthPosition(DateTime date, int firstYear) =>
    (date.year - firstYear) * 12 +
    date.month -
    1 +
    (date.day - 1) / DateUtils.getDaysInMonth(date.year, date.month);

class _EloTrajectoryPainter extends CustomPainter {
  const _EloTrajectoryPainter({
    required this.points,
    required this.firstYear,
    required this.monthCount,
    required this.selectedIndex,
    required this.color,
    required this.gridColor,
    required this.textColor,
    required this.textScaler,
  });

  final List<EloTrajectoryPoint> points;
  final int firstYear;
  final int monthCount;
  final int? selectedIndex;
  final Color color;
  final Color gridColor;
  final Color textColor;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;
    const padding = 12.0;
    const bottom = 40.0;
    final plot = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding - bottom,
    );
    final ratings = [for (final item in points) item.rating];
    final low = math.min(1000, ratings.reduce(math.min)).toDouble();
    final high = math.max(1000, ratings.reduce(math.max)).toDouble();
    final range = math.max(high - low, 1);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var line = 0; line < 4; line++) {
      final y = plot.top + plot.height * line / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    final monthPaint = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: textScaler,
    );
    for (var monthIndex = 0; monthIndex < monthCount; monthIndex++) {
      final x = plot.left + plot.width * (monthIndex + 0.5) / monthCount;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      final month = monthIndex % 12;
      final year = firstYear + monthIndex ~/ 12;
      monthPaint.text = TextSpan(
        text: month == 0 ? 'Jan\n$year' : _monthName(month),
        style: TextStyle(color: textColor, fontSize: 10),
      );
      monthPaint.layout();
      monthPaint.paint(
        canvas,
        Offset(x - monthPaint.width / 2, plot.bottom + 5),
      );
    }
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset positionFor(EloTrajectoryPoint item) => Offset(
      plot.left +
          plot.width * _monthPosition(item.playedAt, firstYear) / monthCount,
      plot.bottom - (item.rating - low) / range * plot.height,
    );

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = positionFor(points[index]);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(
        point,
        index == selectedIndex ? 6 : 3.5,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(path, linePaint);
  }

  static String _monthName(int month) => const [
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
  bool shouldRepaint(covariant _EloTrajectoryPainter oldDelegate) =>
      !listEquals(oldDelegate.points, points) ||
      oldDelegate.firstYear != firstYear ||
      oldDelegate.monthCount != monthCount ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.textColor != textColor ||
      oldDelegate.textScaler != textScaler;
}
