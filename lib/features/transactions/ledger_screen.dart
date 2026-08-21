import 'package:flutter/material.dart';

import '../../widgets/spendwise_components.dart';
import '../shell/spendwise_view_model.dart';
import 'transaction_details_screen.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.viewModel});
  final SpendWiseViewModel viewModel;
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final searchController = TextEditingController();
  String query = '';
  TransactionKind? kind;
  String? accountId;
  String? category;
  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.viewModel.transactions
        .where(
          (t) =>
              (kind == null || t.kind == kind) &&
              (accountId == null ||
                  t.accountId == accountId ||
                  t.toAccountId == accountId ||
                  t.accountName ==
                      widget.viewModel.accounts
                          .where((a) => a.id == accountId)
                          .map((a) => a.name)
                          .firstOrNull) &&
              (category == null || t.category == category) &&
              (query.isEmpty ||
                  '${t.title} ${t.subtitle} ${t.category} ${t.accountName}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    final groups = <String, List<TransactionViewData>>{};
    for (final t in filtered) {
      groups.putIfAbsent(_dateLabel(t.occurredAt), () => []).add(t);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          IconButton(
            onPressed: () => _showFilters(context),
            tooltip: 'Filter ledger',
            icon: Badge(
              isLabelVisible: _activeFilterCount > 0,
              label: Text('$_activeFilterCount'),
              child: const Icon(Icons.filter_list_rounded),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: searchController,
                onChanged: (v) => setState(() => query = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search merchant, account, category…',
                  isDense: true,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            sliver: SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final option in <(String, TransactionKind?)>[
                      ('All', null),
                      ('Expenses', TransactionKind.expense),
                      ('Income', TransactionKind.income),
                      ('Transfers', TransactionKind.transfer),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(option.$1),
                          selected: kind == option.$2,
                          onSelected: (_) => setState(() => kind = option.$2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: widget.viewModel.transactions.isEmpty
                    ? Icons.receipt_long_outlined
                    : Icons.manage_search_rounded,
                title: widget.viewModel.transactions.isEmpty
                    ? 'Your ledger is empty'
                    : 'No matching transactions',
                message: widget.viewModel.transactions.isEmpty
                    ? 'Add an account, import a statement, or enable notification capture to begin.'
                    : 'Try another search or filter.',
                action: widget.viewModel.transactions.isEmpty
                    ? null
                    : 'Clear search and filters',
                onAction: widget.viewModel.transactions.isEmpty
                    ? null
                    : _clearSearchAndFilters,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
              sliver: SliverList.list(
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(3, 13, 3, 8),
                      child: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < entry.value.length; i++) ...[
                            TransactionTile(
                              entry.value[i],
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailsScreen(
                                    viewModel: widget.viewModel,
                                    transaction: entry.value[i],
                                  ),
                                ),
                              ),
                            ),
                            if (i < entry.value.length - 1)
                              const Divider(height: 1, indent: 68),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'TODAY';
    }
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  int get _activeFilterCount =>
      [kind, accountId, category].where((value) => value != null).length;

  void _clearSearchAndFilters() => setState(() {
    query = '';
    kind = null;
    accountId = null;
    category = null;
    searchController.clear();
  });

  void _showFilters(BuildContext context) {
    var draftKind = kind;
    var draftAccountId = accountId;
    var draftCategory = category;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter ledger',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 18),
                const Text('Transaction type'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in TransactionKind.values)
                      ChoiceChip(
                        label: Text(titleCase(value.name)),
                        selected: draftKind == value,
                        onSelected: (_) =>
                            modalSetState(() => draftKind = value),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: draftAccountId,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All accounts'),
                    ),
                    ...widget.viewModel.accounts.map(
                      (item) => DropdownMenuItem<String?>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      modalSetState(() => draftAccountId = value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: draftCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...widget.viewModel.transactions
                        .map((item) => item.category)
                        .toSet()
                        .map(
                          (item) => DropdownMenuItem<String?>(
                            value: item,
                            child: Text(item),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      modalSetState(() => draftCategory = value),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => modalSetState(() {
                          draftKind = null;
                          draftAccountId = null;
                          draftCategory = null;
                        }),
                        child: const Text('Clear filters'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            kind = draftKind;
                            accountId = draftAccountId;
                            category = draftCategory;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
