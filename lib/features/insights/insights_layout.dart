/// What Insights is made of, and which of it you want.
///
/// The screen answers three separate questions, and it took building four
/// visuals to see that they were separate. "Where your money went" is a share
/// of one period. "What changed" is one period against another, and needs data
/// the first question never asks for — a category you stopped spending on is
/// absent from a share breakdown entirely and is one of the most useful things
/// a comparison can tell you. "Over time" is neither; it is the shape of the
/// days themselves.
///
/// So there are three settings rather than one list of five drawings. A single
/// chooser offering the dial, the desk, the trace and the corridor as
/// alternatives would have been asking people to pick between answers to
/// different questions.
library;

/// The shape of the days: money in and money out, bucket by bucket.
enum InsightsOverTime {
  spine(
    id: 'spine',
    title: 'Show the days',
    detail: 'What came in and what left, one bar per day.',
  ),
  off(id: 'off', title: 'Skip it', detail: 'Insights starts at the figures.');

  const InsightsOverTime({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  bool get isOn => this == spine;

  static InsightsOverTime fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return spine;
  }
}

/// Where the money went: this period's spending, split by category.
enum InsightsShare {
  bars(
    id: 'bars',
    title: 'Bars',
    detail: 'One bar to true proportion, then every category by name.',
  ),
  chronograph(
    id: 'chronograph',
    title: 'Chronograph',
    detail: 'A dial. Each category a marker on the rim, its length the share.',
  ),
  mixingDesk(
    id: 'desk',
    title: 'Mixing desk',
    detail: 'A fader per category, each one keeping its own channel.',
  ),
  off(id: 'off', title: 'Skip it', detail: 'No breakdown of where it went.');

  const InsightsShare({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  bool get isOn => this != off;

  static InsightsShare fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return chronograph;
  }
}

/// What changed: this period measured against the one before it.
///
/// Off by default. It is the one section that makes a claim about the past
/// rather than reporting the present, and a claim like that is better turned
/// on deliberately than met on a first run.
enum InsightsChange {
  off(
    id: 'off',
    title: 'Skip it',
    detail: 'Insights reports this period only.',
  ),
  seismograph(
    id: 'seismograph',
    title: 'Seismograph',
    detail: 'One continuous trace. A quiet period is nearly a straight line.',
  ),
  gate(
    id: 'gate',
    title: 'The gate',
    detail: 'Only what moved enough to matter. The rest is filed as steady.',
  );

  const InsightsChange({
    required this.id,
    required this.title,
    required this.detail,
  });

  final String id;
  final String title;
  final String detail;

  bool get isOn => this != off;

  static InsightsChange fromId(String? id) {
    for (final value in values) {
      if (value.id == id) return value;
    }
    return off;
  }
}

/// The keys these are stored under. Named here rather than typed as strings
/// at each call site, because a preference read with a misspelt key does not
/// fail — it silently returns the default, and the setting appears to do
/// nothing at all. That has already happened once on this screen's siblings.
abstract final class InsightsPreference {
  static const overTime = 'insights_over_time';
  static const share = 'insights_share';
  static const change = 'insights_change';
  static const gateSensitivity = 'insights_gate_sensitivity';
  static const period = 'insights_period';
}
