import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/insights/insights_screen.dart';
import 'package:spendwise/features/review/review_inbox_screen.dart';
import 'package:spendwise/features/settings/source_selection_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Home and the Ledger already say when nothing is being read for alerts.
/// Review and Insights did not, and both said the opposite: Review reported
/// that "every alert SpendWise captured was clear enough to file on its own"
/// when nothing had been captured, and Insights promised that transactions
/// would reach the ledger when nothing was going to.
///
/// Before notification access is granted is the state every new install
/// starts in, so that pair of sentences was the first thing most people read
/// on those two tabs, and neither offered a way out of it.
void main() {
  Future<void> pumpReview(WidgetTester tester, _Fake model) =>
      _pump(tester, ReviewInboxScreen(viewModel: model));

  Future<void> pumpInsights(WidgetTester tester, _Fake model) =>
      _pump(tester, InsightsScreen(viewModel: model));

  group('Review', () {
    testWidgets('does not report work it never did', (tester) async {
      await pumpReview(tester, _Fake(granted: false));

      expect(
        find.textContaining('clear enough to'),
        findsNothing,
        reason: 'nothing was captured, so nothing was filed on its own',
      );
      expect(find.textContaining('Turn on notification access'), findsWidgets);
    });

    testWidgets('and offers the way out, not directions to it', (tester) async {
      final model = _Fake(granted: false);
      await pumpReview(tester, model);

      await tester.tap(find.text('Turn on notification access'));
      await tester.pumpAndSettle();

      expect(model.accessRequests, 1);
    });

    testWidgets('access granted with no source enabled is the same gap', (
      tester,
    ) async {
      await pumpReview(tester, _Fake());

      expect(find.textContaining('No app is being read'), findsOneWidget);

      await tester.tap(find.text('Choose notification sources'));
      await tester.pumpAndSettle();

      expect(find.byType(SourceSelectionScreen), findsOneWidget);
    });

    testWidgets('with capture running the empty inbox means what it says', (
      tester,
    ) async {
      await pumpReview(tester, _Fake(enabled: true));

      expect(find.textContaining('clear enough to'), findsOneWidget);
      expect(find.textContaining('No app is being read'), findsNothing);
    });
  });

  group('Insights', () {
    testWidgets('does not promise arrivals that cannot happen', (tester) async {
      await pumpInsights(tester, _Fake(granted: false));

      expect(find.textContaining('Once transactions reach'), findsNothing);
      expect(find.text('Turn on notification access'), findsOneWidget);
    });

    testWidgets('access granted with no source enabled is the same gap', (
      tester,
    ) async {
      await pumpInsights(tester, _Fake());

      expect(find.textContaining('No app is being read'), findsOneWidget);

      await tester.tap(find.text('Choose notification sources'));
      await tester.pumpAndSettle();

      expect(find.byType(SourceSelectionScreen), findsOneWidget);
    });

    testWidgets('with capture running the promise is made again', (
      tester,
    ) async {
      await pumpInsights(tester, _Fake(enabled: true));

      expect(find.textContaining('Once transactions reach'), findsOneWidget);
      expect(find.textContaining('No app is being read'), findsNothing);
    });
  });
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  // A real phone, at the default font size: these are rest states with a
  // button under two sentences, and the 800x600 test default hides nothing
  // else so well as a paragraph that does not fit.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: SpendWiseTheme.dark,
      home: Scaffold(body: screen),
    ),
  );
  await tester.pumpAndSettle();
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  _Fake({this.granted = true, this.enabled = false});

  /// Whether the listener has been allowed to read notifications at all.
  final bool granted;

  /// Whether any app was picked to be read. Granted with nothing picked is
  /// as dead as refused, and it is the state somebody lands in by turning a
  /// source off again.
  final bool enabled;

  int accessRequests = 0;

  @override
  bool get notificationAccessGranted => granted;

  @override
  Future<void> requestNotificationAccess() async => accessRequests++;

  @override
  List<SourceViewData> get sources => [
    SourceViewData(
      packageName: 'com.example.bank',
      label: 'Example Bank',
      enabled: enabled,
    ),
  ];

  @override
  List<TransactionViewData> get transactions => const [];

  @override
  List<ReviewViewData> get reviews => const [];

  @override
  List<AlertViewData> get unroutedAlerts => const [];

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<AccountViewData> get accounts => const [];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
