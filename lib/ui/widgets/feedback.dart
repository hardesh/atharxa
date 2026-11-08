import 'package:flutter/material.dart';

import '../theme/semantic.dart';

/// Snackbar with an Undo action (sits above the nav bar — floating behaviour).
void showUndo(BuildContext context, String message, Future<void> Function() undo) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Undo', onPressed: () => undo()),
    ),
  );
}

void showMessage(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(message)));
}

/// Calm empty state: icon, title, one line of help, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: context.cs.secondaryContainer,
            foregroundColor: context.cs.onSecondaryContainer,
            child: Icon(icon, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, style: context.tt.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: context.tt.bodyMedium?.copyWith(color: context.cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Confirmation dialog built into the page (returns true on confirm).
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: ctx.cs.error, foregroundColor: ctx.cs.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}
