import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:atharxa/data/currency.dart';
import 'package:atharxa/data/db.dart';
import 'package:atharxa/data/finance_repo.dart';
import 'package:atharxa/services/transactions_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// DESIGN.md §8: Nov 2026 — income ₹1,35,000; expenses ₹45,139; balance ₹89,861.
const sampleExpenses = [
  ('Rent', 28000),
  ('Shopping', 6499),
  ('Groceries', 2500),
  ('Groceries', 1270),
  ('Bills', 2340),
  ('Transport', 1150),
  ('Transport', 500),
  ('Food', 1280),
  ('Health', 860),
  ('Entertainment', 740),
];

Future<FinanceRepo> seedNovember([AppDb? db]) async {
  final repo = FinanceRepo(db ?? await openTestDb());
  await repo.save({
    'day': '2026-11-01',
    'kind': 'income',
    'amount_minor': 13500000,
    'currency': 'INR',
    'category': 'Salary',
  });
  var d = 2;
  for (final (cat, rupees) in sampleExpenses) {
    await repo.save({
      'day': '2026-11-${(d++).toString().padLeft(2, '0')}',
      'kind': 'expense',
      'amount_minor': rupees * 100,
      'currency': 'INR',
      'category': cat,
    });
  }
  // One USD expense: kept separate, not converted.
  await repo.save({
    'day': '2026-11-20',
    'kind': 'expense',
    'amount_minor': 1999,
    'currency': 'USD',
    'category': 'Shopping',
  });
  return repo;
}

void main() {
  test('currency formatting: Indian grouping, symbols, minor units', () {
    final inr = Currency.of('INR');
    expect(inr.format(13500000), '₹1,35,000');
    expect(inr.format(4513900), '₹45,139');
    expect(inr.format(115050), '₹1,150.50');
    expect(inr.format(-115000), '−₹1,150');
    expect(inr.format(115000, sign: true), '+₹1,150');
    expect(Currency.of('USD').format(123450), r'$1,234.50');
    expect(Currency.of('JPY').format(1500), '¥1,500');
    expect(inr.parseMinor('1,150.5'), 115050);
    expect(Currency.of('JPY').parseMinor('1500'), 1500);
    expect(inr.parseMinor('0'), isNull);
    expect(inr.plain(4513900), '45139.00');
  });

  test('§8 November summary, per-currency totals, categories, days', () async {
    final repo = await seedNovember();
    final s = MonthSummary(await repo.month('2026-11'), 'INR');
    final inr = Currency.of('INR');
    expect(inr.format(s.main.income), '₹1,35,000');
    expect(inr.format(s.main.expense), '₹45,139');
    expect(inr.format(s.main.balance), '₹89,861');
    expect(s.others.single.currency, 'USD');
    expect(s.others.single.expense, 1999);
    final cats = s.categoriesSorted;
    expect(cats.first.key, 'Rent');
    expect((cats.first.value / s.main.expense * 100).round(), 62);
    expect(cats.map((e) => e.key).take(5), ['Rent', 'Shopping', 'Groceries', 'Bills', 'Transport']);
    expect(s.byCategory['Groceries'], 377000);
    expect(s.byDay.first.$1, '2026-11-20');
  });

  test('custom categories are added once and merge by name', () async {
    final repo = FinanceRepo(await openTestDb());
    expect(await repo.addCategory('Freelance ', TxKind.income), 'Freelance');
    expect(await repo.addCategory('freelance', TxKind.income), 'Freelance');
    expect(await repo.categories(TxKind.income), ['Salary', 'Other', 'Freelance']);
  });

  test('CSV export: BOM, columns, negative expenses, filters, quoting', () async {
    final repo = await seedNovember();
    final all = await repo.month('2026-11');
    final csv = TransactionsExport(all, const ExportOptions(negativeExpenses: true)).csv();
    expect(csv.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    final lines = utf8.decode(csv.sublist(3)).trim().split('\r\n');
    expect(lines.first, 'date,type,category,amount,currency,note');
    expect(lines.length, 13); // header + 12 transactions
    expect(lines[1], '2026-11-01,income,Salary,135000.00,INR,');
    expect(lines[2], '2026-11-02,expense,Rent,-28000.00,INR,');
    final onlyIncome = TransactionsExport(all, const ExportOptions(expenses: false)).rows;
    expect(onlyIncome.single.category, 'Salary');
    expect(TransactionsExport.fileName('2026-11-01', '2026-11-30', ExportFormat.csv), 'transactions-2026-11.csv');
    expect(
      TransactionsExport.fileName('2026-09-01', '2026-11-30', ExportFormat.xlsx),
      'transactions-2026-09_2026-11.xlsx',
    );
  });

  test('XLSX export: valid zip with three sheets and totals', () async {
    final repo = await seedNovember();
    final bytes = TransactionsExport(
      await repo.month('2026-11'),
      const ExportOptions(format: ExportFormat.xlsx),
    ).xlsx();
    final zip = ZipDecoder().decodeBytes(bytes);
    final names = zip.files.map((f) => f.name).toSet();
    expect(
      names,
      containsAll(['[Content_Types].xml', 'xl/workbook.xml', 'xl/worksheets/sheet1.xml', 'xl/worksheets/sheet3.xml']),
    );
    String read(String n) => utf8.decode(zip.findFile(n)!.content as List<int>);
    expect(read('xl/workbook.xml'), contains('name="By category"'));
    expect(read('xl/worksheets/sheet2.xml'), contains('Rent'));
    final summary = read('xl/worksheets/sheet3.xml');
    expect(summary, contains('<v>135000.0</v>'));
    expect(summary, contains('<v>45139.0</v>'));
    expect(summary, contains('<v>89861.0</v>'));
  });
}
