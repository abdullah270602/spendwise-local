import '../models/canonical_transaction.dart';
import '../models/event_candidate.dart';

final class CategoryClassification {
  const CategoryClassification({
    required this.categoryId,
    required this.ruleId,
    required this.confidence,
  });

  final String categoryId;
  final String ruleId;
  final double confidence;
}

/// Ordered, deterministic, network-free categorization rules.
///
/// Rules deliberately prefer precision over coverage. Unknown merchants remain
/// `other` until the user corrects them; user rules are persisted by the ledger.
final class CategoryClassifier {
  const CategoryClassifier();

  CategoryClassification classify({
    required String text,
    required TransactionKind kind,
    Iterable<CandidateType> candidateTypes = const [],
  }) {
    if (kind == TransactionKind.transfer) {
      return const CategoryClassification(
        categoryId: 'transfer',
        ruleId: 'type.transfer',
        confidence: 1,
      );
    }
    if (kind == TransactionKind.income) {
      return const CategoryClassification(
        categoryId: 'income',
        ruleId: 'type.income',
        confidence: 1,
      );
    }
    final types = candidateTypes.toSet();
    if (types.contains(CandidateType.cashWithdrawal)) {
      return const CategoryClassification(
        categoryId: 'cash',
        ruleId: 'type.cash_withdrawal',
        confidence: 1,
      );
    }
    if (types.contains(CandidateType.fee)) {
      return const CategoryClassification(
        categoryId: 'fees',
        ruleId: 'type.fee',
        confidence: 1,
      );
    }

    final normalized = normalize(text);
    for (final rule in _rules) {
      if (rule.terms.any((term) => _containsPhrase(normalized, term))) {
        return CategoryClassification(
          categoryId: rule.categoryId,
          ruleId: rule.id,
          confidence: rule.confidence,
        );
      }
    }
    return const CategoryClassification(
      categoryId: 'other',
      ruleId: 'fallback.other',
      confidence: 0,
    );
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _containsPhrase(String normalized, String phrase) =>
      ' $normalized '.contains(' ${normalize(phrase)} ');
}

final class _CategoryRule {
  const _CategoryRule(this.id, this.categoryId, this.terms);
  final String id;
  final String categoryId;
  final List<String> terms;
  double get confidence => .9;
}

const _rules = <_CategoryRule>[
  _CategoryRule('merchant.groceries', 'groceries', [
    'grocery',
    'groceries',
    'supermarket',
    'hypermarket',
    'carrefour',
    'imtiaz',
    'naheed',
    'metro cash and carry',
    'alfatah',
    'al fatah',
  ]),
  _CategoryRule('merchant.entertainment', 'entertainment', [
    'netflix',
    'hbo',
    'hbo max',
    'tapmad',
    'prime video',
    'amazon prime video',
    'disney plus',
    'spotify',
    'youtube premium',
    'apple music',
    'cinema',
    'cinepax',
  ]),
  _CategoryRule('merchant.subscription_services', 'subscriptions', [
    'openai',
    'chatgpt',
    'anthropic',
    'claude ai',
    'google one',
    'hostinger',
    'godaddy',
    'go daddy',
    'namecheap',
    'digitalocean',
    'cloudflare',
    'microsoft 365',
    'office 365',
    'icloud plus',
    'dropbox',
    'github copilot',
    'notion',
  ]),
  _CategoryRule('merchant.food', 'food', [
    'foodpanda',
    'restaurant',
    'cafe',
    'coffee',
    'kfc',
    'mcdonalds',
    'mcdonald',
    'dominos',
    'pizza hut',
  ]),
  _CategoryRule('merchant.transport', 'transport', [
    'careem',
    'uber',
    'indrive',
    'yango',
    'petrol',
    'fuel station',
    'total parco',
    'pakistan state oil',
  ]),
  _CategoryRule('merchant.shopping', 'shopping', [
    'daraz',
    'aliexpress',
    'temu',
    'shopping mall',
  ]),
  _CategoryRule('merchant.health', 'health', [
    'hospital',
    'clinic',
    'pharmacy',
    'medical store',
    'laboratory',
    'diagnostic',
    'doctor fee',
    'dawaai',
    'sehat',
  ]),
  _CategoryRule('merchant.education', 'education', [
    'school fee',
    'university fee',
    'college fee',
    'tuition fee',
    'coursera',
    'udemy',
    'edx',
    'book store',
    'bookshop',
  ]),
  _CategoryRule('merchant.travel', 'travel', [
    'airline',
    'airways',
    'pia ticket',
    'airblue',
    'fly jinnah',
    'serene air',
    'booking com',
    'agoda',
    'hotel',
    'guest house',
  ]),
  _CategoryRule('merchant.personal_care', 'personal-care', [
    'salon',
    'barber',
    'spa',
    'cosmetics',
    'skin care',
    'makeup',
  ]),
  _CategoryRule('merchant.home', 'home', [
    'furniture',
    'home appliance',
    'hardware store',
    'interwood',
    'habitt',
    'ikea',
  ]),
  _CategoryRule('merchant.insurance', 'insurance', [
    'insurance premium',
    'takaful',
    'jubilee life',
    'efulife',
    'adamjee insurance',
  ]),
  _CategoryRule('merchant.gifts_charity', 'gifts-charity', [
    'donation',
    'charity',
    'zakat',
    'edhi foundation',
    'shaukat khanum',
    'saylani',
  ]),
  _CategoryRule('merchant.government_tax', 'government-tax', [
    'tax payment',
    'fbr',
    'government fee',
    'passport fee',
    'driving license fee',
    'excise taxation',
  ]),
  _CategoryRule('merchant.bills', 'bills', [
    'electricity bill',
    'gas bill',
    'water bill',
    'internet bill',
    'ptcl',
    'stormfiber',
    'nayatel',
    'jazz postpaid',
    'zong postpaid',
    'telenor postpaid',
  ]),
  _CategoryRule('merchant.cash', 'cash', ['atm withdrawal', 'cash withdrawal']),
  _CategoryRule('merchant.fees', 'fees', [
    'bank fee',
    'service fee',
    'annual fee',
    'card fee',
    'transaction fee',
  ]),
];
