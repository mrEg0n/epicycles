// The small marks of the two modes: a chain of circles with its pen for Draw, a scatter of
// points on two axes for Measure.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Which mode a [ModeGlyph] stands for.
enum Mode { draw, measure }

class ModeGlyph extends StatelessWidget {
  const ModeGlyph(this.mode, {super.key, this.size = 96, this.ink = kInk});
  final Mode mode;
  final double size;

  /// Colour of the neutral lines; the accents keep their own colours.
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: mode == Mode.draw ? _DrawGlyph(ink) : _MeasureGlyph(ink),
      ),
    );
  }
}

/// The colour of the neutral lines: lighter ink is thinned out on a dark background, dark ink is
/// kept nearly full on a light one, where it would otherwise fade.
Color _line(Color ink) =>
    ink.withValues(alpha: ink.computeLuminance() < 0.5 ? 0.85 : 0.45);

Paint _stroke(Color c, double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = c;

/// Two chained circles, their arms, and the piece of curve the pen has just traced.
class _DrawGlyph extends CustomPainter {
  _DrawGlyph(this.ink);
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, w = math.max(0.8, s / 70);
    // A large circle, a smaller one riding on it, and the curve their pen leaves behind.
    const r1 = 0.24, r2 = 0.12, f2 = 4;
    final centre = Offset(0.42, 0.56) * s;
    Offset joint(double t) =>
        centre +
        Offset(math.cos(2 * math.pi * t), math.sin(2 * math.pi * t)) * (r1 * s);
    Offset pen(double t) =>
        joint(t) +
        Offset(math.cos(2 * math.pi * f2 * t), math.sin(2 * math.pi * f2 * t)) *
            (r2 * s);
    const now = 0.915;
    final trail = Path();
    for (var i = 0; i <= 90; i++) {
      final p = pen(now - 0.62 * (1 - i / 90));
      i == 0 ? trail.moveTo(p.dx, p.dy) : trail.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(trail, _stroke(kAccent, 1.4 * w));
    canvas.drawCircle(centre, r1 * s, _stroke(_line(ink), w));
    canvas.drawCircle(joint(now), r2 * s, _stroke(_line(ink), w));
    canvas.drawPath(
      Path()..addPolygon([centre, joint(now), pen(now)], false),
      _stroke(kArm, 1.5 * w),
    );
    canvas.drawCircle(pen(now), 2.6 * w, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(covariant _DrawGlyph old) => old.ink != ink;
}

/// Two axes and two groups of points.
class _MeasureGlyph extends CustomPainter {
  _MeasureGlyph(this.ink);
  final Color ink;

  static const _a = [
    (0.24, 0.40),
    (0.33, 0.27),
    (0.38, 0.45),
    (0.22, 0.58),
    (0.36, 0.60),
  ];
  static const _b = [
    (0.64, 0.36),
    (0.74, 0.50),
    (0.62, 0.62),
    (0.78, 0.70),
    (0.70, 0.24),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width, w = math.max(1.0, s / 48);
    final axis = _stroke(_line(ink), w);
    canvas.drawLine(Offset(0.5 * s, 0.10 * s), Offset(0.5 * s, 0.90 * s), axis);
    canvas.drawLine(Offset(0.10 * s, 0.5 * s), Offset(0.90 * s, 0.5 * s), axis);
    for (final (x, y) in _a) {
      canvas.drawCircle(Offset(x, y) * s, 1.9 * w, Paint()..color = kAccent);
    }
    for (final (x, y) in _b) {
      canvas.drawCircle(Offset(x, y) * s, 1.9 * w, Paint()..color = kArm);
    }
  }

  @override
  bool shouldRepaint(covariant _MeasureGlyph old) => old.ink != ink;
}
