import 'package:flutter/material.dart';

import 'palettes.dart';
import 'semantic.dart';

/// Builds the full ThemeData for a palette + brightness (DESIGN.md §3).
ThemeData buildTheme(AppPalette palette, Brightness brightness) {
  final s = schemeFor(palette, brightness);
  final text = _textTheme(s);
  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    fontFamily: 'Roboto',
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    extensions: [Semantic.of(palette, s)],
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: s.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
    ),
    // Cards are flat tonal surfaces (surfaceContainerLow), radius 16.
    cardTheme: CardThemeData(
      color: s.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: text.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLow,
      showDragHandle: true,
      dragHandleColor: s.outline,
      dragHandleSize: const Size(32, 4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: s.outline),
      labelStyle: text.labelLarge?.copyWith(color: s.onSurfaceVariant),
      selectedColor: s.secondaryContainer,
      secondarySelectedColor: s.secondaryContainer,
      backgroundColor: Colors.transparent,
      checkmarkColor: s.onSecondaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: s.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: s.primary, width: 2),
      ),
      suffixStyle: text.bodyLarge?.copyWith(color: s.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: pill,
        side: BorderSide(color: s.outline),
        minimumSize: const Size(64, 40),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(40, 40), foregroundColor: s.onSurfaceVariant),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primaryContainer,
      foregroundColor: s.onPrimaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: s.secondaryContainer,
        selectedForegroundColor: s.onSecondaryContainer,
        side: BorderSide(color: s.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: s.surfaceContainer,
      indicatorColor: s.secondaryContainer,
      surfaceTintColor: Colors.transparent,
      height: 80,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => text.labelMedium?.copyWith(color: st.contains(WidgetState.selected) ? s.onSurface : s.onSurfaceVariant),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: s.surfaceContainerLow,
      indicatorColor: s.secondaryContainer,
      selectedIconTheme: IconThemeData(color: s.onSecondaryContainer),
      unselectedIconTheme: IconThemeData(color: s.onSurfaceVariant),
      selectedLabelTextStyle: text.labelMedium?.copyWith(color: s.onSurface),
      unselectedLabelTextStyle: text.labelMedium?.copyWith(color: s.onSurfaceVariant),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: s.primary,
      unselectedLabelColor: s.onSurfaceVariant,
      indicatorColor: s.primary,
      dividerColor: s.outlineVariant,
      labelStyle: text.titleSmall,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: s.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface),
      actionTextColor: s.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: s.onSurfaceVariant,
      titleTextStyle: text.bodyLarge?.copyWith(color: s.onSurface),
      subtitleTextStyle: text.bodySmall,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? s.onPrimary : s.outline),
      trackColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected) ? s.primary : s.surfaceContainerHigh,
      ),
    ),
  );
}

const _tab = [FontFeature.tabularFigures()];

/// t0 headline · t1 title-large · t2 title-medium · t3 title-small · bd body · sm label-small · dl display.
TextTheme _textTheme(ColorScheme s) {
  TextStyle st(double size, double line, FontWeight w, [Color? c]) => TextStyle(
    fontFamily: 'Roboto',
    fontSize: size,
    height: line / size,
    fontWeight: w,
    color: c ?? s.onSurface,
    fontFeatures: _tab,
    letterSpacing: 0,
  );
  return TextTheme(
    displaySmall: st(36, 44, FontWeight.w400), // dl
    headlineMedium: st(28, 36, FontWeight.w400), // t0
    headlineSmall: st(24, 32, FontWeight.w400),
    titleLarge: st(22, 28, FontWeight.w400), // t1
    titleMedium: st(16, 24, FontWeight.w500), // t2
    titleSmall: st(14, 20, FontWeight.w500), // t3
    bodyLarge: st(16, 24, FontWeight.w400),
    bodyMedium: st(14, 20, FontWeight.w400), // bd
    bodySmall: st(12, 16, FontWeight.w400, s.onSurfaceVariant), // sm
    labelLarge: st(14, 20, FontWeight.w500),
    labelMedium: st(12, 16, FontWeight.w500),
    labelSmall: st(11, 16, FontWeight.w500),
  );
}
