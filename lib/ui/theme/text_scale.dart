import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// App-level text size (DESIGN.md §3.2): multiplies the system scale, clamps the
/// total at 2.0, and scales large styles (≥ 20 px: headline, title-large,
/// display) by only half as much — 130 % → ×1.15 — like Android 14's
/// non-linear scaling.
class AppTextScaler extends TextScaler {
  const AppTextScaler({required this.system, required this.userFactor});

  final TextScaler system;
  final double userFactor;

  static const largeThreshold = 20.0;
  static const maxTotal = 2.0;

  @override
  double scale(double fontSize) {
    final sys = system.scale(fontSize) / (fontSize == 0 ? 1 : fontSize);
    final total = math.min(sys * userFactor, maxTotal);
    final f = fontSize >= largeThreshold ? 1 + (total - 1) / 2 : total;
    return fontSize * f;
  }

  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) => other is AppTextScaler && other.system == system && other.userFactor == userFactor;

  @override
  int get hashCode => Object.hash(system, userFactor);
}

/// Wraps [child] so all descendant text uses the app text-size setting.
class AppTextScale extends StatelessWidget {
  const AppTextScale({super.key, required this.factor, required this.child});

  final double factor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: AppTextScaler(system: mq.textScaler, userFactor: factor),
      ),
      child: child,
    );
  }
}

extension TextScaleContext on BuildContext {
  /// True when the effective body scale is large enough to need stacked layouts.
  bool get largeText => MediaQuery.textScalerOf(this).scale(14) / 14 > 1.2;
}
