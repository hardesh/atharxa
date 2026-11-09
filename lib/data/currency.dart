import 'package:intl/intl.dart';

/// An ISO 4217 currency with its symbol and minor-unit digits.
class Currency {
  const Currency(this.code, this.symbol, this.name, {this.digits = 2});
  final String code, symbol, name;

  /// Minor units (2 for INR/USD, 0 for JPY).
  final int digits;

  int get factor => const [1, 10, 100, 1000][digits];

  static Currency of(String code) => all.firstWhere((c) => c.code == code, orElse: () => Currency(code, code, code));

  /// Common ones first (shown as chips); the rest in the search list.
  static const common = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'JPY'];

  static const all = [
    Currency('INR', '₹', 'Indian rupee'),
    Currency('USD', r'$', 'US dollar'),
    Currency('EUR', '€', 'Euro'),
    Currency('GBP', '£', 'British pound'),
    Currency('AED', 'AED', 'UAE dirham'),
    Currency('SGD', r'S$', 'Singapore dollar'),
    Currency('JPY', '¥', 'Japanese yen', digits: 0),
    Currency('AUD', r'A$', 'Australian dollar'),
    Currency('CAD', r'C$', 'Canadian dollar'),
    Currency('CHF', 'CHF', 'Swiss franc'),
    Currency('CNY', 'CN¥', 'Chinese yuan'),
    Currency('HKD', r'HK$', 'Hong Kong dollar'),
    Currency('NZD', r'NZ$', 'New Zealand dollar'),
    Currency('SEK', 'kr', 'Swedish krona'),
    Currency('NOK', 'kr', 'Norwegian krone'),
    Currency('DKK', 'kr', 'Danish krone'),
    Currency('ZAR', 'R', 'South African rand'),
    Currency('BRL', r'R$', 'Brazilian real'),
    Currency('MXN', r'MX$', 'Mexican peso'),
    Currency('KRW', '₩', 'South Korean won', digits: 0),
    Currency('THB', '฿', 'Thai baht'),
    Currency('MYR', 'RM', 'Malaysian ringgit'),
    Currency('IDR', 'Rp', 'Indonesian rupiah', digits: 0),
    Currency('PHP', '₱', 'Philippine peso'),
    Currency('VND', '₫', 'Vietnamese dong', digits: 0),
    Currency('LKR', 'Rs', 'Sri Lankan rupee'),
    Currency('NPR', 'Rs', 'Nepalese rupee'),
    Currency('BDT', '৳', 'Bangladeshi taka'),
    Currency('PKR', 'Rs', 'Pakistani rupee'),
    Currency('SAR', 'SAR', 'Saudi riyal'),
    Currency('QAR', 'QAR', 'Qatari riyal'),
    Currency('KWD', 'KWD', 'Kuwaiti dinar', digits: 3),
    Currency('OMR', 'OMR', 'Omani rial', digits: 3),
    Currency('BHD', 'BHD', 'Bahraini dinar', digits: 3),
    Currency('TRY', '₺', 'Turkish lira'),
    Currency('RUB', '₽', 'Russian rouble'),
    Currency('PLN', 'zł', 'Polish złoty'),
    Currency('ILS', '₪', 'Israeli new shekel'),
    Currency('EGP', 'E£', 'Egyptian pound'),
    Currency('NGN', '₦', 'Nigerian naira'),
    Currency('KES', 'KSh', 'Kenyan shilling'),
  ];

  /// Parses user input ("1,150.5") into minor units; null if invalid.
  int? parseMinor(String input) {
    final v = double.tryParse(input.replaceAll(',', '').trim());
    if (v == null || v <= 0 || v > 1e12) return null;
    return (v * factor).round();
  }

  /// "₹1,35,000" (Indian grouping for INR), "$1,234.50". Whole amounts drop
  /// the decimals.
  String format(int minor, {bool sign = false}) {
    final value = minor / factor;
    final whole = minor % factor == 0;
    final f = NumberFormat.currency(
      locale: code == 'INR' ? 'en_IN' : 'en_US',
      symbol: symbol.length > 1 && !symbol.contains(r'$') ? '$symbol ' : symbol,
      decimalDigits: whole ? 0 : digits,
    );
    final s = f.format(value.abs());
    if (!sign) return value < 0 ? '−$s' : s;
    return '${value < 0 ? '−' : '+'}$s';
  }

  /// Plain number for exports ("45139.00").
  String plain(int minor) => (minor / factor).toStringAsFixed(digits);
}
