import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  final time = DateTime.utc(2026, 8, 21, 10);

  EventCandidate event({
    required String id,
    required String account,
    required EntryDirection direction,
    ObservationKind kind = ObservationKind.notification,
    int minute = 0,
    String? reference,
    String? counterparty,
    String? package,
  }) {
    final raw = RawObservation(
      id: id,
      kind: kind,
      observedAt: time.add(Duration(minutes: minute)),
      body: 'sanitized $id',
      accountId: account,
      sourcePackage: package,
      externalId: '$id-external',
    );
    return EventCandidate(
      id: 'candidate:$id',
      observation: raw,
      accountId: account,
      amount: const Money.pkr(100000),
      direction: direction,
      occurredAt: raw.observedAt,
      reference: reference,
      counterparty: counterparty,
    );
  }

  test(
    'does not collapse identical separate purchases without a strong key',
    () {
      final result = const Reconciler().reconcile([
        event(
          id: 'purchase-1',
          account: 'bank',
          direction: EntryDirection.debit,
          package: 'bank.app',
        ),
        event(
          id: 'purchase-2',
          account: 'bank',
          direction: EntryDirection.debit,
          minute: 1,
          package: 'bank.app',
        ),
      ]);
      expect(result.transactions, hasLength(2));
    },
  );

  test('reference allows late CSV evidence to attach to notification leg', () {
    final result = const Reconciler().reconcile([
      event(
        id: 'notification',
        account: 'bank',
        direction: EntryDirection.debit,
        reference: 'REF100',
        package: 'bank.app',
      ),
      event(
        id: 'csv',
        account: 'bank',
        direction: EntryDirection.debit,
        kind: ObservationKind.csvImport,
        minute: 600,
        reference: 'REF100',
      ),
    ]);
    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.evidenceIds, {'notification', 'csv'});
    expect(
      result.decisions.single.type,
      ReconciliationDecisionType.mergeEvidence,
    );
    expect(result.decisions.single.reversible, isTrue);
  });

  test('ambiguous equal transfers remain separate and reviewable', () {
    final result = const Reconciler().reconcile([
      event(id: 'out', account: 'bank', direction: EntryDirection.debit),
      event(
        id: 'in-1',
        account: 'wallet-a',
        direction: EntryDirection.credit,
        minute: 1,
      ),
      event(
        id: 'in-2',
        account: 'wallet-b',
        direction: EntryDirection.credit,
        minute: 2,
      ),
    ]);
    expect(result.transactions, hasLength(3));
    expect(
      result.transactions.every(
        (value) =>
            value.effectiveReconciliationState ==
            ReconciliationState.needsReview,
      ),
      isTrue,
    );
    expect(
      result.decisions.any(
        (value) => value.type == ReconciliationDecisionType.keepSeparate,
      ),
      isTrue,
    );
  });
}
