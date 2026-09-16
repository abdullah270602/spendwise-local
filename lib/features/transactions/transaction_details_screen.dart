import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/failure_text.dart';
import '../../app/theme.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/shape_kit.dart';
import '../debts/debt_matching.dart';
import '../debts/debt_sheets.dart' as debt_sheets;
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

/// One entry, drawn as a receipt: what it was, what it came to, what it did
/// to the account, and where it came from — in that order and once each.
///
/// The screen this replaced stated the entry's *type* twice (a header eyebrow,
/// then a "Type:" row), its *category* twice (the header subtitle, then a
/// "Category:" row) and its *account* three times (subtitle, "Account:" row,
/// and the heading of the balance block). A Details list of five rows carried
/// facts the header above it had already carried, at the same weight as the
/// one figure on the page an owner can actually check against a bank
/// statement. The list is gone: category and time ride one mono line under the
/// amount, and the account is named once, on the balance block, because that
/// is where it is being checked.
///
/// Two things are loud — the amount and the balance. Everything else is one
/// hairline row until it is asked for.
class TransactionDetailsScreen extends StatelessWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.viewModel,
    required this.transaction,
  });
  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    // The screen is handed a snapshot taken when it was pushed. Attaching an
    // entry to a loan rewrites the entry's own category and its debt, not
    // just the section that offered it, so the whole page reads the entry
    // back rather than redrawing the copy it arrived with.
    animation: viewModel,
    builder: (context, _) => _body(context),
  );

  Widget _body(BuildContext context) {
    final live =
        viewModel.transactions
            .where((item) => item.id == transaction.id)
            .firstOrNull ??
        transaction;
    final debt = live.debtId == null
        ? null
        : viewModel.uiDebts.where((item) => item.id == live.debtId).firstOrNull;
    final accounts = viewModel.accounts;
    final cash = _cashWithdrawal(live, accounts);

    // The Ledger paints a transfer `mine` -- the palette's third hue, the one
    // that answers "did this only move between accounts you already own".
    // This screen reached for `warning`, a hardcoded amber that
    // `SpendWiseColors.apply` never touches, so the same entry was one colour
    // in the register and another when you tapped it, and stayed amber
    // through every palette the user chose.
    final color = switch (live.kind) {
      TransactionKind.expense => SpendWiseColors.spend,
      TransactionKind.income => SpendWiseColors.keep,
      TransactionKind.transfer => SpendWiseColors.mine,
    };
    // Held money is deliberately given no hue: keep and spend both mean
    // "yours", and drawing somebody else's money in either of them would be
    // the picture disagreeing with the rule the enum exists to enforce.
    final storyTone = debt == null
        ? color
        : debt_sheets.toneForDebtKind(debt.kind);
    final figureTone = debt?.kind == DebtKind.holding
        ? SpendWiseColors.dim
        : color;

    final printed = formatMoney(
      live.amount,
      signed: live.kind != TransactionKind.transfer,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          IconButton(
            onPressed: () => _showCorrection(context),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit classification',
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                await _confirmDelete(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete transaction')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          SpendWiseTheme.gutter,
          14,
          SpendWiseTheme.gutter,
          40,
        ),
        children: [
          // The one eyebrow on the page carries which of the stories this
          // entry is, in that story's hue. On a debt entry it replaces the
          // category rather than joining it: the category *is* the story
          // ("Lent out"), and saying it in both places is the duplication
          // this screen was redrawn to remove.
          Eyebrow(_story(live, debt, cash: cash), color: storyTone),
          const SizedBox(height: 8),
          Text(live.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          // The title may wrap; the figure may not — a wrapped amount reads
          // as two amounts. Past eleven characters the type steps down one
          // size rather than reflowing, and the scale-down underneath is the
          // guard for a large font scale, not the usual path.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              printed,
              maxLines: 1,
              softWrap: false,
              style:
                  (printed.length > 11
                          ? SpendWiseType.figure.copyWith(
                              fontSize: 28,
                              letterSpacing: -.9,
                            )
                          : SpendWiseType.figure)
                      .copyWith(color: figureTone),
            ),
          ),
          const SizedBox(height: 10),
          Text(_factLine(live, debt), style: SpendWiseType.meta),
          if (live.note.isNotEmpty) _Quoted(live.note),
          if (_settlementNote(live, debt) case final String said) _Quoted(said),
          ..._flags(live, accounts, cash: cash),
          const SizedBox(height: 24),
          _BalanceTrail(
            transaction: live,
            onFile: () => _showCorrection(context),
          ),
          _LoanSection(viewModel: viewModel, transaction: live, debt: debt),
          const SizedBox(height: 4),
          if (live.kind != TransactionKind.transfer && debt == null)
            _WhoseMoney(viewModel: viewModel, transaction: live),
          _Evidence(transaction: live),
        ],
      ),
    );
  }

  /// Whether this entry is money leaving a bank for the owner's own pocket.
  ///
  /// A withdrawal is the one transfer the app asserts from a single alert,
  /// and the owner's instinct is to read it as money spent. Nothing else on
  /// the page says otherwise.
  static bool _cashWithdrawal(
    TransactionViewData entry,
    List<AccountViewData> accounts,
  ) {
    if (entry.kind != TransactionKind.transfer) return false;
    final into = accounts
        .where((item) => item.id == entry.toAccountId)
        .firstOrNull;
    return into?.isCash ?? false;
  }

  /// The eyebrow: which story this entry is.
  static String _story(
    TransactionViewData entry,
    DebtViewData? debt, {
    required bool cash,
  }) {
    if (debt != null) return debt.kind.categoryName;
    if (cash) return 'Cash';
    return switch (entry.kind) {
      TransactionKind.expense => 'Expense',
      TransactionKind.income => 'Income',
      TransactionKind.transfer => 'Transfer',
    };
  }

  /// Category, day and time, in the order a person says them.
  ///
  /// The category is dropped on a transfer — the app's own category for one
  /// is literally named "Between your accounts", and the eyebrow has just
  /// said TRANSFER — and on a debt entry, where the category is the story.
  static String _factLine(TransactionViewData entry, DebtViewData? debt) {
    final at = entry.occurredAt.toLocal();
    final says =
        entry.kind != TransactionKind.transfer &&
        debt == null &&
        entry.category.isNotEmpty;
    return [
      if (says) entry.category.toUpperCase(),
      DateFormat('EEE d MMM').format(at).toUpperCase(),
      '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}',
    ].join('  ·  ');
  }

  /// What attaching this entry to a loan did to the month, for the entry that
  /// paid into one rather than the entry that opened it.
  static String? _settlementNote(
    TransactionViewData entry,
    DebtViewData? debt,
  ) {
    if (debt == null) return null;
    // The opening leg of a loan moves the same way the loan does; a payment
    // into it moves the other way. That is the only thing telling the two
    // apart, and it is exactly what the matcher tests.
    final incoming = entry.kind == TransactionKind.income;
    if (incoming != debt.lent) return null;
    return switch (debt.kind) {
      DebtKind.lent =>
        'Stopped counting as income. It came off what was still out.',
      DebtKind.borrowed =>
        'Stopped counting as spending. It came off what you owe.',
      DebtKind.holding =>
        'Not spending — it was never yours. It came off what you are holding.',
    };
  }

  /// The states an entry can be in that change how it should be read.
  ///
  /// One bordered block each, hue on the left edge only, never a fill.
  List<Widget> _flags(
    TransactionViewData entry,
    List<AccountViewData> accounts, {
    required bool cash,
  }) {
    final flags = <Widget>[];
    if (cash) {
      flags.add(
        _Flag(
          tone: SpendWiseColors.mine,
          heading: 'Not spending. Not yet.',
          body:
              'This left the bank but it never left you — it is in a '
              'pocket. It becomes spending only when you record what the '
              'cash went on.',
        ),
      );
    }
    if (!entry.isReviewed) {
      final read = entry.evidence.isEmpty
          ? null
          : entry.evidence
                .map((item) => item.confidence)
                .reduce((a, b) => a > b ? a : b);
      flags.add(
        _Flag(
          tone: SpendWiseColors.spend,
          heading: read != null && read < .8
              ? 'Posted, but only ${(read * 100).round()}% sure'
              : 'Posted, but not confirmed yet',
          body:
              'It is in your ledger and counted in the month. Below 80% '
              'SpendWise marks the entry rather than trusting it. Review is '
              'where it gets confirmed; Edit is where it gets corrected.',
        ),
      );
    }
    // Reconciliation rebuilds automatic entries from stored evidence on
    // every run, so an owner who has corrected one has every reason to
    // wonder whether the next sync will quietly undo them. This is the
    // promise worth printing, in the `mine` hue rather than an alarm colour,
    // because nothing here is wrong.
    if (entry.isLocked && entry.evidenceCount > 0 && entry.debtId == null) {
      flags.add(
        _Flag(
          tone: SpendWiseColors.mine,
          heading: 'Your answer stands',
          body:
              'You settled something about this entry by hand. SpendWise '
              're-reads stored alerts every time it reconciles and will not '
              'touch this one again — and the alert underneath is kept '
              'exactly as it arrived.',
        ),
      );
    }
    // Two currencies in one entry is the one arithmetic on this page the
    // owner cannot check, so it is named rather than quietly performed.
    final held = accounts
        .where((item) => item.id == entry.accountId)
        .firstOrNull
        ?.currency;
    if (held != null && held != entry.amount.currency) {
      flags.add(
        _Flag(
          tone: SpendWiseColors.spend,
          heading:
              'Charged in ${entry.amount.currency}. '
              'The account keeps $held.',
          body:
              'SpendWise does not convert currencies and will not guess a '
              'rate. The balance below moves by the figure as it was read, '
              'not by what this cost in $held.',
        ),
      );
    }
    return [
      for (final flag in flags) ...[const SizedBox(height: 16), flag],
    ];
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: const Text(
          'The ledger entry will be removed. Its original notification or import evidence remains available for reconciliation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SpendWiseColors.expense,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete transaction'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    // Grabbed before the pop below: once this screen is gone its own
    // Scaffold is gone with it, and the messenger and navigator this screen
    // sat inside are what stay -- the same reason the review inbox grabs
    // both before it pops the sheet it deletes from.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = transaction.id;
    try {
      await viewModel.deleteTransaction(id);
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(failureText('Could not delete', error))),
        );
      }
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Transaction deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => viewModel.restoreTransaction(id),
        ),
      ),
    );
  }

  Future<void> _showCorrection(BuildContext context) async {
    var kind = transaction.kind;
    var category = transaction.category;
    final accounts = viewModel.accounts;
    final accountIds = accounts.map((item) => item.id).toSet();
    String? accountId = accountIds.contains(transaction.accountId)
        ? transaction.accountId
        : accounts.firstOrNull?.id;
    String? toAccountId =
        accountIds.contains(transaction.toAccountId) &&
            transaction.toAccountId != accountId
        ? transaction.toAccountId
        : accounts.where((item) => item.id != accountId).firstOrNull?.id;
    var saving = false;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 16),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit classification',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Change the type, category, or account. Original source evidence stays unchanged.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                SegmentedButton<TransactionKind>(
                  segments: const [
                    ButtonSegment(
                      value: TransactionKind.expense,
                      label: Text('Expense'),
                    ),
                    ButtonSegment(
                      value: TransactionKind.income,
                      label: Text('Income'),
                    ),
                    ButtonSegment(
                      value: TransactionKind.transfer,
                      label: Text('Transfer'),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: saving
                      ? null
                      : (value) => setModalState(() {
                          kind = value.first;
                          if (kind == TransactionKind.transfer) {
                            if (toAccountId == null ||
                                toAccountId == accountId) {
                              toAccountId = accounts
                                  .where((item) => item.id != accountId)
                                  .firstOrNull
                                  ?.id;
                            }
                            // Saying "this was a transfer" and leaving the
                            // category alone left the entry reading "Income"
                            // in the ledger after the correction -- which is
                            // the very thing being corrected. Worse, the
                            // ledger learns from a hand-set category, so the
                            // wrong one taught the classifier to repeat the
                            // mistake on the next alert from the same sender.
                            final transferCategory = viewModel.uiCategories
                                .where((item) => item.id == 'transfer')
                                .firstOrNull;
                            if (transferCategory != null) {
                              category = transferCategory.name;
                            }
                          }
                        }),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: saving
                      ? null
                      : () async {
                          final picked = await pickCategory(
                            context,
                            viewModel: viewModel,
                            kind: kind,
                            current: category,
                          );
                          if (picked != null) {
                            setModalState(() => category = picked);
                          }
                        },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Category'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(category, style: SpendWiseType.row),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: SpendWiseColors.dim,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: accounts
                      .map(
                        (value) => DropdownMenuItem(
                          value: value.id,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setModalState(() {
                          accountId = value;
                          if (toAccountId == accountId) {
                            toAccountId = accounts
                                .where((item) => item.id != accountId)
                                .firstOrNull
                                ?.id;
                          }
                        }),
                ),
                if (kind == TransactionKind.transfer) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('destination-$accountId-$toAccountId'),
                    initialValue: toAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Destination account',
                    ),
                    items: accounts
                        .where((value) => value.id != accountId)
                        .map(
                          (value) => DropdownMenuItem(
                            value: value.id,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setModalState(() => toAccountId = value),
                  ),
                  if (accounts.length < 2) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Add another account before classifying this as a transfer.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: saving || accounts.isEmpty
                        ? null
                        : () async {
                            if (accountId == null) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text('Choose an account first.'),
                                ),
                              );
                              return;
                            }
                            if (kind == TransactionKind.transfer &&
                                (toAccountId == null ||
                                    toAccountId == accountId)) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Choose a different destination account.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setModalState(() => saving = true);
                            try {
                              await viewModel.uiCorrectTransaction(
                                transaction.id,
                                TransactionCorrectionDraft(
                                  kind: kind,
                                  category: category,
                                  accountId: accountId,
                                  toAccountId: toAccountId,
                                ),
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            } on UnsupportedError {
                              if (sheetContext.mounted) {
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'This ledger build cannot edit imported records yet.',
                                    ),
                                  ),
                                );
                              }
                            } catch (error) {
                              if (sheetContext.mounted) {
                                setModalState(() => saving = false);
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not save changes: ${error.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '')}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save classification'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved == true && context.mounted) Navigator.pop(context);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Prose the owner wrote, or one sentence about what this entry did.
///
/// A left hairline, not a box: a bordered panel would compete with the
/// balance block for the same weight, and a single rule says "quoted" and
/// costs nothing.
class _Quoted extends StatelessWidget {
  const _Quoted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.only(left: 11),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: SpendWiseColors.edge)),
    ),
    child: Text(text, style: SpendWiseType.body.copyWith(fontSize: 13.5)),
  );
}

/// A state the entry is in: one bordered block with the hue on its left edge
/// and nowhere else. State is never a fill on this screen.
class _Flag extends StatelessWidget {
  const _Flag({required this.tone, required this.heading, required this.body});

  final Color tone;
  final String heading, body;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: tone, width: 2),
        top: BorderSide(color: SpendWiseColors.line),
        right: BorderSide(color: SpendWiseColors.line),
        bottom: BorderSide(color: SpendWiseColors.line),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(heading, style: SpendWiseType.rowStrong.copyWith(fontSize: 14)),
        const SizedBox(height: 6),
        Text(body, style: SpendWiseType.body.copyWith(fontSize: 12.5)),
      ],
    ),
  );
}

/// Full-width bordered action. Quieter than [PrimaryAction], and still a
/// control rather than a sentence that happens to be tappable.
class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.onPressed, this.sub});

  final String label;
  final String? sub;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: SpendWiseColors.edge),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: SpendWiseType.rowStrong.copyWith(fontSize: 14.5),
                  ),
                  if (sub != null) ...[
                    const SizedBox(height: 3),
                    Text(sub!, style: SpendWiseType.metaTight),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('›', style: TextStyle(color: SpendWiseColors.dim)),
          ],
        ),
      ),
    ),
  );
}

/// One hairline row that opens. The whole foot of this page is made of them.
///
/// Hand-rolled rather than [ExpansionTile]: the stock tile ships its own
/// chevron rotation and expand animation, on a duration this app never chose
/// and with no way to honour reduced motion short of reaching past the widget
/// to silence it.
class _Disclosure extends StatefulWidget {
  const _Disclosure({
    required this.title,
    required this.child,
    this.sub,
    this.last = false,
  });

  final String title;
  final String? sub;
  final Widget child;
  final bool last;

  @override
  State<_Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<_Disclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    // 220ms is the short end of the app's own range: a chevron and a detail
    // panel are the smallest motion this screen makes.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: SpendWiseColors.line),
          bottom: widget.last
              ? BorderSide(color: SpendWiseColors.line)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: SpendWiseType.row),
                          if (widget.sub != null) ...[
                            const SizedBox(height: 3),
                            Text(widget.sub!, style: SpendWiseType.metaTight),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedRotation(
                      turns: _open ? .5 : 0,
                      duration: duration,
                      curve: Curves.easeOutQuint,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: SpendWiseColors.dim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutQuint,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: widget.child,
                  ),
          ),
        ],
      ),
    );
  }
}

/// A mono key and its value, right-aligned. Machinery, not prose.
class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label.toUpperCase(), style: SpendWiseType.metaTight),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: SpendWiseType.meta.copyWith(color: const Color(0xFF9AA1A5)),
          ),
        ),
      ],
    ),
  );
}

/// What this entry did to the balance of every account it touched.
///
/// Every other figure in this app is derived from something derived, and past
/// a certain number of derivations a person is entitled to stop believing
/// them. This is the one an owner can hold against a bank statement and check
/// line by line without trusting a single sum SpendWise made.
///
/// Worked downward, the way a sum is written. Side by side the three figures
/// did not line up, the arithmetic had to be spelled out with a drawn minus
/// and equals to read as arithmetic at all, and three eight-digit numbers
/// were cramped at 360dp. Stacked, the digits align and the rule above the
/// total says "sum" without a word.
class _BalanceTrail extends StatelessWidget {
  const _BalanceTrail({required this.transaction, required this.onFile});

  final TransactionViewData transaction;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading('Balance around this'),
      const SizedBox(height: 10),
      // An alert that matched no account has no balance to have moved, and
      // inventing one would be the app asserting something it cannot know.
      // The block stays where it was, under the same heading, so the absence
      // reads as an absence rather than as a section that failed to draw.
      if (transaction.balances.isEmpty) ...[
        Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No account',
                style: SpendWiseType.row.copyWith(color: SpendWiseColors.dim),
              ),
              const SizedBox(height: 6),
              Text(
                'There is nothing to show. This entry reached no account in '
                'your list, so there is no balance for it to have moved — '
                'and SpendWise will not invent one.',
                style: SpendWiseType.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              _GhostButton(
                label: 'File it against an account',
                onPressed: onFile,
              ),
            ],
          ),
        ),
        if (_stillCounted case final String said) ...[
          const SizedBox(height: 7),
          Text(said, style: SpendWiseType.metaTight),
        ],
      ] else
        for (final change in transaction.balances) ...[
          _TrailBlock(change: change),
          const SizedBox(height: 8),
        ],
      const SizedBox(height: 14),
    ],
  );

  /// The month is still right even when the reconciliation check is missing.
  /// Two different truths, and only one of them is broken.
  String? get _stillCounted {
    final month = DateFormat('MMMM')
        .format(transaction.occurredAt.toLocal())
        .toUpperCase();
    return switch (transaction.kind) {
      TransactionKind.expense => "STILL COUNTED IN $month'S SPENDING",
      TransactionKind.income => "STILL COUNTED IN $month'S INCOME",
      TransactionKind.transfer => null,
    };
  }
}

/// One account, before and after.
class _TrailBlock extends StatelessWidget {
  const _TrailBlock({required this.change});

  final AccountBalanceChange change;

  @override
  Widget build(BuildContext context) {
    // Paisa are contagious on purpose: the moment one figure in a block needs
    // decimals, all three show them, or the column of tabular digits stops
    // lining up and the subtraction stops being checkable by eye — which is
    // the block's only job.
    final cents = [
      change.beforeMinor,
      change.deltaMinor,
      change.afterMinor,
    ].any((minor) => minor % 100 != 0);
    final moved = change.deltaMinor < 0
        ? SpendWiseColors.spend
        : SpendWiseColors.keep;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(change.accountName, style: SpendWiseType.row),
          const SizedBox(height: 6),
          _TrailStep(
            label: 'Before',
            figure: _figure(change.beforeMinor, cents: cents),
            tone: SpendWiseColors.dim,
          ),
          _TrailStep(
            label: 'Moved',
            // The sign rides on the figure. There is no drawn minus or
            // equals between the cells: a rule above the total means "total
            // below" and needs no other label.
            figure:
                '${change.deltaMinor < 0 ? '−' : '+'} '
                '${_figure(change.deltaMinor.abs(), cents: cents)}',
            tone: moved,
          ),
          _TrailStep(
            label: 'After',
            figure: _figure(change.afterMinor, cents: cents),
            tone: SpendWiseColors.fg,
            sum: true,
          ),
        ],
      ),
    );
  }

  /// Grouped digits, with paisa only when the block as a whole needs them.
  ///
  /// [formatAmount] drops `.00` whatever it is asked for, which is right in a
  /// register and wrong in a column that has to line up.
  static String _figure(int minor, {required bool cents}) {
    final base = formatMinor(minor, cents: false);
    if (!cents) return base;
    final paisa = (minor.abs() % 100).toString().padLeft(2, '0');
    return '$base.$paisa';
  }
}

class _TrailStep extends StatelessWidget {
  const _TrailStep({
    required this.label,
    required this.figure,
    required this.tone,
    this.sum = false,
  });

  final String label, figure;
  final Color tone;
  final bool sum;

  @override
  Widget build(BuildContext context) => Container(
    margin: EdgeInsets.only(top: sum ? 4 : 0),
    padding: EdgeInsets.only(top: sum ? 9 : 5, bottom: 5),
    decoration: sum
        ? BoxDecoration(
            border: Border(top: BorderSide(color: SpendWiseColors.edge)),
          )
        : null,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Eyebrow(label)),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              figure,
              maxLines: 1,
              softWrap: false,
              style: SpendWiseType.rowStrong.copyWith(
                color: tone,
                fontSize: sum ? 17 : 15,
                fontWeight: sum ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The proportion of a loan that has come home, drawn flat at its true
/// fraction, square, with no motion.
///
/// It is never the only statement: the figures it summarises are written out
/// underneath it, and this is a second reading of them. Deliberately not
/// Home's ribbon — that shape is one bar of income *fanning* into parts that
/// coexist, and a part-paid loan is one fixed principal eaten from one end.
/// Drawing it as a fan would assert a split that is not there.
class LoanShareRule extends StatelessWidget {
  const LoanShareRule({super.key, required this.fraction, required this.tone});

  /// How much of the principal has come back, 0 to 1.
  final double fraction;
  final Color tone;

  /// How much of a rule [width] wide is actually filled.
  ///
  /// Two guards, both of them refusals. A returned share too small to fill
  /// one pixel draws nothing at all, rather than a sliver that reads as
  /// "something came back" on a loan where nothing has. And a share under
  /// 100% never fills the last pixel, so "nearly settled" can never be
  /// mistaken for "settled". The printed percentage rounds; the figures
  /// above it never do, and those figures are the record.
  static double fillWidth({required double width, required double fraction}) {
    if (width <= 0) return 0;
    final share = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    if (share >= 1) return width;
    final fill = width * share;
    if (fill < 1) return 0;
    return fill > width - 1 ? width - 1 : fill;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 11, bottom: 7),
    child: SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerLeft,
          child: ColoredBox(
            color: SpendWiseColors.line,
            child: SizedBox(
              key: const Key('loan-share-track'),
              width: constraints.maxWidth,
              height: 4,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  key: const Key('loan-share-fill'),
                  width: fillWidth(
                    width: constraints.maxWidth,
                    fraction: fraction,
                  ),
                  height: 4,
                  child: ColoredBox(color: tone),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// One payment into a loan, as this screen knows about it.
class _Instalment {
  const _Instalment({
    required this.label,
    required this.minor,
    required this.isThisEntry,
    this.at,
  });

  final String label;
  final int minor;
  final bool isThisEntry;
  final DateTime? at;
}

/// Lending is invisible to a bank alert, so this is where a person tells the
/// ledger what really happened — and, once they have, where the loan says how
/// much of itself has come home.
class _LoanSection extends StatelessWidget {
  const _LoanSection({
    required this.viewModel,
    required this.transaction,
    required this.debt,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final DebtViewData? debt;

  @override
  Widget build(BuildContext context) {
    final loan = debt;
    if (loan != null) return _attached(context, loan);
    if (transaction.kind == TransactionKind.transfer) return _refusal(context);
    return _unattached(context);
  }

  /// The loan this entry belongs to, with its own arithmetic worked downward
  /// in the same shape as the balance trail — and a 2px tone rule down its
  /// left edge that the trail never has. A loan is not an account and must
  /// not be read as one.
  Widget _attached(BuildContext context, DebtViewData loan) {
    final incoming = transaction.kind == TransactionKind.income;
    final paidInto = incoming != loan.lent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(_heading(loan, paidInto: paidInto)),
        const SizedBox(height: 10),
        _LoanBlock(
          viewModel: viewModel,
          debt: loan,
          entryId: transaction.id,
          instalments: _instalmentsOf(
            debt: loan,
            transactions: viewModel.transactions,
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  String _heading(DebtViewData loan, {required bool paidInto}) {
    if (loan.kind == DebtKind.holding) {
      return paidInto ? 'What this passed on' : 'Holding it for';
    }
    final noun = loan.kind == DebtKind.lent ? 'loan' : 'debt';
    if (!paidInto) return 'The $noun';
    return loan.isSettled
        ? 'The $noun this closed'
        : 'The $noun this paid into';
  }

  /// Money moving between the owner's own accounts is not somebody paying
  /// them back. The code has always known it — [debtMatchesFor] returns
  /// nothing for a transfer and so does [debtsOpenTo], the hand picker that
  /// is otherwise deliberately permissive — and nothing on screen said so.
  /// A correct decision the owner cannot see is indistinguishable from a bug.
  ///
  /// No tone rule down its left edge: lent is sage, borrowed is clay, held is
  /// dim, and this is none of the three. The absence of the colour is the
  /// statement.
  Widget _refusal(BuildContext context) {
    final debts = viewModel.uiDebts;
    // Only worth saying to somebody who has loans. A refusal is an answer to
    // a question, and an owner who has never recorded one is not asking it.
    if (debts.isEmpty) return const SizedBox.shrink();
    final open = debts
        .where((item) => !item.isSettled && item.outstanding.minorUnits > 0)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('No loan is offered here'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
          decoration: BoxDecoration(
            border: Border.all(color: SpendWiseColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Both sides of this are yours. Money moving between your own '
                'accounts is not somebody paying you back, so SpendWise will '
                'not suggest a loan against it — and it is not in the picker '
                'either.',
                style: SpendWiseType.body.copyWith(fontSize: 13),
              ),
              if (open.isNotEmpty) ...[
                const SizedBox(height: 9),
                // Naming what this did not touch is the load-bearing line.
                // Without it the owner has to take on faith that their own
                // transfer did not quietly eat somebody's repayment.
                Text(
                  open.length == 1
                      ? '${open.single.counterparty} is still open at '
                            '${formatMoney(open.single.outstanding)}, and '
                            'this did not touch it.'
                      : 'Your ${open.length} open loans are untouched by this.',
                  style: SpendWiseType.body.copyWith(fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  /// What an entry that belongs to no loan offers: the loans it could be the
  /// end of. The three stories it could be the *start* of live below, behind
  /// one disclosure, because most entries are none of them.
  Widget _unattached(BuildContext context) {
    final matches = debtMatchesFor(
      transaction: transaction,
      debts: viewModel.uiDebts,
    );
    final open = debtsOpenTo(
      transaction: transaction,
      debts: viewModel.uiDebts,
    );
    if (matches.isEmpty && open.isEmpty) return const SizedBox.shrink();
    final incoming = transaction.kind == TransactionKind.income;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('This might close something'),
        const SizedBox(height: 10),
        if (matches.isNotEmpty)
          _Suggestion(
            viewModel: viewModel,
            transaction: transaction,
            match: matches.first,
            others: matches.length - 1,
          )
        else
          // Opening a new loan and closing an old one are opposite answers to
          // the same question, and only one of them used to be on this
          // screen. It was a bare sage sentence acting as a button: no edge,
          // no target, nothing to say it could be pressed. It is a bordered
          // row now, and when exactly one loan could take the money it names
          // that loan and what is still out on it.
          _GhostButton(
            label: incoming
                ? 'This is money coming back on a loan'
                : 'This is money going back on a loan',
            sub: open.length == 1
                ? '${open.single.counterparty.toUpperCase()}  ·  '
                      '${formatAmount(open.single.outstanding, cents: false)}'
                      ' STILL OUT'
                : '${open.length} OPEN TO CHOOSE FROM',
            onPressed: () => debt_sheets.settleFromEntry(
              context,
              viewModel: viewModel,
              transaction: transaction,
            ),
          ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// Every payment into [debt] this screen can see, oldest first.
///
/// Read back off the entries themselves rather than out of the settlements
/// table, which no view model surfaces: a settlement carries the whole entry
/// it was made from, and the opening leg of a loan moves the opposite way to
/// every payment into it. What was typed in as a bare amount has no entry at
/// all, so it is carried as one row of its own.
List<_Instalment> _instalmentsOf({
  required DebtViewData debt,
  required Iterable<TransactionViewData> transactions,
  String? thisEntryId,
}) {
  final rows = <_Instalment>[
    for (final item in transactions)
      if (item.debtId == debt.id &&
          (item.kind == TransactionKind.income) == debt.lent)
        _Instalment(
          label: DateFormat('d MMM')
              .format(item.occurredAt.toLocal())
              .toUpperCase(),
          minor: item.amount.minorUnits.abs(),
          isThisEntry: item.id == thisEntryId,
          at: item.occurredAt,
        ),
  ]..sort((a, b) => a.at!.compareTo(b.at!));
  if (debt.settledByHand.minorUnits > 0) {
    rows.add(
      _Instalment(
        label: 'RECORDED BY HAND',
        minor: debt.settledByHand.minorUnits,
        isThisEntry: false,
      ),
    );
  }
  return rows;
}

/// A loan's own arithmetic: the principal, what has come back, and what is
/// still out — with the instalments that brought it.
///
/// The data has been in `debt_settlements` since loans arrived, and nothing
/// ever drew a loan that was half home. Recording a repayment against a
/// ten-thousand loan and coming back to an entry that said only "5,000 still
/// out" gave the owner no way to tell a loan barely started from one nearly
/// finished.
class _LoanBlock extends StatelessWidget {
  const _LoanBlock({
    required this.viewModel,
    required this.debt,
    required this.entryId,
    required this.instalments,
  });

  final SpendWiseViewModel viewModel;
  final DebtViewData debt;
  final String entryId;
  final List<_Instalment> instalments;

  /// The three rows, named for the side of the loan the owner is standing on.
  (String, String, String) get _labels => switch (debt.kind) {
    DebtKind.lent => ('Principal', 'Back', 'Still out'),
    DebtKind.borrowed => ('Principal', 'Paid back', 'Still owed'),
    DebtKind.holding => ('Came in', 'Passed on', 'Still holding'),
  };

  String get _backWord => switch (debt.kind) {
    DebtKind.lent => 'BACK',
    DebtKind.borrowed => 'PAID BACK',
    DebtKind.holding => 'PASSED ON',
  };

  String get _openLabel => switch (debt.kind) {
    DebtKind.lent => 'Open the loan',
    DebtKind.borrowed => 'Open the debt',
    DebtKind.holding => 'Open what you are holding',
  };

  /// A loan is finished only when all of it came home. One written off is
  /// closed with money still out, and collapsing it to "all back" would be
  /// the screen inventing a repayment that never happened.
  bool get _finished =>
      debt.isSettled && debt.settled.minorUnits >= debt.principal.minorUnits;

  @override
  Widget build(BuildContext context) {
    final tone = debt_sheets.toneForDebtKind(debt.kind);
    final principal = debt.principal.minorUnits;
    final fraction = principal <= 0 ? 0.0 : debt.settled.minorUnits / principal;
    final (first, second, total) = _labels;
    final payments = _instalmentsOf(
      debt: debt,
      transactions: viewModel.transactions,
      thisEntryId: entryId,
    );
    final shown = payments.length > 3
        ? payments.sublist(payments.length - 3)
        : payments;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        border: Border(
          // The one thing that separates a loan from an account at a glance.
          left: BorderSide(
            color: _finished ? SpendWiseColors.dim : tone,
            width: 2,
          ),
          top: BorderSide(color: SpendWiseColors.line),
          right: BorderSide(color: SpendWiseColors.line),
          bottom: BorderSide(color: SpendWiseColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  debt.counterparty,
                  style: SpendWiseType.row.copyWith(
                    color: _finished ? SpendWiseColors.dim : SpendWiseColors.fg,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(_when, style: SpendWiseType.metaTight),
            ],
          ),
          LoanShareRule(
            fraction: fraction,
            tone: _finished ? SpendWiseColors.dim : tone,
          ),
          Text(_cap(fraction), style: SpendWiseType.metaTight),
          // A finished loan is history, so it is drawn as history: three
          // figures where one of them is now 0 and another equals the
          // principal is arithmetic nobody needs performed. One mono line
          // carries the outcome and the payments fold away behind it.
          if (!_finished) ...[
            const SizedBox(height: 4),
            _TrailStep(
              label: first,
              figure: formatAmount(debt.principal, cents: false),
              tone: SpendWiseColors.dim,
            ),
            _TrailStep(
              label: second,
              figure: formatAmount(debt.settled, cents: false),
              tone: SpendWiseColors.dim,
            ),
            _TrailStep(
              label: total,
              figure: formatAmount(debt.outstanding, cents: false),
              tone: tone,
              sum: true,
            ),
          ],
          if (shown.isNotEmpty)
            _History(
              rows: shown,
              hidden: payments.length - shown.length,
              folded: _finished,
            ),
          const SizedBox(height: 12),
          _GhostButton(
            label: _openLabel,
            onPressed: () =>
                debt_sheets.openDebt(context, viewModel: viewModel, debt: debt),
          ),
        ],
      ),
    );
  }

  String get _when {
    final opened = DateFormat('d MMM')
        .format(debt.openedAt.toLocal())
        .toUpperCase();
    final closed = debt.closedAt;
    if (closed == null) return 'OPEN SINCE $opened';
    final on = DateFormat('d MMM').format(closed.toLocal()).toUpperCase();
    return _finished ? 'SETTLED $on' : 'WRITTEN OFF $on';
  }

  String _cap(double fraction) {
    final back = debt.settled.minorUnits;
    if (_finished) {
      final days = debt.closedAt?.difference(debt.openedAt).inDays;
      return [
        'ALL ${formatAmount(debt.principal, cents: false)} $_backWord',
        if (instalments.isNotEmpty)
          '${instalments.length} '
              'PAYMENT${instalments.length == 1 ? '' : 'S'}',
        if (days != null && days > 0) '$days DAYS',
      ].join('  ·  ');
    }
    if (back <= 0) return 'NOTHING $_backWord YET';
    return '${formatAmount(debt.settled, cents: false)} OF '
        '${formatAmount(debt.principal, cents: false)} $_backWord'
        '  ·  ${(fraction * 100).round()}%';
  }
}

/// The instalments, in mono, because a list of payments is a record rather
/// than prose.
class _History extends StatelessWidget {
  const _History({
    required this.rows,
    required this.hidden,
    required this.folded,
  });

  final List<_Instalment> rows;
  final int hidden;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hidden > 0) _HistoryRow(label: '+ $hidden MORE', figure: ''),
        for (final row in rows)
          _HistoryRow(
            // "This entry" rather than the date and figure already printed
            // at the top of the screen.
            label: row.isThisEntry ? '${row.label}  ·  THIS ENTRY' : row.label,
            figure: formatMinor(row.minor, cents: false),
            lit: row.isThisEntry,
          ),
      ],
    );
    if (!folded) {
      return Container(
        margin: const EdgeInsets.only(top: 11),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: SpendWiseColors.line)),
        ),
        child: list,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: _Disclosure(title: 'How it came back', child: list),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.label,
    required this.figure,
    this.lit = false,
  });

  final String label, figure;
  final bool lit;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 7),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: SpendWiseType.metaTight.copyWith(
              color: lit ? const Color(0xFF9AA1A5) : SpendWiseColors.dim,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          figure,
          style: SpendWiseType.metaTight.copyWith(
            color: lit ? SpendWiseColors.fg : const Color(0xFF9AA1A5),
          ),
        ),
      ],
    ),
  );
}

/// The one loan this entry most looks like, offered as a question.
///
/// Never acted on by itself. Settling a loan the owner did not settle is the
/// expensive mistake here: a loan they believe is closed is money they will
/// never ask for again, and nothing in a bank alert can carry that decision.
class _Suggestion extends StatelessWidget {
  const _Suggestion({
    required this.viewModel,
    required this.transaction,
    required this.match,
    required this.others,
  });

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;
  final DebtMatch match;

  /// How many other open loans this entry also looks like.
  final int others;

  @override
  Widget build(BuildContext context) {
    final debt = match.debt;
    final tone = debt_sheets.toneForDebtKind(debt.kind);
    final headline = switch (debt.kind) {
      DebtKind.lent => 'Is this ${debt.counterparty} paying you back?',
      DebtKind.borrowed => 'Is this you paying ${debt.counterparty} back?',
      DebtKind.holding => 'Is this ${debt.counterparty} money going on?',
    };
    final principal = debt.principal.minorUnits;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tone, width: 2),
          top: BorderSide(color: SpendWiseColors.line),
          right: BorderSide(color: SpendWiseColors.line),
          bottom: BorderSide(color: SpendWiseColors.line),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(headline, style: SpendWiseType.row),
          const SizedBox(height: 4),
          // The reason is on screen because a suggestion nobody can check is
          // just an assertion, and this one moves money out of the month.
          Text(
            // Two sentences, because the reason is itself sometimes a
            // conjunction: "the name matches and it is exactly what is still
            // out" joined to a leading "and" produced a sentence with two of
            // them in it.
            '${formatAmount(debt.outstanding, cents: false)} is still out on '
            'this loan. Suggested because ${match.reason}.',
            style: SpendWiseType.body.copyWith(fontSize: 12.5),
          ),
          if (debt.settled.minorUnits > 0) ...[
            LoanShareRule(
              fraction: principal <= 0
                  ? 0
                  : debt.settled.minorUnits / principal,
              tone: tone,
            ),
            Text(
              '${formatAmount(debt.settled, cents: false)} OF '
              '${formatAmount(debt.principal, cents: false)} ALREADY BACK',
              style: SpendWiseType.metaTight,
            ),
          ],
          const SizedBox(height: 12),
          PrimaryAction(
            label: 'Record it against this loan',
            onPressed: () => debt_sheets.settleFromEntry(
              context,
              viewModel: viewModel,
              transaction: transaction,
              debt: debt,
            ),
          ),
          if (others > 0) ...[
            const SizedBox(height: 8),
            _GhostButton(
              label: others == 1
                  ? 'One other loan also fits'
                  : '$others other loans also fit',
              onPressed: () => debt_sheets.settleFromEntry(
                context,
                viewModel: viewModel,
                transaction: transaction,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A bank alert cannot tell spending from lending, so this is the question
/// only the owner can answer — folded away, and asked in the one direction
/// the money actually went.
///
/// It used to be three permanent full-width buttons on every ordinary entry,
/// which meant money arriving in an account was offered "I lent it out". Two
/// of the three are possible on any given entry, never all three.
class _WhoseMoney extends StatelessWidget {
  const _WhoseMoney({required this.viewModel, required this.transaction});

  final SpendWiseViewModel viewModel;
  final TransactionViewData transaction;

  /// Money that left may have been lent, or held for somebody. Money that
  /// arrived may have been borrowed, or held for somebody. Nothing that moved
  /// between the owner's own accounts is any of them, and this is not drawn
  /// there at all.
  static List<DebtKind> optionsFor(TransactionKind kind) => switch (kind) {
    TransactionKind.expense => const [DebtKind.lent, DebtKind.holding],
    TransactionKind.income => const [DebtKind.borrowed, DebtKind.holding],
    TransactionKind.transfer => const [],
  };

  @override
  Widget build(BuildContext context) {
    final options = optionsFor(transaction.kind);
    if (options.isEmpty) return const SizedBox.shrink();
    final incoming = transaction.kind == TransactionKind.income;
    return _Disclosure(
      title: 'Whose money was this?',
      sub: incoming
          ? 'BORROWED, OR HELD FOR SOMEONE'
          : 'LENT, OR HELD FOR SOMEONE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A bank alert cannot tell spending from lending. This one '
            '${incoming ? 'arrived' : 'went out'}, so it can only be two of '
            'the three.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final kind in options) ...[
            _GhostButton(
              label: kind.title,
              onPressed: () => debt_sheets.markAsLoan(
                context,
                viewModel: viewModel,
                transaction: transaction,
                initialKind: kind,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// The alert behind the entry, exactly as it arrived.
///
/// This used to be a bordered panel with a tinted icon whose whole content
/// was a count — "1 evidence item" — followed by a timeline of dots and rails
/// down a list that is usually one item long. The count is the summary line
/// of one hairline row now, and the dots are gone.
class _Evidence extends StatelessWidget {
  const _Evidence({required this.transaction});

  final TransactionViewData transaction;

  @override
  Widget build(BuildContext context) {
    final items = transaction.evidence;
    final count = transaction.evidenceCount;
    return _Disclosure(
      title: 'Where this came from',
      sub: _summary,
      last: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (count == 0)
            Text(
              'Nothing was read. You typed this, and SpendWise claims nothing '
              'else about it — no merchant string, no reader, no confidence, '
              'because there is no reading to be confident about. '
              'Reconciliation re-derives automatic entries from stored alerts '
              'on every run and leaves this one alone.',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            )
          else if (items.isEmpty)
            Text(
              'The alert behind this entry is no longer on file, so there is '
              'nothing to quote. The entry itself is unchanged.',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            )
          else ...[
            if (items.length > 1) ...[
              // Said before either alert is shown, because being charged
              // twice is the fear the owner opened this to check.
              Text(
                '${items.length} alerts, one movement. It is counted once: '
                'the balance above moves '
                '${formatMoney(transaction.amount)}, and no more.',
                style: SpendWiseType.body.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 12),
            ],
            for (final item in items) ...[
              _EvidenceBlock(item: item),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  String get _summary {
    final count = transaction.evidenceCount;
    if (count == 0) return 'YOU  ·  NO ALERT';
    final items = transaction.evidence;
    final best = items.isEmpty
        ? null
        : items.map((item) => item.confidence).reduce((a, b) => a > b ? a : b);
    return [
      '$count ALERT${count == 1 ? '' : 'S'}',
      // What the reader thought is history the moment somebody overrides it,
      // and the percentage is left visible rather than deleted: it is what
      // explains why the correction was needed.
      if (transaction.isLocked && transaction.debtId == null)
        'ANSWERED BY YOU'
      else if (items.isNotEmpty && items.first.sourceLabel.isNotEmpty)
        items.first.sourceLabel.toUpperCase(),
      if (best != null) '${(best * 100).round()}%',
    ].join('  ·  ');
  }
}

/// One alert, verbatim, with the machinery that read it underneath.
///
/// Facts, then machinery, then doubt: which app said this, then the reader
/// and the rule that matched, then the confidence — the order of increasing
/// doubt, and the order somebody asks the questions in.
class _EvidenceBlock extends StatelessWidget {
  const _EvidenceBlock({required this.item});

  final EvidenceViewData item;

  @override
  Widget build(BuildContext context) {
    final raw = [
      item.title,
      item.body,
    ].where((value) => value.isNotEmpty).join('\n');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: SpendWiseColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  item.sourceLabel,
                  style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_stateLabel(item.state)}  ·  '
                '${(item.confidence * 100).round()}%',
                style: SpendWiseType.metaTight,
              ),
            ],
          ),
          if (raw.isNotEmpty) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SpendWiseColors.background,
                border: Border.all(color: SpendWiseColors.line),
              ),
              // Verbatim means verbatim: an owner comparing this against
              // their messages app has to find the same characters, so
              // nothing is tidied, trimmed or reflowed.
              child: Text(
                raw,
                style: SpendWiseType.meta.copyWith(
                  fontSize: 11.5,
                  color: const Color(0xFF9AA1A5),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (item.packageName.isNotEmpty) _Kv('From app', item.packageName),
          _Kv('Source reader', item.parserId),
          if (item.ruleId.isNotEmpty) _Kv('Matching rule', item.ruleId),
          _Kv('Observed', _dateTime(item.observedAt)),
          if (item.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Eyebrow('Why it matched'),
            const SizedBox(height: 6),
            for (final reason in item.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• ${reason.replaceAll('_', ' ')}',
                  style: SpendWiseType.body.copyWith(fontSize: 12.5),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _stateLabel(EvidenceState state) => switch (state) {
    EvidenceState.accepted => 'COUNTED',
    // "Duplicate" reads like an error the owner should go and fix. It is
    // corroboration, and it is why the entry is at 94% and not 84%.
    EvidenceState.duplicate => 'SAME PAYMENT',
    EvidenceState.matched => 'MATCHED LEG',
    EvidenceState.unparsed => 'COULD NOT BE READ',
    EvidenceState.ignored => 'NOT USED',
  };

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
