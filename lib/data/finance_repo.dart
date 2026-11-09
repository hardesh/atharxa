import 'db.dart';

enum TxKind {
  expense('Expense'),
  income('Income');

  const TxKind(this.label);
  final String label;

  static TxKind parse(String? v) => v == 'income' ? TxKind.income : TxKind.expense;
}

/// A row of `transactions`. Amounts are in minor units of [currency].
class Tx {
  Tx(this.row);
  final Map<String, Object?> row;

  String get id => row['id'] as String;
  String get day => row['day'] as String;
  TxKind get kind => TxKind.parse(row['kind'] as String?);
  int get amountMinor => (row['amount_minor'] as num).toInt();
  String get currency => row['currency'] as String;
  String get category => row['category'] as String;
  String? get note => row['note'] as String?;

  /// +income / −expense, in minor units.
  int get signed => kind == TxKind.income ? amountMinor : -amountMinor;

  Map<String, Object?> fields() => AppDb.editable(row);
}

/// Totals for one currency.
class CurrencyTotals {
  CurrencyTotals(this.currency);
  final String currency;
  int income = 0, expense = 0, count = 0;
  int get balance => income - expense;
}

/// A month's transactions with per-currency totals and the category split
/// (in the default currency).
class MonthSummary {
  MonthSummary(this.transactions, this.defaultCurrency) {
    for (final t in transactions) {
      final c = totals.putIfAbsent(t.currency, () => CurrencyTotals(t.currency));
      c.count++;
      if (t.kind == TxKind.income) {
        c.income += t.amountMinor;
      } else {
        c.expense += t.amountMinor;
        if (t.currency == defaultCurrency) byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amountMinor;
      }
    }
  }

  final List<Tx> transactions;
  final String defaultCurrency;

  /// Per currency, no conversion (user decision).
  final Map<String, CurrencyTotals> totals = {};

  /// Expenses by category in the default currency, largest first.
  final Map<String, int> byCategory = {};

  CurrencyTotals get main => totals[defaultCurrency] ?? CurrencyTotals(defaultCurrency);

  /// Other currencies used this month.
  List<CurrencyTotals> get others => totals.values.where((t) => t.currency != defaultCurrency).toList();

  List<MapEntry<String, int>> get categoriesSorted =>
      byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  /// Days (newest first) with their transactions.
  List<(String day, List<Tx> txs)> get byDay {
    final map = <String, List<Tx>>{};
    for (final t in transactions) {
      (map[t.day] ??= []).add(t);
    }
    final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final d in days) (d, map[d]!)];
  }
}

class FinanceRepo {
  FinanceRepo(this.db);
  final AppDb db;

  static const table = 'transactions';

  /// Transactions with day in [from, to] (inclusive day keys), newest first.
  Future<List<Tx>> between(String from, String to) async {
    final rows = await db.query(
      table,
      where: 'day BETWEEN ? AND ?',
      args: [from, to],
      orderBy: 'day DESC, updated_at DESC',
    );
    return rows.map(Tx.new).toList();
  }

  /// "2026-11" → all transactions of that month.
  Future<List<Tx>> month(String yyyyMm) => between('$yyyyMm-01', '$yyyyMm-31');

  Future<String> save(Map<String, Object?> fields) => db.save(table, fields);
  Future<void> remove(String id) => db.delete(table, id);
  Future<void> restore(Tx t) => db.save(table, t.fields());

  /// Category names for [kind], defaults first (seeded with fixed ids), then
  /// custom ones alphabetically.
  Future<List<String>> categories(TxKind kind) async {
    final rows = await db.query('categories', where: 'kind = ?', args: [kind.name], orderBy: 'is_custom, sort, name');
    return [for (final r in rows) r['name'] as String];
  }

  /// Adds a custom category; returns its name (existing ones are reused).
  Future<String> addCategory(String name, TxKind kind) async {
    final n = name.trim();
    final existing = await db.query('categories', where: 'kind = ? AND name = ? COLLATE NOCASE', args: [kind.name, n]);
    if (existing.isNotEmpty) return existing.first['name'] as String;
    // Id derived from the name so two devices adding the same category merge.
    await db.save('categories', {
      'id': 'cat-${kind.name}-${n.toLowerCase().replaceAll(RegExp(r'\s+'), '-')}',
      'name': n,
      'kind': kind.name,
      'is_custom': 1,
      'sort': 100,
    });
    return n;
  }
}
