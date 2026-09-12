import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/theme.dart';
import 'package:spendwise/features/reports/report_screen.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';
import 'package:spendwise/widgets/shape_kit.dart';

/// Dismissing the save dialog is somebody changing their mind about *where*
/// to put the file, not about having it: the report is built and one tap from
/// being offered again. The screen answered that routine cancel with "Report
/// discarded.", which reads as work thrown away -- and answered a real failure
/// by printing the Dart exception into the same strip.
void main() {
  testWidgets('a cancelled save is not a discarded report', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    FilePicker.platform = _CancellingPicker();
    await _pump(tester);
    await _create(tester);

    expect(find.text('Not saved.'), findsOneWidget);
    expect(
      find.textContaining('discarded'),
      findsNothing,
      reason: 'nothing was thrown away; the file was simply not written',
    );
  });

  testWidgets('a save that succeeds still says so', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    FilePicker.platform = _SavingPicker();
    await _pump(tester);
    await _create(tester);

    expect(find.text('Report saved.'), findsOneWidget);
  });

  testWidgets('a failure is a sentence, not a Dart exception', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    FilePicker.platform = _FailingPicker();
    await _pump(tester);
    await _create(tester);

    expect(
      find.text('Could not save the report. There is no room left.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception'), findsNothing);
  });
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SpendWiseTheme.dark,
      home: ReportScreen(viewModel: _Fake()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _create(WidgetTester tester) async {
  // The button sits below the fold on a phone, and a lazy ListView has not
  // built it yet, so it has to be scrolled to rather than found.
  final button = find.byType(PrimaryAction);
  await tester.dragUntilVisible(
    button,
    find.byType(ListView),
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
  expect(
    find.textContaining('Create'),
    findsOneWidget,
    reason: 'the period must have something in it to report on',
  );
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _CancellingPicker extends FilePicker {
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => null;
}

class _SavingPicker extends FilePicker {
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => '/somewhere/spendwise.pdf';
}

class _FailingPicker extends FilePicker {
  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async => throw StateError('There is no room left');
}

class _Fake extends ChangeNotifier implements SpendWiseAdvancedViewModel {
  static final _now = DateTime.now();

  @override
  List<TransactionViewData> get transactions => [
    TransactionViewData(
      id: 'tx-1',
      title: 'Grocer',
      subtitle: 'Everyday',
      amount: const MoneyViewData(-450000),
      kind: TransactionKind.expense,
      occurredAt: DateTime(_now.year, _now.month, 2),
      category: 'Groceries',
      accountId: 'bank',
      accountName: 'Everyday',
    ),
  ];

  @override
  List<AccountViewData> get accounts => const [
    AccountViewData(
      id: 'bank',
      name: 'Everyday',
      type: 'Bank',
      balance: MoneyViewData(2500000),
    ),
  ];

  @override
  List<DebtViewData> get debts => const [];

  @override
  List<CategoryViewData> get categories => const [];

  @override
  String? viewPreference(String key) => null;

  @override
  void setViewPreference(String key, String value) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
