import 'package:flutter/material.dart';

import 'palettes.dart';

/// Colours that aren't Material roles (DESIGN.md §3.1 "Semantic colours").
@immutable
class Semantic extends ThemeExtension<Semantic> {
  const Semantic({
    required this.protein,
    required this.carbs,
    required this.fiber,
    required this.fat,
    required this.water,
    required this.waterContainer,
    required this.income,
    required this.expense,
    required this.success,
    required this.successContainer,
    required this.track,
  });

  final Color protein, carbs, fiber, fat, water, waterContainer, income, expense, success, successContainer;

  /// Bar track used inside the primary-container summary card.
  final Color track;

  factory Semantic.of(AppPalette p, ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    final ocean = p == AppPalette.ocean;
    return Semantic(
      protein: s.primary,
      carbs: dark ? const Color(0xFFFFB95E) : const Color(0xFFA35F00),
      fiber: switch ((dark, ocean)) {
        (false, false) => const Color(0xFF3566BC),
        (false, true) => const Color(0xFF6B4FA0),
        (true, false) => const Color(0xFFAAC7FF),
        (true, true) => const Color(0xFFD4BBFF),
      },
      fat: dark ? const Color(0xFFF4AED6) : const Color(0xFF9C3F7A),
      water: switch ((dark, ocean)) {
        (false, false) => const Color(0xFF1A5FC2),
        (false, true) => const Color(0xFF00677D),
        (true, false) => const Color(0xFFADC6FF),
        (true, true) => const Color(0xFF5DD5F9),
      },
      waterContainer: switch ((dark, ocean)) {
        (false, false) => const Color(0xFFD8E2FF),
        (false, true) => const Color(0xFFB4EBFF),
        (true, false) => const Color(0xFF00458F),
        (true, true) => const Color(0xFF004E5F),
      },
      income: dark ? const Color(0xFF8AD89B) : const Color(0xFF1B6D2F),
      expense: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      success: dark ? const Color(0xFF8AD89B) : const Color(0xFF1B6D2F),
      successContainer: dark ? const Color(0xFF0F5223) : const Color(0xFFC3EFC9),
      track: dark ? Colors.white.withValues(alpha: .16) : s.onPrimaryContainer.withValues(alpha: .14),
    );
  }

  @override
  Semantic copyWith() => this;

  @override
  Semantic lerp(Semantic? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Semantic(
      protein: l(protein, other.protein),
      carbs: l(carbs, other.carbs),
      fiber: l(fiber, other.fiber),
      fat: l(fat, other.fat),
      water: l(water, other.water),
      waterContainer: l(waterContainer, other.waterContainer),
      income: l(income, other.income),
      expense: l(expense, other.expense),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      track: l(track, other.track),
    );
  }
}

extension SemanticContext on BuildContext {
  Semantic get sem => Theme.of(this).extension<Semantic>()!;
  ColorScheme get cs => Theme.of(this).colorScheme;
  TextTheme get tt => Theme.of(this).textTheme;
}
