import 'package:flutter/material.dart';

import '../../../data/currency.dart';
import '../../theme/semantic.dart';

/// Bottom sheet: common currencies as chips + search over the full list.
Future<String?> pickCurrency(BuildContext context, {required String selected}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _CurrencySheet(selected: selected),
);

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.selected});
  final String selected;

  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final matches = Currency.all
        .where((c) => q.isEmpty || c.code.toLowerCase().contains(q) || c.name.toLowerCase().contains(q))
        .toList();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Currency', style: context.tt.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in Currency.common)
                    ChoiceChip(
                      label: Text('${Currency.of(code).symbol} $code'),
                      selected: code == widget.selected,
                      onSelected: (_) => Navigator.pop(context, code),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search currencies'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in matches)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(width: 40, child: Text(c.symbol, style: context.tt.titleMedium)),
                        title: Text(c.name),
                        trailing: Text(c.code),
                        selected: c.code == widget.selected,
                        onTap: () => Navigator.pop(context, c.code),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
