import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/statement_account_inferer.dart';

void main() {
  const inferer = StatementAccountInferer();
  const accounts = [
    StatementAccountProfile(
      id: 'meezan',
      name: 'Meezan Current',
      institution: 'Meezan Bank',
      suffix: '4821',
    ),
    StatementAccountProfile(
      id: 'nayapay',
      name: 'NayaPay Wallet',
      institution: 'NayaPay',
      suffix: '9012',
    ),
  ];

  test('matches account suffix and institution above the table', () {
    const text = '''Meezan Bank Account Statement
Account Number,PK00MEZN000000004821
Statement Period,August 2026

Transaction Date,Transaction Remarks,Withdrawal Amount,Deposit Amount,Reference
2026-08-20,FOODPANDA,4250,,TX-1
''';
    final result = inferer.infer(
      sheetName: 'Current account',
      csvText: text,
      accounts: accounts,
    );

    expect(result.suggestedAccountId, 'meezan');
    expect(result.detectedInstitution, 'Meezan Bank');
    expect(result.detectedSuffix, '4821');
    expect(result.confidence, greaterThanOrEqualTo(.9));
  });

  test('uses a worksheet wallet name without reading counterparties', () {
    const text = '''Date,Description,Debit,Credit
2026-08-20,Transfer to Meezan Bank,1000,
''';
    final result = inferer.infer(
      sheetName: 'NayaPay Wallet',
      csvText: text,
      accounts: accounts,
    );

    expect(result.suggestedAccountId, 'nayapay');
  });

  test('leaves an ambiguous workbook for explicit confirmation', () {
    const text = '''Date,Description,Debit,Credit
2026-08-20,Card purchase,1000,
''';
    final result = inferer.infer(
      sheetName: 'Transactions',
      csvText: text,
      accounts: accounts,
    );

    expect(result.suggestedAccountId, isNull);
    expect(result.reason, contains('choose an account'));
  });

  test('uses a lone statement account number as a suffix clue', () {
    const text = '''00000000004821
Opening Balance,PKR 100
Closing Balance,PKR 50
Currency,Pakistan Rupee(PKR)
Booking Date,Description,Debit,Credit
2026-08-20,Card purchase,50,
''';
    final result = inferer.infer(
      sheetName: 'Meezan-25-26.xlsx · Sheet1',
      csvText: text,
      accounts: accounts,
    );

    expect(result.suggestedAccountId, 'meezan');
    expect(result.detectedSuffix, '4821');
  });
}
