import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme_controller.dart';

class ChristmasSecondScreenBackground extends StatelessWidget {
  const ChristmasSecondScreenBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppThemeStyle>(
    valueListenable: AppThemeController.instance.themeStyleNotifier,
    builder: (context, style, _) => style == AppThemeStyle.christmas
        ? ChristmasDecorations(child: child)
        : child,
  );
}

class ChristmasDecorations extends StatelessWidget {
  const ChristmasDecorations({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const Positioned.fill(
        child: ExcludeSemantics(
          child: CustomPaint(painter: _WinterBackgroundPainter()),
        ),
      ),
      child,
    ],
  );
}

class _WinterBackgroundPainter extends CustomPainter {
  const _WinterBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF06131A), Color(0xFF0B2028), Color(0xFF142A31)],
          stops: [0, .58, 1],
        ).createShader(bounds),
    );

    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFFB88A4A).withValues(alpha: .18),
              const Color(0xFFB88A4A).withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * .5, size.height * .84),
              radius: size.width * .42,
            ),
          );
    canvas.drawRect(bounds, glow);
    _drawStars(canvas, size);
    _drawForest(canvas, size);
    _drawSnowLine(canvas, size);
    _drawGarland(canvas, size);
  }

  void _drawStars(Canvas canvas, Size size) {
    for (var index = 0; index < 115; index++) {
      final x = (index * 97.31 + 19) % size.width;
      final y = (index * 53.73 + 65) % (size.height * .82);
      final radius = .45 + (index % 4) * .22;
      final opacity = .22 + (index % 5) * .08;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = const Color(0xFFE6F0EE).withValues(alpha: opacity),
      );
    }
  }

  void _drawForest(Canvas canvas, Size size) {
    final treePaint = Paint()
      ..color = const Color(0xFF07151A).withValues(alpha: .8);
    final snowPaint = Paint()
      ..color = const Color(0xFFB5C9C6).withValues(alpha: .28);
    final scale = (size.width / 1200).clamp(.45, 1.4);
    for (var index = 0; index < 12; index++) {
      final side = index.isEven ? 0.0 : 1.0;
      final localIndex = index ~/ 2;
      final x = side == 0
          ? 14 + localIndex * 25 * scale
          : size.width - 14 - localIndex * 25 * scale;
      final height = (size.height * (.13 + (localIndex % 4) * .028)).clamp(
        34.0,
        size.height * .28,
      );
      final top = size.height - height * .38;
      final halfWidth = height * .32;
      final path = Path()
        ..moveTo(x, top - height * .62)
        ..lineTo(x - halfWidth, top + height * .34)
        ..lineTo(x - halfWidth * .4, top + height * .2)
        ..lineTo(x - halfWidth * 1.2, top + height * .7)
        ..lineTo(x + halfWidth * 1.2, top + height * .7)
        ..lineTo(x + halfWidth * .4, top + height * .2)
        ..lineTo(x + halfWidth, top + height * .34)
        ..close();
      canvas.drawPath(path, treePaint);
      final snowPath = Path()
        ..moveTo(x, top - height * .62)
        ..lineTo(x - halfWidth * .24, top - height * .08)
        ..lineTo(x - halfWidth * .06, top - height * .02)
        ..lineTo(x + halfWidth * .1, top - height * .3)
        ..lineTo(x + halfWidth * .3, top - height * .08)
        ..close();
      canvas.drawPath(snowPath, snowPaint);
    }
  }

  void _drawSnowLine(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .93)
      ..quadraticBezierTo(
        size.width * .25,
        size.height * .84,
        size.width * .47,
        size.height * .92,
      )
      ..quadraticBezierTo(
        size.width * .72,
        size.height * .99,
        size.width,
        size.height * .88,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFB6C5C2).withValues(alpha: .12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE8F0EC).withValues(alpha: .24),
    );
  }

  void _drawGarland(Canvas canvas, Size size) {
    final wirePaint = Paint()
      ..color = const Color(0xFF315444)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final garland = Path()..moveTo(0, 4);
    for (var x = 0.0; x < size.width; x += size.width / 6) {
      garland.quadraticBezierTo(x + size.width / 12, 33, x + size.width / 6, 4);
    }
    canvas.drawPath(garland, wirePaint);

    for (var index = 0; index < 40; index++) {
      final progress = index / 39;
      final x = progress * size.width;
      final y = 4 + math.sin(progress * math.pi * 12) * 13 + 13;
      final color = switch (index % 3) {
        0 => const Color(0xFFFFC96B),
        1 => const Color(0xFFFFE6A3),
        _ => const Color(0xFFF3AC53),
      };
      final halo = Paint()..color = color.withValues(alpha: .16);
      canvas.drawCircle(Offset(x, y), 10, halo);
      canvas.drawCircle(Offset(x, y), 2.2, Paint()..color = color);
      canvas.drawLine(
        Offset(x, y - 2),
        Offset(x, y - 5),
        Paint()
          ..color = const Color(0xFF536F54)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_WinterBackgroundPainter oldDelegate) => false;
}
