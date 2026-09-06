import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'alert_demo.dart';
import 'onboarding_figures.dart';

/// First run: four cards, and every one of them changes something.
///
/// The earlier version was nine pages and six hundred words, three of which
/// explained the app without advancing anything. The measured advice is
/// unanimous that those pages buy nothing -- people read about a fifth of the
/// words on a screen, and a controlled study of mobile tutorials found
/// readers no more successful than skippers and rather more likely to call
/// the task hard. So the explaining moved to the guide in Settings, and what
/// is left is the shortest path to the only moment that matters: an alert you
/// did not type becoming a line in your ledger.
///
/// That needs exactly three things -- notification access, at least one app
/// to watch, and somewhere for entries to land. Your name, a PIN, more
/// accounts and everything else are reachable later and are not on the path.
///
/// Cutting the words is not the same as leaving the screen empty, so every
/// card carries a figure that does the explaining the prose used to: the
/// transformation itself, the shape of what the permission buys, the actual
/// icons of the apps being watched, and where a digit sends an alert.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.viewModel, this.onDone});

  final SpendWiseViewModel viewModel;

  /// What the last button does. Unset on first run, where finishing means
  /// marking onboarding complete; set when the flow is replayed from the
  /// guide, where it just closes.
  final VoidCallback? onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  bool finishing = false;

  static const _cards = 4;

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _go(int next) {
    if (next < 0 || next >= _cards) return;
    controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    if (widget.onDone case final done?) return done();
    setState(() => finishing = true);
    try {
      await viewModel.completeOnboarding();
    } catch (error) {
      if (mounted) {
        setState(() => finishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not finish setup: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _ShowIt(),
      _Access(viewModel: viewModel),
      _Sources(viewModel: viewModel),
      _Landing(viewModel: viewModel, onFinish: _finish, finishing: finishing),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Progress(page: page, count: _cards),
            Expanded(
              child: PageView(
                controller: controller,
                onPageChanged: (value) => setState(() => page = value),
                children: [
                  for (var index = 0; index < pages.length; index++)
                    // Short cards sit in the middle of the screen rather than
                    // clinging to the top over a screenful of nothing; tall
                    // ones scroll as usual.
                    LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          SpendWiseTheme.gutter,
                          6,
                          SpendWiseTheme.gutter,
                          16,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 22,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Keyed so re-entering a card replays its
                              // stagger instead of snapping into place.
                              KeyedSubtree(
                                key: ValueKey('$index-${page == index}'),
                                child: pages[index],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (page < _cards - 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SpendWiseTheme.gutter,
                  8,
                  SpendWiseTheme.gutter,
                  14,
                ),
                child: PrimaryAction(
                  label: switch (page) {
                    0 => 'Set it up',
                    1 => viewModel.notificationAccessGranted
                        ? 'Next'
                        : 'Skip for now',
                    _ => 'Next',
                  },
                  onPressed: () => _go(page + 1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      16,
      SpendWiseTheme.gutter,
      18,
    ),
    child: Row(
      children: [
        for (var index = 0; index < count; index++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              margin: EdgeInsets.only(right: index == count - 1 ? 0 : 5),
              height: 2,
              color: index <= page ? SpendWiseColors.fg : SpendWiseColors.line,
            ),
          ),
      ],
    ),
  );
}

/// A headline and, at most, one short line under it.
class _Say extends StatelessWidget {
  const _Say(this.headline, {this.detail});

  final String headline;
  final String? detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        headline,
        style: SpendWiseType.statement.copyWith(fontSize: 29, height: 1.15),
      ),
      if (detail case final text?) ...[
        const SizedBox(height: 10),
        Text(text, style: SpendWiseType.body.copyWith(fontSize: 14)),
      ],
      const SizedBox(height: 26),
    ],
  );
}

// ---- 1. Show it ----------------------------------------------------------

/// No welcome and no mission statement: the thing the app does, done once.
class _ShowIt extends StatelessWidget {
  const _ShowIt();

  @override
  Widget build(BuildContext context) => Stagger(
    children: [
      Row(
        children: [
          const SpendWiseMark(size: 24),
          const SizedBox(width: 10),
          Text('SpendWise', style: SpendWiseType.metaTight),
        ],
      ),
      const SizedBox(height: 20),
      const _Say('Your bank already tells you everything.'),
      AlertDemo(example: AlertExample.purchase, compact: true),
    ],
  );
}

// ---- 2. The permission ---------------------------------------------------

/// The scary one, primed.
///
/// Android's own screen warns that this app could read every notification,
/// and it is right to. Saying so before it appears is what the evidence
/// shows converts; narrowing the scope converts better still than promising
/// to behave, which is why the figure ends in a wall and the next card is
/// the allowlist.
class _Access extends StatelessWidget {
  const _Access({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final granted = viewModel.notificationAccessGranted;
    return Stagger(
      children: [
        _Say(
          granted
              ? 'Done. It can see your alerts.'
              : 'Android is about to warn you.',
          detail: granted
              ? null
              : 'It will say SpendWise can read every notification. It reads '
                    'only the apps you pick next.',
        ),
        ClosedCircuit(granted: granted),
        const SizedBox(height: 26),
        if (granted)
          const _Done('Notification access on')
        else ...[
          PrimaryAction(
            label: 'Open the setting',
            onPressed: viewModel.requestNotificationAccess,
          ),
          const SizedBox(height: 16),
          Text(
            'Toggle greyed out? App info, then the menu, then Allow '
            'restricted settings.',
            style: SpendWiseType.body.copyWith(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Text('✓', style: TextStyle(color: SpendWiseColors.keep, fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: SpendWiseType.row)),
      ],
    ),
  );
}

// ---- 3. Which apps -------------------------------------------------------

/// The allowlist, which is the trust argument rather than a page about trust.
class _Sources extends StatelessWidget {
  const _Sources({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final chosen = viewModel.sources.where((item) => item.enabled).toList();
    return Stagger(
      children: [
        const _Say(
          'Which apps talk about money?',
          detail: 'Everything else on your phone stays invisible.',
        ),
        SourceGrid(sources: chosen),
        const SizedBox(height: 26),
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SourceSelectionScreen(viewModel: viewModel),
            ),
          ),
          child: Text(chosen.isEmpty ? 'Choose apps' : 'Change the list'),
        ),
      ],
    );
  }
}

// ---- 4. Where it lands, and the first win --------------------------------

/// One account, then a look in the notification tray.
///
/// The last card has to end on something happening rather than on a list of
/// things still undone. SpendWise cannot manufacture a bank alert, but
/// Android is still holding whatever sits in the shade, and often enough
/// that is a real transaction the app can file straight away.
class _Landing extends StatefulWidget {
  const _Landing({
    required this.viewModel,
    required this.onFinish,
    required this.finishing,
  });

  final SpendWiseViewModel viewModel;
  final VoidCallback onFinish;
  final bool finishing;

  @override
  State<_Landing> createState() => _LandingState();
}

class _LandingState extends State<_Landing> {
  final name = TextEditingController(text: 'Everyday');
  final suffix = TextEditingController();
  final balance = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final attached = <String>{};
  String type = 'Bank';
  bool saving = false;
  bool scanning = false;

  /// Whether the form is open. It starts open when there is nothing yet and
  /// folds away after each save, so what you see is what exists.
  bool adding = false;
  int? found;

  static const types = ['Bank', 'Wallet', 'Cash', 'Credit card', 'Savings'];

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    name.dispose();
    suffix.dispose();
    balance.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!formKey.currentState!.validate()) return;
    final opening = Money.tryParsePkr('PKR ${balance.text.trim()}');
    setState(() => saving = true);
    try {
      await viewModel.uiAddDetailedAccount(
        AccountCreationDraft(
          name: name.text.trim(),
          type: type,
          openingBalance: MoneyViewData(opening?.minorUnits ?? 0),
          suffix: suffix.text.trim(),
          sourcePackages: {...attached},
        ),
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() {
        adding = false;
        name.text = '';
        suffix.clear();
        balance.clear();
        attached.clear();
        type = 'Bank';
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add the account: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _scanThenFinish() async {
    setState(() => scanning = true);
    try {
      final scan = await viewModel.uiScanNotificationTray();
      if (mounted) setState(() => found = scan.queuedCount);
    } catch (_) {
      // An empty tray is the ordinary case, not a failure worth reporting.
    } finally {
      if (mounted) setState(() => scanning = false);
    }
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = viewModel.accounts;
    final enabled = viewModel.sources.where((item) => item.enabled).toList();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final open = adding || accounts.isEmpty;

    return Form(
      key: formKey,
      child: Stagger(
        children: [
          _Say(
            accounts.isEmpty
                ? 'Where should it all land?'
                : 'Add as many as you like.',
            detail: accounts.isEmpty
                ? 'The last digits are how an alert finds the right account.'
                : null,
          ),
          if (accounts.isEmpty) ...[
            RoutingFigure(suffix: suffix.text.trim()),
            const SizedBox(height: 22),
          ],
          for (final account in accounts) _AccountLine(account: account),
          if (accounts.isNotEmpty) const SizedBox(height: 16),
          if (open) ...[
            TextFormField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Needs a name' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: type,
                    // Without this the button takes the width of its widest
                    // entry, which is wider than half a narrow phone.
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      for (final option in types)
                        DropdownMenuItem(value: option, child: Text(option)),
                    ],
                    onChanged: (value) => setState(() => type = value ?? type),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: suffix,
                    keyboardType: TextInputType.number,
                    // The figure above quotes whatever is typed here, so the
                    // example is about this account within a keypress.
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Last digits',
                      hintText: '4821',
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      return RegExp(r'^\d{2,8}$').hasMatch(text)
                          ? null
                          : '2 to 8 digits';
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
              ),
              decoration: const InputDecoration(
                labelText: 'Balance now',
                prefixText: 'PKR ',
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return null;
                return Money.tryParsePkr('PKR $text') == null
                    ? 'Not an amount'
                    : null;
              },
            ),
            const SizedBox(height: 20),
            // The half of setup that decides whether an alert ever finds its
            // way home. Leaving it for later is how an account ends up
            // watching nothing at all.
            Text(
              'Which app tells you about it?',
              style: SpendWiseType.row.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 10),
            SourceChips(
              sources: enabled,
              selected: attached,
              isShared: viewModel.uiIsSharedSource,
              onToggle: (package) => setState(() {
                if (attached.contains(package)) {
                  attached.remove(package);
                } else {
                  attached.add(package);
                }
              }),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                OutlinedButton(
                  onPressed: saving ? null : _add,
                  child: Text(saving ? 'Adding…' : 'Add it'),
                ),
                if (accounts.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () => setState(() => adding = false),
                    style: TextButton.styleFrom(
                      foregroundColor: SpendWiseColors.dim,
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ],
            ),
          ] else
            OutlinedButton(
              onPressed: () => setState(() {
                adding = true;
                name.text = '';
              }),
              child: const Text('Add another account'),
            ),
          const SizedBox(height: 26),
          if (found case final count?)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                count > 0
                    ? '$count already waiting in your notifications.'
                    : 'Nothing waiting yet. The next alert lands on its own.',
                style: SpendWiseType.body.copyWith(
                  fontSize: 13,
                  color: count > 0 ? SpendWiseColors.keep : null,
                ),
              ),
            ),
          PrimaryAction(
            label: scanning ? 'Looking…' : 'Open SpendWise',
            busy: widget.finishing || scanning,
            onPressed: _scanThenFinish,
          ),
          SizedBox(height: keyboard > 0 ? keyboard + 12 : 0),
        ],
      ),
    );
  }
}

/// One account already added, with the apps that speak for it.
class _AccountLine extends StatelessWidget {
  const _AccountLine({required this.account});

  final AccountViewData account;

  @override
  Widget build(BuildContext context) {
    final watching = account.sources.map((item) => item.label).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '✓',
              style: TextStyle(color: SpendWiseColors.keep, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.suffix.isEmpty
                      ? account.name
                      : '${account.name} · ${account.suffix}',
                  style: SpendWiseType.row,
                ),
                if (watching.isNotEmpty)
                  Text(
                    watching.join(', '),
                    style: SpendWiseType.body.copyWith(fontSize: 11.5),
                  )
                else
                  Text(
                    'No app attached yet',
                    style: SpendWiseType.body.copyWith(
                      fontSize: 11.5,
                      color: SpendWiseColors.spend,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
