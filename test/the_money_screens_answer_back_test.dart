import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/dashboard_screen.dart';
import 'package:spendwise/features/settings/home_period_screen.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/transactions/ledger_screen.dart';

import 'light_mode_fixture.dart';

/// Six places the money screens stated something and offered no way to act
/// on it. Each one had the machinery already built somewhere else.
void main() {
  void onAPhone(WidgetTester tester, {double height = 1600}) {
    tester.view.physicalSize = Size(390 * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<LightModeFixture> pumpShell(WidgetTester tester) async {
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);
    // Home draws no breakdown until somebody asks for one.
    fixture.ledger.setViewPreference('home_categories', 'all');
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: SpendWiseShell(viewModel: fixture),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  testWidgets('Home period opens the window it names', (tester) async {
    // `home_period.dart` says why this matters in its own words: a calendar
    // month is near zero on the 1st and full after payday, "so for the first
    // days of every month the ratio is either meaningless or a lie". The
    // answer lived four taps into Settings and Home showed the denominator
    // as inert text.
    onAPhone(tester);
    final fixture = await pumpShell(tester);

    final period = find.bySemanticsLabel(RegExp('^Period: '));
    expect(period, findsOneWidget);
    await tester.tap(period);
    await tester.pumpAndSettle();
    expect(find.byType(HomePeriodScreen), findsOneWidget);
    fixture.ledger.close;
  });

  testWidgets('the Ledger names each filter and drops it on its own', (
    tester,
  ) async {
    onAPhone(tester);
    await pumpShell(tester);

    // Arriving from Home's breakdown is the ordinary way to end up filtered.
    final row = find.byType(CategoryRow).first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    final chip = find.bySemanticsLabel(RegExp('^Filter: '));
    expect(
      chip,
      findsOneWidget,
      reason:
          'the screen knew how many filters were set and used it only to '
          'tint an icon',
    );

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Filter: ')),
      findsNothing,
      reason: 'Clear drops every filter at once; a chip drops its own',
    );
  });

  testWidgets('Insights offers the report it is the source of', (tester) async {
    // The report picks its own default template by reading the Insights
    // preference, and its only door was in Settings under "Your data".
    onAPhone(tester, height: 2600);
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.ssid_chart_outlined).last);
    await tester.pumpAndSettle();

    final entry = find.text('Save this as a report');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    expect(entry, findsOneWidget);
  });

  testWidgets('a day in All months says which month it is', (tester) async {
    // Out of the month scope no month is named anywhere on the screen, so
    // "WED 16" read the same for September, for July and for last July — in
    // the one mode that exists for finding a payment from two years ago.
    onAPhone(tester, height: 2600);
    final fixture = LightModeFixture();
    addTearDown(fixture.ledger.close);
    fixture.ledger.setViewPreference('ledger_span', 'all');
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(body: LedgerScreen(viewModel: fixture)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            RegExp(r'^[A-Z]{3} \d{2} [A-Z]{3} \d{2}$').hasMatch(widget.data!),
      ),
      findsWidgets,
      reason: 'a day out of scope carries its month and year',
    );
  });

  testWidgets('the add-account form has no field that cannot be used', (
    tester,
  ) async {
    // A read-only "Currency" field whose helper read "PKR totals stay
    // mathematically exact" — an implementation note under a dead control,
    // in the first form anybody fills in. The fact it carried is on the
    // balance field's own prefix.
    onAPhone(tester, height: 2600);
    await pumpShell(tester);

    await tester.tap(find.byIcon(Icons.grid_view_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add account'));
    await tester.pumpAndSettle();

    expect(find.text('Account name'), findsOneWidget, reason: 'form opened');
    expect(find.text('Last digits'), findsOneWidget);
    expect(find.text('PKR totals stay mathematically exact'), findsNothing);
    expect(find.text('Currency'), findsNothing);
  });
}
