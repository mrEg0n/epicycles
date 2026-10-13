// The animated mark of the app: three chained circles trace a four-pointed rosette.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class EpicycleLogo extends StatefulWidget {
  const EpicycleLogo({super.key, this.size = 230});

  /// Side of the square the mark is drawn in.
  final double size;

  @override
  State<EpicycleLogo> createState() => _EpicycleLogoState();
}

class _EpicycleLogoState extends State<EpicycleLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _turn.value = 0.8;
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(painter: _LogoPainter(_turn)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.turn) : super(repaint: turn);
  final Animation<double> turn;

  // (radius as a fraction of the side, frequency, phase)
  static const _terms = [(0.30, 1, -0.5), (0.146, -3, 0.5), (0.061, 5, -0.5)];

  List<Offset> _chain(double t, Size s) {
    var p = s.center(Offset.zero);
    final out = [p];
    for (final (r, f, ph) in _terms) {
      final a = 2 * math.pi * f * t + ph;
      p += Offset(math.cos(a), math.sin(a)) * (r * s.width);
      out.add(p);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = turn.value;
    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = c;
    Path curve(double upTo) {
      final path = Path();
      const n = 360;
      for (var i = 0; i <= (n * upTo).round(); i++) {
        final p = _chain(i / n, size).last;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      return path;
    }

    canvas.drawPath(curve(1), stroke(const Color(0x24FFFFFF), 1));
    final done = curve(t);
    canvas.drawPath(
      done,
      stroke(const Color(0x668FA8FF), 7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(done, stroke(kInk, 2));
    final pts = _chain(t, size);
    for (var i = 0; i < _terms.length; i++) {
      canvas.drawCircle(
        pts[i],
        _terms[i].$1 * size.width,
        stroke(const Color(0x33FFFFFF), 0.7),
      );
    }
    canvas.drawPath(
      Path()..addPolygon(pts, false),
      stroke(const Color(0x99FFFFFF), 1),
    );
    canvas.drawCircle(pts.last, 3.2, Paint()..color = kAccent);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => false;
}
