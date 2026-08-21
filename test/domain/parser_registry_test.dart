import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/domain.dart';

void main() {
  final observedAt = DateTime.utc(2026, 8, 21, 10);

  test('snapshot retains sanitized notification evidence', () {
    final snapshot = RawNotificationSnapshot(
      packageName: 'pk.example.wallet',
      postedAt: observedAt,
      notificationKey: 'sanitized-key',
      title: 'Payment alert',
      text: 'Paid PKR 500',
      bigText: 'Paid PKR 500',
      subText: 'Card',
    );
    expect(snapshot.combinedText, 'Payment alert Paid PKR 500 Card');
  });

  test('custom parser definition records provenance and reasons', () {
    final definition = ParserDefinition(
      id: 'pk.example.wallet',
      version: 3,
      packageNames: const {'pk.example.wallet'},
      rules: [
        ParserRule(
          id: 'outgoing',
          pattern: RegExp(
            r'OUT (?<amount>PKR [\d,]+) TO (?<counterparty>[A-Z ]+)',
          ),
          direction: EntryDirection.debit,
          type: CandidateType.transfer,
          confidence: 0.96,
        ),
      ],
    );
    final raw = RawObservation(
      id: 'n1',
      kind: ObservationKind.notification,
      observedAt: observedAt,
      body: 'OUT PKR 2,500 TO SAMPLE WALLET',
      accountId: 'bank',
      sourcePackage: 'pk.example.wallet',
    );
    final result = NotificationParser(registry: ParserRegistry([definition]))
        .parseDetailed(raw);
    expect(result.status, ParseStatus.parsed);
    expect(result.parserId, 'pk.example.wallet');
    expect(result.parserVersion, 3);
    expect(result.candidate!.counterparty, 'SAMPLE WALLET');
    expect(result.candidate!.type, CandidateType.transfer);
    expect(result.reasons.single, contains('outgoing'));
  });

  test('ambiguous multi-amount notification is not guessed', () {
    final raw = RawObservation(
      id: 'n2',
      kind: ObservationKind.notification,
      observedAt: observedAt,
      body: 'Paid PKR 100. Available balance PKR 900.',
      accountId: 'bank',
    );
    final result = const NotificationParser().parseDetailed(raw);
    expect(result.status, ParseStatus.ambiguous);
    expect(result.candidate, isNull);
  });
}
