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
  int? _selectedIndex;

  void _selectPoint(double x, double width) {
    if (widget.points.isEmpty) return;
    const padding = 12.0;
    final plotWidth = math.max(width - padding * 2, 1);
    final fraction = ((x - padding) / plotWidth).clamp(0.0, 1.0);
    final index = (fraction * (widget.points.length - 1)).round();
    if (_selectedIndex != index) setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final selected = _selectedIndex;
      final tooltipWidth = math.min(constraints.maxWidth, 240.0);
      final tooltipLeft = selected == null || widget.points.length < 2
          ? 0.0
          : (constraints.maxWidth - tooltipWidth) *
                selected /
                (widget.points.length - 1);
      final point = selected == null ? null : widget.points[selected];
      return Semantics(
        label: 'Interaktive Elo-Entwicklung pro Turnier',
        value: point == null
            ? 'Punkt auswählen, um Turnier und Wertungsänderung anzuzeigen'
            : [
                '${point.tournamentName}, ${point.rating} Elo, '
                    '${point.delta >= 0 ? '+' : ''}${point.delta}',
                ...point.breakdown,
              ].join(', '),
        child: MouseRegion(
          onHover: (event) =>
              _selectPoint(event.localPosition.dx, constraints.maxWidth),
          onExit: (_) => setState(() => _selectedIndex = null),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _selectPoint(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (details) =>
                _selectPoint(details.localPosition.dx, constraints.maxWidth),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _EloTrajectoryPainter(
                        ratings: [
                          for (final item in widget.points) item.rating,
                        ],
                        selectedIndex: selected,
                        color: widget.color,
                        gridColor: widget.gridColor,
                      ),
                    ),
                  ),
                  if (point != null)
                    Positioned(
                      top: 0,
                      left: tooltipLeft
                          .clamp(0.0, constraints.maxWidth - tooltipWidth)
                          .toDouble(),
                      width: tooltipWidth,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.inverseSurface,
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
          ),
        ),
      );
    },
  );
}

class _EloTrajectoryPainter extends CustomPainter {
  const _EloTrajectoryPainter({
    required this.ratings,
    required this.selectedIndex,
    required this.color,
    required this.gridColor,
  });

  final List<int> ratings;
  final int? selectedIndex;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (ratings.length < 2 || size.isEmpty) return;
    const padding = 12.0;
    final plot = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );
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
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var index = 0; index < ratings.length; index++) {
      final point = Offset(
        plot.left + plot.width * index / (ratings.length - 1),
        plot.bottom - (ratings[index] - low) / range * plot.height,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      if (index == selectedIndex) {
        canvas.drawCircle(
          point,
          6,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _EloTrajectoryPainter oldDelegate) =>
      !listEquals(oldDelegate.ratings, ratings) ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor;
}
