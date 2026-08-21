import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Accounts'),
      actions: [
        IconButton(
          onPressed: () => _addAccount(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    ),
    body: viewModel.accounts.isEmpty
        ? EmptyState(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Add your first account',
            message: 'Accounts keep balances and transfers accurate.',
            action: 'Add account',
            onAction: () => _addAccount(context),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
            children: [
              const PrivacyBanner(compact: true),
              const SizedBox(height: 20),
              const SectionHeading('Your accounts'),
              const SizedBox(height: 8),
              for (final account in viewModel.accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
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
                                  account.type.toLowerCase().contains('cash')
                                      ? Icons.payments_outlined
                                      : Icons.account_balance_outlined,
                                  color: SpendWiseColors.accent,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      account.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      account.type,
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
            ],
          ),
  );
  static IconData _sourceIcon(String kind) => switch (kind.toLowerCase()) {
    'sms' || 'messages' => Icons.sms_outlined,
    'statement' || 'csv' => Icons.table_view_outlined,
    'institution' || 'bank' => Icons.account_balance_outlined,
    _ => Icons.notifications_outlined,
  };
  void _addAccount(BuildContext context) {
    final name = TextEditingController();
    final balance = TextEditingController(text: '0');
    final institution = TextEditingController();
    final suffix = TextEditingController();
    final smsSender = TextEditingController();
    final selectedSources = <String>{};
    String type = 'Bank';
    String currency = 'PKR';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const ['Bank', 'Wallet', 'Cash', 'Credit card']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
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
                    child: DropdownButtonFormField<String>(
                      initialValue: currency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: const ['PKR', 'USD', 'EUR', 'GBP']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => currency = value ?? currency),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: suffix,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Last digits',
                        hintText: '4821',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balance,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Opening balance'),
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
                    subtitle: Text(source.packageName),
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
                      helperText:
                          'Filters Messages notifications for this account.',
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final parsed = Money.tryParsePkr('PKR ${balance.text}');
                    if (name.text.trim().isNotEmpty && parsed != null) {
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
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    }
                  },
                  child: const Text('Add account'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
