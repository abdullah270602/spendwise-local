import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/features/insights/insights_layout.dart';

/// The last setting this app shipped did nothing, because the value reached
/// storage and no one asked whether the screen obeyed it. These are the
/// cheap half of that lesson: the ids round-trip, and an unset or corrupt
/// preference lands on a defensible default rather than on whatever the
/// first enum member happens to be.
void main() {
  test('every id round-trips', () {
    for (final value in InsightsOverTime.values) {
      expect(InsightsOverTime.fromId(value.id), value);
    }
    for (final value in InsightsShare.values) {
      expect(InsightsShare.fromId(value.id), value);
    }
    for (final value in InsightsChange.values) {
      expect(InsightsChange.fromId(value.id), value);
    }
  });

  test('ids are distinct within each question', () {
    for (final ids in [
      InsightsOverTime.values.map((v) => v.id),
      InsightsShare.values.map((v) => v.id),
      InsightsChange.values.map((v) => v.id),
    ]) {
      expect(ids.toSet(), hasLength(ids.length));
    }
  });

  test('an unset preference lands on the agreed defaults', () {
    // Nothing stored, and a value stored by a version that no longer exists.
    for (final absent in <String?>[null, '', 'donut']) {
      expect(InsightsOverTime.fromId(absent), InsightsOverTime.spine);
      expect(InsightsShare.fromId(absent), InsightsShare.chronograph);
      expect(InsightsChange.fromId(absent), InsightsChange.off);
    }
  });

  test('what changed stays off until it is asked for', () {
    // It is the only section that makes a claim about the past rather than
    // reporting the present, so it is opted into, not met on a first run.
    expect(InsightsChange.fromId(null).isOn, isFalse);
    expect(InsightsOverTime.fromId(null).isOn, isTrue);
    expect(InsightsShare.fromId(null).isOn, isTrue);
  });

  test('preference keys are distinct and namespaced', () {
    const keys = [
      InsightsPreference.overTime,
      InsightsPreference.share,
      InsightsPreference.change,
      InsightsPreference.gateSensitivity,
    ];
    expect(keys.toSet(), hasLength(keys.length));
    for (final key in keys) {
      expect(key, startsWith('insights_'));
    }
  });

  test('every choice says what it is, briefly', () {
    for (final detail in [
      ...InsightsOverTime.values.map((v) => v.detail),
      ...InsightsShare.values.map((v) => v.detail),
      ...InsightsChange.values.map((v) => v.detail),
    ]) {
      expect(detail, isNotEmpty);
      // One short line. The preview above does the explaining; a settings
      // screen that argues with you in prose is one nobody reads.
      expect(detail.length, lessThan(80), reason: detail);
    }
  });
}
