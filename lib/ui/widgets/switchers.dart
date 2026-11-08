import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../format.dart';
import '../theme/semantic.dart';

/// ‹ "Today, 8 Nov" › — tap the label for a date picker.
class DateSwitcher extends StatelessWidget {
  const DateSwitcher({super.key, required this.date, required this.onChanged});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onChanged(date.subtract(const Duration(days: 1))),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: context.cs.onSurface),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (d != null) onChanged(d);
            },
            child: Text(
              relativeDay(date),
              style: context.tt.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onChanged(date.add(const Duration(days: 1))),
          ),
        ],
      ),
    );
  }
}

/// ‹ "November 2026" › for Finance.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged, this.trailing});

  /// Any day in the month; only year/month are used.
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          ),
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: context.tt.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}
