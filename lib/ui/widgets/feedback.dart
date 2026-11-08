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

/// Single text-field dialog (name, IP address, custom amount…). Returns the
/// trimmed text, or null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String? hint,
  String? message,
  String? suffix,
  String confirmLabel = 'Save',
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.none,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(
    title: title,
    label: label,
    initial: initial,
    hint: hint,
    message: message,
    suffix: suffix,
    confirmLabel: confirmLabel,
    keyboardType: keyboardType,
    capitalization: capitalization,
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    required this.capitalization,
    this.hint,
    this.message,
    this.suffix,
    this.keyboardType,
  });

  final String title, label, initial, confirmLabel;
  final String? hint, message, suffix;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _c.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.message != null) ...[Text(widget.message!, style: context.tt.bodySmall), const SizedBox(height: 12)],
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.capitalization,
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, suffixText: widget.suffix),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}
