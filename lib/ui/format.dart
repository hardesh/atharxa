import 'package:intl/intl.dart';

import '../data/models.dart';

final _int = NumberFormat('#,##0', 'en_US');
final _one = NumberFormat('#,##0.0', 'en_US');
final _hm = DateFormat.Hm();
final _dayShort = DateFormat('EEE d MMM');
final _weekday = DateFormat('E');

/// kcal and ml: integers with grouping ("1,498").
String fmtInt(num v) => _int.format(v.round());

/// Macros: one decimal ("65.9"). `null` (unknown) renders as an em dash.
String fmtMacro(double? v) => v == null ? '—' : _one.format(v);

/// Grams typed by the user: no trailing ".0".
String fmtGrams(double g) => g == g.roundToDouble() ? _int.format(g) : _one.format(g);

/// "227 kcal · Protein 7.9 g · Carbs 40.6 g · Fiber 6.1 g · Fat 3.9 g" (DESIGN.md §4).
String nutrientLine(Nutrients n) =>
    '${fmtInt(n.kcal)} kcal · Protein ${fmtMacro(n.protein)} g · '
    'Carbs ${fmtMacro(n.carbs)} g · Fiber ${fmtMacro(n.fiber)} g · Fat ${fmtMacro(n.fat)} g';

String relativeDay(DateTime d) {
  final today = DateTime.now();
  final a = DateTime(today.year, today.month, today.day);
  final b = DateTime(d.year, d.month, d.day);
  final diff = b.difference(a).inDays;
  final date = DateFormat('d MMM').format(d);
  return switch (diff) {
    0 => 'Today, $date',
    -1 => 'Yesterday, $date',
    1 => 'Tomorrow, $date',
    _ => '${DateFormat('EEE').format(d)}, $date',
  };
}

/// "19:29".
String fmtTime(DateTime t) => _hm.format(t);

/// "Sun 8 Nov".
String fmtDayShort(DateTime d) => _dayShort.format(d);

/// "S" — first letter of the weekday (chart labels).
String fmtWeekdayInitial(DateTime d) => _weekday.format(d).substring(0, 1);

/// "today, 13:12" / "yesterday, 08:05" / "Sun 8 Nov, 13:12".
String fmtWhen(DateTime t) {
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  final day = switch (days) {
    0 => 'today',
    1 => 'yesterday',
    _ => fmtDayShort(t),
  };
  return '$day, ${fmtTime(t)}';
}

/// "November 2026".
String fmtMonth(DateTime d) => DateFormat('MMMM yyyy').format(d);
