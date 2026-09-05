import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/insights/spending_analytics.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

void main() {
  test(
    'daily analytics calculates spend, income, change, and excludes transfers',
    () {
      final analytics = SpendingAnalytics.calculate(
        now: DateTime(2026, 8, 22, 18),
        resolution: AnalyticsResolution.last7Days,
        transactions: [
          _transaction(
            'food',
            TransactionKind.expense,
            12000,
            DateTime(2026, 8, 22),
            'Food & dining',
          ),
          _transaction(
            'movie',
            TransactionKind.expense,
            3000,
            DateTime(2026, 8, 20),
            'Entertainment',
          ),
          _transaction(
            'salary',
            TransactionKind.income,
            50000,
            DateTime(2026, 8, 21),
            'Income',
          ),
          _transaction(
            'transfer',
            TransactionKind.transfer,
            99000,
            DateTime(2026, 8, 22),
            'Transfer',
          ),
          _transaction(
            'previous',
            TransactionKind.expense,
            10000,
            DateTime(2026, 8, 12),
            'Food & dining',
          ),
        ],
      );

      expect(analytics.buckets, hasLength(7));
      expect(analytics.totalSpendingMinor, 15000);
      expect(analytics.totalIncomeMinor, 50000);
      expect(analytics.previousSpendingMinor, 10000);
      expect(analytics.spendingChangePercent, 50);
      expect(analytics.netMinor, 35000);
      expect(analytics.weekdaySpending.fold<int>(0, (a, b) => a + b), 15000);
    },
  );

  test(
    'category filtering changes the trend without corrupting category shares',
    () {
      final analytics = SpendingAnalytics.calculate(
        now: DateTime(2026, 8, 22),
        resolution: AnalyticsResolution.months,
        category: 'Entertainment',
        transactions: [
          _transaction(
            'netflix',
            TransactionKind.expense,
            2000,
            DateTime(2026, 8, 10),
            'Entertainment',
          ),
          _transaction(
            'groceries',
            TransactionKind.expense,
            8000,
            DateTime(2026, 8, 11),
            'Food & dining',
          ),
        ],
      );

      expect(analytics.buckets, hasLength(12));
      expect(analytics.totalSpendingMinor, 2000);
      expect(analytics.totalIncomeMinor, 0);
      expect(
        analytics.categories.map((item) => item.category),
        containsAll(['Entertainment', 'Food & dining']),
      );
      expect(analytics.categories.first.fraction, .8);
    },
  );

  test('year resolution covers ledger history with stable year labels', () {
    final analytics = SpendingAnalytics.calculate(
      now: DateTime(2026, 8, 22),
      resolution: AnalyticsResolution.years,
      transactions: [
        _transaction(
          'old',
          TransactionKind.expense,
          100,
          DateTime(2023, 1, 1),
          'Other',
        ),
        _transaction(
          'new',
          TransactionKind.expense,
          200,
          DateTime(2026, 1, 1),
          'Other',
        ),
      ],
    );
    expect(analytics.buckets.map((bucket) => bucket.label), [
      '2023',
      '2024',
      '2025',
      '2026',
    ]);
    expect(analytics.totalSpendingMinor, 300);
  });
}

TransactionViewData _transaction(
  String id,
  TransactionKind kind,
  int amount,
  DateTime occurredAt,
  String category,
) => TransactionViewData(
  id: id,
  title: id,
  subtitle: 'Account',
  amount: MoneyViewData(kind == TransactionKind.expense ? -amount : amount),
  kind: kind,
  occurredAt: occurredAt,
  category: category,
);
