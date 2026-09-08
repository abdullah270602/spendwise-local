import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// What a register row says, to someone who can see it and to someone who
/// cannot.
///
/// The row is the ledger and it is also the review inbox, which makes it the
/// densest surface in the app -- and until now the only thing separating a
/// salary from a supermarket bill was a hue. Income and expense printed the
/// identical glyphs, the pending mark was a five-pixel dot with no text
/// anywhere near it, and there was no `Semantics` in the widget at all, so a
/// screen reader read out a name, a shouted category and a bare number and
/// left the reader to guess which way the money had gone.
void main() {
  /// A 360px phone, which is the narrow end of what this app ships to, and
  /// optionally the text size someone who needs it actually uses. The project
  /// once shipped a 108px header overflow because every widget test ran at
  /// the 800x600 desktop default.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpendWiseTheme.gutter,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  String labelOn(WidgetTester tester) =>
      tester.getSemantics(find.byType(RegisterRow)).label;

  /// Turns the semantics tree on for the length of one test and off again.
  /// `addTearDown` is too late: the framework checks for a live handle before
  /// tear-downs run, and reports a leak instead of the assertion that failed.
  Future<void> listening(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await body();
    } finally {
      handle.dispose();
    }
  }

  group('which way the money went', () {
    testWidgets('is printed, not only coloured', (tester) async {
      await pump(
        tester,
        Column(
          children: [
            RegisterRow(
              name: 'Monthly salary',
              meta: 'Income · Current',
              amount: '85,000.00',
              amountColor: SpendWiseColors.keep,
            ),
          ],
        ),
      );
      // Colour cannot be the whole answer: a third of the palettes this app
      // ships put kept and spent within a hue of each other, and a person who
      // cannot separate them has no other cue on the row.
      expect(find.text('+85,000.00'), findsOneWidget);

      await pump(
        tester,
        Column(
          children: [
            RegisterRow(
              name: 'Valley Mart',
              meta: 'Groceries · Everyday',
              amount: '85,000.00',
              amountColor: SpendWiseColors.spend,
            ),
          ],
        ),
      );
      expect(find.text('−85,000.00'), findsOneWidget);
    });

    testWidgets('leaves a figure the caller already signed alone', (
      tester,
    ) async {
      // The help screens and the onboarding demo write their own examples out
      // by hand, sign included. A row that signed them again would print
      // "−−2,450.00", which is not a number.
      await pump(
        tester,
        Column(
          children: [
            RegisterRow(
              name: 'Valley Mart',
              meta: 'Groceries · Everyday',
              amount: '−2,450.00',
              amountColor: SpendWiseColors.spend,
            ),
          ],
        ),
      );
      expect(find.text('−2,450.00'), findsOneWidget);
      expect(find.text('−−2,450.00'), findsNothing);
    });

    testWidgets('says nothing about a transfer between your own accounts', (
      tester,
    ) async {
      // It neither arrived nor left, so either sign would be a claim that is
      // untrue. The arrow beside the name is what marks it.
      await pump(
        tester,
        Column(
          children: [
            RegisterRow(
              name: 'To savings',
              meta: 'Your own accounts',
              amount: '20,000.00',
              amountColor: SpendWiseColors.mine,
              ownTransfer: true,
            ),
          ],
        ),
      );
      expect(find.text('20,000.00'), findsOneWidget);
    });
  });

  group('a screen reader hears', () {
    testWidgets('what it was, which way, how much, and whether it is settled', (
      tester,
    ) async {
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'Valley Mart',
                meta: 'Groceries · Everyday',
                amount: '2,450.00',
                amountColor: SpendWiseColors.spend,
                pending: true,
                onTap: () {},
              ),
            ],
          ),
        );

        final label = labelOn(tester);
        expect(label, contains('Valley Mart'), reason: 'what it was');
        expect(label, contains('out'), reason: 'which way the money went');
        expect(label, contains('2,450.00'), reason: 'how much');
        expect(
          label,
          contains('Not confirmed yet'),
          reason: 'the pending dot is five pixels of colour and nothing else',
        );
        expect(label, contains('Groceries · Everyday'));
      });
    });

    testWidgets('the word "in" for money that arrived', (tester) async {
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'Monthly salary',
                meta: 'Income · Current',
                amount: '85,000.00',
                amountColor: SpendWiseColors.keep,
              ),
            ],
          ),
        );
        expect(labelOn(tester), contains('85,000.00 in'));
        expect(labelOn(tester), isNot(contains('Not confirmed yet')));
      });
    });

    testWidgets('a transfer named as one', (tester) async {
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'To savings',
                meta: 'Your own accounts',
                amount: '20,000.00',
                amountColor: SpendWiseColors.mine,
                ownTransfer: true,
              ),
            ],
          ),
        );
        expect(labelOn(tester), contains('moved between your own accounts'));
      });
    });

    testWidgets('the amount without the sign glyph read out as a word', (
      tester,
    ) async {
      // A reader meeting the minus glyph either says "minus" or skips it
      // entirely, and neither of those is the sentence. The direction is
      // given as a word instead.
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'Valley Mart',
                meta: 'Groceries',
                amount: '−2,450.00',
                amountColor: SpendWiseColors.spend,
              ),
            ],
          ),
        );
        expect(labelOn(tester), contains('2,450.00 out'));
        expect(labelOn(tester), isNot(contains('−')));
      });
    });

    testWidgets('one sentence, not four fragments', (tester) async {
      // The row draws its metadata in capitals, which a reader is liable to
      // spell out letter by letter, and draws the amount without saying which
      // way it went. Those nodes are dropped so the sentence above is the
      // only thing said.
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'Valley Mart',
                meta: 'Groceries · Everyday',
                amount: '2,450.00',
                amountColor: SpendWiseColors.spend,
              ),
            ],
          ),
        );
        expect(find.bySemanticsLabel('GROCERIES · EVERYDAY'), findsNothing);
      });
    });

    testWidgets('and can still tap it', (tester) async {
      var tapped = 0;
      await listening(tester, () async {
        await pump(
          tester,
          Column(
            children: [
              RegisterRow(
                name: 'Valley Mart',
                meta: 'Groceries',
                amount: '2,450.00',
                amountColor: SpendWiseColors.spend,
                onTap: () => tapped++,
              ),
            ],
          ),
        );
        // Labelling a row is worthless if labelling it took the tap away,
        // which is exactly what excluding the subtree above the InkWell
        // would have done.
        expect(
          tester.getSemantics(find.byType(RegisterRow)),
          isSemantics(isButton: true, hasTapAction: true),
        );

        await tester.tap(find.byType(RegisterRow));
        expect(tapped, 1);
      });
    });
  });

  testWidgets('the row still fits a 360px phone at twice the text size', (
    tester,
  ) async {
    await pump(
      tester,
      Column(
        children: [
          RegisterRow(
            name: 'A shop with a genuinely long name on the receipt',
            meta: 'Groceries · Everyday current account',
            amount: '2,450.00',
            amountColor: SpendWiseColors.spend,
            pending: true,
          ),
        ],
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
