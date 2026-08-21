import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  const classifier = CategoryClassifier();

  test('classifies entertainment merchants deterministically', () {
    for (final merchant in ['NETFLIX.COM', 'HBO Max', 'Tapmad TV']) {
      final result = classifier.classify(
        text: 'Card purchase at $merchant',
        kind: TransactionKind.expense,
      );
      expect(result.categoryId, 'entertainment', reason: merchant);
    }
  });

  test('classifies subscriptions and digital services deterministically', () {
    for (final merchant in [
      'OPENAI CHATGPT',
      'Google One',
      'Hostinger International',
      'Go Daddy',
    ]) {
      final result = classifier.classify(
        text: 'Recurring payment to $merchant',
        kind: TransactionKind.expense,
      );
      expect(result.categoryId, 'subscriptions', reason: merchant);
    }
  });

  test('classifies broader everyday statement merchants', () {
    const cases = {
      'IMTIAZ SUPERMARKET': 'groceries',
      'CITY PHARMACY': 'health',
      'UNIVERSITY FEE': 'education',
      'AIRBLUE TICKET': 'travel',
      'JUBILEE LIFE INSURANCE PREMIUM': 'insurance',
      'FBR TAX PAYMENT': 'government-tax',
      'EDHI FOUNDATION DONATION': 'gifts-charity',
    };
    for (final entry in cases.entries) {
      expect(
        classifier
            .classify(text: entry.key, kind: TransactionKind.expense)
            .categoryId,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('type rules take priority and unknown merchants stay other', () {
    expect(
      classifier
          .classify(text: 'Netflix', kind: TransactionKind.transfer)
          .categoryId,
      'transfer',
    );
    expect(
      classifier
          .classify(text: 'Salary', kind: TransactionKind.income)
          .categoryId,
      'income',
    );
    expect(
      classifier
          .classify(text: 'ACME 4912', kind: TransactionKind.expense)
          .categoryId,
      'other',
    );
  });
}
