import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:spendwise/app/category_tones.dart';
import 'package:spendwise/features/reports/report_hero.dart' as hero;
import 'package:spendwise/features/reports/report_hero_desk.dart';
import 'package:spendwise/features/reports/spending_report.dart';
import 'package:spendwise/features/shell/spendwise_view_model.dart';

/// Walks a `pw` widget tree without ever laying it out or painting it to PDF
/// bytes -- every class this hero builds with (`Container`, `SizedBox`,
/// `Row`, `Column`, `Stack`, `Positioned`, `Expanded`, `Text`) stores its
/// children as plain, readable fields, so "does every category's name reach
/// the page" and "does no stray colour appear" are questions a test can ask
/// of the widget objects directly, the same way the fraction-to-height
/// arithmetic is asked of [deskLevelFor] directly rather than through a
/// rendered page.
Iterable<pw.Widget> _flatten(pw.Widget root) sync* {
  yield root;
  if (root is pw.Container) {
    if (root.child != null) yield* _flatten(root.child!);
  } else if (root is pw.SizedBox) {
    if (root.child != null) yield* _flatten(root.child!);
  } else if (root is pw.MultiChildWidget) {
    for (final child in root.children) {
      yield* _flatten(child);
    }
  } else if (root is pw.SingleChildWidget) {
    if (root.child != null) yield* _flatten(root.child!);
  }
}

List<String> _allText(List<pw.Widget> roots) => roots
    .expand(_flatten)
    .whereType<pw.Text>()
    .map((widget) => widget.text.toPlainText())
    .toList();

List<PdfColor> _fillColors(List<pw.Widget> roots) => roots
    .expand(_flatten)
    .whereType<pw.Container>()
    .map((container) => container.decoration?.color)
    .whereType<PdfColor>()
    .toList();

void main() {
  const paperTone = PdfColor.fromInt(0xFFFAF9F6);
  const inkTone = PdfColor.fromInt(0xFF17191A);
  const mutedTone = PdfColor.fromInt(0xFF6B7176);
  const ruleTone = PdfColor.fromInt(0xFFDFDDD6);

  TransactionViewData expense(String category, int minor, {int day = 1}) =>
      TransactionViewData(
        id: '$category-$day-$minor',
        title: '$category purchase',
        subtitle: 'Test account',
        amount: MoneyViewData(-minor),
        kind: TransactionKind.expense,
        occurredAt: DateTime(2026, 9, day),
        category: category,
        accountName: 'Test account',
      );

  ReportData dataFor(List<TransactionViewData> transactions) =>
      ReportData.gather(
        request: ReportRequest.forRange(
          ReportRange.thisMonth,
          hero.ReportTemplate.ribbon,
          now: DateTime(2026, 9, 30),
        ),
        transactions: transactions,
        accounts: const [],
      );

  hero.ReportPaper paperFor(
    ReportData data, {
    Map<String, PdfColor> tones = const {},
  }) => hero.ReportPaper(
    data: data,
    sans: pw.Font.helvetica(),
    bold: pw.Font.helveticaBold(),
    mono: pw.Font.courier(),
    ink: inkTone,
    muted: mutedTone,
    rule: ruleTone,
    paper: paperTone,
    keep: const PdfColor.fromInt(0xFF2E5339),
    spend: const PdfColor.fromInt(0xFF7A3B2E),
    mine: const PdfColor.fromInt(0xFF2E4A5B),
    channelOf: (category) => 1,
    toneOf: (category) => tones[category] ?? const PdfColor.fromInt(0xFF444444),
    money: (minor) => (minor / 100).toStringAsFixed(2),
    width: 499.28,
  );

  group('template identity', () {
    test('the hero answers to the desk template', () {
      expect(const DeskHero().template, hero.ReportTemplate.desk);
    });
  });

  group('the degenerate cases', () {
    test('an empty period states so plainly, without drawing a strip', () {
      final paper = paperFor(dataFor(const []));
      final widgets = const DeskHero().build(paper);
      expect(widgets, isNotEmpty);
      final texts = _allText(widgets);
      expect(
        texts.any((text) => text.contains('No categories')),
        isTrue,
        reason: 'texts were: $texts',
      );
      // Nothing pretending to be a fader for a period with nothing in it.
      expect(_fillColors(widgets), isEmpty);
    });

    test('one category draws the solo module, named in full', () {
      final paper = paperFor(
        dataFor([expense('Groceries', 150000)]),
        tones: {'Groceries': const PdfColor.fromInt(0xFF8A5A3C)},
      );
      final widgets = const DeskHero().build(paper);
      final texts = _allText(widgets);
      expect(texts, contains('Groceries'));
      expect(texts, contains('100%'));
      expect(
        texts.any((text) => text.contains('1500.00')),
        isTrue,
        reason: 'the solo module states the amount, texts were: $texts',
      );
    });

    test('three categories lay out as a centred mini desk', () {
      const categories = [
        MapEntry('Groceries', 96000),
        MapEntry('Rent', 320000),
        MapEntry('Transport', 41000),
      ];
      final tones = deskTonesFor(categories);
      final layout = deskLayoutFor(categories, tones.channelOf);
      expect(layout.mini, isTrue);
      expect(layout.channels, hasLength(3));

      final paper = paperFor(
        dataFor([
          for (final entry in categories) expense(entry.key, entry.value),
        ]),
        tones: {
          for (final entry in categories)
            entry.key: const PdfColor.fromInt(0xFF8A5A3C),
        },
      );
      final texts = _allText(const DeskHero().build(paper));
      for (final entry in categories) {
        expect(texts, contains(entry.key));
      }
    });

    test(
      'thirty categories fold, but every one is still named on the page',
      () {
        final categories = [
          for (var i = 0; i < 30; i++) MapEntry('Category $i', 1000 + i * 37),
        ];
        final tones = deskTonesFor(categories);
        final layout = deskLayoutFor(categories, tones.channelOf);

        // Past foldAt (14), the strip keeps foldAt - 1 real channels and folds
        // the rest into exactly one AUX channel -- the screen's own rule.
        expect(layout.channels, hasLength(DeskHero.foldAt));
        final aux = layout.channels.singleWhere((channel) => channel.isAux);
        expect(aux.auxCount, 30 - (DeskHero.foldAt - 1));
        expect(aux.auxFolded, hasLength(aux.auxCount));

        final paper = paperFor(
          dataFor([
            for (final entry in categories)
              expense(
                entry.key,
                entry.value,
                day: (categories.indexOf(entry) % 27) + 1,
              ),
          ]),
          tones: {
            for (final entry in categories)
              entry.key: const PdfColor.fromInt(0xFF8A5A3C),
          },
        );
        final texts = _allText(const DeskHero().build(paper));
        for (final entry in categories) {
          expect(
            texts.any((text) => text == entry.key),
            isTrue,
            reason:
                '${entry.key} must be named on the page even if it was '
                'folded into AUX -- paper has no tap to reveal it',
          );
        }
      },
    );
  });

  group('proportion and the floor', () {
    test('a fader\'s cap height is in true proportion to its share, and the '
        'floor keeps a sliver visible', () {
      const maxFraction = 0.234;
      const smallFraction = 0.00433; // 0.433%, the design's own stress case
      final bigLevel = deskLevelFor(maxFraction, maxFraction);
      final smallLevel = deskLevelFor(smallFraction, maxFraction);

      expect(
        bigLevel,
        DeskHero.minCap + (maxFraction / maxFraction) * DeskHero.range,
      );
      expect(
        smallLevel,
        DeskHero.minCap + (smallFraction / maxFraction) * DeskHero.range,
      );
      // Proportion holds even at the floor: the additive offset is the
      // same for both, so the *difference* between the two levels still
      // scales with the difference in share.
      expect(
        bigLevel - smallLevel,
        closeTo(
          (maxFraction - smallFraction) / maxFraction * DeskHero.range,
          1e-9,
        ),
      );

      // The floor's whole purpose: a 0.4% category next to a 23% one is
      // still drawn with a real, visible cap, not nothing.
      expect(smallLevel, greaterThanOrEqualTo(DeskHero.minCap));
      expect(smallLevel, lessThan(bigLevel));
    });

    test('a category with no share at all draws no cap', () {
      expect(deskLevelFor(0, 0.5), 0);
    });

    test(
      'a 0.4% category beside a 23% one are both visible and both named',
      () {
        const categories = [
          MapEntry('Groceries', 2341000), // 23.41% of the total below
          MapEntry('Transport', 3000000),
          MapEntry('Insurance', 43300), // 0.433% of the total below
        ];
        final total = categories.fold<int>(0, (sum, e) => sum + e.value);
        expect(total, 5384300);
        final tones = deskTonesFor(categories);
        final layout = deskLayoutFor(categories, tones.channelOf);
        final insurance = layout.channels.singleWhere(
          (c) => c.category == 'Insurance',
        );
        final level = deskLevelFor(insurance.fraction, layout.maxFraction);
        expect(level, greaterThanOrEqualTo(DeskHero.minCap));

        final paper = paperFor(
          dataFor([
            for (final entry in categories) expense(entry.key, entry.value),
          ]),
          tones: {
            for (final entry in categories)
              entry.key: const PdfColor.fromInt(0xFF8A5A3C),
          },
        );
        final texts = _allText(const DeskHero().build(paper));
        expect(texts, contains('Groceries'));
        expect(texts, contains('Insurance'));
      },
    );
  });

  group('channel numbering agrees with CategoryTones', () {
    test('every channel\'s printed number equals CategoryTones.channelOf for '
        'the same stable order', () {
      const categories = [
        MapEntry('Zebra crossing tolls', 1000),
        MapEntry('Groceries', 96000),
        MapEntry('Rent', 320000),
        MapEntry('Airfare', 41000),
      ];
      final sortedNames = categories.map((e) => e.key).toList()..sort();
      final independentTones = CategoryTones.positional(sortedNames);
      final tones = deskTonesFor(categories);
      final layout = deskLayoutFor(categories, tones.channelOf);

      for (final channel in layout.channels) {
        expect(
          channel.no,
          independentTones.channelOf(channel.category),
          reason:
              '${channel.category} disagreed with an independently '
              'built CategoryTones over the same stable order',
        );
      }
    });

    test('numbering is stable across periods with the same categories, '
        'even when this period\'s ranking differs', () {
      const periodA = [
        MapEntry('Groceries', 96000),
        MapEntry('Rent', 320000),
        MapEntry('Transport', 41000),
      ];
      const periodB = [
        MapEntry('Groceries', 12000),
        MapEntry('Rent', 8000),
        MapEntry('Transport', 190000), // now the largest, was the smallest
      ];
      final tonesA = deskTonesFor(periodA);
      final tonesB = deskTonesFor(periodB);
      expect(tonesA.channelOf('Groceries'), tonesB.channelOf('Groceries'));
      expect(tonesA.channelOf('Rent'), tonesB.channelOf('Rent'));
      expect(tonesA.channelOf('Transport'), tonesB.channelOf('Transport'));
    });

    test('a folded AUX category still carries its own real stable number', () {
      final categories = [
        for (var i = 0; i < 20; i++) MapEntry('Category $i', 1000 + i * 11),
      ];
      final tones = deskTonesFor(categories);
      final layout = deskLayoutFor(categories, tones.channelOf);
      final aux = layout.channels.singleWhere((c) => c.isAux);
      final independentTones = CategoryTones.positional(
        categories.map((e) => e.key).toList()..sort(),
      );
      for (final folded in aux.auxFolded) {
        expect(folded.no, independentTones.channelOf(folded.category));
      }
    });
  });

  group('print-safe colour', () {
    test('every fill colour on the page is one the paper handed over, never '
        'an invented one', () {
      final categories = [
        for (var i = 0; i < 16; i++) MapEntry('Category $i', 1000 + i * 53),
      ];
      final toneMap = {
        for (final entry in categories)
          entry.key: PdfColor.fromInt(0xFF100000 + entry.value),
      };
      final paper = paperFor(
        dataFor([
          for (final entry in categories) expense(entry.key, entry.value),
        ]),
        tones: toneMap,
      );
      final allowed = {
        inkTone,
        mutedTone,
        ruleTone,
        paperTone,
        ...toneMap.values,
      };
      final used = _fillColors(const DeskHero().build(paper));
      expect(used, isNotEmpty);
      for (final colour in used) {
        expect(
          allowed,
          contains(colour),
          reason:
              '$colour was drawn but never came from paper.toneOf, '
              'paper.ink, paper.muted, paper.rule or paper.paper',
        );
      }
    });
  });
}
