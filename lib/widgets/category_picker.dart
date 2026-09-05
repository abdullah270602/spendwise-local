import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';
import 'shape_kit.dart';

/// One way to choose a category, everywhere. Filing something is the most
/// common correction in the app, so it opens as a searchable, grouped list
/// with the user's own categories first — and lets them add one without
/// leaving the flow, because the moment you need a category that does not
/// exist is the moment you are trying to file something.
Future<String?> pickCategory(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  TransactionKind kind = TransactionKind.expense,
  String? current,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (sheetContext) => _CategorySheet(
    viewModel: viewModel,
    kind: kind,
    current: current,
  ),
);

/// Twenty categories in one alphabetical column is a list you read; grouped by
/// what the money was for, it becomes a list you skim. The groups are stated
/// here rather than stored, so adding a seeded category never needs a
/// migration to stay organised.
const _groups = <String, List<String>>{
  'Day to day': ['groceries', 'food', 'transport', 'bills', 'home'],
  'Life': [
    'shopping',
    'entertainment',
    'subscriptions',
    'travel',
    'personal-care',
  ],
  'Health & obligations': [
    'health',
    'education',
    'insurance',
    'government-tax',
    'gifts-charity',
  ],
  'Money moving': ['income', 'transfer', 'cash', 'fees', 'other'],
};

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({
    required this.viewModel,
    required this.kind,
    required this.current,
  });

  final SpendWiseViewModel viewModel;
  final TransactionKind kind;
  final String? current;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final search = TextEditingController();
  final draft = TextEditingController();
  bool adding = false;
  bool saving = false;

  @override
  void dispose() {
    search.dispose();
    draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final usable = widget.viewModel.uiCategories
        .where((item) => item.suits(widget.kind))
        .where((item) => query.isEmpty || item.name.toLowerCase().contains(query))
        .toList();

    final mine = usable.where((item) => !item.isSystem).toList();
    final builtIn = usable.where((item) => item.isSystem).toList();

    final sections = <_Section>[
      if (mine.isNotEmpty) _Section('Yours', mine),
      for (final entry in _groups.entries)
        if (builtIn.any((item) => entry.value.contains(item.id)))
          _Section(entry.key, [
            for (final id in entry.value)
              ...builtIn.where((item) => item.id == id),
          ]),
      // Anything seeded later that no group claims still has to appear.
      if (builtIn.any(
        (item) => !_groups.values.any((ids) => ids.contains(item.id)),
      ))
        _Section('Other categories', [
          for (final item in builtIn)
            if (!_groups.values.any((ids) => ids.contains(item.id))) item,
        ]),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      maxChildSize: .96,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              0,
              SpendWiseTheme.gutter,
              10,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('File it under', style: SpendWiseType.title),
                ),
                if (!adding)
                  TextButton(
                    onPressed: () => setState(() => adding = true),
                    child: const Text('New'),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              0,
              SpendWiseTheme.gutter,
              10,
            ),
            child: adding
                ? Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: draft,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          style: SpendWiseType.row,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Rent, Zakat, Gym…',
                          ),
                          onSubmitted: (_) => _create(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: saving ? null : _create,
                        child: Text(saving ? 'Adding…' : 'Add'),
                      ),
                    ],
                  )
                : TextField(
                    controller: search,
                    style: SpendWiseType.row,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search categories',
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () => setState(search.clear),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                    ),
                  ),
          ),
          Expanded(
            child: sections.isEmpty
                ? _NoMatch(
                    query: search.text.trim(),
                    onCreate: () => setState(() {
                      draft.text = search.text.trim();
                      adding = true;
                    }),
                  )
                : ListView(
                    controller: scrollController,
                    // The sheet floats above the gesture bar, so the last row
                    // needs to clear it or it reads as cut in half.
                    padding: EdgeInsets.fromLTRB(
                      SpendWiseTheme.gutter,
                      0,
                      SpendWiseTheme.gutter,
                      24 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    children: [
                      for (final section in sections) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                          child: Eyebrow(section.title),
                        ),
                        for (final item in section.items)
                          _CategoryRow(
                            category: item,
                            selected: item.name == widget.current,
                            onTap: () => Navigator.pop(context, item.name),
                            onRemove: item.isSystem
                                ? null
                                : () => _remove(item),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = draft.text.trim();
    if (name.isEmpty) return;
    setState(() => saving = true);
    try {
      final stored = await widget.viewModel.uiAddCategory(
        name,
        kind: widget.kind == TransactionKind.income ? 'income' : 'expense',
      );
      if (mounted) Navigator.pop(context, stored);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add that category: $error')),
      );
    }
  }

  Future<void> _remove(CategoryViewData item) async {
    await widget.viewModel.uiRemoveCategory(item.id);
    if (mounted) setState(() {});
  }
}

class _Section {
  const _Section(this.title, this.items);
  final String title;
  final List<CategoryViewData> items;
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.query, required this.onCreate});

  final String query;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(SpendWiseTheme.gutter, 30, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No category called "$query".', style: SpendWiseType.lead),
        const SizedBox(height: 10),
        Text(
          'You can make one — it will be there next time too.',
          style: SpendWiseType.body.copyWith(fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: onCreate, child: Text('Add "$query"')),
      ],
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.selected,
    required this.onTap,
    this.onRemove,
  });

  final CategoryViewData category;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: selected ? SpendWiseType.rowStrong : SpendWiseType.row,
            ),
          ),
          if (selected)
            Padding(
              padding: EdgeInsets.only(right: 4),
              child: Text(
                '✓',
                style: TextStyle(color: SpendWiseColors.keep, fontSize: 15),
              ),
            ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove ${category.name}',
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.close_rounded,
                size: 16,
                color: SpendWiseColors.dim,
              ),
            ),
        ],
      ),
    ),
  );
}
