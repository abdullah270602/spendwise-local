import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/category_picker.dart';

/// The `×` beside a category the owner made was one tap, with no question and
/// no undo, sitting on the same row as the name you tap to *choose* that
/// category. `LocalLedger.removeCategory` re-files every transaction filed
/// under it to Other and deletes every rule the app had learned for it, so a
/// slip of the thumb rewrites history and un-teaches the filing at once.
void main() {
  Future<_Fake> openPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final model = _Fake();
    await tester.pumpWidget(
      MaterialApp(
        theme: SpendWiseTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => pickCategory(context, viewModel: model),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return model;
  }

  testWidgets('removing asks first, and names what is lost', (tester) async {
    final model = await openPicker(tester);

    await tester.tap(find.byTooltip('Remove Zakat'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Zakat?'), findsOneWidget);
    expect(
      find.textContaining('moves to Other'),
      findsOneWidget,
      reason: 'the entries already filed under it do not simply vanish',
    );
    expect(
      find.textContaining('forgotten'),
      findsOneWidget,
      reason: 'the learned rules go with it, which is the invisible half',
    );
    expect(model.removed, isEmpty);
  });

  testWidgets('keeping it removes nothing', (tester) async {
    final model = await openPicker(tester);

    await tester.tap(find.byTooltip('Remove Zakat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(model.removed, isEmpty);
    expect(find.text('Zakat'), findsOneWidget, reason: 'still in the list');
  });

  testWidgets('confirming still removes it', (tester) async {
    // The gate must not be so good that the feature stops working.
    final model = await openPicker(tester);

    await tester.tap(find.byTooltip('Remove Zakat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(model.removed, ['zakat']);
  });

  testWidgets('a refused new category is explained in words', (tester) async {
    // The same sheet's other failure path. It interpolated the caught object
    // into the strip -- 'Could not add that category: Bad state: ...' -- and
    // a Dart exception in a snackbar reads as the app breaking rather than
    // the name being refused.
    await openPicker(tester);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Zakat');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not add that category. That name is taken.'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
  });

  testWidgets('a built-in category is not removable at all', (tester) async {
    await openPicker(tester);

    expect(find.byTooltip('Remove Groceries'), findsNothing);
  });
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  final removed = <String>[];

  @override
  List<CategoryViewData> get categories => const [
    CategoryViewData(
      id: 'zakat',
      name: 'Zakat',
      kind: 'expense',
      isSystem: false,
    ),
    CategoryViewData(
      id: 'groceries',
      name: 'Groceries',
      kind: 'expense',
      isSystem: true,
    ),
  ];

  @override
  Future<String> addCategory(String name, {String kind = 'expense'}) async =>
      throw StateError('That name is taken');

  @override
  Future<void> removeCategory(String id) async {
    removed.add(id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
