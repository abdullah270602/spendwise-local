import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

/// Accounts is a map of where your money actually sits: every block's height
/// is its share of the total, so the account holding most of it is literally
/// the largest thing on screen. `Map / Plain` swaps in a straight list for a
/// clean view, and the choice sticks.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key, required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  static const _preferenceKey = 'accounts_map';

  /// Total pixel budget the map divides between accounts by share. Big enough
  /// that the largest block dominates, small enough that four accounts still
  /// fit above the fold on a normal phone.
  static const _mapBudget = 300.0;
  static const _minBlock = 34.0;

  late bool asMap;

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    asMap = viewModel.uiViewPreference(_preferenceKey) != 'plain';
  }

  @override
  Widget build(BuildContext context) {
    final deleted = viewModel.uiLastDeletedAccount;
    final everyday = viewModel.accounts
        .where((account) => account.isIncluded)
        .toList(growable: false);
    final savings = viewModel.accounts
        .where((account) => !account.isIncluded)
        .toList(growable: false);
    final everydayTotal = _sum(everyday);
    final savingsTotal = _sum(savings);
    final total = everydayTotal + savingsTotal;
    final unconfigured = viewModel.accounts
        .where((account) => account.suffix.trim().isEmpty)
        .toList(growable: false);

    if (viewModel.accounts.isEmpty && deleted == null) {
      return SafeArea(
        bottom: false,
        child: RestState(
          headline: 'No accounts yet.',
          detail: 'An account is what a bank alert gets attached to. Without '
              'one, nothing SpendWise captures can reach a balance.',
          action: FilledButton(
            onPressed: () => _addAccount(context),
            child: const Text('Add your first account'),
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                18,
                SpendWiseTheme.gutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Eyebrow(
                          'Total tracked · '
                          '${viewModel.accounts.first.currency}',
                        ),
                      ),
                      ViewToggle(
                        options: const ['Map', 'Plain'],
                        selected: asMap ? 0 : 1,
                        onSelected: _setMap,
                      ),
                      IconButton(
                        onPressed: () => _addAccount(context),
                        tooltip: 'Add account',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: SpendWiseColors.dim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(formatMinor(total), style: SpendWiseType.figure),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.only(bottom: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: SpendWiseColors.line),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _Share(
                            label: 'Available',
                            value: _percent(everydayTotal, total),
                          ),
                        ),
                        if (savings.isNotEmpty)
                          _Share(
                            label: 'Held back',
                            value: _percent(savingsTotal, total),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (deleted != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  14,
                  SpendWiseTheme.gutter,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${deleted.name} was removed — its transactions are '
                        'still in your ledger.',
                        style: SpendWiseType.body.copyWith(fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _restoreAccount(context, deleted),
                      child: const Text('Restore'),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                96 + MediaQuery.viewPaddingOf(context).bottom,
              ),
            sliver: SliverList.list(
              children: [
                if (everyday.isNotEmpty) ...[
                  _zone('Available to spend', everydayTotal),
                  ..._blocks(everyday, total),
                ],
                if (savings.isNotEmpty) ...[
                  _zone('Held back · savings', savingsTotal),
                  ..._blocks(savings, total),
                ],
                if (unconfigured.isNotEmpty) _incomplete(unconfigured),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zone(String label, int amount) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 18, 0, 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Eyebrow(label)),
        Text(
          formatMinor(amount),
          style: SpendWiseType.rowStrong.copyWith(fontSize: 14),
        ),
      ],
    ),
  );

  List<Widget> _blocks(List<AccountViewData> accounts, int grandTotal) {
    if (!asMap) {
      return [for (final account in accounts) _plainRow(context, account)];
    }
    final safeTotal = grandTotal == 0 ? 1 : grandTotal;
    return [
      for (final account in accounts)
        ProportionBlock(
          name: account.name,
          amount: formatMinor(account.balance.minorUnits),
          detail: [
            if (account.suffix.isNotEmpty) '••${account.suffix}',
            if (account.sources.isNotEmpty)
              account.sources.map((s) => s.label).join(' + '),
          ].join(' · '),
          height: math.max(
            _minBlock,
            _mapBudget * (account.balance.minorUnits.abs() / safeTotal),
          ),
          filled: account.isIncluded,
          onTap: () => _editAccount(context, account),
        ),
    ];
  }

  /// One aggregate warning rather than a second copy of every block: an
  /// account with no last digits saved cannot be matched from an alert, which
  /// is a gap in the map, not an extra entry in it.
  Widget _incomplete(List<AccountViewData> accounts) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: InkWell(
      onTap: () => _editAccount(context, accounts.first),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          border: Border.all(
            color: SpendWiseColors.spend.withValues(alpha: .55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: accounts.length == 1
                          ? '${accounts.first.name} has no last digits saved. '
                          : '${accounts.length} accounts have no last digits '
                                'saved. ',
                      style: SpendWiseType.row.copyWith(
                        fontSize: 13,
                        color: SpendWiseColors.spend,
                      ),
                    ),
                    TextSpan(
                      text: 'Alerts cannot be matched to '
                          '${accounts.length == 1 ? 'it' : 'them'} until they '
                          'are added.',
                      style: SpendWiseType.body.copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '→',
              style: TextStyle(fontSize: 14, color: SpendWiseColors.spend),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _plainRow(BuildContext context, AccountViewData account) => InkWell(
    onTap: () => _editAccount(context, account),
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(_accountIcon(account.type), size: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: SpendWiseType.row),
                const SizedBox(height: 2),
                Text(
                  [
                    if (account.institution.isNotEmpty) account.institution,
                    if (account.suffix.isNotEmpty) '••${account.suffix}',
                    if (!account.isIncluded) 'savings',
                  ].join(' · '),
                  style: SpendWiseType.metaTight,
                ),
              ],
            ),
          ),
          Text(
            formatMinor(account.balance.minorUnits),
            style: SpendWiseType.rowStrong,
          ),
        ],
      ),
    ),
  );

  void _setMap(int index) {
    setState(() => asMap = index == 0);
    viewModel.uiSetViewPreference(_preferenceKey, asMap ? 'map' : 'plain');
  }

  static int _sum(List<AccountViewData> accounts) => accounts.fold<int>(
    0,
    (total, account) => total + account.balance.minorUnits,
  );

  static String _percent(int part, int whole) =>
      whole == 0 ? '0%' : '${((part / whole) * 100).round()}%';

  static IconData _accountIcon(String type) => switch (type.toLowerCase()) {
    String value when value.contains('saving') => Icons.savings_outlined,
    String value when value.contains('cash') => Icons.payments_outlined,
    String value when value.contains('wallet') => Icons.wallet_outlined,
    String value when value.contains('card') => Icons.credit_card_outlined,
    _ => Icons.account_balance_outlined,
  };

  Future<void> _restoreAccount(
    BuildContext context,
    DeletedAccountViewData account,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await viewModel.uiRestoreAccount(account.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${account.name} was restored.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not restore account: $error')),
      );
    }
  }

  void _editAccount(BuildContext context, AccountViewData account) {
    final screenContext = context;
    final messenger = ScaffoldMessenger.of(context);
    final name = TextEditingController(text: account.name);
    final institution = TextEditingController(text: account.institution);
    final suffix = TextEditingController(text: account.suffix);
    var type = _typeLabel(account.type);
    final selected = account.sources
        .map((source) => source.packageName)
        .where((value) => value.isNotEmpty)
        .toSet();
    final formKey = GlobalKey<FormState>();
    var saving = false;
    Future<void> adjustBalance(BuildContext sheetContext) async {
      final balance = TextEditingController(
        text: _editableAmount(account.balance.minorUnits),
      );
      final adjustmentKey = GlobalKey<FormState>();
      var adjusting = false;
      try {
        await showDialog<void>(
          context: sheetContext,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Adjust account balance'),
              content: Form(
                key: adjustmentKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Set the balance shown by your bank. Existing transactions stay unchanged; SpendWise adjusts the account baseline by the difference.',
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: balance,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatedAmountFormatter(),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Current balance',
                        prefixText: '${account.currency} ',
                      ),
                      validator: (value) =>
                          Money.tryParsePkr('PKR ${value ?? ''}') == null
                          ? 'Enter a valid amount with up to 2 decimals'
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: adjusting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: adjusting
                      ? null
                      : () async {
                          if (!adjustmentKey.currentState!.validate()) return;
                          final parsed = Money.tryParsePkr(
                            'PKR ${balance.text}',
                          )!;
                          setDialogState(() => adjusting = true);
                          try {
                            await viewModel.uiSetAccountCurrentBalance(
                              account.id,
                              MoneyViewData(
                                parsed.minorUnits,
                                currency: account.currency,
                              ),
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Account balance updated.'),
                                ),
                              );
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              setDialogState(() => adjusting = false);
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not update balance: $error',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: Text(adjusting ? 'Updating…' : 'Update balance'),
                ),
              ],
            ),
          ),
        );
      } finally {
        balance.dispose();
      }
    }

    Future<void> deleteAccount(
      BuildContext sheetContext,
      StateSetter setState,
    ) async {
      final confirmed = await showDialog<bool>(
        context: sheetContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete account?'),
          content: Text(
            '${account.name} will be removed from your accounts and disconnected from notification sources. Existing transactions stay safely in your ledger.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete account'),
            ),
          ],
        ),
      );
      if (confirmed != true || !sheetContext.mounted) return;
      setState(() => saving = true);
      try {
        await viewModel.uiArchiveAccount(account.id);
        if (sheetContext.mounted) {
          Navigator.pop(sheetContext);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                '${account.name} was removed. Existing transactions were kept.',
              ),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _restoreAccount(
                  screenContext,
                  DeletedAccountViewData(id: account.id, name: account.name),
                ),
              ),
            ),
          );
        }
      } catch (error) {
        if (sheetContext.mounted) {
          setState(() => saving = false);
          messenger.showSnackBar(
            SnackBar(content: Text('Could not remove account: $error')),
          );
        }
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ControllerDisposalScope(
        controllers: [name, institution, suffix],
        child: StatefulBuilder(
          builder: (context, setState) => SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Manage account',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        PopupMenuButton<_AccountAction>(
                          enabled: !saving,
                          tooltip: 'Account actions',
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (action) {
                            if (action == _AccountAction.delete) {
                              deleteAccount(sheetContext, setState);
                            }
                          },
                          itemBuilder: (menuContext) => [
                            PopupMenuItem(
                              value: _AccountAction.delete,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: Theme.of(menuContext)
                                        .colorScheme
                                        .error,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Delete account',
                                    style: TextStyle(
                                      color: Theme.of(menuContext)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(account.balance),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: saving ? null : () => adjustBalance(context),
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Adjust balance'),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Account name',
                      ),
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Enter an account name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: _accountTypes
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) => setState(() => type = value ?? type),
                    ),
                    if (type == 'Savings') ...[
                      const SizedBox(height: 8),
                      const _SavingsExplanation(),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: institution,
                      decoration: const InputDecoration(
                        labelText: 'Institution (optional)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: suffix,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Last digits (optional)',
                      ),
                      validator: (value) {
                        final normalized = value?.trim() ?? '';
                        return normalized.isNotEmpty &&
                                !RegExp(r'^\d{2,8}$').hasMatch(normalized)
                            ? 'Use 2–8 digits'
                            : null;
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Notification sources',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attach apps whose alerts belong to this account. Apps '
                      'that carry several banks stay global — their alerts are '
                      'filed by what each one says.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final source in viewModel.sources.where(
                      (item) => item.enabled,
                    ))
                      _SourceChoice(
                        source: source,
                        shared: viewModel.uiIsSharedSource(source.packageName),
                        selected: selected.contains(source.packageName),
                        onChanged: (value) => setState(
                          () => value
                              ? selected.add(source.packageName)
                              : selected.remove(source.packageName),
                        ),
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                setState(() => saving = true);
                                try {
                                  await viewModel.uiUpdateDetailedAccount(
                                    account.id,
                                    AccountUpdateDraft(
                                      name: name.text.trim(),
                                      type: type,
                                      institution: institution.text.trim(),
                                      suffix: suffix.text.trim(),
                                      sourcePackages: Set.unmodifiable(
                                        selected,
                                      ),
                                    ),
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                } catch (error) {
                                  if (sheetContext.mounted) {
                                    setState(() => saving = false);
                                    ScaffoldMessenger.of(
                                      sheetContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not update account: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Text(saving ? 'Saving…' : 'Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addAccount(BuildContext context) {
    final name = TextEditingController();
    final balance = TextEditingController(text: '0');
    final institution = TextEditingController();
    final suffix = TextEditingController();
    final smsSender = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final selectedSources = <String>{};
    String type = 'Bank';
    const currency = 'PKR';
    var saving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => _ControllerDisposalScope(
        controllers: [name, balance, institution, suffix, smsSender],
        child: StatefulBuilder(
          builder: (context, setState) => SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 16),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Account name',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final normalized = value?.trim() ?? '';
                        if (normalized.isEmpty) return 'Enter an account name';
                        if (normalized.length > 80) {
                          return 'Use 80 characters or fewer';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: _accountTypes
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => type = v ?? type),
                    ),
                    if (type == 'Savings') ...[
                      const SizedBox(height: 8),
                      const _SavingsExplanation(),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: institution,
                      decoration: const InputDecoration(
                        labelText: 'Institution (optional)',
                        hintText: 'Meezan Bank',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: currency,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Currency',
                              helperText:
                                  'PKR totals stay mathematically exact',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: suffix,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Last digits',
                              hintText: '4821',
                            ),
                            validator: (value) {
                              final normalized = value?.trim() ?? '';
                              if (normalized.isEmpty) return null;
                              if (!RegExp(r'^\d{2,8}$').hasMatch(normalized)) {
                                return 'Use 2–8 digits';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: balance,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      inputFormatters: const [
                        _ThousandsSeparatedAmountFormatter(),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Opening balance',
                        prefixText: 'PKR ',
                      ),
                      validator: (value) =>
                          Money.tryParsePkr('PKR ${value ?? ''}') == null
                          ? 'Enter a valid amount with up to 2 decimals'
                          : null,
                    ),
                    if (viewModel.sources.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Attach notification sources',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'An account can use several sources. Apps that carry '
                        'several banks stay global — their alerts are filed by '
                        'what each one says.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      for (final source in viewModel.sources.where(
                        (item) => item.enabled,
                      ))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: selectedSources.contains(source.packageName),
                          title: Text(source.label),
                          subtitle: Text(
                            source.packageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (selected) => setState(() {
                            selected == true
                                ? selectedSources.add(source.packageName)
                                : selectedSources.remove(source.packageName);
                          }),
                        ),
                      if (selectedSources.any(
                        (package) =>
                            package.contains('messaging') ||
                            package.contains('messages'),
                      ))
                        TextField(
                          controller: smsSender,
                          decoration: const InputDecoration(
                            labelText: 'Bank SMS sender (optional)',
                            hintText: 'HBL or MEEZAN',
                            helperText: 'Filters Messages notifications for this account.',
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!formKey.currentState!.validate()) return;
                                final parsed = Money.tryParsePkr(
                                  'PKR ${balance.text}',
                                );
                                if (parsed != null) {
                                  setState(() => saving = true);
                                  try {
                                    await viewModel.uiAddDetailedAccount(
                                      AccountCreationDraft(
                                        name: name.text.trim(),
                                        type: type,
                                        openingBalance: MoneyViewData(
                                          parsed.minorUnits,
                                          currency: currency,
                                        ),
                                        currency: currency,
                                        institution: institution.text.trim(),
                                        suffix: suffix.text.trim(),
                                        sourcePackages: selectedSources,
                                        smsSenderPattern: smsSender.text.trim(),
                                      ),
                                    );
                                    if (sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                  } catch (error) {
                                    if (sheetContext.mounted) {
                                      setState(() => saving = false);
                                      ScaffoldMessenger.of(sheetContext)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Could not add account: $error',
                                              ),
                                            ),
                                          );
                                    }
                                  }
                                }
                              },
                        child: Text(saving ? 'Adding…' : 'Add account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _accountTypes = ['Bank', 'Wallet', 'Cash', 'Credit card', 'Savings'];

String _typeLabel(String type) => switch (type.toLowerCase()) {
  String value when value.contains('saving') => 'Savings',
  String value when value.contains('wallet') => 'Wallet',
  String value when value.contains('cash') => 'Cash',
  String value when value.contains('card') => 'Credit card',
  _ => 'Bank',
};

String _editableAmount(int minorUnits) {
  final sign = minorUnits < 0 ? '-' : '';
  final absolute = minorUnits.abs();
  final whole = absolute ~/ 100;
  final fraction = (absolute % 100).toString().padLeft(2, '0');
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$sign$grouped.$fraction';
}

/// A source the user can attach to an account. A shared app -- a messaging or
/// mail client -- carries several banks, so attaching it never means "file
/// everything from here into this account"; the alert's own text decides.
class _SourceChoice extends StatelessWidget {
  const _SourceChoice({
    required this.source,
    required this.shared,
    required this.selected,
    required this.onChanged,
  });

  final SourceViewData source;
  final bool shared;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: selected,
    title: Row(
      children: [
        Flexible(
          child: Text(
            source.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (shared)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: SpendWiseColors.mine,
            child: const Text(
              'SHARED',
              style: TextStyle(
                fontFamily: SpendWiseType.sans,
                fontSize: 8.5,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: SpendWiseColors.bg,
              ),
            ),
          ),
      ],
    ),
    subtitle: Text(
      shared
          ? 'Carries several banks — alerts are filed by what they say, '
                'never all into this account'
          : source.packageName,
      style: SpendWiseType.metaTight,
    ),
    onChanged: (value) => onChanged(value == true),
  );
}

/// One half of the available / held-back split under the total.
class _Share extends StatelessWidget {
  const _Share({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label ',
          style: SpendWiseType.body.copyWith(fontSize: 12.5),
        ),
        TextSpan(
          text: value,
          style: SpendWiseType.rowStrong.copyWith(fontSize: 13),
        ),
      ],
    ),
  );
}

class _SavingsExplanation extends StatelessWidget {
  const _SavingsExplanation();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: SpendWiseColors.accentMuted,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.savings_outlined, size: 19, color: SpendWiseColors.accent),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Savings stay visible here, but are excluded from Available to spend.',
          ),
        ),
      ],
    ),
  );
}

enum _AccountAction { delete }

final class _ControllerDisposalScope extends StatefulWidget {
  const _ControllerDisposalScope({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_ControllerDisposalScope> createState() =>
      _ControllerDisposalScopeState();
}

final class _ControllerDisposalScopeState
    extends State<_ControllerDisposalScope> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}

final class _ThousandsSeparatedAmountFormatter extends TextInputFormatter {
  const _ThousandsSeparatedAmountFormatter();

  static final _validAmount = RegExp(r'^-?\d*(?:\.\d{0,2})?$');
  static final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(',', '');
    if (!_validAmount.hasMatch(raw)) return oldValue;

    final rawCursor = newValue.selection.isValid
        ? newValue.text
              .substring(0, newValue.selection.extentOffset)
              .replaceAll(',', '')
              .length
        : raw.length;
    final negative = raw.startsWith('-');
    final unsigned = negative ? raw.substring(1) : raw;
    final dot = unsigned.indexOf('.');
    final whole = dot == -1 ? unsigned : unsigned.substring(0, dot);
    final decimal = dot == -1 ? '' : unsigned.substring(dot);
    final groupedWhole = whole.replaceAllMapped(_thousands, (match) => ',');
    final formatted = '${negative ? '-' : ''}$groupedWhole$decimal';

    var formattedCursor = 0;
    var consumedRawCharacters = 0;
    while (formattedCursor < formatted.length &&
        consumedRawCharacters < rawCursor) {
      if (formatted[formattedCursor] != ',') consumedRawCharacters++;
      formattedCursor++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formattedCursor),
    );
  }
}

