import 'package:flutter/material.dart';

import '../../state/app_info.dart';
import 'brand_wordmark.g.dart';

/// The dsh-go wordmark: the same four shapes as [BrandMark], laid out in one row.
///
/// Vector paths generated from the master in `assets/brand/wordmark.svg`
/// (`brand_wordmark.g.dart`, by `tool/make_brand_wordmark.py`).
///
/// One flat fill, so it follows the page: [color] when given, else the theme's
/// on-surface colour. Use it where brand type belongs on a single line — the
/// welcome heading, one-line loading states, the poster and share card — and keep
/// [BrandMark] where space is tight.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.height = 20, this.color});

  /// Height of the wordmark; its width is [aspect] × this.
  final double height;

  /// A flat tint; defaults to the theme's on-surface colour.
  final Color? color;

  /// Width / height of the wordmark.
  static const aspect = BrandWordmarkPaths.aspect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppInfo.wordmark,
      image: true,
      child: CustomPaint(
        size: Size(height * aspect, height),
        painter: _WordmarkPainter(color ?? Theme.of(context).colorScheme.onSurface),
      ),
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  const _WordmarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const box = BrandWordmarkPaths.box;
    canvas.save();
    canvas.scale(size.width / box.width, size.height / box.height);
    canvas.translate(-box.left, -box.top);
    canvas.drawPath(BrandWordmarkPaths.ink, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordmarkPainter oldDelegate) => oldDelegate.color != color;
}
