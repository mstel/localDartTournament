import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../rankings/domain/local_elo_calculator.dart';

class PlayerEloComparisonChart extends StatelessWidget {
  const PlayerEloComparisonChart({
    super.key,
    required this.left,
    required this.right,
    required this.leftColor,
    required this.rightColor,
    required this.gridColor,
  });

  final List<LocalEloHistoryItem> left;
  final List<LocalEloHistoryItem> right;
  final Color leftColor;
  final Color rightColor;
  final Color gridColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    width: double.infinity,
    child: CustomPaint(
      painter: _PlayerEloComparisonPainter(
        leftRatings: [
          for (final item in left) (item.playedAt, item.ratingAfter),
        ],
        rightRatings: [
          for (final item in right) (item.playedAt, item.ratingAfter),
        ],
        leftColor: leftColor,
        rightColor: rightColor,
        gridColor: gridColor,
      ),
    ),
  );
}

class _PlayerEloComparisonPainter extends CustomPainter {
  const _PlayerEloComparisonPainter({
    required this.leftRatings,
    required this.rightRatings,
    required this.leftColor,
    required this.rightColor,
    required this.gridColor,
  });

  final List<(DateTime, int)> leftRatings;
  final List<(DateTime, int)> rightRatings;
  final Color leftColor;
  final Color rightColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 16.0;
    final plot = Rect.fromLTWH(
      padding,
      padding,
      math.max(0, size.width - padding * 2),
      math.max(0, size.height - padding * 2),
    );
    if (plot.isEmpty) return;
    final allRatings = [
      ...leftRatings.map((item) => item.$2),
      ...rightRatings.map((item) => item.$2),
      1000,
    ];
    final low = allRatings.reduce(math.min).toDouble();
    final high = allRatings.reduce(math.max).toDouble();
    final range = math.max(high - low, 1).toDouble();
    final allDates = [
      ...leftRatings.map((item) => item.$1.millisecondsSinceEpoch),
      ...rightRatings.map((item) => item.$1.millisecondsSinceEpoch),
    ];
    final minDate = allDates.isEmpty ? 0 : allDates.reduce(math.min);
    final maxDate = allDates.isEmpty ? 0 : allDates.reduce(math.max);
    final dateRange = math.max(maxDate - minDate, 1);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var line = 0; line < 4; line++) {
      final y = plot.top + plot.height * line / 3;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    _drawSeries(
      canvas,
      plot,
      leftRatings,
      minDate,
      dateRange,
      low,
      range,
      leftColor,
    );
    _drawSeries(
      canvas,
      plot,
      rightRatings,
      minDate,
      dateRange,
      low,
      range,
      rightColor,
    );
  }

  void _drawSeries(
    Canvas canvas,
    Rect plot,
    List<(DateTime, int)> ratings,
    int minDate,
    int dateRange,
    double low,
    double ratingRange,
    Color color,
  ) {
    if (ratings.isEmpty) return;
    final points = [
      for (final item in ratings)
        Offset(
          (plot.left +
                  plot.width *
                      (item.$1.millisecondsSinceEpoch - minDate) /
                      dateRange)
              .toDouble(),
          (plot.bottom - (item.$2 - low) / ratingRange * plot.height.toDouble())
              .toDouble(),
        ),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
    final markerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 4, markerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlayerEloComparisonPainter oldDelegate) =>
      oldDelegate.leftRatings != leftRatings ||
      oldDelegate.rightRatings != rightRatings ||
      oldDelegate.leftColor != leftColor ||
      oldDelegate.rightColor != rightColor ||
      oldDelegate.gridColor != gridColor;
}
