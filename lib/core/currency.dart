/// What the app needs to know about a currency to read it out of a sentence.
///
/// Three facts, and the app was getting two of them wrong outside Pakistan.
///
/// **How many minor units.** Money is stored as an integer of the smallest
/// unit, and the code multiplied by 100 unconditionally. A yen, a won or a
/// dong has no minor unit at all, so `JPY 500` became 50,000. A dinar has
/// three, so `KWD 1.250` became 125 fils instead of 1,250. Wrong by a factor
/// of a hundred and by a factor of ten, silently, in a ledger.
///
/// **Where the marker sits.** The amount pattern only ever matched a marker
/// *before* the number — `PKR 5,000`. A survey of 5,629 real bank-message
/// formats across seventy countries found the marker *after* the number in
/// **90%** of them: `1.500,00 RUB`, `706.96THB`, `-325,440VND`, `1,000원`.
/// The app read the minority spelling and nothing else.
///
/// **Which currency a marker means.** Most do not name one. `Rs` is used by
/// Pakistan, India, Sri Lanka and Nepal; `$` by a dozen countries; `kr` by
/// three. A marker like that cannot be resolved from the text, so it is
/// resolved from the ledger: the only candidates are currencies the owner
/// actually holds an account in. Somebody with one PKR account reading `Rs`
/// has no ambiguity to resolve.
library;

final class Currency {
  const Currency({
    required this.code,
    required this.minorDigits,
    required this.markers,
    this.ambiguousMarkers = const {},
  });

  /// ISO 4217 alphabetic code.
  final String code;

  /// Digits after the decimal separator, per ISO 4217. The multiplier is
  /// `10^minorDigits`, never a hardcoded hundred.
  final int minorDigits;

  /// Spellings that name this currency and no other, so they can be trusted
  /// on sight. The code itself is always one of them.
  final Set<String> markers;

  /// Spellings this currency shares with others. Only usable when the ledger
  /// narrows the field to one candidate.
  final Set<String> ambiguousMarkers;

  int get multiplier {
    var value = 1;
    for (var i = 0; i < minorDigits; i++) {
      value *= 10;
    }
    return value;
  }
}

/// The currencies the app can read.
///
/// Chosen to cover the regions where bank alerts are the primary record of a
/// payment, which is not the same list as the world's largest economies.
/// Adding one is a row here, and nothing else.
const currencyTable = <Currency>[
  // South Asia. "Rs" is shared four ways and "₨" three, so both are
  // ambiguous and only the ISO codes are decisive.
  Currency(
    code: 'PKR',
    minorDigits: 2,
    markers: {'PKR'},
    ambiguousMarkers: {'Rs', 'Rs.', '₨', 'RS'},
  ),
  Currency(
    code: 'INR',
    minorDigits: 2,
    markers: {'INR', '₹'},
    ambiguousMarkers: {'Rs', 'Rs.', '₨', 'RS'},
  ),
  Currency(
    code: 'LKR',
    minorDigits: 2,
    markers: {'LKR'},
    ambiguousMarkers: {'Rs', 'Rs.', '₨'},
  ),
  Currency(
    code: 'NPR',
    minorDigits: 2,
    markers: {'NPR'},
    ambiguousMarkers: {'Rs', 'Rs.', '₨'},
  ),
  Currency(code: 'BDT', minorDigits: 2, markers: {'BDT', '৳', 'Tk', 'Tk.'}),

  // Gulf and Middle East. The three-digit dinars are the reason
  // `minorDigits` exists at all.
  Currency(code: 'AED', minorDigits: 2, markers: {'AED', 'Dhs', 'د.إ'}),
  Currency(
    code: 'SAR',
    minorDigits: 2,
    // U+FDFC is the old riyal ligature; U+20C1 is the sign adopted in 2025.
    markers: {'SAR', 'SR', '﷼', '⃁', 'ر.س', 'ر.س.'},
  ),
  Currency(code: 'QAR', minorDigits: 2, markers: {'QAR', 'QR'}),
  Currency(code: 'KWD', minorDigits: 3, markers: {'KWD', 'KD', 'د.ك'}),
  Currency(code: 'BHD', minorDigits: 3, markers: {'BHD', 'BD', 'د.ب'}),
  Currency(code: 'OMR', minorDigits: 3, markers: {'OMR', 'RO', 'ر.ع.'}),
  Currency(code: 'JOD', minorDigits: 3, markers: {'JOD', 'JD'}),
  Currency(code: 'IQD', minorDigits: 3, markers: {'IQD'}),
  Currency(code: 'TND', minorDigits: 3, markers: {'TND', 'DT'}),
  Currency(code: 'EGP', minorDigits: 2, markers: {'EGP', 'ج.م'}),
  Currency(code: 'TRY', minorDigits: 2, markers: {'TRY', 'TL', '₺'}),
  Currency(code: 'ILS', minorDigits: 2, markers: {'ILS', '₪'}),

  // Major reserve currencies. Every symbol here is shared, which is why the
  // ledger has to narrow them.
  Currency(
    code: 'USD',
    minorDigits: 2,
    markers: {'USD'},
    ambiguousMarkers: {r'$', r'US$'},
  ),
  Currency(code: 'EUR', minorDigits: 2, markers: {'EUR', '€'}),
  Currency(
    code: 'GBP',
    minorDigits: 2,
    markers: {'GBP'},
    ambiguousMarkers: {'£'},
  ),

  // South-East and East Asia. Three of these have no minor unit.
  Currency(
    code: 'MYR',
    minorDigits: 2,
    markers: {'MYR', 'RM'},
  ),
  Currency(
    code: 'SGD',
    minorDigits: 2,
    markers: {'SGD'},
    ambiguousMarkers: {r'$', r'S$'},
  ),
  Currency(code: 'IDR', minorDigits: 2, markers: {'IDR', 'Rp'}),
  Currency(code: 'THB', minorDigits: 2, markers: {'THB', '฿', 'Bt'}),
  Currency(code: 'VND', minorDigits: 0, markers: {'VND', '₫', 'đ'}),
  Currency(code: 'PHP', minorDigits: 2, markers: {'PHP', '₱'}),
  Currency(code: 'KRW', minorDigits: 0, markers: {'KRW', '₩', '원'}),
  Currency(code: 'JPY', minorDigits: 0, markers: {'JPY', '¥', '円'}),
  Currency(code: 'CNY', minorDigits: 2, markers: {'CNY', 'RMB', '元'}),

  // Africa.
  Currency(code: 'NGN', minorDigits: 2, markers: {'NGN', '₦'}),
  Currency(code: 'KES', minorDigits: 2, markers: {'KES', 'KSh', 'Ksh'}),
  Currency(code: 'GHS', minorDigits: 2, markers: {'GHS', 'GH₵'}),
  // A bare "R" is how the rand is written, and it is also the first
  // letter of half the words in a bank message. It is only trusted for
  // somebody who actually holds rand.
  Currency(
    code: 'ZAR',
    minorDigits: 2,
    markers: {'ZAR'},
    ambiguousMarkers: {'R'},
  ),
  Currency(code: 'TZS', minorDigits: 2, markers: {'TZS'}),
  Currency(code: 'UGX', minorDigits: 0, markers: {'UGX'}),
  Currency(code: 'ETB', minorDigits: 2, markers: {'ETB'}),

  // Latin America. The peso sign is shared with the dollar sign.
  Currency(code: 'BRL', minorDigits: 2, markers: {'BRL', r'R$'}),
  Currency(
    code: 'MXN',
    minorDigits: 2,
    markers: {'MXN'},
    ambiguousMarkers: {r'$'},
  ),
  Currency(
    code: 'COP',
    minorDigits: 2,
    markers: {'COP'},
    ambiguousMarkers: {r'$'},
  ),
  Currency(
    code: 'CLP',
    minorDigits: 0,
    markers: {'CLP'},
    ambiguousMarkers: {r'$'},
  ),

  // CIS and Caucasus, where the marker follows the number almost without
  // exception.
  Currency(code: 'RUB', minorDigits: 2, markers: {'RUB', '₽', 'руб', 'р.'}),
  Currency(code: 'UAH', minorDigits: 2, markers: {'UAH', '₴', 'грн'}),
  Currency(code: 'KZT', minorDigits: 2, markers: {'KZT', '₸'}),
  Currency(code: 'GEL', minorDigits: 2, markers: {'GEL', '₾'}),
  Currency(code: 'AZN', minorDigits: 2, markers: {'AZN', '₼'}),
  Currency(code: 'UZS', minorDigits: 2, markers: {'UZS'}),
];

final _byCode = {
  for (final currency in currencyTable) currency.code: currency,
};

/// The currency with this ISO code, or null.
Currency? currencyForCode(String code) => _byCode[code.toUpperCase()];

/// How many minor units this currency has, defaulting to two for a code the
/// table has never heard of — which is the commonest case and the least
/// damaging guess.
int minorDigitsFor(String code) => currencyForCode(code)?.minorDigits ?? 2;
