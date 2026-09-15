import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/data/parser_health.dart';
import 'package:spendwise/features/settings/parser_health_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// The screen that answers "why did it miss that".
///
/// Its one real obligation is to be honest about small numbers. Every
/// percentage on a page like this is a lie at n=1, and a source that has
/// sent nothing at all must not read as a source that is failing — that
/// difference is the whole reason somebody opens it.
void main() {
  Future<void> pump(WidgetTester tester, ParserHealth health) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: ParserHealthScreen(viewModel: _Fake(health)),
      ),
    );
    await tester.pumpAndSettle();
  }

  SourceCoverage coverage({
    required String label,
    int parsed = 0,
    int review = 0,
    int error = 0,
    int ignored = 0,
    Map<String, int> parsers = const {},
    List<ReasonCount> reasons = const [],
  }) => SourceCoverage(
    sourceId: label,
    label: label,
    packageName: 'com.example.${label.toLowerCase()}',
    institution: label,
    parsed: parsed,
    review: review,
    error: error,
    ignored: ignored,
    parsers: parsers,
    reasons: reasons,
    firstSeen: DateTime.utc(2026, 5),
    lastSeen: DateTime.utc(2026, 5, 20),
  );

  testWidgets('it counts before it judges', (tester) async {
    await pump(
      tester,
      ParserHealth(
        sources: [coverage(label: 'Northbank', parsed: 7, review: 3, ignored: 5)],
      ),
    );

    expect(find.textContaining('7 of 10'), findsWidgets);
    expect(
      find.textContaining('%'),
      findsNothing,
      reason: 'a percentage at these counts says more than the data supports',
    );
  });

  testWidgets('alerts that were never about money are not failures', (
    tester,
  ) async {
    // The parser correctly declining to invent a transaction out of a
    // passcode must not be shown as the parser losing.
    await pump(
      tester,
      ParserHealth(
        sources: [coverage(label: 'Northbank', parsed: 2, ignored: 40)],
      ),
    );

    expect(find.textContaining('2 of 2'), findsWidgets);
    expect(find.textContaining('40'), findsWidgets);
    expect(find.textContaining('not about money'), findsWidgets);
  });

  testWidgets('a silent source is listed apart from a failing one', (
    tester,
  ) async {
    await pump(
      tester,
      ParserHealth(
        sources: [
          coverage(label: 'Northbank', parsed: 4, review: 2),
          coverage(label: 'Southbank'),
        ],
      ),
    );

    expect(find.text('Enabled, nothing captured'), findsOneWidget);
    expect(find.textContaining('never posted an alert'), findsOneWidget);
    expect(find.text('Southbank'), findsOneWidget);
    expect(find.textContaining('2 unread'), findsWidgets);
  });

  testWidgets('it repeats the reason the parser gave, not its own', (
    tester,
  ) async {
    await pump(
      tester,
      ParserHealth(
        sources: [
          coverage(
            label: 'Southbank',
            review: 3,
            reasons: const [
              ReasonCount('Nothing here says which way the money went.', 3),
            ],
          ),
        ],
      ),
    );

    expect(find.text('What stopped it'), findsOneWidget);
    expect(
      find.textContaining('Nothing here says which way the money went.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty ledger says so instead of scoring itself', (
    tester,
  ) async {
    await pump(tester, const ParserHealth(sources: []));
    expect(
      find.textContaining('No alert has looked like money yet'),
      findsOneWidget,
    );
  });
}

/// Implements the *advanced* interface deliberately.
///
/// `uiParserHealth` is an extension method on `SpendWiseViewModel`, and
/// extension methods are resolved statically — a fake that merely declares
/// its own `uiParserHealth` is never consulted, and the screen quietly
/// renders the empty state instead. The extension delegates to
/// `SpendWiseAdvancedViewModel.parserHealth`, so that is what a fake has to
/// provide.
class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake(this._health);
  final ParserHealth _health;

  @override
  ParserHealth parserHealth() => _health;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
