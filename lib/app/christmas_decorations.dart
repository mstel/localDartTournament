import 'dart:math' as math;

import 'package:flutter/material.dart';

class ChristmasDecorations extends StatefulWidget {
  const ChristmasDecorations({super.key, required this.child});

  final Widget child;

  @override
  State<ChristmasDecorations> createState() => _ChristmasDecorationsState();
}

class _ChristmasDecorationsState extends State<ChristmasDecorations>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _snow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _snow,
              builder: (context, _) =>
                  CustomPaint(painter: _SnowfallPainter(_snow.value)),
            ),
          ),
        ),
      ),
      const Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 20,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: CustomPaint(painter: _LightsPainter()),
          ),
        ),
      ),
      const Positioned(
        top: 1,
        right: 12,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xE6234D36),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xCCFFD166)),
                ),
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🎅', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 4),
                    Text('🎄 🎁', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const Positioned(
        left: 12,
        bottom: 12,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xD9234D36),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xAAFFD166)),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text('🎁 🍪', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ),
      ),
      const Positioned(
        right: 14,
        bottom: 12,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0xD9234D36),
                borderRadius: BorderRadius.all(Radius.circular(12)),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xAAFFD166)),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text('🌲 🍬', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _SnowfallPainter extends CustomPainter {
  const _SnowfallPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..color = const Color(0xA6FFFFFF);
    for (var index = 0; index < 38; index++) {
      final phase = (progress + index * 0.173) % 1;
      final x =
          (index * 79.0 + math.sin((phase + index * 0.07) * math.pi * 2) * 18) %
          size.width;
      final y = (phase * size.height + index * 13.0) % size.height;
      canvas.drawCircle(Offset(x, y), 1 + (index % 3) * 0.55, paint);
    }
  }

  @override
  bool shouldRepaint(_SnowfallPainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _LightsPainter extends CustomPainter {
  const _LightsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wire = Paint()
      ..color = const Color(0xFF315D4A)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width / 2, 12, size.width, 0);
    canvas.drawPath(path, wire);
    const colors = [
      Color(0xFFFF5964),
      Color(0xFFFFD166),
      Color(0xFF65D58A),
      Color(0xFF78D8F5),
    ];
    for (var index = 0; index * 34 < size.width; index++) {
      final x = index * 34.0;
      final y = 2 + math.sin(index * 0.7) * 4;
      final bulb = Paint()..color = colors[index % colors.length];
      canvas.drawCircle(Offset(x, y), 3, bulb);
    }
  }

  @override
  bool shouldRepaint(_LightsPainter oldDelegate) => false;
}
