import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  final baseTime = DateTime.utc(2026, 8, 21, 12);

  EventCandidate candidate({
    required String id,
    required String account,
    required EntryDirection direction,
    String package = 'bank.app',
    int minute = 0,
    String? reference,
    String? description,
  }) {
    final observation = RawObservation(
      id: id,
      kind: ObservationKind.notification,
      observedAt: baseTime.add(Duration(minutes: minute)),
      body: id,
      accountId: account,
      sourcePackage: package,
    );
    return EventCandidate(
      id: 'c:$id',
      observation: observation,
      accountId: account,
      amount: const Money.pkr(1000000),
      direction: direction,
      occurredAt: observation.observedAt,
      reference: reference,
      description: description,
    );
  }

  const reconciler = Reconciler();

  test('reconciles debit and credit as an internal transfer', () {
    final result = reconciler.reconcile([
      candidate(id: 'hbl', account: 'hbl', direction: EntryDirection.debit),
      candidate(
        id: 'sadapay',
        account: 'sadapay',
        direction: EntryDirection.credit,
        minute: 2,
      ),
    ]);
    expect(result.transactions, hasLength(1));
    final transaction = result.transactions.single;
    expect(transaction.kind, TransactionKind.transfer);
    expect(transaction.fromAccountId, 'hbl');
    expect(transaction.toAccountId, 'sadapay');
    expect(transaction.evidenceIds, {'hbl', 'sadapay'});
  });

  test('collapses duplicate same-leg evidence before transfer matching', () {
    final result = reconciler.reconcile([
      candidate(
        id: 'bank-app',
        account: 'hbl',
        direction: EntryDirection.debit,
        reference: 'ABC123',
      ),
      candidate(
        id: 'sms',
        account: 'hbl',
        direction: EntryDirection.debit,
        package: 'messages',
        minute: 1,
        reference: 'ABC123',
      ),
      candidate(
        id: 'wallet',
        account: 'sadapay',
        direction: EntryDirection.credit,
        minute: 2,
      ),
    ]);
    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.evidenceIds, {
      'bank-app',
      'sms',
      'wallet',
    });
  });

  test('is independent of candidate ordering', () {
    final values = [
      candidate(id: 'a', account: 'hbl', direction: EntryDirection.debit),
      candidate(
        id: 'b',
        account: 'wallet',
        direction: EntryDirection.credit,
        minute: 1,
      ),
    ];
    final forward = reconciler.reconcile(values).transactions.single;
    final reverse = reconciler.reconcile(values.reversed).transactions.single;
    expect(reverse.id, forward.id);
    expect(reverse.evidenceIds, forward.evidenceIds);
  });

  test(
    'marks all plausible legs for review when transfer match is ambiguous',
    () {
      final result = reconciler.reconcile([
        candidate(id: 'debit', account: 'hbl', direction: EntryDirection.debit),
        candidate(
          id: 'credit-1',
          account: 'wallet-1',
          direction: EntryDirection.credit,
          minute: 1,
        ),
        candidate(
          id: 'credit-2',
          account: 'wallet-2',
          direction: EntryDirection.credit,
          minute: 2,
        ),
      ]);
      expect(result.transactions, hasLength(3));
      expect(result.reviewCount, 3);
      expect(
        result.transactions.every(
          (item) => item.kind != TransactionKind.transfer,
        ),
        isTrue,
      );
    },
  );

  test('preserves locked and manual existing transactions', () {
    final manual = CanonicalTransaction(
      id: 'manual:1',
      kind: TransactionKind.expense,
      amount: const Money.pkr(50000),
      occurredAt: baseTime,
      evidenceIds: const {},
      accountId: 'cash',
      description: 'Dinner',
      origin: TransactionOrigin.manual,
      locked: true,
    );
    final result = reconciler.reconcile(const [], existing: [manual]);
    expect(result.transactions.single, same(manual));
  });
}
