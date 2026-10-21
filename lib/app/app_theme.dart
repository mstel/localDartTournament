import 'package:flutter/material.dart';

/// Club-inspired color palette for DC Unzenberg/Heinzenbach.
ThemeData buildDartTournamentTheme() => _buildTheme(isDark: false);

ThemeData buildDartTournamentDarkTheme() => _buildTheme(isDark: true);

ThemeData _buildTheme({required bool isDark}) {
  final ink = isDark ? const Color(0xFFF5F3ED) : const Color(0xFF191B20);
  final gold = isDark ? const Color(0xFFD49B44) : const Color(0xFFB5811E);
  final bg = isDark ? const Color(0xFF121316) : const Color(0xFFF7F5F0);
  final surface = isDark ? const Color(0xFF1B1D24) : const Color(0xFFFFFFFF);
  final surfaceSecondary = isDark
      ? const Color(0xFF242731)
      : const Color(0xFFF1EFEA);

  final scheme =
      (isDark
              ? ColorScheme.fromSeed(
                  seedColor: gold,
                  brightness: Brightness.dark,
                )
              : ColorScheme.fromSeed(
                  seedColor: gold,
                  brightness: Brightness.light,
                ))
          .copyWith(
            primary: gold,
            onPrimary: isDark ? const Color(0xFF121316) : Colors.white,
            primaryContainer: isDark
                ? const Color(0xFF382B14)
                : const Color(0xFFFCEECF),
            onPrimaryContainer: isDark
                ? const Color(0xFFFDE8B5)
                : const Color(0xFF281C03),
            secondary: isDark
                ? const Color(0xFFB0B4C0)
                : const Color(0xFF2D323E),
            onSecondary: isDark ? const Color(0xFF121316) : Colors.white,
            secondaryContainer: surfaceSecondary,
            surface: surface,
            onSurface: ink,
            onSurfaceVariant: isDark
                ? const Color(0xFFA5AAB7)
                : const Color(0xFF5B606D),
            outline: isDark ? const Color(0xFF3E4351) : const Color(0xFF757065),
            outlineVariant: isDark
                ? const Color(0xFF2A2E38)
                : const Color(0xFFE2DDD2),
          );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: isDark ? Brightness.dark : Brightness.light,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.45),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: ink,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: rounded.copyWith(side: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: gold, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      iconColor: gold,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide.none,
      backgroundColor: scheme.secondaryContainer,
      selectedColor: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xFF282C36)
          : const Color(0xFF191B20),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: Colors.white,
      ),
      actionTextColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 24),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(scheme.secondaryContainer),
      headingTextStyle: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      dividerThickness: .6,
      horizontalMargin: 20,
      columnSpacing: 28,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: gold,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      textStyle: base.textTheme.bodyLarge?.copyWith(color: ink),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: gold,
      collapsedIconColor: scheme.onSurfaceVariant,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: gold),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C36) : const Color(0xFF191B20),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
    ),
  );
}
