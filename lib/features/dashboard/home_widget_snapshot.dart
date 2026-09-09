import 'dart:math' as math;

import 'home_savings.dart';

/// Everything a Home-screen widget is allowed to know.
///
/// The widget runs in a different process, at times the app is not alive,
/// and it cannot open the SQLCipher ledger -- the key lives in the Android
/// keystore and decrypting outside the app's own runtime is not a boundary
/// worth trying to cross. So the app publishes the one fact the widget's
/// picture needs and nothing it does not: how much of what came in is still
/// yours, as a bare ratio, plus whether there is anything to draw at all --
/// and, for the one style that asks for it, a second ratio dividing that
/// first one. Ratios and a flag, never a balance, an amount, or an account
/// name -- see `lib/platform/widget_bridge.dart` for exactly what crosses
/// and where it lands.
///
/// [keptFraction] is deliberately a ratio rather than the two minor-unit
/// figures it comes from: a ratio says nothing about whether the month held
/// ten pounds or ten thousand, which two account balances would. [operator
/// ==] treating two snapshots with wildly different underlying amounts as
/// identical, so long as the shape they draw is identical, is the whole
/// point -- it is the test that nothing but the shape survived the trip.
///
/// [hasSavedBranch] and [savedOfKept] carry the one other ratio the widget
/// is ever allowed to draw: "siblings" is the single style, of the three the
/// widget offers, that turns saving into a third branch rather than folding
/// it into or out of the other two. A second ratio is still just a ratio --
/// it says how the kept branch divides, never what either half was worth --
/// so it crosses the same boundary [keptFraction] does, for the same reason.
final class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.hasData,
    required this.keptFraction,
    this.hasSavedBranch = false,
    this.savedOfKept = 0,
  });

  /// Whether anything has arrived or left in the window Home currently
  /// covers. A fresh install and a quiet month both read the same here --
  /// the widget draws neither a shape nor a false 50/50 split for either.
  final bool hasData;

  /// What share of everything that came in is still yours, clamped to
  /// 0..1. Meaningless -- and never read -- when [hasData] is false.
  final double keptFraction;

  /// Whether the kept branch itself divides into a saved sliver and the
  /// rest. False for every style but "siblings", and false for "siblings"
  /// too in the one month it saved nothing -- a branch drawn from zero would
  /// be a division with nothing on one side of it, which Home itself never
  /// draws either.
  final bool hasSavedBranch;

  /// What share of the kept branch [hasSavedBranch] carves off as saved,
  /// clamped to 0..1. Meaningless -- and never read -- when [hasSavedBranch]
  /// is false.
  final double savedOfKept;

  /// Mirrors the fraction [FlowShape] itself derives from a kept and a spent
  /// figure -- same denominator floor, same clamp -- so the widget can never
  /// show a split Home would not. [style] is folded in the same way Home's
  /// own screen folds it before handing figures to the ribbon: "Only what I
  /// can spend" takes saving out of the figure, so it takes it out of the
  /// shape too; "Saving gets its own branch" leaves the figure alone and
  /// instead divides the branch, the same way [FlowShape]'s own
  /// `SavedTreatment.branch` divides it on Home.
  factory HomeWidgetSnapshot.from(HomeFigures figures, HomeSavingsStyle style) {
    // A share of nothing is not a share -- Home never draws a confident
    // split before anything has actually arrived, and the widget does not
    // either.
    final hasData = figures.received != 0 || figures.spent != 0;
    if (!hasData) {
      return const HomeWidgetSnapshot(hasData: false, keptFraction: 0);
    }
    final kept = style == HomeSavingsStyle.available
        ? figures.kept -
              figures.saved.clamp(0, figures.kept < 0 ? 0 : figures.kept)
        : figures.kept;
    final total = math.max(1, kept.abs() + figures.spent.abs());

    // A branch that would divide nothing is no branch at all -- the same
    // guard `FlowShape` applies to `widget.saved` before it ever reaches the
    // painter, kept here so a month with nothing put away draws the plain
    // two-branch split even when "siblings" is the chosen style.
    final hasSavedBranch =
        style == HomeSavingsStyle.siblings &&
        figures.saved > 0 &&
        figures.kept.abs() != 0;
    final savedOfKept = hasSavedBranch
        ? (figures.saved.clamp(0, figures.kept.abs()) / figures.kept.abs())
              .clamp(0.0, 1.0)
        : 0.0;

    return HomeWidgetSnapshot(
      hasData: true,
      keptFraction: (kept.abs() / total).clamp(0.0, 1.0),
      hasSavedBranch: hasSavedBranch,
      savedOfKept: savedOfKept,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetSnapshot &&
      other.hasData == hasData &&
      other.keptFraction == keptFraction &&
      other.hasSavedBranch == hasSavedBranch &&
      other.savedOfKept == savedOfKept;

  @override
  int get hashCode =>
      Object.hash(hasData, keptFraction, hasSavedBranch, savedOfKept);

  @override
  String toString() =>
      'HomeWidgetSnapshot(hasData: $hasData, keptFraction: $keptFraction, '
      'hasSavedBranch: $hasSavedBranch, savedOfKept: $savedOfKept)';
}
