import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_icon_state.dart';
import '../../state/app_info.dart';
import '../theme/theme.dart';

/// The Coka mark: the 3D cube C the launcher icons are made from.
///
/// The same four renders are bundled (`assets/brand/icons/logo_*.png`), so the
/// drawer's lockup, the about page, the splash and the launcher icon never drift
/// apart. [color] draws the mono silhouette tinted instead, for quiet footers.
class BrandMark extends ConsumerWidget {
  const BrandMark({super.key, this.size = 28, this.color, this.tile = false});

  /// Side of the mark. The artwork is square.
  final double size;

  /// A flat tint of the mono silhouette instead of the colour logo.
  final Color? color;

  /// Kept for callers that draw the launcher tile: the artwork already is the tile.
  final bool tile;

  /// Width / height of the glyph (the artwork is square).
  static const aspect = 1.0;

  /// The logo for each launcher theme, as bundled: the same four 3D renders the
  /// launcher icons are cut from.
  static const assets = <AppIcon, String>{
    AppIcon.mist: 'assets/brand/icons/logo_mist.png',
    AppIcon.night: 'assets/brand/icons/logo_night.png',
    AppIcon.frost: 'assets/brand/icons/logo_frost.png',
    AppIcon.ink: 'assets/brand/icons/logo_ink.png',
  };

  static const monoAsset = 'assets/brand/icons/logo_mono.png';

  /// The artwork is centred, so the visual centre is the box's.
  static const visualCentre = Offset(0.5, 0.5);

  /// How far to move a glyph so its visual centre sits on the centre of the
  /// space it is centred in: nothing, the artwork is centred already.
  static Offset opticalShift(double size) => Offset.zero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appIconProvider).value?.current ?? AppIcon.mist;
    final tint = color;
    return Semantics(
      label: AppInfo.wordmark,
      image: true,
      child: tint == null
          ? Image.asset(
              assets[current] ?? assets[AppIcon.mist]!,
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            )
          : Image.asset(
              monoAsset,
              width: size,
              height: size,
              fit: BoxFit.contain,
              color: tint,
              colorBlendMode: BlendMode.srcIn,
            ),
    );
  }
}

/// The glyph and a wordmark on one line.
///
/// Everything follows the word's size (0.95 × [height] by default, times the app's
/// text scale):
/// - the glyph is [glyphScale] × the word's size tall;
/// - its visual centre ([BrandMark.visualCentre]) sits on the centre of the word's
///   main band: the x-height for a lowercase word (「dsh-go」), the cap height for
///   capitals (「DSH」);
/// - [gapScale] × the word's size separates the glyph's ink from the word.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.height = 20,
    this.fontSize,
    this.label = AppInfo.wordmark,
    this.color,
    this.glyphColor,
  });

  /// The lockup's size; the word is set at 0.95 × this unless [fontSize] is given.
  final double height;

  /// The word's size, overriding the one derived from [height].
  final double? fontSize;

  final String label;

  /// The word's colour (default: onSurface).
  final Color? color;

  /// A flat glyph tint instead of the colour glyph.
  final Color? glyphColor;

  /// Glyph height / word size.
  static const glyphScale = 1.25;

  /// Gap between the glyph and the word / word size.
  static const gapScale = 0.36;

  /// x-height and cap height of the system sans, in ems (Roboto: 1082 and 1456 of
  /// 2048 units).
  static const xHeight = 0.528;
  static const capHeight = 0.711;

  /// Height above the baseline of the line the glyph centres on, for [label] set at
  /// [size].
  static double centreRise(String label, double size) =>
      (label.contains(RegExp('[a-z]')) ? xHeight : capHeight) * size / 2;

  /// Where the word starts, from the lockup's left edge, for a word drawn at [size]
  /// (after text scaling): glyph width + gap.
  static double wordInset(double size) => size * glyphScale * BrandMark.aspect + size * gapScale;

  double get _size => fontSize ?? height * 0.95;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The word's drawn size: the glyph and the gap scale with the text.
    final drawn = MediaQuery.textScalerOf(context).scale(_size);
    final glyph = drawn * glyphScale;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _GlyphBaseline(
          // A baseline this far below the glyph's top puts its visual centre on the
          // word's x-height (or cap-height) centre when the row aligns baselines.
          baseline: glyph * BrandMark.visualCentre.dy + centreRise(label, drawn),
          child: BrandMark(size: glyph, color: glyphColor),
        ),
        SizedBox(width: drawn * gapScale),
        Text(
          label,
          style: AppType.wordmark(size: _size, color: color ?? scheme.onSurface),
        ),
      ],
    );
  }
}

/// Reports [baseline] as its child's alphabetic baseline.
class _GlyphBaseline extends SingleChildRenderObjectWidget {
  const _GlyphBaseline({required this.baseline, required super.child});

  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlyphBaseline(baseline);

  @override
  void updateRenderObject(BuildContext context, _RenderGlyphBaseline renderObject) {
    renderObject.baseline = baseline;
  }
}

class _RenderGlyphBaseline extends RenderProxyBox {
  _RenderGlyphBaseline(this._baseline);

  double _baseline;

  set baseline(double value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _baseline;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => _baseline;
}
