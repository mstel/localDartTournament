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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        cardTheme: theme.cardTheme.copyWith(
          color: const Color(0xD914202B),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: ExcludeSemantics(
              child: Image(
                image: AssetImage('assets/images/christmas_theme.png'),
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
          ),
          const Positioned.fill(
            child: ExcludeSemantics(
              child: ColoredBox(color: Color(0x70030A0E)),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(child: _ChristmasSnowfall()),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ChristmasSnowfall extends StatefulWidget {
  const _ChristmasSnowfall();

  @override
  State<_ChristmasSnowfall> createState() => _ChristmasSnowfallState();
}

class _ChristmasSnowfallState extends State<_ChristmasSnowfall>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      key: const ValueKey('christmas-snowfall'),
      painter: _SnowfallPainter(_progress),
    ),
  );
}

class _SnowfallPainter extends CustomPainter {
  const _SnowfallPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  static const _flakeCount = 52;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final phase = progress.value;
    for (var index = 0; index < _flakeCount; index++) {
      final y = (index / _flakeCount + phase) % 1;
      final baseX = ((index * 73) % 101) / 100;
      final sway =
          math.sin((phase + index / _flakeCount) * math.pi * 2) * 0.012;
      final opacity = 0.28 + (index % 4) * 0.08;
      final radius = 1.1 + (index % 3) * 0.55;
      paint.color = Color.fromRGBO(255, 255, 255, opacity);
      canvas.drawCircle(
        Offset((baseX + sway) * size.width, y * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SnowfallPainter oldDelegate) => false;
}
