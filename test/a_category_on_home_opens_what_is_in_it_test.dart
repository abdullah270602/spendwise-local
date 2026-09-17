import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';

import 'light_mode_fixture.dart';

/// The most available tap on the launch screen, and it answered nothing.
///
/// Home's breakdown names what each category cost. Every row was given the
/// same callback — a bare tab switch — so "Groceries · 38,420" and
/// "Everything else" both opened the unfiltered ledger. The row is a figure
/// with a colour swatch and a 48dp hit box; it reads as a link to the
/// entries behind it, and the Ledger has had a category filter all along.
void main() {
  setUp(() => ledgerCategoryRequest.value = null);
  tearDown(() => ledgerCategoryRequest.value = null);

  testWidgets('tapping a category asks the Ledger for that category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);
    // Home draws no breakdown until somebody asks for one; the rows are the
    // subject of this test.
    fixture.ledger.setViewPreference('home_categories', 'all');

    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SpendWiseShell(viewModel: fixture),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byType(CategoryRow).first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    // Consumed by the Ledger on arrival rather than left set, so coming back
    // to the tab later does not silently re-apply a filter nobody asked for.
    expect(ledgerCategoryRequest.value, isNull);
    expect(
      find.text('Every match'),
      findsWidgets,
      reason: 'a filtered ledger drops the month scope and says so',
    );
  });
}
