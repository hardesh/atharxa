import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/workout_repo.dart';
import '../../../services/file_saver.dart';
import '../../../services/workout_share.dart';
import '../../../state/core_providers.dart';
import '../../theme/semantic.dart';
import '../../widgets/feedback.dart';

/// Share one or more plans: copy a chat-friendly message, or save a file.
Future<void> sharePlans(BuildContext context, List<WorkoutPlan> plans) => showModalBottomSheet<void>(
  context: context,
  builder: (sheet) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            plans.length == 1 ? 'Share “${plans.single.name}”' : 'Share ${plans.length} plans',
            style: sheet.tt.titleLarge,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.copy_outlined),
          title: const Text('Copy to share'),
          subtitle: const Text('Paste it in WhatsApp, Messages or email. They import it from Workout › Import.'),
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: WorkoutShare.encodeMessage(plans)));
            if (!sheet.mounted) return;
            Navigator.pop(sheet);
            showMessage(context, 'Copied — paste it in a message');
          },
        ),
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: const Text('Save as file'),
          subtitle: Text(WorkoutShare.fileName(plans)),
          onTap: () async {
            final where = await saveExportedFile(
              WorkoutShare.fileName(plans),
              Uint8List.fromList(WorkoutShare.encodeJson(plans).codeUnits),
            );
            if (!sheet.mounted) return;
            Navigator.pop(sheet);
            if (where != null) showMessage(context, 'Saved to $where');
          },
        ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

/// Import plans from pasted text (any platform) or a file (Mac).
Future<void> showImportPlans(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ImportDialog());

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog();

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    try {
      final drafts = WorkoutShare.decode(_text.text);
      final names = await WorkoutShare.import(ref.read(dbProvider), drafts);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Added ${names.join(', ')}');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Import workout plans'),
    scrollable: true,
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paste the message someone shared with you.', style: context.tt.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(labelText: 'Shared plan', errorText: _error, errorMaxLines: 3),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) setState(() => _text.text = data!.text!);
                },
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final text = await openTextFile();
                  if (text != null) setState(() => _text.text = text);
                },
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Open file…'),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _text.text.trim().isEmpty ? null : _import, child: const Text('Import')),
    ],
  );
}
