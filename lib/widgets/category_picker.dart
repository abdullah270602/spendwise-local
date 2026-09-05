import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../features/shell/spendwise_view_model.dart';
import 'shape_kit.dart';

/// One way to choose a category, everywhere. Filing something is the most
/// common correction in the app, so it opens as a full list with the user's
/// own categories first — and lets them add one without leaving the flow,
/// because the moment you need a category that does not exist is the moment
/// you are trying to file something.
Future<String?> pickCategory(
  BuildContext context, {
  required SpendWiseViewModel viewModel,
  TransactionKind kind = TransactionKind.expense,
  String? current,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _CategorySheet(
    viewModel: viewModel,
    kind: kind,
    current: current,
  ),
);

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
  final controller = TextEditingController();
  bool adding = false;
  bool saving = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.viewModel.uiCategories;
    final usable = all.where((item) => item.suits(widget.kind)).toList();
    // The user's own first: they added them because the built-ins did not fit.
    final mine = usable.where((item) => !item.isSystem).toList();
    final builtIn = usable.where((item) => item.isSystem).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      maxChildSize: .94,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SpendWiseTheme.gutter,
              0,
              SpendWiseTheme.gutter,
              12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('File it under', style: SpendWiseType.title),
                ),
                if (!adding)
                  TextButton(
                    onPressed: () => setState(() => adding = true),
                    child: const Text('New category'),
                  ),
              ],
            ),
          ),
          if (adding)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                14,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
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
              ),
            ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                SpendWiseTheme.gutter,
                0,
                SpendWiseTheme.gutter,
                28,
              ),
              children: [
                if (mine.isNotEmpty) ...[
                  const Eyebrow('Yours'),
                  const SizedBox(height: 4),
                  for (final item in mine)
                    _CategoryRow(
                      category: item,
                      selected: item.name == widget.current,
                      onTap: () => Navigator.pop(context, item.name),
                      onRemove: () => _remove(item),
                    ),
                  const SizedBox(height: 18),
                ],
                const Eyebrow('Built in'),
                const SizedBox(height: 4),
                for (final item in builtIn)
                  _CategoryRow(
                    category: item,
                    selected: item.name == widget.current,
                    onTap: () => Navigator.pop(context, item.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = controller.text.trim();
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
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: selected
                  ? SpendWiseType.rowStrong
                  : SpendWiseType.row,
            ),
          ),
          if (selected)
            const Text(
              '✓',
              style: TextStyle(color: SpendWiseColors.keep, fontSize: 15),
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
