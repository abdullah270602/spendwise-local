package com.spendwise.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import kotlin.math.roundToInt

/// Draws the widget's one picture: everything that came in, splitting into
/// what stayed and what went -- and, for the one style that asks for it,
/// what stayed dividing further into what is still liquid and what was put
/// away. No digits are ever composed into this bitmap; the only inputs are
/// one or two fractions, a flag, and three colours, none of which crossed
/// from Dart carrying an amount.
///
/// This is a second implementation of the static case of `FlowShape` --
/// `reveal` fixed at 1, no wobble -- because a widget is redrawn on demand
/// rather than animated. It draws exactly the three shapes Home itself
/// offers as `HomeSavingsStyle`: the plain two-branch split ("off" and
/// "only what I can spend" -- the widget cannot tell those apart by shape,
/// because Home doesn't either, having already folded the difference into
/// the fraction before either one reaches a ribbon), and the three-branch
/// split ("saving gets its own branch"). `HomeSavingsStyle.divided` and
/// `.seam` mark the same division as a shading inside the kept ribbon
/// rather than a branch beside it -- legible on a phone screen someone is
/// looking at up close, and indistinguishable from noise at launcher scale
/// with no legend to explain what the shading means. So this renderer never
/// draws them; a month set to either style publishes the same two-branch
/// shape "off" would.
///
/// That duplication of Home's own geometry is the one this project's own
/// build note warned against, and it survives here only because
/// `flow_shape_geometry_ports_test.dart` (in the Flutter test suite) reads
/// the named constants back out of both this file and
/// `lib/widgets/shape_kit.dart` as plain text and fails the moment either
/// one changes without the other. Touching a constant below without
/// touching that test, or the Dart file it compares against, is the mistake
/// this whole arrangement exists to catch loudly instead of silently.
///
/// There used to be a fixed near-black card behind all of this, matching
/// the app's own ground so the palette's `keep` and `spend` tones -- picked
/// to read against that ground specifically -- never had to prove
/// themselves against anything else. The card is gone: the shape now sits
/// directly on whatever the launcher is showing, which is the whole point
/// of a home-screen widget, and which means every filled area here can end
/// up on a wallpaper lighter than it is, darker than it is, or with both in
/// the same frame. [drawHalo] is what survives that -- see its own comment
/// for the technique, and the class comment on why it is not a shadow or a
/// gradient in disguise.
object SpendWiseHomeWidgetRenderer {
    // Mirrors `_buildFlowGeometry`'s local constants of the same name --
    // dp figures, scaled by `density` at the point they are used below,
    // because unlike Flutter's logical pixels this canvas is measured in
    // real device pixels.
    private const val BAR_HEIGHT_DP = 10f
    private const val TOP_Y_DP = 6f
    private const val TOP_WIDTH_FRACTION = 0.46f
    private const val MARGIN_FRACTION = 0.14f
    private const val CONTROL_1_FRACTION = 0.42f
    private const val CONTROL_2_FRACTION = 0.60f

    /// The gap between the kept and saved footings when the "siblings" style
    /// draws three branches -- mirrors `shape_kit.dart`'s `siblingGapDp`.
    private const val SIBLING_GAP_DP = 6f

    // The alphas the kept, spent and saved ribbons are painted at in
    // shape_kit.dart's `_buildFlowGeometry` (`SpendWiseColors.keep/spend/mine`
    // `.withValues(alpha: ...)`), and the trunk tone, which is a true
    // constant in that file rather than part of the user's palette choice
    // -- SpendWiseColors.fg never changes with `SpendWiseColors.apply`,
    // unlike `keep`, `spend` and `mine`, so it never needs to cross the
    // channel at all. These alphas are not part of the guarded geometry
    // contract above: an alpha changes how a branch reads, never which
    // branch a tap or a glance lands on, which is the line
    // `flow_shape_geometry_ports_test.dart` actually polices.
    private const val KEPT_RIBBON_ALPHA = 0.30f
    private const val SPENT_RIBBON_ALPHA = 0.48f
    private const val SAVED_RIBBON_ALPHA = 0.34f
    private const val TRUNK_COLOR = 0xFFE9E7E2.toInt()

    /// The keyline's dark ring -- mirrors `SpendWiseColors.bg`, the app's own
    /// near-black ground. Not the widget's background any more (there is
    /// none), just one half of the two-tone outline in [drawHalo].
    private const val OUTLINE_DARK_COLOR = 0xFF0F1113.toInt()

    /// The keyline's light ring. Deliberately the same value as
    /// [TRUNK_COLOR] rather than a second constant -- both are
    /// `SpendWiseColors.fg`, and drawing the trunk in it and haloing every
    /// shape in it is the same choice made twice, not two different ones.
    private const val OUTLINE_LIGHT_COLOR = TRUNK_COLOR

    private const val HALO_OUTER_WIDTH_DP = 1.5f
    private const val HALO_INNER_WIDTH_DP = 0.75f

    /// Below this height a Bezier has no room to read as a curve -- it would
    /// draw as a jagged pinch, not a ribbon. A flat two-tone bar says the
    /// same proportion honestly at a size the full shape cannot fit. The
    /// third branch needs no lower threshold of its own: a launcher cell
    /// too small for the plain split to read as a curve is smaller still for
    /// three of them, so the same guard already covers it.
    private const val MIN_RIBBON_HEIGHT_DP = 64f

    /// A launcher cell makes no promise about its own aspect ratio the way
    /// Home's own column does -- Home never draws this ribbon taller than
    /// it is wide, so a cell that lands square or taller would stretch the
    /// same curve into a needle rather than widen it into a fan. The ribbon
    /// is drawn at a height capped by its width instead, and centred in
    /// whatever height is left over -- which [render] gets for free by
    /// simply drawing a shorter bitmap than the widget's own canvas and
    /// letting the layout's `fitCenter` place it, rather than by drawing
    /// into a padded sub-rectangle of a bitmap the same size as the cell.
    private const val MAX_RIBBON_HEIGHT_TO_WIDTH = 0.85f

    fun render(
        widthPx: Int,
        heightPx: Int,
        densityDpToPx: Float,
        hasData: Boolean,
        keptFraction: Float,
        hasSavedBranch: Boolean,
        savedFraction: Float,
        keepColor: Int,
        spendColor: Int,
        mineColor: Int,
    ): Bitmap {
        val heightDp = heightPx / densityDpToPx
        // Whether there is room for the full fan, whether or not there is
        // yet anything to pour into it -- the empty state draws the same
        // outline the populated one would fill, so it needs the same floor
        // and the same short, width-capped bitmap the populated one gets.
        val ribbonShaped = heightDp >= MIN_RIBBON_HEIGHT_DP
        // `.coerceAtMost(heightPx)` guards a rounding edge: right at the
        // threshold, converting the dp floor back to pixels can round up by
        // a hair more than converting the actual height did, which would
        // otherwise hand `coerceIn` a lower bound above its own upper bound.
        val minRibbonPx = (MIN_RIBBON_HEIGHT_DP * densityDpToPx).roundToInt().coerceAtMost(heightPx)
        val bitmapHeightPx = if (ribbonShaped) {
            (widthPx * MAX_RIBBON_HEIGHT_TO_WIDTH).roundToInt().coerceIn(minRibbonPx, heightPx)
        } else {
            heightPx
        }

        val bitmap = Bitmap.createBitmap(
            widthPx.coerceAtLeast(1),
            bitmapHeightPx.coerceAtLeast(1),
            Bitmap.Config.ARGB_8888,
        )
        val canvas = Canvas(bitmap)
        val w = widthPx.toFloat()
        val h = bitmapHeightPx.toFloat()
        when {
            !hasData && ribbonShaped -> drawEmptyRibbonOutline(canvas, w, h, densityDpToPx)
            !hasData -> drawEmptyPill(canvas, w, h, densityDpToPx)
            !ribbonShaped -> drawFlatBar(canvas, w, h, densityDpToPx, keptFraction, keepColor, spendColor)
            else -> drawRibbon(
                canvas,
                w,
                h,
                densityDpToPx,
                keptFraction,
                hasSavedBranch,
                savedFraction,
                keepColor,
                spendColor,
                mineColor,
            )
        }
        return bitmap
    }

    /// Draws a two-tone "keyline" around [path]: a slightly wider ring in
    /// the app's own near-black ground colour, then a thinner ring in its
    /// near-white foreground colour on top -- two flat, fully opaque
    /// hairlines, not a shadow (no blur, no offset, nothing sampled from the
    /// shape itself) and not a gradient (each ring is one colour, not a
    /// transition between colours). Every filled area in this file now sits
    /// directly on the launcher's own wallpaper rather than the card that
    /// used to sit behind it, and no single hairline colour can promise a
    /// contrasting edge against every ground a person might drop this
    /// widget on: a wallpaper that is itself near-black would swallow a
    /// dark ring, and one that is near-white would swallow a light one.
    /// Drawing both means whichever ring the local wallpaper pixel fails to
    /// contrast against, the other one still holds the boundary -- and
    /// against a busy photograph, which is light in some places and dark in
    /// others, one ring or the other is doing that job at every point along
    /// the same outline.
    private fun drawHalo(canvas: Canvas, path: Path, density: Float) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        paint.strokeWidth = HALO_OUTER_WIDTH_DP * density
        paint.color = OUTLINE_DARK_COLOR
        canvas.drawPath(path, paint)
        paint.strokeWidth = HALO_INNER_WIDTH_DP * density
        paint.color = OUTLINE_LIGHT_COLOR
        canvas.drawPath(path, paint)
    }

    private fun rectPath(l: Float, t: Float, r: Float, b: Float): Path =
        Path().apply { addRect(l, t, r, b, Path.Direction.CW) }

    /// The cubic-Bezier fan one branch of the ribbon is built from --
    /// shared by [drawRibbon] and [drawEmptyRibbonOutline] so the resting
    /// state is provably the same curve the populated one uses, not a
    /// lookalike that could drift from it.
    private fun ribbonPath(aTop: Float, bTop: Float, aBot: Float, bBot: Float, yTop: Float, botY: Float, c1: Float, c2: Float): Path {
        val path = Path()
        path.moveTo(aTop, yTop)
        path.cubicTo(aTop, c1, aBot, c2, aBot, botY)
        path.lineTo(bBot, botY)
        path.cubicTo(bBot, c2, bTop, c1, bTop, yTop)
        path.close()
        return path
    }

    /// Nothing has arrived or left yet, and the widget is too small for the
    /// full fan to have room to read as one -- a single haloed pill, empty
    /// rather than filled. Not a 50/50 split, and not filled-in-dim either:
    /// a share of nothing is not a share, and a shape with nothing poured
    /// into it is not the same claim as a shape half full of something.
    private fun drawEmptyPill(canvas: Canvas, w: Float, h: Float, density: Float) {
        val barH = (h * 0.14f).coerceIn(4f * density, BAR_HEIGHT_DP * density)
        val top = (h - barH) / 2f
        val margin = w * MARGIN_FRACTION
        val radius = barH / 2f
        val path = Path().apply {
            addRoundRect(margin, top, w - margin, top + barH, radius, radius, Path.Direction.CW)
        }
        drawHalo(canvas, path, density)
    }

    /// The resting state once the widget is large enough for the full fan:
    /// the same trunk-into-two-branches shape [drawRibbon] fills once there
    /// is a fraction to show, but every fill skipped and only the keyline
    /// drawn -- an outline of the shape with nothing in it yet, rather than
    /// a bar that reads as a divider or a stalled progress indicator. The
    /// split is exactly even because there is no fraction to be honest
    /// about: this is the shape, not a claim about a proportion that does
    /// not exist yet.
    private fun drawEmptyRibbonOutline(canvas: Canvas, w: Float, h: Float, density: Float) {
        val barH = BAR_HEIGHT_DP * density
        val topY = TOP_Y_DP * density
        val topW = w * TOP_WIDTH_FRACTION
        val topX = (w - topW) / 2f
        val botY = h - barH - 2f * density
        val margin = w * MARGIN_FRACTION

        val keptW = topW / 2f
        val spentW = topW - keptW
        val keptBotX = margin
        val spentBotX = (w - margin) - spentW
        val splitX = topX + keptW
        val c1 = topY + barH + (botY - topY - barH) * CONTROL_1_FRACTION
        val c2 = topY + barH + (botY - topY - barH) * CONTROL_2_FRACTION
        val yTop = topY + barH

        drawHalo(canvas, ribbonPath(topX, splitX, keptBotX, keptBotX + keptW, yTop, botY, c1, c2), density)
        drawHalo(canvas, rectPath(keptBotX, botY, keptBotX + keptW, botY + barH), density)
        drawHalo(canvas, ribbonPath(splitX, topX + topW, spentBotX, spentBotX + spentW, yTop, botY, c1, c2), density)
        drawHalo(canvas, rectPath(spentBotX, botY, spentBotX + spentW, botY + barH), density)
        drawHalo(canvas, rectPath(topX, topY, topX + topW, topY + barH), density)
    }

    /// The smallest honest drawing: two rounded segments, widths at true
    /// proportion, no curve. Same two tones the ribbon uses, same idea, no
    /// room for the fan the full shape needs -- and none for a third sliver
    /// either: a bar already at the minimum readable size gains nothing from
    /// a division too thin to see, so "siblings" draws the identical bar
    /// "off" would at this size, and only the full ribbon ever shows three.
    private fun drawFlatBar(canvas: Canvas, w: Float, h: Float, density: Float, keptFraction: Float, keepColor: Int, spendColor: Int) {
        val margin = w * MARGIN_FRACTION
        val usable = (w - margin * 2f).coerceAtLeast(0f)
        val gap = (2f * density).coerceAtMost(usable * 0.04f)
        val keptW = (usable - gap) * keptFraction
        val spentW = (usable - gap) - keptW
        val barH = (h * 0.4f).coerceIn(6f * density, 18f * density)
        val top = (h - barH) / 2f
        val radius = barH / 2f

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        if (keptW > 0f) {
            paint.color = keepColor
            canvas.drawRoundRect(margin, top, margin + keptW, top + barH, radius, radius, paint)
            drawHalo(canvas, Path().apply { addRoundRect(margin, top, margin + keptW, top + barH, radius, radius, Path.Direction.CW) }, density)
        }
        if (spentW > 0f) {
            paint.color = spendColor
            canvas.drawRoundRect(w - margin - spentW, top, w - margin, top + barH, radius, radius, paint)
            drawHalo(canvas, Path().apply { addRoundRect(w - margin - spentW, top, w - margin, top + barH, radius, radius, Path.Direction.CW) }, density)
        }
    }

    /// The full ribbon: a trunk (everything that arrived) fanning by two
    /// cubic Beziers into a kept branch and a spent branch, with a third
    /// branch carved out of the kept side when [hasSavedBranch] is set.
    /// Formula-for-formula the static case of `_buildFlowGeometry`'s
    /// `asBranch` path -- see the class comment for how the two are kept
    /// from drifting apart. Every filled shape is haloed once it is drawn --
    /// see [drawHalo] for why a fill alone, translucent or not, is no
    /// longer enough to promise an edge a person can actually see.
    private fun drawRibbon(
        canvas: Canvas,
        w: Float,
        h: Float,
        density: Float,
        keptFraction: Float,
        hasSavedBranch: Boolean,
        savedFraction: Float,
        keepColor: Int,
        spendColor: Int,
        mineColor: Int,
    ) {
        val barH = BAR_HEIGHT_DP * density
        val topY = TOP_Y_DP * density
        val topW = w * TOP_WIDTH_FRACTION
        val topX = (w - topW) / 2f
        val botY = h - barH - 2f * density
        val margin = w * MARGIN_FRACTION

        val keptW = topW * keptFraction
        val spentW = topW - keptW

        // reveal = 1: the bottom bars sit at their fully-poured position.
        val keptBotX = margin
        val spentBotRight = w - margin
        val spentBotX = spentBotRight - spentW

        val splitX = topX + keptW
        val c1 = topY + barH + (botY - topY - barH) * CONTROL_1_FRACTION
        val c2 = topY + barH + (botY - topY - barH) * CONTROL_2_FRACTION
        val yTop = topY + barH

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

        // A branch of its own comes out of the kept side, because that is
        // where the money actually came from -- kept narrows by exactly the
        // saved slice, the same way `_buildFlowGeometry` narrows it.
        val savedTopW = if (hasSavedBranch) keptW * savedFraction else 0f
        val liveKeptW = keptW - savedTopW
        val gap = if (hasSavedBranch && savedTopW > 0f) SIBLING_GAP_DP * density else 0f

        val keptRibbon = ribbonPath(topX, topX + liveKeptW, keptBotX, keptBotX + liveKeptW, yTop, botY, c1, c2)
        paint.color = withAlpha(keepColor, KEPT_RIBBON_ALPHA)
        canvas.drawPath(keptRibbon, paint)
        drawHalo(canvas, keptRibbon, density)
        val keptFooting = rectPath(keptBotX, botY, keptBotX + liveKeptW, botY + barH)
        paint.color = keepColor
        canvas.drawPath(keptFooting, paint)
        drawHalo(canvas, keptFooting, density)

        if (hasSavedBranch && savedTopW > 0f) {
            val savedBotX = keptBotX + liveKeptW + gap
            val savedRibbon = ribbonPath(topX + liveKeptW, splitX, savedBotX, savedBotX + savedTopW, yTop, botY, c1, c2)
            paint.color = withAlpha(mineColor, SAVED_RIBBON_ALPHA)
            canvas.drawPath(savedRibbon, paint)
            drawHalo(canvas, savedRibbon, density)
            val savedFooting = rectPath(savedBotX, botY, savedBotX + savedTopW, botY + barH)
            paint.color = mineColor
            canvas.drawPath(savedFooting, paint)
            drawHalo(canvas, savedFooting, density)
        }

        val spentRibbon = ribbonPath(splitX, topX + topW, spentBotX, spentBotX + spentW, yTop, botY, c1, c2)
        paint.color = withAlpha(spendColor, SPENT_RIBBON_ALPHA)
        canvas.drawPath(spentRibbon, paint)
        drawHalo(canvas, spentRibbon, density)
        val spentFooting = rectPath(spentBotX, botY, spentBotX + spentW, botY + barH)
        paint.color = spendColor
        canvas.drawPath(spentFooting, paint)
        drawHalo(canvas, spentFooting, density)

        val trunk = rectPath(topX, topY, topX + topW, topY + barH)
        paint.color = TRUNK_COLOR
        canvas.drawPath(trunk, paint)
        drawHalo(canvas, trunk, density)
    }

    private fun withAlpha(color: Int, alpha: Float): Int =
        Color.argb((alpha * 255f).roundToInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))
}
