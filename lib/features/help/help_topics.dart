import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/shape_kit.dart';
import '../onboarding/alert_demo.dart';
import 'help_kit.dart';

/// One chapter of the manual.
@immutable
class HelpTopic {
  const HelpTopic({
    required this.title,
    required this.summary,
    required this.body,
  });

  final String title;
  final String summary;
  final List<Widget> Function() body;
}

/// The manual, in reading order: what comes in, what the app makes of it,
/// what you do about it, and what it will never do. Numbered on the index
/// because that order is real, not decoration.
List<HelpTopic> helpTopics() => [
  HelpTopic(
    title: 'How an alert becomes a line',
    summary: 'The three shapes of message, and what SpendWise takes from each',
    body: () => [
      const HelpProse(
        'SpendWise never guesses from an amount alone. It reads the sentence: '
        'which way the money went, who was on the other end, and which of '
        'your accounts it touched. Three shapes cover almost everything a '
        'bank or wallet sends.',
      ),
      const HelpHeading('Money leaving'),
      const HelpProse(
        'The commonest and the easiest to read wrongly, because the number '
        'you care about sits next to a much larger one that means something '
        'else entirely.',
      ),
      HelpExample(
        framed: false,
        child: AlertDemo(example: AlertExample.purchase),
      ),
      const HelpHeading('Money arriving'),
      const HelpProse(
        'The direction comes from the verb, not from a plus or minus sign, '
        'because most alerts have neither.',
      ),
      HelpExample(
        framed: false,
        child: AlertDemo(example: AlertExample.received),
      ),
      const HelpHeading('Money that only moved'),
      const HelpProse(
        'Sending yourself money is neither earning nor spending. SpendWise '
        'can only tell if it knows what your bank calls you, which is the one '
        'thing it has to be told.',
      ),
      HelpExample(
        framed: false,
        child: AlertDemo(example: AlertExample.ownTransfer),
      ),
      const HelpWhere('Settings → Your name(s)'),
      const HelpHeading('What it throws away'),
      const HelpProse(
        'Offers, prize draws, delivery updates and one-time codes carry '
        'amounts too. They are recognised and dropped before they reach the '
        'ledger, so they never become a question for you to answer.',
      ),
      const HelpContrast(
        leftLabel: 'Ignored',
        left:
            'Congratulations! You could win Rs 500,000. Reply WIN to enter.',
        rightLabel: 'Kept',
        right:
            'Rs 2,450.00 debited from A/C ****4821 at VALLEY MART.',
      ),
      const HelpNote(
        'If something was dropped that should not have been, you can still '
        'find it: every captured alert is kept, including the ignored ones.',
      ),
      const HelpWhere('Review → Alerts'),
    ],
  ),

  HelpTopic(
    title: 'Home, and the one question',
    summary: 'Of everything that arrived, how much is still yours',
    body: () => [
      const HelpProse(
        'Home is not a dashboard. It answers a single question and draws the '
        'answer to true proportion: of everything that came in over a stretch '
        'of time, this much stayed and this much left.',
      ),
      HelpExample(
        caption:
            'The bar is the whole of what arrived. Underneath, the part that '
            'left is broken down by category.',
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
      const HelpProse(
        'A proportion needs a denominator that exists. A calendar month has '
        'an unstable one: nearly nothing on the 1st, full after payday. If '
        'you are paid on the 3rd, then on the 1st of the next month the money '
        'you are spending arrived four weeks ago and the calendar month has '
        'no idea.',
      ),
      const HelpProse(
        'So the window is yours to set, and every option shows you the '
        'figures it would actually produce from your own ledger before you '
        'pick it.',
      ),
      const HelpWhere('Settings → What Home covers'),
      const HelpNote(
        'Paid every two weeks? Choose the rolling fortnight. A calendar month '
        'gives you two paydays in some months and one in others, so your Home '
        'would swing for a reason you had nothing to do with.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Review: decisions, not alerts',
    summary: 'One tap that settles ten things at once',
    body: () => [
      const HelpProse(
        'When SpendWise is unsure, it does not queue up every uncertain line '
        'for you to confirm one at a time. If ten alerts are uncertain for '
        'the same reason, that is one question, not ten.',
      ),
      const HelpProse(
        'Each item in Review names the reason, quotes a real alert so you can '
        'check the claim rather than take it, and carries the one action that '
        'answers it for the whole group.',
      ),
      const HelpNote(
        'The number on the Review tab counts decisions, not alerts. Fourteen '
        'unread alerts that collapse into two questions show as 2 — promising '
        'fourteen would be a lie about how much work is waiting.',
      ),
      const HelpHeading('Going through them one by one'),
      const HelpProse(
        'Open any group to see the individual entries. There, the gestures '
        'are the fast path:',
      ),
      const HelpStep(
        index: 1,
        title: 'Swipe right to confirm',
        detail: 'Accepts the entry as read and locks it.',
      ),
      const HelpStep(
        index: 2,
        title: 'Swipe left to delete',
        detail: 'For alerts that were never transactions at all.',
      ),
      const HelpStep(
        index: 3,
        title: 'Tap to open',
        detail:
            'Shows the alert it came from, word for word, and everything that '
            'was read out of it.',
      ),
      const HelpHeading('Alerts that reached nowhere'),
      const HelpProse(
        'Sometimes a message is perfectly readable but has no account to land '
        'in — a bank you have not added yet, or digits that match nothing. '
        'Those sit at the top of Review. Tell SpendWise which account they '
        'belong to and it reads them again, properly.',
      ),
    ],
  ),

  HelpTopic(
    title: 'The ledger and categories',
    summary: 'Correcting things, and filing them your way',
    body: () => [
      const HelpProse(
        'Ledger is the register: every entry, newest first, grouped by day. '
        'Tap any line to see what it was built from and to change anything '
        'that is wrong.',
      ),
      const HelpStep(
        index: 1,
        title: 'Wrong category',
        detail:
            'Open the entry and pick another. The picker has a search box, so '
            'you can type instead of hunting.',
      ),
      const HelpStep(
        index: 2,
        title: 'Wrong direction',
        detail:
            'Money read as spending that was actually income, or the reverse. '
            'Changing it on one entry usually means Review offers to fix the '
            'rest of the same shape too.',
      ),
      const HelpStep(
        index: 3,
        title: 'Wrong account',
        detail: 'Move it, and future alerts of that shape follow.',
      ),
      const HelpHeading('Your own categories'),
      const HelpProse(
        'The built-in list covers the ordinary run of things. If something in '
        'your life does not fit one of them, add it at the bottom of the '
        'category picker and it stays for good.',
      ),
      const HelpHeading('Things no alert will ever mention'),
      const HelpProse(
        'Cash out of your pocket leaves no message. Add it by hand with the + '
        'button on Ledger; it sits in the same register as everything else.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Accounts',
    summary: 'Where alerts land, and why the last digits matter',
    body: () => [
      const HelpProse(
        'An account is where money sits. Every automatic entry has to land in '
        'one, and the last few digits are how SpendWise decides which — banks '
        'print them in almost every message they send.',
      ),
      const HelpNote(
        'If you have two accounts at the same bank and have not entered the '
        'digits, alerts cannot be told apart. This is the single most useful '
        'field on the account form.',
      ),
      const HelpHeading('Everyday money and savings'),
      const HelpProse(
        'Marking an account as Savings takes it out of the "available to '
        'spend" figure without hiding it. Savings and everyday money are '
        'drawn as separate zones in Accounts, each scaled on its own, so a '
        'large savings balance does not squash everything else into a sliver.',
      ),
      const HelpHeading('Apps that carry several banks'),
      const HelpProse(
        'Your messages app is not one bank — it carries all of them, plus '
        'your dentist. So it is never tied to a single account. Its alerts '
        'are filed by what each one says: the bank it names, the digits it '
        'quotes. The same is true of any app that speaks for more than one '
        'institution.',
      ),
      const HelpWhere('Settings → Notification sources'),
    ],
  ),

  HelpTopic(
    title: 'Lent and borrowed',
    summary: 'Money that left but is still yours',
    body: () => [
      const HelpProse(
        'A bank alert cannot tell a loan from a purchase. Both read "Rs '
        '20,000 sent". Only you know it is coming back, so this one is marked '
        'by hand — and once it is marked, the money stops counting as '
        'spending.',
      ),
      const HelpStep(
        index: 1,
        title: 'Open the entry in Ledger',
        detail: 'Any entry, automatic or typed in.',
      ),
      const HelpStep(
        index: 2,
        title: 'Say what it was',
        detail:
            '"I lent this out" for money going, "I borrowed this" for money '
            'arriving that is not yours to keep.',
      ),
      const HelpStep(
        index: 3,
        title: 'Record it coming back',
        detail:
            'In part or in full, whenever it happens. A repayment that went '
            'through an account can be attached to the real entry; cash that '
            'never touched a bank can just be recorded.',
      ),
      const HelpNote(
        'Loans are left out of Home, out of the category breakdown and out of '
        'Insights, because counting them would say you spent money you are '
        'getting back.',
      ),
    ],
  ),

  HelpTopic(
    title: 'Insights, reports and exports',
    summary: 'Looking further back, and taking your data out',
    body: () => [
      const HelpProse(
        'Insights covers longer stretches than Home: the last seven days, the '
        'last thirty, by month or by year. Each reading compares against the '
        'stretch immediately before it, so "up" and "down" mean something '
        'specific rather than something vague.',
      ),
      const HelpHeading('A report you can hand to someone'),
      const HelpProse(
        'A PDF of a month, a quarter or any range you pick, in one of two '
        'layouts. It is generated on the phone and saved to a file you '
        'choose. Nothing is uploaded to produce it.',
      ),
      const HelpWhere('Settings → Spending report'),
      const HelpHeading('The whole thing, as data'),
      const HelpProse(
        'CSV or JSON, filtered by date, account, kind or category, and '
        'optionally including the raw alert behind every entry. This is your '
        'escape hatch: nothing here is locked in.',
      ),
      const HelpWhere('Settings → Export data'),
    ],
  ),

  HelpTopic(
    title: 'Privacy, and the app lock',
    summary: 'What it cannot do, and the one thing you can add',
    body: () => [
      const HelpProse(
        'An app that reads your bank messages is asking for real trust. The '
        'only honest way to earn it is to make the promise structural rather '
        'than something you have to take on faith.',
      ),
      const HelpStep(
        index: 1,
        title: 'It has no internet permission',
        detail:
            'Not disabled, not opted out of — never requested. Android will '
            'not give SpendWise network access, so there is nowhere for your '
            'data to go and no server that could ask for it.',
      ),
      const HelpStep(
        index: 2,
        title: 'The ledger is encrypted on the phone',
        detail:
            'Its key is held by the Android keystore. Notification text is '
            'encrypted before it is even handed to the app.',
      ),
      const HelpStep(
        index: 3,
        title: 'Nothing syncs or backs up',
        detail:
            'Android backup is switched off for this app. Data leaves only '
            'when you export it yourself.',
      ),
      const HelpHeading('The app lock'),
      const HelpProse(
        'Because the ledger is already encrypted, a PIN is not about someone '
        'taking the phone apart. It is about the ordinary case: somebody '
        'holding your unlocked phone, opening the app, and reading what you '
        'spend.',
      ),
      const HelpProse(
        'You choose how soon it asks after you leave, whether a fingerprint '
        'counts, and whether Android may keep a preview of the app in the '
        'task switcher.',
      ),
      const HelpWhere('Settings → App lock'),
      const HelpNote(
        'There is no way to recover a forgotten PIN, because nothing outside '
        'this phone knows it. That is the point, and it is also the cost.',
      ),
    ],
  ),
];
