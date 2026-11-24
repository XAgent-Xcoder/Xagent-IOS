import 'package:flutter/material.dart';

import 'brand_glyph.g.dart';

/// The approved Xagent symbol, optionally tinted or placed on its launcher tile.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28, this.color, this.tile = false});

  /// Height of the glyph (its width is [aspect] × this), or the side of the tile when
  /// [tile] is true.
  final double size;

  /// A flat tint instead of the colour glyph. Ignored on a tile.
  final Color? color;

  /// Draw the launcher tile (splash, about, update).
  final bool tile;

  /// Width / height of the glyph.
  static const aspect = BrandGlyph.aspect;

  /// The glyph's visual centre, the area centroid of its ink, as fractions of its
  /// width and height from the top left.
  static final visualCentre = Offset(
    (BrandGlyph.centroid.dx - BrandGlyph.box.left) / BrandGlyph.box.width,
    (BrandGlyph.centroid.dy - BrandGlyph.box.top) / BrandGlyph.box.height,
  );

  /// How far to move a glyph of height [size] so its visual centre, not its box,
  /// sits on the centre of the space it is centred in.
  static Offset opticalShift(double size) =>
      Offset((0.5 - visualCentre.dx) * size * aspect, (0.5 - visualCentre.dy) * size);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Xagent',
      image: true,
      child: CustomPaint(
        size: tile ? Size.square(size) : Size(size * aspect, size),
        painter: _BrandPainter(tile, color),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter(this.tile, this.color);
  final bool tile;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (tile) {
      canvas.scale(size.width / 464, size.height / 464);
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 464, 464), const Radius.circular(86)),
        Paint()..color = BrandGlyph.ink,
      );
      canvas.translate(57, 96);
    } else {
      canvas.scale(size.width / 357, size.height / 280);
    }
    BrandGlyph.paint(canvas, tile ? null : color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter old) => old.tile != tile || old.color != color;
}

/// The outlined Xagent lettering. Its height includes the descender of the g.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, required this.height, this.color});
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'Xagent',
    child: CustomPaint(
      size: Size(height * 735 / 165, height),
      painter: _WordPainter(color ?? (Theme.of(context).brightness == Brightness.dark ? Colors.white : BrandGlyph.ink)),
    ),
  );
}

class _WordPainter extends CustomPainter {
  const _WordPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 735, size.height / 165);
    canvas.translate(-8, -13);
    canvas.drawPath(BrandGlyph.word, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WordPainter old) => old.color != color;
}

/// The original vertical signature, using the 464 × 572 master proportions.
class BrandSignature extends StatelessWidget {
  const BrandSignature({super.key, required this.width, this.wordColor});
  final double width;
  final Color? wordColor;

  @override
  Widget build(BuildContext context) {
    final unit = width / 464;
    return Semantics(
      image: true,
      label: 'Xagent',
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: unit * 572,
          child: Stack(
            children: [
              BrandMark(tile: true, size: width),
              Positioned(
                left: 45 * unit,
                top: 477 * unit,
                child: BrandWordmark(height: 82.5 * unit, color: wordColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
