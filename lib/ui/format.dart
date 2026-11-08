import 'package:intl/intl.dart';

import '../data/models.dart';

final _int = NumberFormat('#,##0', 'en_US');
final _one = NumberFormat('#,##0.0', 'en_US');

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
