import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/currency.dart';
import '../data/finance_repo.dart';

enum ExportFormat { csv, xlsx }

/// Export options (DESIGN.md §5 Finance › Export).
class ExportOptions {
  const ExportOptions({
    this.format = ExportFormat.csv,
    this.expenses = true,
    this.income = true,
    this.notes = true,
    this.extraSheets = true,
    this.negativeExpenses = false,
  });

  final ExportFormat format;
  final bool expenses, income, notes;

  /// Excel only: add "By category" and "Summary" sheets.
  final bool extraSheets;

  /// Expenses as negative amounts (handy for SUM()).
  final bool negativeExpenses;

  ExportOptions copyWith({
    ExportFormat? format,
    bool? expenses,
    bool? income,
    bool? notes,
    bool? extraSheets,
    bool? negativeExpenses,
  }) => ExportOptions(
    format: format ?? this.format,
    expenses: expenses ?? this.expenses,
    income: income ?? this.income,
    notes: notes ?? this.notes,
    extraSheets: extraSheets ?? this.extraSheets,
    negativeExpenses: negativeExpenses ?? this.negativeExpenses,
  );
}

/// Builds CSV / XLSX files from transactions. Columns:
/// `date,type,category,amount,currency,note`.
class TransactionsExport {
  TransactionsExport(List<Tx> all, this.options)
    : rows = all.where((t) => t.kind == TxKind.expense ? options.expenses : options.income).toList()
        ..sort((a, b) => a.day.compareTo(b.day));

  final ExportOptions options;
  final List<Tx> rows;

  static const header = ['date', 'type', 'category', 'amount', 'currency', 'note'];

  /// `transactions-2026-11.csv`, or `transactions-2026-09_2026-11.xlsx` for a range.
  static String fileName(String fromDay, String toDay, ExportFormat f) {
    final a = fromDay.substring(0, 7), b = toDay.substring(0, 7);
    return 'transactions-${a == b ? a : '${a}_$b'}.${f.name}';
  }

  List<Object> _cells(Tx t) {
    final c = Currency.of(t.currency);
    final amount = double.parse(c.plain(t.amountMinor));
    return [
      t.day,
      t.kind.name,
      t.category,
      t.kind == TxKind.expense && options.negativeExpenses ? -amount : amount,
      t.currency,
      options.notes ? (t.note ?? '') : '',
    ];
  }

  Uint8List build() => options.format == ExportFormat.csv ? csv() : xlsx();

  /// UTF-8 with BOM so Excel shows ₹ correctly.
  Uint8List csv() {
    String esc(Object v) {
      final s = v is double ? _num(v) : '$v';
      return s.contains(RegExp(r'[",\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer()..writeln(header.join(','));
    for (final t in rows) {
      b.write('${_cells(t).map(esc).join(',')}\r\n');
    }
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString().replaceFirst('\n', '\r\n'))]);
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toStringAsFixed(2) : '$v';

  // ------------------------------------------------------------------- xlsx

  /// Minimal Office Open XML workbook (inline strings, no styles).
  Uint8List xlsx() {
    final sheets = <(String, List<List<Object>>)>[
      ('Transactions', [header, for (final t in rows) _cells(t)]),
      if (options.extraSheets) ...[('By category', _byCategory()), ('Summary', _summary())],
    ];
    final archive = Archive();
    void add(String name, String xml) => archive.add(ArchiveFile.bytes(name, utf8.encode(xml)));

    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
          '</Types>',
    );
    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
          '${[for (final (i, s) in sheets.indexed) '<sheet name="${_x(s.$1)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
          '</sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '${[for (var i = 1; i <= sheets.length; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
          '</Relationships>',
    );
    for (final (i, s) in sheets.indexed) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(s.$2));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _sheet(List<List<Object>> rows) {
    String col(int i) => String.fromCharCode(65 + i); // A–Z is enough here
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
    );
    for (final (r, row) in rows.indexed) {
      b.write('<row r="${r + 1}">');
      for (final (c, v) in row.indexed) {
        final ref = '${col(c)}${r + 1}';
        b.write(
          v is num
              ? '<c r="$ref"><v>$v</v></c>'
              : '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_x('$v')}</t></is></c>',
        );
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  static String _x(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  /// Expenses per category and currency, largest first.
  List<List<Object>> _byCategory() {
    final sums = <(String, String), int>{};
    for (final t in rows.where((t) => t.kind == TxKind.expense)) {
      sums[(t.category, t.currency)] = (sums[(t.category, t.currency)] ?? 0) + t.amountMinor;
    }
    final entries = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      ['category', 'currency', 'expenses'],
      for (final e in entries) [e.key.$1, e.key.$2, double.parse(Currency.of(e.key.$2).plain(e.value))],
    ];
  }

  /// Income / expenses / balance / count per currency.
  List<List<Object>> _summary() {
    final s = MonthSummary(rows, rows.isEmpty ? 'INR' : rows.first.currency);
    double v(String c, int minor) => double.parse(Currency.of(c).plain(minor));
    return [
      ['currency', 'income', 'expenses', 'balance', 'transactions'],
      for (final t in s.totals.values)
        [t.currency, v(t.currency, t.income), v(t.currency, t.expense), v(t.currency, t.balance), t.count],
    ];
  }
}
