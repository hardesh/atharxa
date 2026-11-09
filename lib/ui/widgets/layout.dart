import 'package:flutter/material.dart';

/// ≥ 600 dp → rail layout (foldables, tablets, Mac window). DESIGN.md §2.
const wideBreakpoint = 600.0;

/// Content column max width (DESIGN.md §2), excluding side padding.
const contentMaxWidth = 760.0;

extension LayoutContext on BuildContext {
  bool get isWide => MediaQuery.sizeOf(this).width >= wideBreakpoint;

  /// Room for labelled header buttons (Mac window, large tablets).
  bool get isRoomy => MediaQuery.sizeOf(this).width >= 900;
  double get screenPad => isWide ? 32 : 16;
  double get cardGap => isWide ? 16 : 12;
}

/// Scrollable page content: centred column, max 760 dp, 16/32 side padding,
/// 12/16 gap between children.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.bottomPadding = 24, this.controller});

  final List<Widget> children;
  final double bottomPadding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final gap = context.cardGap;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth + 2 * context.screenPad),
        child: ListView.separated(
          controller: controller,
          padding: EdgeInsets.fromLTRB(context.screenPad, 4, context.screenPad, bottomPadding),
          itemCount: children.length,
          separatorBuilder: (_, _) => SizedBox(height: gap),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    );
  }
}

/// Flat tonal card (surfaceContainerLow, radius 16, padding 16).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}
