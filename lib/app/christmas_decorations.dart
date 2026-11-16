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
                image: AssetImage('assets/images/christmas_winter_forest.jpg'),
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
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 128,
            child: ExcludeSemantics(
              child: Image(
                image: AssetImage('assets/images/christmas_garland.jpg'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          const Positioned(
            top: 80,
            left: 0,
            right: 0,
            height: 52,
            child: ExcludeSemantics(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0x70030A0E)],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
