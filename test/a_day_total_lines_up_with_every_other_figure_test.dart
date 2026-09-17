import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// The day's net belongs on the right edge, in the column every other figure
/// in the register is drawn in.
///
/// Making the label `Flexible` to stop a long date overflowing at twice the
/// text size had a side effect: `Flexible` and the `Expanded` rule beside it
/// split the free space evenly, the label used only part of its half, and
/// the remainder collected at the end of the row — pushing the total into
/// the middle of the screen, out of line with every amount beneath it.
void main() {
  Future<double> netRightEdge(
    WidgetTester tester, {
    required String label,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RegisterDay(label: label, total: '-29,000'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the day header overflowed');
    return tester.getRect(find.text('-29,000')).right;
  }

  testWidgets('a short date leaves the net at the right edge', (tester) async {
    // 390 wide, 20 of gutter each side.
    expect(await netRightEdge(tester, label: 'Fri 18'), closeTo(370, 1));
  });

  testWidgets('and so does a date carrying its month and year', (tester) async {
    expect(
      await netRightEdge(tester, label: 'Fri 18 Sep 26'),
      closeTo(370, 1),
      reason: 'the longer label must not move the figure it sits beside',
    );
  });

  testWidgets('and neither overflows at twice the text size', (tester) async {
    expect(
      await netRightEdge(tester, label: 'Fri 18 Sep 26', textScale: 2.0),
      closeTo(370, 1),
    );
  });
}
