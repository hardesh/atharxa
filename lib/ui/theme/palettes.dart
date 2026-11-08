import 'package:flutter/material.dart';

/// The three shipped themes (DESIGN.md §3.1). Forest is the first-launch default.
enum AppPalette {
  forest('Forest'),
  teal('Teal'),
  ocean('Ocean');

  const AppPalette(this.label);
  final String label;

  static AppPalette parse(String? v) =>
      AppPalette.values.firstWhere((p) => p.name == v, orElse: () => AppPalette.forest);
}

/// Built explicitly from the spec's hex values — never `fromSeed` (it drifts).
ColorScheme schemeFor(AppPalette p, Brightness b) {
  final dark = b == Brightness.dark;
  final c = switch ((p, dark)) {
    (AppPalette.forest, false) => const _Roles(
      primary: 0xFF4C662B,
      onPrimary: 0xFFFFFFFF,
      primaryContainer: 0xFFCDEDA3,
      onPrimaryContainer: 0xFF102000,
      secondaryContainer: 0xFFDCE7C8,
      onSecondaryContainer: 0xFF151E0B,
      surface: 0xFFF9FAEF,
      low: 0xFFEEEFE3,
      mid: 0xFFE8E9DE,
      high: 0xFFE0E2D6,
      onSurface: 0xFF1A1C16,
      onSurfaceVariant: 0xFF44483D,
      outline: 0xFF75796C,
      outlineVariant: 0xFFC5C8BA,
    ),
    (AppPalette.forest, true) => const _Roles(
      primary: 0xFFB1D18A,
      onPrimary: 0xFF1F3701,
      primaryContainer: 0xFF354E16,
      onPrimaryContainer: 0xFFCDEDA3,
      secondaryContainer: 0xFF404A33,
      onSecondaryContainer: 0xFFDCE7C8,
      surface: 0xFF11140E,
      low: 0xFF1A1D16,
      mid: 0xFF1E211A,
      high: 0xFF282B24,
      onSurface: 0xFFE2E3D8,
      onSurfaceVariant: 0xFFC5C8BA,
      outline: 0xFF8F9285,
      outlineVariant: 0xFF44483D,
    ),
    (AppPalette.teal, false) => const _Roles(
      primary: 0xFF00695C,
      onPrimary: 0xFFFFFFFF,
      primaryContainer: 0xFFA5F2E4,
      onPrimaryContainer: 0xFF00201C,
      secondaryContainer: 0xFFCDE8E2,
      onSecondaryContainer: 0xFF06201C,
      surface: 0xFFF4FBF8,
      low: 0xFFEAF2EF,
      mid: 0xFFE3EBE8,
      high: 0xFFD9E2DF,
      onSurface: 0xFF161D1B,
      onSurfaceVariant: 0xFF3F4946,
      outline: 0xFF6F7976,
      outlineVariant: 0xFFBEC9C5,
    ),
    (AppPalette.teal, true) => const _Roles(
      primary: 0xFF83D5C6,
      onPrimary: 0xFF003731,
      primaryContainer: 0xFF005047,
      onPrimaryContainer: 0xFFA1F1E2,
      secondaryContainer: 0xFF324B47,
      onSecondaryContainer: 0xFFCDE8E2,
      surface: 0xFF0E1513,
      low: 0xFF171D1B,
      mid: 0xFF1B2220,
      high: 0xFF262D2B,
      onSurface: 0xFFDDE4E1,
      onSurfaceVariant: 0xFFBEC9C5,
      outline: 0xFF899390,
      outlineVariant: 0xFF3F4946,
    ),
    (AppPalette.ocean, false) => const _Roles(
      primary: 0xFF0061A4,
      onPrimary: 0xFFFFFFFF,
      primaryContainer: 0xFFD1E4FF,
      onPrimaryContainer: 0xFF001D36,
      secondaryContainer: 0xFFD7E3F7,
      onSecondaryContainer: 0xFF101C2B,
      surface: 0xFFFDFCFF,
      low: 0xFFEFF0F5,
      mid: 0xFFE9EAEF,
      high: 0xFFE1E2E8,
      onSurface: 0xFF1A1C1E,
      onSurfaceVariant: 0xFF43474E,
      outline: 0xFF73777F,
      outlineVariant: 0xFFC3C7CF,
    ),
    (AppPalette.ocean, true) => const _Roles(
      primary: 0xFF9ECAFF,
      onPrimary: 0xFF003258,
      primaryContainer: 0xFF00497D,
      onPrimaryContainer: 0xFFD1E4FF,
      secondaryContainer: 0xFF3B4858,
      onSecondaryContainer: 0xFFD7E3F7,
      surface: 0xFF111418,
      low: 0xFF1A1C20,
      mid: 0xFF1E2024,
      high: 0xFF282A2E,
      onSurface: 0xFFE2E2E6,
      onSurfaceVariant: 0xFFC3C7CF,
      outline: 0xFF8D9199,
      outlineVariant: 0xFF43474E,
    ),
  };
  Color k(int v) => Color(v);
  return ColorScheme(
    brightness: b,
    primary: k(c.primary),
    onPrimary: k(c.onPrimary),
    primaryContainer: k(c.primaryContainer),
    onPrimaryContainer: k(c.onPrimaryContainer),
    // The spec doesn't define secondary/tertiary accents; derive from primary roles.
    secondary: k(c.primary),
    onSecondary: k(c.onPrimary),
    secondaryContainer: k(c.secondaryContainer),
    onSecondaryContainer: k(c.onSecondaryContainer),
    tertiary: k(c.primary),
    onTertiary: k(c.onPrimary),
    error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    onError: dark ? const Color(0xFF690005) : const Color(0xFFFFFFFF),
    errorContainer: dark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
    onErrorContainer: dark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
    surface: k(c.surface),
    onSurface: k(c.onSurface),
    onSurfaceVariant: k(c.onSurfaceVariant),
    surfaceContainerLowest: k(c.surface),
    surfaceContainerLow: k(c.low),
    surfaceContainer: k(c.mid),
    surfaceContainerHigh: k(c.high),
    surfaceContainerHighest: k(c.high),
    outline: k(c.outline),
    outlineVariant: k(c.outlineVariant),
    inverseSurface: dark ? const Color(0xFFE2E3D8) : const Color(0xFF2B3230),
    onInverseSurface: dark ? const Color(0xFF2B3230) : const Color(0xFFECF2EF),
    inversePrimary: k(c.primaryContainer),
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

class _Roles {
  const _Roles({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.surface,
    required this.low,
    required this.mid,
    required this.high,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
  });

  final int primary, onPrimary, primaryContainer, onPrimaryContainer, secondaryContainer, onSecondaryContainer;
  final int surface, low, mid, high, onSurface, onSurfaceVariant, outline, outlineVariant;
}
