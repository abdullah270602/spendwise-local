import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) {
    final deleted = viewModel.uiLastDeletedAccount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            onPressed: () => _addAccount(context),
            tooltip: 'Add account',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: viewModel.accounts.isEmpty && deleted == null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Add your first account',
                  message: 'Accounts keep balances and transfers accurate.',
                  action: 'Add account',
                  onAction: () => _addAccount(context),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              children: [
                const PrivacyBanner(compact: true),
                if (deleted != null) ...[
                  const SizedBox(height: 14),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: Text('${deleted.name} was deleted'),
                      subtitle: const Text(
                        'Its transactions are still safely in your ledger.',
                      ),
                      trailing: TextButton(
                        onPressed: () => _restoreAccount(context, deleted),
                        child: const Text('Restore'),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (viewModel.accounts.isNotEmpty) ...[
                  const SectionHeading('Your accounts'),
                  const SizedBox(height: 8),
                ],
                for (final account in viewModel.accounts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _editAccount(context, account),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: SpendWiseColors.accentMuted,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      account.type.toLowerCase().contains(
                                            'cash',
                                          )
                                          ? Icons.payments_outlined
                                          : Icons.account_balance_outlined,
                                      color: SpendWiseColors.accent,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          account.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          titleCase(account.type),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatMoney(account.balance),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        [
                                          if (account.suffix.isNotEmpty)
                                            '••${account.suffix}',
                                          account.currency,
                                        ].join(' · '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (account.sources.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    for (final source in account.sources)
                                      Chip(
                                        avatar: Icon(
                                          _sourceIcon(source.kind),
                                          size: 15,
                                        ),
                                        label: Text(source.label),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static IconData _sourceIcon(String kind) => switch (kind.toLowerCase()) {
    'sms' || 'messages' => Icons.sms_outlined,
    'statement' || 'csv' => Icons.table_view_outlined,
    'institution' || 'bank' => Icons.account_balance_outlined,
    _ => Icons.notifications_outlined,
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
    final selected = account.sources
        .map((source) => source.packageName)
        .where((value) => value.isNotEmpty)
        .toSet();
    final formKey = GlobalKey<FormState>();
    var saving = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
                    Text(
                      'Manage account',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatMoney(account.balance),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: sheetContext,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Delete account?'),
                                    content: Text(
                                      '${account.name} will be removed from your accounts and disconnected from notification sources. Existing transactions stay safely in your ledger.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(
                                            dialogContext,
                                          ).colorScheme.error,
                                          foregroundColor: Theme.of(
                                            dialogContext,
                                          ).colorScheme.onError,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        child: const Text('Delete account'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed != true ||
                                    !sheetContext.mounted) {
                                  return;
                                }
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
                                            DeletedAccountViewData(
                                              id: account.id,
                                              name: account.name,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } catch (error) {
                                  if (sheetContext.mounted) {
                                    setState(() => saving = false);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Could not remove account: $error',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete account'),
                      ),
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
                      'Attach apps whose transactions belong to this account.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final source in viewModel.sources.where(
                      (item) => item.enabled,
                    ))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(source.packageName),
                        title: Text(source.label),
                        subtitle: Text(source.packageName),
                        onChanged: (value) => setState(
                          () => value == true
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
                      items: const ['Bank', 'Wallet', 'Cash', 'Credit card']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => type = v ?? type),
                    ),
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
                        'An account can use several app, SMS, statement, and manual sources.',
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
