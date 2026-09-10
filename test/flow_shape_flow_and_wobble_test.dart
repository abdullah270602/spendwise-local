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
/// when tapped -- and, on the wobble, for it to move only the branch that
/// was actually touched: tap Gone and only Gone moves, tap Available (or
/// Saved, where it is drawn) and only that one does. Home's State is never
/// recreated when the tabs switch away and back, so the first of those needs
/// an explicit signal -- the shell has exactly one hook for "the user just
/// came back to Home", and this is the only place that hook is meant to
/// matter. The wobble is Home's alone: a settings preview that already
/// replays its own draw-in on every choice does not need a second reason to
/// move.
///
/// Mirrors the geometry `_buildFlowGeometry` builds inside shape_kit.dart, so
/// a tap in the wobble tests below can be aimed at a point that is actually,
/// provably inside one branch's curve -- never a guess at a rectangle that
/// happens to sit near it.
class _Geometry {
  _Geometry(
    this.width,
    this.height,
    this.keptFraction, {
    this.savedOfKept = 0,
    this.asBranch = false,
  });

  final double width;
  final double height;
  final double keptFraction;
  final double savedOfKept;
  final bool asBranch;

  static const _barH = 10.0;

  double get _topW => width * .46;
  double get _margin => width * .075;
  double get _botY => height - _barH - 2;
  double get _keptW => _topW * keptFraction;
  double get _spentW => _topW - _keptW;
  // `reveal` is always 1 in the tests this is used from -- every widget
  // there passes `animate: false` -- so the bottom bars sit at their final,
  // fully-poured position: kept's left edge at the margin, spent's right
  // edge at width minus the margin.
  double get _keptBotX => _margin;
  double get _spentBotX => (width - _margin) - _spentW;
  double get _liveKeptW => asBranch ? _keptW * (1 - savedOfKept) : _keptW;
  double get _savedBotW => asBranch ? _keptW * savedOfKept : 0.0;
  double get _gap => asBranch && _savedBotW > 0 ? 6.0 : 0.0;

  /// A point near the bottom of each branch's curve, well clear of its
  /// edges -- the curve's control points share an x-coordinate with the
  /// endpoint on their own side, so the curve never bows past the straight
  /// bottom edge's own width, and this stays inside regardless of exactly
  /// how the middle of it bows.
  Offset get kept => Offset(_keptBotX + _liveKeptW / 2, _botY - 8);
  Offset get spend => Offset(_spentBotX + _spentW / 2, _botY - 8);
  Offset get saved =>
      Offset(_keptBotX + _liveKeptW + _gap + _savedBotW / 2, _botY - 8);

  /// Left of the margin every branch's bottom edge stays inside of --
  /// nothing is ever drawn there.
  Offset get miss => Offset(4, height / 2);
}

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

    // The painter's `wobbleBranch` and `wobbleOffset` fields are private;
    // its toString carries them, the same way the tests above read `reveal`
    // and `keptFraction` back.
    String? wobbleBranchOn(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(ribbonPaint());
      final name = RegExp(r'wobbleBranch: (\w+)')
          .firstMatch('${paint.painter}')
          ?.group(1);
      return name == 'null' ? null : name;
    }

    double wobbleOffsetOn(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(ribbonPaint());
      // Matched up to the closing paren rather than a digit class alone --
      // a settled value this close to zero often prints in exponential
      // notation (e.g. "-4.44e-16"), which a `[-0-9.]+` class would truncate
      // at the "e" and misread as a value nowhere near zero.
      return double.parse(
        RegExp(r'wobbleOffset: ([^)]+)\)')
                .firstMatch('${paint.painter}')
                ?.group(1) ??
            '0',
      );
    }

    Widget wobbly({
      bool reduceMotion = false,
      int savedMinor = 0,
      SavedTreatment saved = SavedTreatment.none,
    }) => MediaQuery(
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
              savedMinor: savedMinor,
              saved: saved,
              animate: false,
              wobble: true,
            ),
          ),
        ),
      ),
    );

    // Every widget in this group passes `animate: false` and a fixed 8000 of
    // a 10000 total, so `keptFraction` is always 0.8 from the first frame.
    _Geometry geometryOf(WidgetTester tester) {
      final size = tester.getSize(ribbonPaint());
      return _Geometry(size.width, size.height, 0.8);
    }

    testWidgets('tapping Available wobbles only Available', (tester) async {
      await tester.pumpWidget(wobbly());
      await tester.pumpAndSettle();
      final geometry = geometryOf(tester);
      final origin = tester.getTopLeft(ribbonPaint());

      await tester.tapAt(origin + geometry.kept);
      // One frame at zero elapsed time for the controller's ticker to record
      // its own start; only the frame after that shows any progress.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(wobbleBranchOn(tester), 'kept');
      expect(
        wobbleOffsetOn(tester).abs(),
        inExclusiveRange(0.0, 3.0),
        reason: 'a nudge, not a bounce -- at most a couple of logical pixels',
      );

      // No spring, no loop: it rings down within the one pass and stops.
      await tester.pumpAndSettle();
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));
    });

    testWidgets('tapping Gone wobbles only Gone', (tester) async {
      await tester.pumpWidget(wobbly());
      await tester.pumpAndSettle();
      final geometry = geometryOf(tester);
      final origin = tester.getTopLeft(ribbonPaint());

      await tester.tapAt(origin + geometry.spend);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(wobbleBranchOn(tester), 'spend');
      expect(wobbleOffsetOn(tester).abs(), inExclusiveRange(0.0, 3.0));

      await tester.pumpAndSettle();
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));
    });

    testWidgets('tapping the saved branch wobbles only that branch', (
      tester,
    ) async {
      final widget = wobbly(savedMinor: 3000, saved: SavedTreatment.branch);
      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      final size = tester.getSize(ribbonPaint());
      final geometry = _Geometry(
        size.width,
        size.height,
        0.8,
        savedOfKept: 3000 / 8000,
        asBranch: true,
      );
      final origin = tester.getTopLeft(ribbonPaint());

      await tester.tapAt(origin + geometry.saved);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(wobbleBranchOn(tester), 'saved');
      expect(wobbleOffsetOn(tester).abs(), inExclusiveRange(0.0, 3.0));

      await tester.pumpAndSettle();
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));
    });

    testWidgets('a tap that misses every branch does nothing at all', (
      tester,
    ) async {
      await tester.pumpWidget(wobbly());
      await tester.pumpAndSettle();
      final geometry = geometryOf(tester);
      final origin = tester.getTopLeft(ribbonPaint());

      await tester.tapAt(origin + geometry.miss);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      expect(
        wobbleBranchOn(tester),
        isNull,
        reason: 'the gap beside the branches is not a fourth branch',
      );
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));

      await tester.pumpAndSettle();
      expect(wobbleBranchOn(tester), isNull);
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));
    });

    testWidgets('does nothing under reduced motion', (tester) async {
      await tester.pumpWidget(wobbly(reduceMotion: true));
      await tester.pumpAndSettle();
      final geometry = geometryOf(tester);
      final origin = tester.getTopLeft(ribbonPaint());

      await tester.tapAt(origin + geometry.kept);
      await tester.pump(const Duration(milliseconds: 40));
      expect(wobbleBranchOn(tester), isNull);
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));

      await tester.pumpAndSettle();
      expect(wobbleBranchOn(tester), isNull);
      expect(wobbleOffsetOn(tester), closeTo(0, 0.01));
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

  /// The entries the dashboard above is a summary of. Home works out what
  /// came in and what went from these, over the window it names, so the
  /// 4,000 the dashboard reports has to be an entry a person could point at.
  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: '0',
      title: 'Salary',
      subtitle: 'Everyday',
      amount: const MoneyViewData(400000),
      kind: TransactionKind.income,
      occurredAt: DateTime.now(),
      // Not 'Income': Export draws the kinds it can filter by, and a category
      // sharing a kind's name makes that list read as two of one kind.
      category: 'Salary',
      accountId: 'bank',
    ),
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
