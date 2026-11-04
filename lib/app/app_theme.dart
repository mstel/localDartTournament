import 'package:flutter/material.dart';

/// Club-inspired color palette for DC Unzenberg/Heinzenbach.
ThemeData buildDartTournamentTheme({bool christmas = false}) =>
    _buildTheme(isDark: false, christmas: christmas);

ThemeData buildDartTournamentDarkTheme({bool christmas = false}) =>
    _buildTheme(isDark: true, christmas: christmas);

ThemeData _buildTheme({required bool isDark, required bool christmas}) {
  final ink = isDark ? const Color(0xFFF1F5F8) : const Color(0xFF15212B);
  final primary = christmas
      ? (isDark ? const Color(0xFFF0808B) : const Color(0xFFB52D43))
      : (isDark ? const Color(0xFF70C4E8) : const Color(0xFF1D648A));
  final bg = isDark ? const Color(0xFF0F1720) : const Color(0xFFF4F7FA);
  final surface = isDark ? const Color(0xFF16212B) : const Color(0xFFFFFFFF);
  final surfaceSecondary = isDark
      ? const Color(0xFF1D2D3A)
      : const Color(0xFFE9F0F5);
  final primaryContainer = christmas
      ? (isDark ? const Color(0xFF3A1D29) : const Color(0xFFFBE8EC))
      : (isDark ? const Color(0xFF19394B) : const Color(0xFFDCECF5));
  final onPrimaryContainer = christmas
      ? (isDark ? const Color(0xFFFFE7EA) : const Color(0xFF45101B))
      : (isDark ? const Color(0xFFC9EDFA) : const Color(0xFF163144));

  final scheme =
      (isDark
              ? ColorScheme.fromSeed(
                  seedColor: primary,
                  brightness: Brightness.dark,
                )
              : ColorScheme.fromSeed(
                  seedColor: primary,
                  brightness: Brightness.light,
                ))
          .copyWith(
            primary: primary,
            onPrimary: isDark ? const Color(0xFF0F1720) : Colors.white,
            primaryContainer: primaryContainer,
            onPrimaryContainer: onPrimaryContainer,
            secondary: christmas
                ? (isDark ? const Color(0xFF8BD7A8) : const Color(0xFF287548))
                : (isDark ? const Color(0xFFA9C6D6) : const Color(0xFF385D76)),
            onSecondary: isDark ? const Color(0xFF0F1720) : Colors.white,
            secondaryContainer: surfaceSecondary,
            surface: surface,
            onSurface: ink,
            onSurfaceVariant: isDark
                ? const Color(0xFFA8B8C3)
                : const Color(0xFF536674),
            outline: isDark ? const Color(0xFF405464) : const Color(0xFF718696),
            outlineVariant: isDark
                ? const Color(0xFF2D3F50)
                : const Color(0xFFD3DFE8),
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
        borderSide: BorderSide(color: primary, width: 2),
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
      iconColor: primary,
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
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
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
      labelColor: primary,
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
      iconColor: primary,
      collapsedIconColor: scheme.onSurfaceVariant,
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    tooltipTheme: TooltipThemeData(
      textStyle: TextStyle(
        color: isDark ? const Color(0xFFF5F3ED) : Colors.white,
        fontSize: 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C36) : const Color(0xFF191B20),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
    ),
  );
}
