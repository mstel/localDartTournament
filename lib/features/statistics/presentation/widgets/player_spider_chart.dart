import 'dart:math' as math;

import 'package:flutter/material.dart';

class PlayerSpiderMetric {
  const PlayerSpiderMetric({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.averageValue,
    required this.normalizedValue,
    required this.normalizedAverage,
    this.valueText,
    this.averageText,
    this.maxText,
  });

  final String label;
  final double value;
  final double maxValue;
  final double averageValue;
  final double normalizedValue;
  final double normalizedAverage;
  final String? valueText;
  final String? averageText;
  final String? maxText;

  String get displayValue => valueText ?? _defaultFormat(value);
  String get displayAverage => averageText ?? _defaultFormat(averageValue);
  String get displayMax => maxText ?? _defaultFormat(maxValue);

  static String _defaultFormat(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
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
          child: _SpiderChartWithTooltip(
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
              label: 'Vereinsmaximum',
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
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SpiderChartWithTooltip extends StatefulWidget {
  const _SpiderChartWithTooltip({
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
  State<_SpiderChartWithTooltip> createState() =>
      _SpiderChartWithTooltipState();
}

class _SpiderChartWithTooltipState extends State<_SpiderChartWithTooltip> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          onExit: (_) => setState(() => _hovered = null),
          onHover: (event) => _updateHover(event.localPosition, size),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _updateHover(details.localPosition, size),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PlayerSpiderPainter(
                      metrics: widget.metrics,
                      playerColor: widget.playerColor,
                      gridColor: widget.gridColor,
                      labelStyle: widget.labelStyle,
                      averageColor: widget.averageColor,
                      hoveredIndex: _hovered,
                    ),
                  ),
                ),
                if (_hovered != null && _hovered! < widget.metrics.length)
                  _tooltip(theme, size, widget.metrics[_hovered!], _hovered!),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateHover(Offset position, Size size) {
    final index = _PlayerSpiderPainter.hitTestIndex(
      position: position,
      size: size,
      metricCount: widget.metrics.length,
    );
    if (index != _hovered) setState(() => _hovered = index);
  }

  Widget _tooltip(ThemeData theme, Size size, PlayerSpiderMetric metric, int i) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    final angleStep = (math.pi * 2) / widget.metrics.length;
    final angle = -math.pi / 2 + angleStep * i;
    final point =
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
    const tooltipWidth = 190.0;
    final left = (point.dx - tooltipWidth / 2).clamp(0.0, size.width - tooltipWidth);
    final placeAbove = point.dy > size.height * 0.45;
    final top = placeAbove
        ? (point.dy - 96).clamp(0.0, size.height - 90)
        : (point.dy + 12).clamp(0.0, size.height - 90);
    return Positioned(
      left: left,
      top: top,
      width: tooltipWidth,
      child: IgnorePointer(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: DefaultTextStyle(
              style: theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(metric.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Spieler: ${metric.displayValue}'),
                  Text('Vereinsdurchschnitt: ${metric.displayAverage}'),
                  Text('Vereinsmaximum: ${metric.displayMax}'),
                ],
              ),
            ),
          ),
        ),
      ),
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
    this.hoveredIndex,
  });

  final List<PlayerSpiderMetric> metrics;
  final Color playerColor;
  final Color gridColor;
  final TextStyle labelStyle;
  final Color averageColor;
  final int? hoveredIndex;

  static int? hitTestIndex({
    required Offset position,
    required Size size,
    required int metricCount,
  }) {
    if (metricCount == 0) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.32;
    final angleStep = (math.pi * 2) / metricCount;
    const startAngle = -math.pi / 2;
    int? closest;
    var closestDistance = 34.0;
    for (var i = 0; i < metricCount; i++) {
      final angle = startAngle + angleStep * i;
      final axisEnd =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      final labelCenter = center +
          Offset(math.cos(angle) * (radius + 24), math.sin(angle) * (radius + 24));
      // Hover anywhere near axis/label area, not only endpoint.
      final axisDist = _distanceToSegment(position, center, axisEnd);
      final endDist = (axisEnd - position).distance;
      final labelDist = (labelCenter - position).distance;
      final distance = [axisDist, endDist, labelDist].reduce(math.min);
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = i;
      }
    }
    return closest;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final ap = p - a;
    final abLen2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLen2 == 0) return (p - a).distance;
    final t = ((ap.dx * ab.dx + ap.dy * ab.dy) / abLen2).clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - proj).distance;
  }

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
      final isHovered = i == hoveredIndex;
      final style = isHovered
          ? labelStyle.copyWith(fontWeight: FontWeight.w700)
          : labelStyle;
      final tp = TextPainter(
        text: TextSpan(text: metrics[i].label, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: 72);
      tp.paint(
        canvas,
        Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2),
      );
      if (isHovered) {
        canvas.drawCircle(end, 5, Paint()..color = playerColor.withValues(alpha: 0.18));
      }
    }

    void drawPolygon(
      List<double> values,
      Color color, {
      required bool fill,
      required bool drawPoints,
    }) {
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
      if (drawPoints) {
        for (var i = 0; i < metrics.length; i++) {
          final angle = startAngle + angleStep * i;
          final r = radius * values[i].clamp(0.0, 1.0);
          final point = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
          final isHovered = i == hoveredIndex;
          canvas.drawCircle(point, isHovered ? 4.5 : 3, Paint()..color = color);
          if (isHovered) {
            canvas.drawCircle(
              point,
              7,
              Paint()
                ..color = color.withValues(alpha: 0.18)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2,
            );
          }
        }
      }
    }

    drawPolygon(
      metrics.map((m) => m.normalizedAverage).toList(),
      averageColor,
      fill: false,
      drawPoints: true,
    );
    drawPolygon(
      metrics.map((m) => m.normalizedValue).toList(),
      playerColor,
      fill: true,
      drawPoints: true,
    );
  }

  @override
  bool shouldRepaint(covariant _PlayerSpiderPainter oldDelegate) {
    return oldDelegate.metrics != metrics ||
        oldDelegate.playerColor != playerColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.averageColor != averageColor ||
        oldDelegate.hoveredIndex != hoveredIndex;
  }
}
