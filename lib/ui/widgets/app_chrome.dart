import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Platform window chrome adjustments.
class AppChrome {
  /// macOS: the title bar is transparent and content runs under it
  /// (MainFlutterWindow.swift). Reserve its height as a top safe-area inset so
  /// SafeArea / AppBar keep content clear of the traffic-light buttons while
  /// backgrounds (rail, surfaces) extend to the top edge.
  static const macTitleBarInset = 28.0;

  static Widget wrap(BuildContext context, Widget child) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    final mq = MediaQuery.of(context);
    EdgeInsets top(EdgeInsets e) => e.copyWith(top: e.top < macTitleBarInset ? macTitleBarInset : e.top);
    return MediaQuery(
      data: mq.copyWith(padding: top(mq.padding), viewPadding: top(mq.viewPadding)),
      child: child,
    );
  }
}
