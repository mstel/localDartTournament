import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlayerSpiderMetric {
  const PlayerSpiderMetric({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.averageValue,
  });

  final String label;
  final double value;
  final double maxValue;
  final double averageValue;

  double get normalizedValue =>
      maxValue <= 0 ? 0 : (value / maxValue).clamp(0.0, 1.0);
  double get normalizedAverage =>
      maxValue <= 0 ? 0 : (averageValue / maxValue).clamp(0.0, 1.0);
}

class PlayerSpiderChart extends StatelessWidget {
  const PlayerSpiderChart({
    super.key,
    required this.metrics,
    required this.playerColor,
    this.size = 260,
    this.title,
    this.subtitle,
  });

  final List<PlayerSpiderMetric> metrics;
  final Color playerColor;
  final double size;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Text(
            title!,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _PlayerSpiderPainter(
              metrics: metrics,
              playerColor: playerColor,
              gridColor: theme.colorScheme.outlineVariant,
              labelStyle:
                  theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ) ??
                  const TextStyle(fontSize: 11),
              averageColor: theme.colorScheme.secondary.withValues(alpha: 0.85),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            _LegendDot(color: playerColor, label: 'Spieler'),
            _LegendDot(
              color: theme.colorScheme.secondary.withValues(alpha: 0.85),
              label: 'Vereinsdurchschnitt',
            ),
            _LegendDot(
              color: theme.colorScheme.outline,
              label: 'Ranglisten-Maximum',
              filled: false,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.filled = true,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PlayerSpiderPainter extends CustomPainter {
  _PlayerSpiderPainter({
    required this.metrics,
    required this.playerColor,
    required this.gridColor,
    required this.labelStyle,
    required this.averageColor,
  });

  final List<PlayerSpiderMetric> metrics;
  final Color playerColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color averageColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    final angleStep = (math.pi * 2) / metrics.length;
    const startAngle = -math.pi / 2;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var ring = 1; ring <= 4; ring++) {
      final r = radius * ring / 4;
      final path = Path();
      for (var i = 0; i < metrics.length; i++) {
        final angle = startAngle + angleStep * i;
        final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    for (var i = 0; i < metrics.length; i++) {
      final angle = startAngle + angleStep * i;
      final end = center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      canvas.drawLine(center, end, axisPaint);

      final labelRadius = radius + 24;
      final labelCenter =
          center + Offset(math.cos(angle) * labelRadius, math.sin(angle) * labelRadius);
      final tp = TextPainter(
        text: TextSpan(text: metrics[i].label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: 72);
      tp.paint(
        canvas,
        Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2),
      );
    }

    void drawPolygon(List<double> values, Color color, {required bool fill}) {
      final path = Path();
      for (var i = 0; i < metrics.length; i++) {
        final angle = startAngle + angleStep * i;
        final r = radius * values[i].clamp(0.0, 1.0);
        final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      if (fill) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: 0.18)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      if (fill) {
        for (var i = 0; i < metrics.length; i++) {
          final angle = startAngle + angleStep * i;
          final r = radius * values[i].clamp(0.0, 1.0);
          final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
          canvas.drawCircle(point, 3, Paint()..color = color);
        }
      }
    }

    drawPolygon(
      metrics.map((m) => m.normalizedAverage).toList(),
      averageColor,
      fill: false,
    );
    drawPolygon(
      metrics.map((m) => m.normalizedValue).toList(),
      playerColor,
      fill: true,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayerSpiderPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.playerColor != playerColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.averageColor != averageColor;
  }
}
