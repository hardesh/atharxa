import 'package:flutter/material.dart';

import '../theme/semantic.dart';

/// Small rounded label ("Online", "soon", "Done").
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.fg, this.bg, this.small = false});

  final String label;
  final Color? fg, bg;

  /// Compact variant used inline next to tab labels.
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
    decoration: BoxDecoration(
      color: bg ?? context.cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(small ? 8 : 6),
    ),
    child: Text(
      label,
      style: context.tt.labelMedium?.copyWith(color: fg ?? context.cs.onSurfaceVariant, fontSize: small ? 10 : null),
    ),
  );
}
