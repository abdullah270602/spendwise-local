import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/home_period.dart';

/// Home is a proportion, and a proportion needs a denominator that exists on
/// every day of the month. These pin down which stretch of time each choice
/// actually covers -- especially the pay-cycle one, where "today is before the
/// start day" quietly means the cycle opened last month.
void main() {
  const noon = Duration(hours: 12);

  test('the calendar month runs from the 1st to today', () {
    final (from, to) = HomePeriod.calendarMonth.resolve(
      DateTime(2026, 11, 4).add(noon),
    );
    expect(from, DateTime(2026, 11));
    expect(to, DateTime(2026, 11, 5));
  });

  test('a rolling month always looks back thirty days', () {
    final (from, to) = HomePeriod.lastThirtyDays.resolve(
      DateTime(2026, 11, 4).add(noon),
    );
    expect(from, DateTime(2026, 10, 6));
    expect(to, DateTime(2026, 11, 5));
    expect(to.difference(from).inDays, 30);
  });

  test('a rolling week looks back seven days', () {
    final (from, to) = HomePeriod.lastSevenDays.resolve(DateTime(2026, 11, 4));
    expect(to.difference(from).inDays, 7);
  });

  group('a pay cycle that starts on the 3rd', () {
    const period = HomePeriod(kind: HomePeriodKind.dayRange, startDay: 3);

    test('on the 10th, the cycle opened this month', () {
      final (from, to) = period.resolve(DateTime(2026, 11, 10));
      expect(from, DateTime(2026, 11, 3));
      expect(to, DateTime(2026, 11, 11));
    });

    test('on the 1st, the cycle opened last month', () {
      // This is the case a calendar month gets wrong: on 1 November your
      // salary arrived on 3 October and is still the money you are spending.
      final (from, to) = period.resolve(DateTime(2026, 11, 1));
      expect(from, DateTime(2026, 10, 3));
      expect(to, DateTime(2026, 11, 2));
    });

    test('it crosses a year boundary', () {
      final (from, _) = period.resolve(DateTime(2026, 1, 2));
      expect(from, DateTime(2025, 12, 3));
    });
  });

  group('a closed window, the 3rd to the 27th', () {
    const period = HomePeriod(
      kind: HomePeriodKind.dayRange,
      startDay: 3,
      endDay: 27,
    );

    test('mid-window it stops at today, not at the 27th', () {
      final (from, to) = period.resolve(DateTime(2026, 11, 10));
      expect(from, DateTime(2026, 11, 3));
      expect(to, DateTime(2026, 11, 11));
    });

    test('past the 27th it stays closed at the 27th', () {
      final (from, to) = period.resolve(DateTime(2026, 11, 30));
      expect(from, DateTime(2026, 11, 3));
      expect(to, DateTime(2026, 11, 28));
    });
  });

  group('a window that wraps the month end, the 27th to the 3rd', () {
    const period = HomePeriod(
      kind: HomePeriodKind.dayRange,
      startDay: 27,
      endDay: 3,
    );

    test('mid-window it never counts days that have not happened', () {
      final (from, to) = period.resolve(DateTime(2026, 11, 30));
      expect(from, DateTime(2026, 11, 27));
      expect(
        to,
        DateTime(2026, 12),
        reason: 'the window runs to 3 Dec, but today is 30 Nov',
      );
    });

    test('once past the 3rd it closes there', () {
      final (from, to) = period.resolve(DateTime(2026, 12, 20));
      expect(from, DateTime(2026, 11, 27));
      expect(to, DateTime(2026, 12, 4));
    });
  });

  group('round-tripping through storage', () {
    const cases = [
      HomePeriod.calendarMonth,
      HomePeriod.lastSevenDays,
      HomePeriod.lastThirtyDays,
      HomePeriod(kind: HomePeriodKind.dayRange, startDay: 3),
      HomePeriod(kind: HomePeriodKind.dayRange, startDay: 3, endDay: 27),
    ];

    for (final period in cases) {
      test(period.encode(), () {
        expect(HomePeriod.decode(period.encode()), period);
      });
    }

    test('nonsense falls back to the calendar month', () {
      expect(HomePeriod.decode('wat'), HomePeriod.calendarMonth);
      expect(HomePeriod.decode(null), HomePeriod.calendarMonth);
    });
  });

  test('labels read as periods, not settings', () {
    final now = DateTime(2026, 11, 10);
    expect(HomePeriod.calendarMonth.label(now), 'November');
    expect(HomePeriod.lastThirtyDays.label(now), 'Last 30 days');
    expect(
      const HomePeriod(
        kind: HomePeriodKind.dayRange,
        startDay: 3,
      ).label(now),
      '3 Nov – 10 Nov',
    );
    expect(
      const HomePeriod(
        kind: HomePeriodKind.dayRange,
        startDay: 3,
        endDay: 27,
      ).title,
      'The 3rd to the 27th',
    );
  });
}
