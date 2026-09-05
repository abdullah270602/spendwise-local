import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/money.dart';
import '../../security/app_lock.dart';
import '../../widgets/shape_kit.dart';
import '../../widgets/spendwise_components.dart';
import '../security/pin_setup_screen.dart';
import '../settings/source_selection_screen.dart';
import '../shell/spendwise_view_model.dart';
import 'alert_demo.dart';

/// First run.
///
/// Three pages explain the idea, then five set the app up, and every one of
/// the five can be skipped. The order is not arbitrary: notification access
/// first because nothing else works without it, then which apps, then an
/// account for the alerts to land in, then the names that let the app tell
/// your own transfers from real spending. Each step is worth less than the
/// one before, so a person who stops early still has a working app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.viewModel, this.onDone});

  final SpendWiseViewModel viewModel;

  /// What the last button does. Unset on first run, where finishing means
  /// marking onboarding complete; set when the same flow is replayed from
  /// Settings, where it just closes.
  final VoidCallback? onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  bool finishing = false;

  static const _pageCount = 9;

  SpendWiseViewModel get viewModel => widget.viewModel;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _go(int next) {
    if (next < 0 || next >= _pageCount) return;
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
    final lock = AppLockScope.maybeOf(context);
    final pages = <Widget>[
      const _CoverPage(),
      const _ReadingPage(),
      const _PrivacyPage(),
      _AccessPage(viewModel: viewModel),
      _SourcesPage(viewModel: viewModel),
      _AccountPage(viewModel: viewModel),
      _NamesPage(viewModel: viewModel),
      _LockPage(lock: lock),
      _ReadyPage(viewModel: viewModel, lock: lock, onJump: _go),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Progress(page: page, count: _pageCount),
            Expanded(
              child: PageView(
                controller: controller,
                onPageChanged: (value) => setState(() => page = value),
                children: [
                  for (var index = 0; index < pages.length; index++)
                    // Every page scrolls: the account form with a keyboard up
                    // on a short phone is the case that breaks otherwise.
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        SpendWiseTheme.gutter,
                        10,
                        SpendWiseTheme.gutter,
                        18,
                      ),
                      child: pages[index],
                    ),
                ],
              ),
            ),
            _Footer(
              page: page,
              count: _pageCount,
              busy: finishing,
              label: _label,
              onBack: page == 0 ? null : () => _go(page - 1),
              onNext: page == _pageCount - 1 ? _finish : () => _go(page + 1),
            ),
          ],
        ),
      ),
    );
  }

  /// The button says what happens next, not "Continue" nine times.
  String get _label => switch (page) {
    0 => 'Show me',
    1 => 'Good',
    2 => 'Set it up',
    3 => viewModel.notificationAccessGranted ? 'Next' : 'Skip for now',
    4 || 5 || 6 || 7 => 'Next',
    _ => widget.onDone == null ? 'Open SpendWise' : 'Done',
  };
}

// ---- Chrome ---------------------------------------------------------------

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
      16,
    ),
    child: Row(
      children: [
        for (var index = 0; index < count; index++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              margin: EdgeInsets.only(right: index == count - 1 ? 0 : 4),
              height: 2,
              color: index <= page
                  ? SpendWiseColors.fg
                  : SpendWiseColors.line,
            ),
          ),
      ],
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.page,
    required this.count,
    required this.busy,
    required this.label,
    required this.onBack,
    required this.onNext,
  });

  final int page;
  final int count;
  final bool busy;
  final String label;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpendWiseTheme.gutter,
      10,
      SpendWiseTheme.gutter,
      14,
    ),
    child: Row(
      children: [
        SizedBox(
          width: 62,
          child: onBack == null
              ? const SizedBox.shrink()
              : Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: SpendWiseColors.dim,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Back'),
                  ),
                ),
        ),
        Expanded(
          child: PrimaryAction(label: label, busy: busy, onPressed: onNext),
        ),
      ],
    ),
  );
}

/// The lead of every page: a rule, a statement, a paragraph. Repeating the
/// same three-part shape is what makes nine screens read as one document.
class _Lead extends StatelessWidget {
  const _Lead({required this.statement, required this.detail, this.eyebrow});

  final String statement;
  final String detail;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow case final text?) ...[
        Eyebrow(text),
        const SizedBox(height: 12),
      ] else ...[
        Container(width: 34, height: 2, color: SpendWiseColors.edge),
        const SizedBox(height: 18),
      ],
      Text(statement, style: SpendWiseType.statement),
      const SizedBox(height: 11),
      Text(detail, style: SpendWiseType.body.copyWith(fontSize: 14.5)),
    ],
  );
}

/// A row that shows whether one thing is set, without a card around it.
class _Status extends StatelessWidget {
  const _Status({required this.done, required this.text, this.onTap});

  final bool done;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SpendWiseColors.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              done ? '✓' : '·',
              style: TextStyle(
                fontSize: done ? 14 : 17,
                color: done ? SpendWiseColors.keep : SpendWiseColors.dim,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: SpendWiseType.row.copyWith(
                color: done ? SpendWiseColors.fg : SpendWiseColors.dim,
              ),
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: SpendWiseColors.dim,
            ),
        ],
      ),
    ),
  );
}

// ---- The three that explain ----------------------------------------------

class _CoverPage extends StatelessWidget {
  const _CoverPage();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 26),
      const SpendWiseMark(size: 58),
      const SizedBox(height: 26),
      Text('SpendWise', style: SpendWiseType.figure),
      const SizedBox(height: 8),
      const Eyebrow('Private · Local · Yours'),
      const SizedBox(height: 30),
      Text(
        'Every payment you make already sends you a message.',
        style: SpendWiseType.statement,
      ),
      const SizedBox(height: 11),
      Text(
        'SpendWise reads those alerts and keeps the ledger you would '
        'otherwise keep by hand — the amount, who it went to, which account '
        'it left. You do not type anything in, and nothing goes out.',
        style: SpendWiseType.body.copyWith(fontSize: 14.5),
      ),
      const SizedBox(height: 26),
      const _ShareIllustration(),
    ],
  );
}

/// The idea of Home, in miniature: of what arrived, this much stayed.
class _ShareIllustration extends StatelessWidget {
  const _ShareIllustration();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Eyebrow('The question it answers'),
      const SizedBox(height: 11),
      SegmentBar(
        weights: [0.62, 0.38],
        colors: [SpendWiseColors.keep, SpendWiseColors.spend],
        height: 12,
        gap: 3,
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Text(
              'Still yours',
              style: SpendWiseType.body.copyWith(
                fontSize: 12,
                color: SpendWiseColors.keep,
              ),
            ),
          ),
          Text(
            'Gone',
            style: SpendWiseType.body.copyWith(
              fontSize: 12,
              color: SpendWiseColors.spend,
            ),
          ),
        ],
      ),
    ],
  );
}

class _ReadingPage extends StatelessWidget {
  const _ReadingPage();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Lead(
        statement: 'It reads the alert, not just its number.',
        detail:
            'Bank messages hide the thing you care about in the middle of a '
            'sentence, next to a bigger number that means something else. '
            'Here is the same alert your bank sends, and what SpendWise takes '
            'out of it.',
      ),
      const SizedBox(height: 24),
      AlertDemo(example: AlertExample.purchase),
      const SizedBox(height: 18),
      Text(
        'Money arriving and money moving between your own accounts read '
        'differently again. You will see both in Settings, under How '
        'SpendWise works.',
        style: SpendWiseType.body.copyWith(fontSize: 12.5),
      ),
    ],
  );
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Lead(
        statement: 'It cannot go online. Not "does not" — cannot.',
        detail:
            'A finance app that reads your messages is asking for a lot of '
            'trust. The honest way to earn it is to make the promise '
            'structural rather than a policy you have to believe.',
      ),
      const SizedBox(height: 26),
      const _Fact(
        title: 'No internet permission',
        detail:
            'Android will not grant SpendWise network access, because it '
            'never asks for it. There is no server to send anything to.',
      ),
      const _Fact(
        title: 'The ledger is encrypted on this phone',
        detail:
            'Its key is held by the Android keystore, not by a password and '
            'not by us.',
      ),
      const _Fact(
        title: 'Nothing syncs, uploads or backs up',
        detail:
            'Your data leaves only when you export it yourself, to a file you '
            'choose.',
      ),
      const SizedBox(height: 8),
      const PrivacyBanner(),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.only(left: 13),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: SpendWiseColors.keep, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: SpendWiseType.lead.copyWith(fontSize: 15.5)),
        const SizedBox(height: 4),
        Text(detail, style: SpendWiseType.body.copyWith(fontSize: 13)),
      ],
    ),
  );
}

// ---- The five that set up -------------------------------------------------

class _AccessPage extends StatelessWidget {
  const _AccessPage({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final granted = viewModel.notificationAccessGranted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Lead(
          eyebrow: 'Step 1 of 5 · required',
          statement: granted
              ? 'Notification access is on.'
              : 'One permission, and only one.',
          detail: granted
              ? 'SpendWise can now see the alerts your banking and wallet '
                    'apps post. It reads only the apps you pick on the next '
                    'screen, and ignores everything else.'
              : 'Notification access is how SpendWise sees your bank alerts '
                    'at all. Android will show you its own warning screen — '
                    'it is worded for apps that could send what they read '
                    'somewhere. This one has no way to.',
        ),
        const SizedBox(height: 24),
        if (!granted)
          PrimaryAction(
            label: 'Turn on notification access',
            onPressed: viewModel.requestNotificationAccess,
          )
        else
          _Status(done: true, text: 'Granted'),
        const SizedBox(height: 18),
        Text(
          granted
              ? 'You can withdraw it at any time in Android settings, and '
                    'SpendWise keeps everything it has already filed.'
              : 'Without it, SpendWise still works — you would just be typing '
                    'every transaction in yourself.',
          style: SpendWiseType.body.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final enabled = viewModel.sources.where((item) => item.enabled).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Lead(
          eyebrow: 'Step 2 of 5',
          statement: 'Which apps talk about money.',
          detail:
              'Pick your banks, your wallets, and your messages app if your '
              'bank texts you. Everything else on your phone stays invisible '
              'to SpendWise — it is not filtering what it collects, it never '
              'collects it.',
        ),
        const SizedBox(height: 22),
        if (enabled.isEmpty)
          Text(
            'Nothing chosen yet.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          )
        else
          for (final source in enabled.take(6))
            _Status(done: true, text: source.label),
        if (enabled.length > 6)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'and ${enabled.length - 6} more',
              style: SpendWiseType.body.copyWith(fontSize: 12.5),
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SourceSelectionScreen(viewModel: viewModel),
            ),
          ),
          child: Text(enabled.isEmpty ? 'Choose apps' : 'Change the list'),
        ),
      ],
    );
  }
}

class _AccountPage extends StatefulWidget {
  const _AccountPage({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<_AccountPage> {
  final name = TextEditingController();
  final suffix = TextEditingController();
  final balance = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String type = 'Bank';
  bool saving = false;

  static const types = ['Bank', 'Wallet', 'Cash', 'Credit card', 'Savings'];

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
      await widget.viewModel.uiAddDetailedAccount(
        AccountCreationDraft(
          name: name.text.trim(),
          type: type,
          openingBalance: MoneyViewData(opening?.minorUnits ?? 0),
          suffix: suffix.text.trim(),
        ),
      );
      if (!mounted) return;
      name.clear();
      suffix.clear();
      balance.clear();
      FocusScope.of(context).unfocus();
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

  @override
  Widget build(BuildContext context) {
    final accounts = widget.viewModel.accounts;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Lead(
            eyebrow: 'Step 3 of 5',
            statement: 'Somewhere for the money to sit.',
            detail:
                'One account is enough to start. The last few digits are what '
                'lets SpendWise file an alert against the right one when you '
                'have several — banks print them in almost every message.',
          ),
          const SizedBox(height: 22),
          for (final account in accounts)
            _Status(
              done: true,
              text: account.suffix.isEmpty
                  ? account.name
                  : '${account.name} · ${account.suffix}',
            ),
          if (accounts.isNotEmpty) const SizedBox(height: 22),
          TextFormField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Account name',
              hintText: 'Everyday',
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'Give the account a name'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final option in types)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (value) => setState(() => type = value ?? type),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
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
                        : 'Use 2 to 8 digits';
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
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
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: saving ? null : _add,
            child: Text(
              saving
                  ? 'Adding…'
                  : accounts.isEmpty
                  ? 'Add this account'
                  : 'Add another',
            ),
          ),
        ],
      ),
    );
  }
}

class _NamesPage extends StatefulWidget {
  const _NamesPage({required this.viewModel});

  final SpendWiseViewModel viewModel;

  @override
  State<_NamesPage> createState() => _NamesPageState();
}

class _NamesPageState extends State<_NamesPage> {
  late final TextEditingController names = TextEditingController(
    text: widget.viewModel.uiOwnNames.join(', '),
  );
  bool saved = false;

  @override
  void dispose() {
    names.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsed = names.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    await widget.viewModel.uiSetOwnNames(parsed);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => saved = true);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Lead(
        eyebrow: 'Step 4 of 5',
        statement: 'What your bank calls you.',
        detail:
            'When you move money between your own accounts, the alert names '
            'you as the person receiving it. Knowing your name is how '
            'SpendWise tells that apart from real spending — otherwise every '
            'transfer to your own savings counts against your month.',
      ),
      const SizedBox(height: 22),
      AlertDemo(example: AlertExample.ownTransfer),
      const SizedBox(height: 20),
      TextField(
        controller: names,
        textCapitalization: TextCapitalization.words,
        onChanged: (_) => setState(() => saved = false),
        decoration: const InputDecoration(
          labelText: 'Your name, as your bank writes it',
          hintText: 'Your Name, Y. Name',
          helperText: 'Separate several with commas',
        ),
      ),
      const SizedBox(height: 14),
      OutlinedButton(
        onPressed: _save,
        child: Text(saved ? 'Saved' : 'Save'),
      ),
    ],
  );
}

class _LockPage extends StatefulWidget {
  const _LockPage({required this.lock});

  final AppLockController? lock;

  @override
  State<_LockPage> createState() => _LockPageState();
}

class _LockPageState extends State<_LockPage> {
  bool busy = false;

  Future<void> _setPin() async {
    final lock = widget.lock;
    if (lock == null) return;
    final pin = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const PinSetupScreen(title: 'Set a PIN'),
      ),
    );
    if (pin == null || !mounted) return;
    setState(() => busy = true);
    await lock.enable(pin, useBiometrics: lock.biometricsAvailable);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final lock = widget.lock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Lead(
          eyebrow: 'Step 5 of 5 · optional',
          statement: 'A PIN, if you want one.',
          detail:
              'The ledger is already encrypted, so this is not about someone '
              'taking the phone apart. It is about the ordinary case: someone '
              'holding your unlocked phone, opening the app, and reading what '
              'you spend.',
        ),
        const SizedBox(height: 22),
        if (lock == null)
          Text(
            'Unavailable on this device.',
            style: SpendWiseType.body.copyWith(fontSize: 13),
          )
        else if (lock.enabled) ...[
          _Status(done: true, text: '${lock.pinLength}-digit PIN set'),
          if (lock.biometricsEnabled)
            _Status(done: true, text: 'Fingerprint or face as well'),
        ] else
          PrimaryAction(
            label: 'Set a PIN',
            busy: busy,
            onPressed: _setPin,
          ),
        const SizedBox(height: 18),
        Text(
          'You can turn this on later in Settings, and change when it asks. '
          'There is no way to recover a forgotten PIN, because nothing '
          'outside this phone knows it.',
          style: SpendWiseType.body.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

class _ReadyPage extends StatelessWidget {
  const _ReadyPage({
    required this.viewModel,
    required this.lock,
    required this.onJump,
  });

  final SpendWiseViewModel viewModel;
  final AppLockController? lock;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    final sources = viewModel.sources.where((item) => item.enabled).length;
    final accounts = viewModel.accounts.length;
    final named = viewModel.uiOwnNames.isNotEmpty;
    final access = viewModel.notificationAccessGranted;
    final ready = access && sources > 0 && accounts > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Lead(
          statement: ready
              ? 'That is everything. It runs on its own now.'
              : 'You can start here and finish later.',
          detail: ready
              ? 'The next alert one of your apps posts becomes a line in your '
                    'ledger. Anything SpendWise is unsure about waits for you '
                    'in Review rather than guessing.'
              : 'Nothing below is required to open the app. Each one is in '
                    'Settings, and Home will nudge you about the ones that '
                    'matter.',
        ),
        const SizedBox(height: 24),
        _Status(
          done: access,
          text: access
              ? 'Notification access on'
              : 'Notification access off',
          onTap: () => onJump(3),
        ),
        _Status(
          done: sources > 0,
          text: sources == 0
              ? 'No apps chosen'
              : '$sources ${sources == 1 ? 'app' : 'apps'} watched',
          onTap: () => onJump(4),
        ),
        _Status(
          done: accounts > 0,
          text: accounts == 0
              ? 'No accounts yet'
              : '$accounts ${accounts == 1 ? 'account' : 'accounts'}',
          onTap: () => onJump(5),
        ),
        _Status(
          done: named,
          text: named ? 'Your name is set' : 'Your name is not set',
          onTap: () => onJump(6),
        ),
        _Status(
          done: lock?.enabled ?? false,
          text: (lock?.enabled ?? false) ? 'App lock on' : 'No app lock',
          onTap: () => onJump(7),
        ),
        const SizedBox(height: 26),
        Text(
          'Everything here is explained again, with worked examples, under '
          'Settings → How SpendWise works.',
          style: SpendWiseType.body.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}
