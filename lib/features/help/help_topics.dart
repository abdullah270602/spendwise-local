import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../onboarding/alert_demo.dart';
import '../shell/spendwise_view_model.dart';
import 'help_figures.dart';
import 'help_kit.dart';

/// One chapter of the manual.
@immutable
class HelpTopic {
  const HelpTopic({
    required this.title,
    required this.summary,
    required this.glyph,
    required this.brief,
    required this.body,
  });

  final String title;
  final String summary;
  final IconData glyph;

  /// The chapter as plain prose, for the copy-a-prompt button.
  ///
  /// Deliberately not generated from the widgets. The screen is for someone
  /// scanning with the app in front of them; this is for a reader with no
  /// screen at all, who needs the sentences the figures replaced.
  final String brief;

  final List<Widget> Function() body;
}

/// The manual: what comes in, what SpendWise makes of it, what you do about
/// it, and what it will never do.
///
/// Every chapter opens on a figure. People scan help rather than read it, and
/// they arrive mildly annoyed looking for one answer, so the picture carries
/// the chapter and the prose is capped at a couple of sentences beside it.
List<HelpTopic> helpTopics(SpendWiseViewModel viewModel) => [
  HelpTopic(
    title: 'Reading an alert',
    summary: 'What SpendWise takes out of a bank message',
    glyph: Icons.mark_email_read_outlined,
    brief:
        'SpendWise reads the sentence, not just the numbers in it: which way '
        'the money went, who was on the other end, and which of your accounts '
        'it touched. Three shapes cover almost everything a bank or wallet '
        'sends. Money leaving is the commonest and the easiest to misread, '
        'because the amount sits next to the available balance, which is a '
        'much larger number that means something else. Money arriving is read '
        'from the verb (credited, received) rather than a plus sign, since '
        'most alerts have neither. Money moved between your own accounts is '
        'neither earning nor spending, and SpendWise can only recognise it if '
        'it knows what your bank calls you. Promotional messages, prize '
        'draws and one-time codes carry amounts too; those are dropped before '
        'they reach the ledger.',
    body: () => [
      AlertDemo(example: AlertExample.purchase),
      const HelpProse(
        'The amount and the balance sit side by side. Only one of them is '
        'what you spent.',
      ),
      const HelpHeading('Money arriving'),
      AlertDemo(example: AlertExample.received),
      const HelpProse(
        'The direction comes from the verb. Most alerts carry no sign at all.',
      ),
      const HelpHeading('Money that only moved'),
      AlertDemo(example: AlertExample.ownTransfer),
      const HelpProse(
        'Recognising this needs one thing from you: what your bank calls you.',
      ),
      const HelpWhere('Settings · Your name(s)'),
      const HelpHeading('What gets dropped'),
      const HelpContrast(
        leftLabel: 'Ignored',
        left: 'Congratulations! You could win Rs 500,000. Reply WIN to enter.',
        rightLabel: 'Kept',
        right: 'Rs 2,450.00 debited from A/C ****4821 at VALLEY MART.',
      ),
      const HelpProse('Dropped alerts are still kept, in Review · Alerts.'),
    ],
  ),

  HelpTopic(
    title: 'Home',
    summary: 'Of what arrived, how much is still yours',
    glyph: Icons.change_history_rounded,
    brief:
        'Home answers a single question and draws the answer to true '
        'proportion: of everything that came in over a stretch of time, this '
        'much stayed and this much left. Underneath, the part that left is '
        'broken down by category. "Left" means everything that left, not only '
        'what was spent: money lent out, a borrowing handed back and money '
        'moved into savings all empty the account without being spending, and '
        'leaving any of them out makes the figure drift from the balances. '
        'Home shows a change over a window, never a balance, so it will not '
        'match Accounts and is not meant to — Accounts also carries '
        'everything from before the window opened. Which stretch of time is '
        'yours to choose, because a proportion needs a denominator that '
        'exists. A calendar month has an unstable one: nearly nothing on the '
        '1st, full after payday. If you are paid on the 3rd, then on the 1st '
        'of the next month the money you are spending arrived four weeks ago. '
        'Options include the calendar month, rolling 7, 14 or 30 days, and a '
        'window anchored to the day you get paid; anyone paid every two weeks '
        'should choose the rolling fortnight. Savings are two further '
        'choices, kept apart because they do different work: whether saving '
        'comes out of the figure, and whether a line appears beneath the '
        'shape. They combine freely. Every one of these settings shows a live '
        'preview of Home itself, so you can see the answer before you keep '
        'it.',
    body: () => [
      HelpExample(
        caption:
            'The bar is everything that arrived. The strip under it is the '
            'part that left, by category.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentBar(
              weights: const [0.62, 0.38],
              colors: [SpendWiseColors.keep, SpendWiseColors.spend],
              height: 12,
              gap: 3,
            ),
            const SizedBox(height: 12),
            SegmentBar(
              weights: const [0.4, 0.28, 0.2, 0.12],
              colors: SpendWiseColors.categoryRamp.take(4).toList(),
              height: 8,
              gap: 2,
            ),
          ],
        ),
      ),
      const HelpHeading('Which stretch of time'),
      const HelpContrast(
        leftLabel: 'On the 1st',
        left:
            'A calendar month has almost nothing in it yet, so the share '
            'means nothing.',
        rightLabel: 'Your cycle',
        right: 'A window that opens on payday always has one full cycle in it.',
      ),
      const HelpProse(
        'Each of these settings previews Home itself, drawn from your own '
        'figures, and redraws as you choose.',
      ),
      const HelpHeading('Home is a change, not a balance'),
      const HelpContrast(
        leftLabel: 'Home',
        left:
            'What happened inside the window you picked. Nothing from before '
            'it counts.',
        rightLabel: 'Accounts',
        right:
            'What you have right now, carried in from before the window and '
            'all. The two are meant to differ.',
      ),
      const HelpWhere('Settings · Home'),
    ],
  ),

  HelpTopic(
    title: 'Review',
    summary: 'One tap that settles ten things',
    glyph: Icons.help_center_outlined,
    brief:
        'When SpendWise is unsure it does not queue every uncertain line for '
        'you to confirm one at a time. If ten alerts are uncertain for the '
        'same reason, that is one question, not ten. Each item in Review '
        'names the reason, quotes a real alert so you can check the claim, '
        'and carries the single action that answers it for the whole group. '
        'The number on the Review tab counts decisions, not alerts. Opening a '
        'group shows the individual entries, where swiping right confirms, '
        'swiping left deletes, and tapping opens the alert it came from, word '
        'for word. Alerts that are readable but have no account to land in — '
        'a bank you have not added, or digits matching nothing — sit at the '
        'top of Review; tell SpendWise which account they belong to and it '
        'reads them again. Alerts it cannot read at all are usually still '
        'real payments, so Review offers to file them: say which way the '
        'money went and SpendWise supplies the rest, from the amount it did '
        'read. Dropping them is there too, for the ones that were never '
        'transactions.',
    body: () => [
      const HelpExample(
        framed: false,
        caption:
            'Right confirms, left deletes. A tap opens the alert behind it.',
        child: SwipeDemo(),
      ),
      const HelpProse(
        'Ten alerts uncertain for the same reason are one question, not ten. '
        'The badge counts questions.',
      ),
      const HelpHeading('Alerts that reached nowhere'),
      const HelpProse(
        'Readable, but with no account to land in. Say which account, and '
        'they are read again properly.',
      ),
      const HelpHeading('Alerts it could not read'),
      const HelpProse(
        'Usually a real payment in wording SpendWise does not know yet. Say '
        'whether the money went out or came in and it files them, using the '
        'amount it did read.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Fixing an entry',
    summary: 'Category, direction, account',
    glyph: Icons.edit_outlined,
    brief:
        'Ledger is the register: every entry, newest first, grouped by day. '
        'Tap any line to see what it was built from and change anything that '
        'is wrong. You can change the category (the picker has a search box, '
        'and you can add your own categories at the bottom of it), the '
        'direction when money read as spending was actually income or the '
        'reverse, and the account it was filed against. Correcting one entry '
        'usually prompts Review to offer to fix every other entry of the same '
        'shape. File the same person or shop under the same category three '
        'times and SpendWise starts doing it for you; disagree once and it '
        'stops immediately. Ledger shows one month at a time — the control '
        'beside search opens the whole ledger when you are looking for '
        'something older. Cash spending leaves no alert at all, so add it by '
        'hand with the + button on Ledger; it sits in the same register as '
        'everything else.',
    body: () => [
      const HelpStep(
        index: 1,
        title: 'Wrong category',
        detail: 'Open the entry and pick another. The picker has a search box.',
      ),
      const HelpStep(
        index: 2,
        title: 'Wrong direction',
        detail:
            'Spending that was really income, or the reverse. Review usually '
            'offers to fix the rest of the same shape.',
      ),
      const HelpStep(
        index: 3,
        title: 'Wrong account',
        detail: 'Move it, and future alerts of that shape follow.',
      ),
      const SizedBox(height: 6),
      const HelpNote(
        'Your own categories go at the bottom of the picker, and stay.',
      ),
      const HelpProse(
        'Cash leaves no alert. Add it with the + button on Ledger.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Accounts',
    summary: 'Why the last digits matter',
    glyph: Icons.grid_view_outlined,
    brief:
        'An account is where money sits, and every automatic entry has to '
        'land in one. The last few digits of the account number are how '
        'SpendWise decides which, because banks print them in almost every '
        'message. If you have two accounts at the same bank and have not '
        'entered the digits, their alerts cannot be told apart; this is the '
        'single most useful field on the account form. Marking an account as '
        'Savings takes it out of the available-to-spend figure without hiding '
        'it, and savings are drawn as a separate zone in Accounts, scaled on '
        'its own so a large balance does not squash everything else. Money '
        'you are holding for somebody else comes off that figure too, with a '
        'line saying so, because a balance is not a permission to spend. An '
        'app that carries several banks, such as your messages app, is never '
        'tied to one account: its alerts are filed by what each one says. '
        'that carries several banks, such as your messages app, is never tied '
        'When a '
        'balance drifts from what the bank says, correcting it writes a '
        'Balance adjustment entry for the difference rather than quietly '
        'moving the number, so the ledger still explains itself.',
    body: () => [
      HelpExample(
        caption:
            'Two accounts at one bank are told apart only by the digits the '
            'alert quotes.',
        child: Column(
          children: [
            for (final row in const [
              ('Everyday', '4821', 'Rs 2,450 at VALLEY MART · ****4821'),
              ('Savings', '9036', 'Rs 20,000 credited · ****9036'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 74,
                      child: Text(row.$1, style: SpendWiseType.row),
                    ),
                    Text(
                      row.$2,
                      style: SpendWiseType.meta.copyWith(
                        color: SpendWiseColors.mine,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        row.$3,
                        style: SpendWiseType.meta.copyWith(fontSize: 10.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const HelpProse(
        'Savings sit in their own zone, scaled on their own, so a big balance '
        'does not squash everything else.',
      ),
      const HelpNote(
        'Your messages app carries every bank, plus your dentist. It is never '
        'tied to one account.',
      ),
      const HelpWhere('Settings · Notification sources'),
    ],
  ),

  HelpTopic(
    title: 'Lent, borrowed and held',
    summary: 'Money that moved but was never spent',
    glyph: Icons.swap_horiz_rounded,
    brief:
        'A bank alert cannot tell a loan from a purchase. Both read "Rs '
        '20,000 sent". Only you know what it was, so it is marked by hand: '
        'open the entry in Ledger and answer one question — whose money was '
        'it. There are three answers. "I lent it out" is money that left and '
        'is coming back, still yours meanwhile. "I borrowed it" is money that '
        'came in and goes back later, yours to spend until it does. "I am '
        'holding it for someone" is money that landed in your account and was '
        'never yours: a relative sending funds for you to pass on, a friend '
        'parking money with you, a group collection you are the keeper of. '
        'That third one is not a kind of borrowing, and the difference is the '
        'one that matters — borrowed money is available to spend and held '
        'money never is, so held money comes off the top of Available to '
        'spend and both its legs stay out of Home entirely. Record repayments '
        'or hand-overs in part or in full whenever they happen; one that went '
        'through an account can be attached to the real entry, and cash that '
        'never touched a bank can simply be recorded. None of the three '
        'counts as spending, because counting them would say you spent money '
        'that was never yours to spend. Anything filed under the wrong one '
        'can be re-filed later from the same sheet, keeping its amount, date '
        'and counterparty.',
    body: () => [
      HelpExample(
        caption: 'Marked as a loan, it stops counting against your month.',
        child: Column(
          children: [
            RegisterRow(
              name: 'Lent to a friend',
              meta: 'Coming back · not spending',
              amount: '20,000.00',
              amountColor: SpendWiseColors.mine,
              ownTransfer: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(width: 14, height: 2, color: SpendWiseColors.keep),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Out of Home, the breakdown and Insights',
                    style: SpendWiseType.body.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const HelpStep(
        index: 1,
        title: 'Open the entry',
        detail: 'Automatic or typed in, either works.',
      ),
      const HelpStep(
        index: 2,
        title: 'Say whose money it was',
        detail: 'Lent out, borrowed, or held for somebody else.',
      ),
      const HelpStep(
        index: 3,
        title: 'Record it moving on',
        detail: 'In part or in full, whenever it happens.',
      ),
      const HelpHeading('Borrowed is not the same as held'),
      const HelpContrast(
        leftLabel: 'Borrowed',
        left: 'It came in and it is yours to spend until you give it back.',
        rightLabel: 'Held',
        right:
            'It came in and it was never yours. It stays out of what you can '
            'spend.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Reports and exports',
    summary: 'Taking your figures out',
    glyph: Icons.picture_as_pdf_outlined,
    brief:
        'Insights covers longer stretches than Home: the last seven days, the '
        'last thirty, by month or by year, each compared against the stretch '
        'immediately before it. A spending report is a PDF of a month, a '
        'quarter or any range you pick, in one of two layouts, generated on '
        'the phone and saved to a file you choose. An export is the whole '
        'ledger as CSV or JSON, filtered by date, account, kind or category, '
        'optionally including the raw alert behind every entry. Nothing is '
        'uploaded to produce either one, and nothing here is locked in.',
    body: () => [
      const HelpProse(
        'Insights reads seven days, thirty, months or years — each against '
        'the stretch immediately before it.',
      ),
      const HelpHeading('A PDF you can hand over'),
      const HelpProse(
        'A month, a quarter or any range, in two layouts. Made on the phone.',
      ),
      const HelpWhere('Settings · Spending report'),
      const HelpHeading('The whole thing, as data'),
      const HelpProse(
        'CSV or JSON, filtered how you like, with the raw alerts if you want '
        'them. Nothing here is locked in.',
      ),
      const HelpWhere('Settings · Export data'),
    ],
  ),

  HelpTopic(
    title: 'Privacy',
    summary: 'Checked, not claimed',
    glyph: Icons.lock_outline_rounded,
    brief:
        'An app that reads your bank messages is asking for real trust, so '
        'the promise is structural rather than a policy. SpendWise has no '
        'internet permission: not disabled, not opted out of, never '
        'requested, so Android will not grant it network access and there is '
        'no server to send anything to. The ledger is encrypted on the phone '
        'with a key held by the Android keystore, and notification text is '
        'encrypted before it is handed to the app. Android backup is switched '
        'off, so nothing syncs; data leaves only when you export it yourself. '
        'The app lock is separate from all of that: because the ledger is '
        'already encrypted, a PIN is about somebody holding your unlocked '
        'phone rather than someone taking the device apart. A forgotten PIN '
        'cannot be recovered, because nothing outside the phone knows it.',
    body: () => [
      HelpExample(
        framed: false,
        caption: 'Read from the installed package, not typed into this page.',
        child: PermissionsFigure(viewModel: viewModel),
      ),
      const HelpProse(
        'Not disabled, not opted out of — never requested. There is no server '
        'to send anything to.',
      ),
      const HelpStep(
        index: 1,
        title: 'Encrypted on the phone',
        detail:
            'The key is held by the Android keystore. Alert text is encrypted '
            'before the app even sees it.',
      ),
      const HelpStep(
        index: 2,
        title: 'No backup, no sync',
        detail: 'Data leaves only when you export it yourself.',
      ),
      const HelpStep(
        index: 3,
        title: 'A PIN, if you want one',
        detail:
            'For somebody holding your unlocked phone. It cannot be '
            'recovered if forgotten.',
      ),
      const HelpWhere('Settings · App lock'),
    ],
  ),
];
