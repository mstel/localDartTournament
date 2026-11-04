import 'package:flutter/material.dart';

class TournamentDisplayPalette {
  const TournamentDisplayPalette._();

  static const background = Color(0xFF0D1318);
  static const card = Color(0xFF14202B);
  static const cardEmphasis = Color(0xFF1B2B38);
  static const border = Color(0xFF263D52);
  static const accent = Color(0xFFD49B44);
  static const text = Color(0xFFF1F3F5);
  static const mutedText = Color(0xFFBCC6CE);

  static TournamentDisplayColors forColorScheme(ColorScheme scheme) =>
      TournamentDisplayColors(
        background: scheme.surface,
        card: scheme.surfaceContainer,
        cardEmphasis: scheme.surfaceContainerHigh,
        border: scheme.outlineVariant,
        accent: scheme.brightness == Brightness.light
            ? Color.lerp(scheme.tertiary, scheme.onSurface, .22)!
            : scheme.tertiary,
        text: scheme.onSurface,
        mutedText: scheme.onSurfaceVariant,
      );
}

class TournamentDisplayColors {
  const TournamentDisplayColors({
    required this.background,
    required this.card,
    required this.cardEmphasis,
    required this.border,
    required this.accent,
    required this.text,
    required this.mutedText,
  });

  final Color background;
  final Color card;
  final Color cardEmphasis;
  final Color border;
  final Color accent;
  final Color text;
  final Color mutedText;
}
