import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

/// Reconciliation compares legs against each other, and it re-runs from
/// scratch every time evidence changes. When those comparisons were done
/// pairwise across the whole ledger the cost grew with the square of the
/// history, which froze the app once a real ledger had built up. Legs are now
/// bucketed on the cheap necessary conditions first, so this stays close to
/// linear. The bound is deliberately loose -- it is here to catch a return to
/// quadratic, not to police milliseconds.
void main() {
  test('reconciles a large ledger without quadratic blow-up', () {
    final baseTime = DateTime.utc(2026, 8, 21, 12);
    final candidates = <EventCandidate>[];
    for (var index = 0; index < 4000; index++) {
      final accountId = 'acct-${index % 5}';
      final observation = RawObservation(
        id: 'obs-$index',
        kind: ObservationKind.notification,
        observedAt: baseTime.add(Duration(minutes: index)),
        body: 'body $index',
        accountId: accountId,
        sourcePackage: 'pkg',
      );
      candidates.add(
        EventCandidate(
          id: 'cand-$index',
          observation: observation,
          accountId: accountId,
          amount: Money.pkr(100000 + (index % 300) * 1000),
          direction: index.isEven
              ? EntryDirection.debit
              : EntryDirection.credit,
          occurredAt: observation.observedAt,
        ),
      );
    }

    final watch = Stopwatch()..start();
    final result = const Reconciler().reconcile(candidates);
    watch.stop();

    expect(result.transactions, hasLength(4000));
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 5)),
      reason: 'reconciliation must not scale with the square of the ledger',
    );
  });
}
