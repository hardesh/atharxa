import 'package:atharxa/ui/theme/app_theme.dart';
import 'package:atharxa/ui/theme/palettes.dart';
import 'package:atharxa/ui/theme/semantic.dart';
import 'package:atharxa/ui/theme/text_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('palettes use the exact spec values', () {
    expect(schemeFor(AppPalette.forest, Brightness.light).primary, const Color(0xFF4C662B));
    expect(schemeFor(AppPalette.teal, Brightness.dark).primary, const Color(0xFF83D5C6));
    expect(schemeFor(AppPalette.ocean, Brightness.light).surfaceContainerLow, const Color(0xFFEFF0F5));
    expect(AppPalette.parse(null), AppPalette.forest);
  });

  test('every theme builds with semantic colours (Ocean overrides fiber/water)', () {
    for (final p in AppPalette.values) {
      for (final b in Brightness.values) {
        expect(buildTheme(p, b).extension<Semantic>(), isNotNull);
      }
    }
    final ocean = buildTheme(AppPalette.ocean, Brightness.light).extension<Semantic>()!;
    expect(ocean.fiber, const Color(0xFF6B4FA0));
    expect(ocean.water, const Color(0xFF00677D));
  });

  test('text scaler: body ×1.3, large styles ×1.15, total clamped at 2.0', () {
    const s = AppTextScaler(system: TextScaler.noScaling, userFactor: 1.3);
    expect(s.scale(14), closeTo(18.2, 1e-9));
    expect(s.scale(36), closeTo(41.4, 1e-9));
    const big = AppTextScaler(system: TextScaler.linear(1.8), userFactor: 1.5);
    expect(big.scale(14), closeTo(28, 1e-9));
  });
}
