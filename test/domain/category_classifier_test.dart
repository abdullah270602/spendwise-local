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
      'SAMPLE SUPERMARKET': 'groceries',
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

  test('classifies recurring Meezan statement narrations', () {
    const cases = {
      'ONLINE PURCHASE FOOD PANDA STAN (123456)': 'food',
      'CAKES & BAKES POS TRANSACTION STAN (123456)': 'food',
      'ONLINE PURCHASE DAILY DELI STAN (123456)': 'food',
      'JALAL SONS POS TRANSACTION STAN (123456)': 'groceries',
      'BILL PAID ZONG PREPAID 03000000000': 'bills',
      'CHARGES TAXES PLUS FED STAN (123456)': 'fees',
      'BANK CHARGES IBB SAMPLE BRANCH': 'fees',
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

  test('a transfer instrument is not a destination', () {
    // "Between your accounts" means both legs landed somewhere the user owns,
    // and only the reconciler can know that -- it says so by setting the kind.
    // Reading it off the narration filed most of a month's real payments under
    // that category and made the breakdown meaningless.
    expect(
      classifier
          .classify(
            text: 'RAAST P2P FUND TRANSFER TO SAMPLE PERSON',
            kind: TransactionKind.expense,
          )
          .categoryId,
      isNot('transfer'),
      reason: 'paying a person by IBFT is a payment, not an own-account move',
    );
    expect(
      classifier
          .classify(
            text: 'MONEY RECEIVED FROM SAMPLE PERSON',
            kind: TransactionKind.income,
          )
          .categoryId,
      'income',
    );
    expect(
      classifier
          .classify(
            text: 'RAAST P2P FUND TRANSFER TO SAMPLE PERSON',
            kind: TransactionKind.transfer,
          )
          .categoryId,
      'transfer',
      reason: 'once the reconciler pairs both legs, it really is one',
    );
  });

  test('generic card fallbacks apply after specific merchants', () {
    expect(
      classifier
          .classify(
            text: 'UNKNOWN MERCHANT POS TRANSACTION STAN 123',
            kind: TransactionKind.expense,
          )
          .categoryId,
      'shopping',
    );
    expect(
      classifier
          .classify(
            text: 'A PLUS PHARMACY POS TRANSACTION',
            kind: TransactionKind.expense,
          )
          .categoryId,
      'health',
    );
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
