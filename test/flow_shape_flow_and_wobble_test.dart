import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/dashboard/home_preview.dart';
import 'package:spendwise/features/dashboard/home_savings.dart';
import 'package:spendwise/features/shell/spendwise_shell.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// Two more promises about motion, on top of the ones `motion_contract_test`
/// already holds the ribbon to.
///
/// The developer asked for the denominator to look like it is flowing when
/// the app opens or the user comes back to Home, and to wobble very subtly
/// when tapped. Home's State is never recreated when the tabs switch away
/// and back, so the first of those needs an explicit signal -- the shell has
/// exactly one hook for "the user just came back to Home", and this is the
/// only place that hook is meant to matter. The wobble is Home's alone: a
/// settings preview that already replays its own draw-in on every choice
/// does not need a second reason to move.
void main() {
  double revealOn(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(FlowShape),
        matching: find.byType(CustomPaint),
      ),
    );
    // The painter's fields are private; its toString carries them, the same
    // way motion_contract_test reads keptFraction back.
    return double.parse(
      RegExp(r'reveal: ([0-9.]+)').firstMatch('${paint.painter}')?.group(1) ??
          '-1',
    );
  }

  tearDown(() {
    // A global signal outlives the widget tree that reads it. Leaving it
    // bumped would make the next test's first build look like a replay.
    homeReturnRevision.value = 0;
  });

  group('the flow', () {
    testWidgets('replays when the shell sends the user back to Home', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: SpendWiseShell(viewModel: _FakeViewModel()),
        ),
      );
      await tester.pumpAndSettle();
      expect(revealOn(tester), closeTo(1, 0.001));

      // Away from Home -- landing elsewhere must not, by itself, count as
      // "coming back".
      await tester.tap(find.text('Ledger'));
      await tester.pumpAndSettle();

      // And back -- the one hook the shell has for it.
      await tester.tap(find.text('Home'));
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        revealOn(tester),
        lessThan(1),
        reason: 'the draw-in is replaying, not sitting at rest',
      );

      await tester.pumpAndSettle();
      expect(revealOn(tester), closeTo(1, 0.001));
    });

    testWidgets('does not replay in the settings preview', (tester) async {
      final figures = HomeFigures(
        received: 400000,
        spent: 150000,
        kept: 250000,
        saved: 0,
        held: 0,
        from: DateTime(2026, 9),
        to: DateTime(2026, 10),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(
            body: HomePreview(
              figures: figures,
              style: HomeSavingsStyle.off,
              extra: HomeSavingsExtra.none,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(revealOn(tester), closeTo(1, 0.001));

      // The same signal that replays Home's ribbon. A preview is not Home
      // and must not answer to it, or a settings screen nobody is looking at
      // would appear to move on its own the next time Home is left and
      // returned to.
      homeReturnRevision.value++;
      await tester.pump(const Duration(milliseconds: 120));
      expect(revealOn(tester), closeTo(1, 0.001));
    });

    testWidgets('is instant under reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: SpendWiseTheme.dark,
            home: Scaffold(
              body: Center(
                child: FlowShape(
                  receivedMinor: 10000,
                  keptMinor: 8000,
                  spentMinor: 2000,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(revealOn(tester), closeTo(1, 0.001));
    });
  });

  group('the wobble', () {
    Finder ribbonPaint() => find.descendant(
      of: find.byType(FlowShape),
      matching: find.byType(CustomPaint),
    );

    Widget wobbly({bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: Center(
            child: FlowShape(
              key: const ValueKey('ribbon'),
              receivedMinor: 10000,
              keptMinor: 8000,
              spentMinor: 2000,
              animate: false,
              wobble: true,
            ),
          ),
        ),
      ),
    );

    testWidgets('a tap disturbs it very slightly and it settles back', (
      tester,
    ) async {
      await tester.pumpWidget(wobbly());
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(ribbonPaint());

      await tester.tap(find.byType(FlowShape));
      // One frame at zero elapsed time for the controller's ticker to record
      // its own start; only the frame after that shows any progress.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final displacement = (tester.getTopLeft(ribbonPaint()).dy - rest.dy)
          .abs();
      expect(
        displacement,
        inExclusiveRange(0.0, 3.0),
        reason: 'a nudge, not a bounce -- at most a couple of logical pixels',
      );

      // No spring, no loop: it rings down within the one pass and stops.
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(ribbonPaint()).dy, closeTo(rest.dy, 0.01));
    });

    testWidgets('does nothing under reduced motion', (tester) async {
      await tester.pumpWidget(wobbly(reduceMotion: true));
      await tester.pumpAndSettle();
      final rest = tester.getTopLeft(ribbonPaint());

      await tester.tap(find.byType(FlowShape));
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.getTopLeft(ribbonPaint()).dy, closeTo(rest.dy, 0.01));

      await tester.pumpAndSettle();
      expect(tester.getTopLeft(ribbonPaint()).dy, closeTo(rest.dy, 0.01));
    });

    testWidgets('stays off where it is not opted into', (tester) async {
      // The settings previews never pass `wobble: true`, so a tap on one
      // should reach nothing -- there is no GestureDetector there to catch it.
      await tester.pumpWidget(
        MaterialApp(
          theme: SpendWiseTheme.dark,
          home: Scaffold(
            body: Center(
              child: FlowShape(
                receivedMinor: 10000,
                keptMinor: 8000,
                spentMinor: 2000,
                animate: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}

class _FakeViewModel extends ChangeNotifier implements SpendWiseViewModel {
  @override
  bool get onboardingComplete => true;
  @override
  bool get notificationAccessGranted => true;
  @override
  DashboardViewData get dashboard => const DashboardViewData(
    netWorth: MoneyViewData(2500000),
    incomeThisMonth: MoneyViewData(400000),
    spendingThisMonth: MoneyViewData(150000),
    monthlyChangePercent: 12,
  );
  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000),
      suffix: '1234',
    ),
  ];
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: '1',
      title: 'Groceries',
      subtitle: 'Everyday',
      amount: const MoneyViewData(-150000),
      kind: TransactionKind.expense,
      occurredAt: DateTime.now(),
      category: 'Food & dining',
      accountId: 'bank',
    ),
  ];
  @override
  List<ReviewViewData> get reviews => const [];
  @override
  List<SourceViewData> get sources => const [];
  @override
  Future<void> addAccount(
    String name,
    String type,
    MoneyViewData openingBalance,
  ) async {}
  @override
  Future<void> completeOnboarding() async {}
  @override
  Future<void> deleteTransaction(String id) async {}
  @override
  Future<void> restoreTransaction(String id) async {}
  @override
  Future<void> eraseAllData() async {}
  @override
  Future<void> exportData() async {}
  @override
  Future<void> requestNotificationAccess() async {}
  @override
  Future<void> resolveReview(String id, {required bool merge}) async {}
  @override
  Future<void> saveManualTransaction(ManualTransactionDraft draft) async {}
  @override
  Future<void> setSourceEnabled(String packageName, bool enabled) async {}
}
