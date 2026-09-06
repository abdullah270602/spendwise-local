import 'package:flutter/foundation.dart' show immutable;

/// What stretch of time Home is a picture of.
///
/// Home's whole idea is a proportion — of what arrived, this much stayed — and
/// a proportion needs a denominator that exists. A calendar month has an
/// unstable one: near zero on the 1st, full after payday, so for the first
/// days of every month the ratio is either meaningless or a lie. Which window
/// is right depends on when a person gets paid, so it is theirs to choose.
enum HomePeriodKind {
  /// The 1st of this month up to today.
  calendarMonth,

  /// A rolling week.
  lastSevenDays,

  /// A rolling fortnight, for anyone paid every two weeks: it contains
  /// exactly one pay cycle whatever day of the month that falls on.
  lastFourteenDays,

  /// A rolling month. Always contains one pay cycle, whatever day that lands.
  lastThirtyDays,

  /// A window anchored to days of the month: "my money month runs 3rd to
  /// 27th", or "from the 3rd" for a pay cycle that wraps into the next month.
  dayRange,
}

@immutable
class HomePeriod {
  const HomePeriod({
    this.kind = HomePeriodKind.calendarMonth,
    this.startDay = 1,
    this.endDay = 0,
  });

  final HomePeriodKind kind;

  /// First day of the month the window opens on. Only read for [dayRange].
  final int startDay;

  /// Last day of the window. Zero means "up to today", which is what a pay
  /// cycle wants; a real day makes a closed window such as the 3rd to the 27th.
  final int endDay;

  static const calendarMonth = HomePeriod();
  static const lastSevenDays = HomePeriod(kind: HomePeriodKind.lastSevenDays);
  static const lastFourteenDays = HomePeriod(
    kind: HomePeriodKind.lastFourteenDays,
  );
  static const lastThirtyDays = HomePeriod(kind: HomePeriodKind.lastThirtyDays);

  /// The stored form, kept short and human so a person reading the database
  /// can tell what it means: `month`, `d7`, `d30`, `range:3-27`, `range:3`.
  String encode() => switch (kind) {
    HomePeriodKind.calendarMonth => 'month',
    HomePeriodKind.lastSevenDays => 'd7',
    HomePeriodKind.lastFourteenDays => 'd14',
    HomePeriodKind.lastThirtyDays => 'd30',
    HomePeriodKind.dayRange =>
      endDay > 0 ? 'range:$startDay-$endDay' : 'range:$startDay',
  };

  static HomePeriod decode(String? value) {
    switch (value) {
      case 'd7':
        return lastSevenDays;
      case 'd14':
        return lastFourteenDays;
      case 'd30':
        return lastThirtyDays;
      case null:
      case 'month':
        return calendarMonth;
    }
    final match = RegExp(r'^range:(\d{1,2})(?:-(\d{1,2}))?$').firstMatch(value);
    if (match == null) return calendarMonth;
    return HomePeriod(
      kind: HomePeriodKind.dayRange,
      startDay: int.parse(match.group(1)!).clamp(1, 28),
      endDay: int.tryParse(match.group(2) ?? '')?.clamp(1, 31) ?? 0,
    );
  }

  /// The window as real dates. [to] is exclusive.
  (DateTime from, DateTime to) resolve(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    switch (kind) {
      case HomePeriodKind.calendarMonth:
        return (DateTime(today.year, today.month), tomorrow);
      case HomePeriodKind.lastSevenDays:
        return (today.subtract(const Duration(days: 6)), tomorrow);
      case HomePeriodKind.lastFourteenDays:
        return (today.subtract(const Duration(days: 13)), tomorrow);
      case HomePeriodKind.lastThirtyDays:
        return (today.subtract(const Duration(days: 29)), tomorrow);
      case HomePeriodKind.dayRange:
        // The cycle that contains today: if today is before this month's
        // start day, the current cycle opened last month.
        final anchor = today.day >= startDay
            ? DateTime(today.year, today.month, startDay)
            : DateTime(today.year, today.month - 1, startDay);
        if (endDay <= 0) return (anchor, tomorrow);
        // A closed window: it ends on endDay of the same month when that is
        // after the start, otherwise it wraps into the following month.
        final closes = endDay >= startDay
            ? DateTime(anchor.year, anchor.month, endDay)
            : DateTime(anchor.year, anchor.month + 1, endDay);
        final endExclusive = closes.add(const Duration(days: 1));
        return (
          anchor,
          endExclusive.isAfter(tomorrow) ? tomorrow : endExclusive,
        );
    }
  }

  /// What the eyebrow on Home says.
  String label(DateTime now) {
    final (from, to) = resolve(now);
    switch (kind) {
      case HomePeriodKind.calendarMonth:
        return _monthName(from.month);
      case HomePeriodKind.lastSevenDays:
        return 'Last 7 days';
      case HomePeriodKind.lastFourteenDays:
        return 'Last 14 days';
      case HomePeriodKind.lastThirtyDays:
        return 'Last 30 days';
      case HomePeriodKind.dayRange:
        final last = to.subtract(const Duration(days: 1));
        return '${from.day} ${_monthName(from.month).substring(0, 3)} – '
            '${last.day} ${_monthName(last.month).substring(0, 3)}';
    }
  }

  /// One line for the settings list, so the choice reads as a rule rather
  /// than a label.
  String get title => switch (kind) {
    HomePeriodKind.calendarMonth => 'This calendar month',
    HomePeriodKind.lastSevenDays => 'Last 7 days',
    HomePeriodKind.lastFourteenDays => 'Last 14 days',
    HomePeriodKind.lastThirtyDays => 'Last 30 days',
    HomePeriodKind.dayRange =>
      endDay > 0
          ? 'The ${_ordinal(startDay)} to the ${_ordinal(endDay)}'
          : 'From the ${_ordinal(startDay)} each month',
  };

  String get blurb => switch (kind) {
    HomePeriodKind.calendarMonth =>
      'The 1st up to today. Thin until payday lands.',
    HomePeriodKind.lastSevenDays => 'A rolling week.',
    HomePeriodKind.lastFourteenDays =>
      'A rolling fortnight, for pay that arrives every two weeks.',
    HomePeriodKind.lastThirtyDays =>
      'Always contains one pay cycle, whatever day it lands on.',
    HomePeriodKind.dayRange =>
      endDay > 0
          ? 'A fixed window each cycle.'
          : 'Your month starts when you get paid.',
  };

  @override
  bool operator ==(Object other) =>
      other is HomePeriod &&
      other.kind == kind &&
      other.startDay == startDay &&
      other.endDay == endDay;

  @override
  int get hashCode => Object.hash(kind, startDay, endDay);

  static String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][(month - 1) % 12];

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }
}
