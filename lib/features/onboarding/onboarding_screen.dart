import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'alert_demo.dart';

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
                  for (final card in pages)
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        SpendWiseTheme.gutter,
                        6,
                        SpendWiseTheme.gutter,
                        16,
                      ),
                      child: card,
                    ),
                ],
              ),
            ),
            // The last card carries its own button, because what it does
            // there is a result rather than a page turn.
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
      14,
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
      Text(headline, style: SpendWiseType.statement),
      if (detail case final text?) ...[
        const SizedBox(height: 10),
        Text(text, style: SpendWiseType.body.copyWith(fontSize: 14)),
      ],
      const SizedBox(height: 22),
    ],
  );
}

// ---- 1. Show it ----------------------------------------------------------

/// No welcome and no mission statement: the thing the app does, done once.
class _ShowIt extends StatelessWidget {
  const _ShowIt();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
/// to behave, which is why the next card is the allowlist.
class _Access extends StatelessWidget {
  const _Access({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final granted = viewModel.notificationAccessGranted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        if (granted)
          const _Done('Notification access on')
        else ...[
          PrimaryAction(
            label: 'Open the setting',
            onPressed: viewModel.requestNotificationAccess,
          ),
          const SizedBox(height: 22),
          // The falsifiable half of the claim. A promise is worth less than
          // something the reader can go and check.
          const _Proof('No internet permission, which the guide will show you'),
          const _Proof('Nothing syncs, uploads or backs up'),
          const SizedBox(height: 14),
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

class _Proof extends StatelessWidget {
  const _Proof(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          width: 14,
          height: 2,
          color: SpendWiseColors.keep,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: SpendWiseType.body.copyWith(fontSize: 13)),
        ),
      ],
    ),
  );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Say(
          'Which apps talk about money?',
          detail: 'Everything else on your phone stays invisible.',
        ),
        for (final source in chosen.take(6)) _Done(source.label),
        if (chosen.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'and ${chosen.length - 6} more',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            ),
          ),
        if (chosen.isNotEmpty) const SizedBox(height: 18),
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
  final formKey = GlobalKey<FormState>();
  String type = 'Bank';
  bool saving = false;
  bool scanning = false;
  int? found;

  static const types = ['Bank', 'Wallet', 'Cash', 'Credit card', 'Savings'];

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    name.dispose();
    suffix.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await viewModel.uiAddDetailedAccount(
        AccountCreationDraft(
          name: name.text.trim(),
          type: type,
          openingBalance: const MoneyViewData(0),
          suffix: suffix.text.trim(),
        ),
      );
      if (mounted) FocusScope.of(context).unfocus();
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
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Say(
            accounts.isEmpty
                ? 'Where should it all land?'
                : 'That is everything.',
            detail: accounts.isEmpty
                ? 'The last digits are how an alert finds the right account.'
                : null,
          ),
          for (final account in accounts)
            _Done(
              account.suffix.isEmpty
                  ? account.name
                  : '${account.name} · ${account.suffix}',
            ),
          if (accounts.isEmpty) ...[
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
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: saving ? null : _add,
              child: Text(saving ? 'Adding…' : 'Add it'),
            ),
          ],
          const SizedBox(height: 24),
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
