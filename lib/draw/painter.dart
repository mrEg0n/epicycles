// The drawing stage: the image outline in the background, the chains of circles and arms, the
// traced curve and the two signals over time.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/fourier_core.dart';
import '../shared/theme.dart';
import 'engine.dart';

export '../shared/theme.dart' show kInk, kAccent, kRe, kIm, kCurve, kArm;

// The counters are overlaid at the top of the sheet, in a band of height [kCounters]. The equation
// is overlaid at the bottom, centred: [kFormulaSum] is the height of its summation and
// [kFormulaLine] that of each line of values. The figure is laid out between the two.
const kCounters = 34.0;
const kFormulaSum = 42.0;
const kFormulaLine = 17.0;
const kFormulaBottom = 8.0;

// Two-chain layout: distance of the chains from the edge of the sheet, and the share of each
// chain's reach towards the figure that is allowed to overlap the figure area. Overlapping leaves
// more room for the figure; the chains still never leave the sheet.
const _bandEdge = 8.0;
const _bandOverlap = 0.85;

/// Where things go on the sheet for one frame.
class _Layout {
  const _Layout({
    required this.left,
    required this.top,
    required this.aw,
    required this.ah,
    required this.sc,
    required this.cx,
    required this.cy,
    required this.xs0,
    required this.xs1,
    required this.ys0,
    required this.ys1,
  });

  /// Top-left corner and size of the area the figure is fitted into.
  final double left, top, aw, ah;

  /// Screen points per path unit, and the screen position of the path origin.
  final double sc, cx, cy;

  /// Time extent of the signal strip on the right ([xs0]..[xs1], time runs rightwards) and of the
  /// one at the bottom ([ys0]..[ys1], time runs downwards).
  final double xs0, xs1, ys0, ys1;
}

class EpiPainter extends CustomPainter {
  EpiPainter(this.e) : super(repaint: Listenable.merge([e, e.clock]));
  final Engine e;

  static Paint _stroke(Color c, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = c;

  // Shared paints. Those whose colour depends on the frame have it set right before each use.
  static final _circle = _stroke(const Color(0x26FFFFFF), 0.9);
  // Heavier than the circles: the arms are the line of the chain.
  static final _arm = _stroke(const Color(0xC7FFFFFF), 1.2);
  static final _newArm = _stroke(kAccent, 1.4);
  static final _newCircle = _stroke(const Color(0xB38FA8FF), 0.9);
  static final _flash = _stroke(kAccent, 4)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
  static final _finish = _stroke(kCurve, 12)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
  static final _ghost = _stroke(const Color(0x80FFFFFF), 1.0);
  // Thin and blue like the previous-turn signals in the strips, so it does not blend with the
  // circles and the image outline, which are white.
  static final _prev = _stroke(kCurve.withValues(alpha: 0.45), 0.8);
  static final _link = _stroke(const Color(0x38FFFFFF), 0.7);
  static final _glow = _stroke(kCurve.withValues(alpha: 0.45), 5)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
  static final _curve = _stroke(kCurve, 1.6);
  static final _axis = _stroke(const Color(0x38FFFFFF), 0.7);
  // Thinner than the curve (1.6): the signals are components and must not compete with the figure.
  static final _signal = _stroke(const Color(0xE6F2F3F5), 0.8);
  static final _signalDim = _stroke(const Color(0x47FFFFFF), 0.6);
  static final Map<String, TextPainter> _labels = {};

  // Size of the sheet in the frame being painted.
  Size _size = Size.zero;

  // The background outline only changes with the analysis or the layout, so its path is cached.
  static Analysis? _gFor;
  static double _gSc = 0, _gCx = 0, _gCy = 0;
  static Path _gPath = Path();

  Path _ghostPath(Analysis an, double cx, double cy, double sc) {
    if (identical(_gFor, an) && _gSc == sc && _gCx == cx && _gCy == cy) {
      return _gPath;
    }
    final path = Path();
    for (final g in an.ghost) {
      path.moveTo(cx + g[0] * sc, cy + g[1] * sc);
      for (var i = 2; i < g.length; i += 2) {
        path.lineTo(cx + g[i] * sc, cy + g[i + 1] * sc);
      }
      path.close();
    }
    _gFor = an;
    _gSc = sc;
    _gCx = cx;
    _gCy = cy;
    return _gPath = path;
  }

  static double _smooth(double x) {
    final v = x.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  /// Intensity of a glow along its life [p] (0 = just lit, 1 = gone): it rises smoothly over the
  /// first [rise] of it, then fades.
  static double _pulse(double p, double rise) =>
      p < rise ? _smooth(p / rise) : 1 - _smooth((p - rise) / (1 - rise));

  /// Draws a chain starting at (ox, oy) and returns its tip.
  /// With [rot] every arm is turned by 90°, so that the vertical component of the tip follows the
  /// signal. Arms are yellow and circles white from the moment they enter, so neither changes
  /// colour afterwards; with [tint] (two-chain mode) the circles take that colour instead.
  Offset _chain(
    Canvas c,
    Chain ch,
    double ox,
    double oy,
    double sc,
    bool rot, {
    Color? tint,
  }) {
    final circHi = tint ?? kInk;
    final ang = 2 * math.pi * e.t;
    final count = math.min(e.nFull, ch.n);
    final newFrom = math.min(e.newFrom, count);
    var x = ox, y = oy;
    var drawn = 0;
    final arms = Path()..moveTo(x, y);
    final fresh = Path();
    // Arms that have just entered fade in, with a halo that rises, widens and fades.
    final p = 1 - e.flash;
    final env = e.flash > 0 ? _pulse(p, 0.25) : 0.0;
    final fadeIn = e.flash > 0 ? _smooth(p / 0.25) : 1.0;
    final glow = _flash
      ..color = circHi.withValues(alpha: 0.85 * env)
      ..strokeWidth = 2.5 + 6 * p
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 7 * p);
    for (var i = 0; i < count; i++) {
      final th = ang * ch.f[i], co = math.cos(th), si = math.sin(th);
      var vx = (ch.re[i] * co - ch.im[i] * si) * sc,
          vy = (ch.re[i] * si + ch.im[i] * co) * sc;
      if (rot) {
        final q = vx;
        vx = -vy;
        vy = q;
      }
      final r = ch.r[i] * sc;
      final isNew = i >= newFrom;
      if (r > 0.35 && drawn < 700) {
        if (e.showCircles) {
          if (isNew) {
            if (env > 0) c.drawCircle(Offset(x, y), r, glow);
            c.drawCircle(
              Offset(x, y),
              r,
              _newCircle..color = circHi.withValues(alpha: 0.7 * fadeIn),
            );
          } else {
            // Large circles stay readable, small ones fade out.
            final ca = 0.13 + 0.17 * math.exp(-i / 14);
            _circle.color =
                tint?.withValues(alpha: 1.5 * ca) ??
                Color.fromRGBO(255, 255, 255, ca);
            c.drawCircle(Offset(x, y), r, _circle);
          }
        }
        drawn++;
      }
      if (isNew) {
        fresh.moveTo(x, y);
        fresh.lineTo(x + vx, y + vy);
        arms.moveTo(x + vx, y + vy);
      } else {
        arms.lineTo(x + vx, y + vy);
      }
      x += vx;
      y += vy;
    }
    c.drawPath(arms, _arm..color = kArm.withValues(alpha: 0.9));
    if (env > 0) {
      c.drawPath(fresh, glow..color = kArm.withValues(alpha: 0.85 * env));
    }
    c.drawPath(fresh, _newArm..color = kArm.withValues(alpha: fadeIn));
    return Offset(x, y);
  }

  static final _reaches = Expando<List<double>>();

  /// How far the circles of [ch] reach across its band over a full turn, in path units: towards
  /// negative and towards positive values of the component the chain does not draw. Computed
  /// once per chain, with every arm in, so the layout does not move while the figure is built.
  static List<double> _reach(Chain ch) {
    final known = _reaches[ch];
    if (known != null) return known;
    const steps = 720;
    var neg = 0.0, pos = 0.0;
    for (var s = 0; s < steps; s++) {
      final ang = 2 * math.pi * s / steps;
      var y = 0.0;
      for (var i = 0; i < ch.n; i++) {
        final r = ch.r[i];
        neg = math.max(neg, r - y);
        pos = math.max(pos, r + y);
        final th = ang * ch.f[i];
        y += ch.re[i] * math.sin(th) + ch.im[i] * math.cos(th);
      }
    }
    return _reaches[ch] = [neg, pos];
  }

  void _dashed(Canvas c, Offset a, Offset b, Color color) {
    final d = b - a, len = d.distance;
    if (len < 1) return;
    final u = d / len;
    _link.color = color.withValues(alpha: 0.5);
    for (var s = 0.0; s < len; s += 7) {
      c.drawLine(a + u * s, a + u * math.min(len, s + 2), _link);
    }
  }

  /// Polyline through the first [upTo] samples, skipping those where the pen is up. If it covers
  /// the whole path and has no jumps, it is closed.
  Path _polyline(
    Uint8List pen,
    int m,
    int upTo,
    double Function(int) px,
    double Function(int) py,
  ) {
    final path = Path();
    var up = true, jumps = false;
    for (var j = 0; j < upTo; j++) {
      if (pen[j] == 0) {
        up = true;
        jumps = true;
        continue;
      }
      if (up) {
        path.moveTo(px(j), py(j));
        up = false;
      } else {
        path.lineTo(px(j), py(j));
      }
    }
    if (!jumps && upTo >= m) path.close();
    return path;
  }

  /// Small label on the sheet. [ax], [ay]: -1 = [at] is the left/top edge of the text, 0 = its
  /// centre, 1 = its right/bottom edge.
  void _text(
    Canvas c,
    String s,
    Offset at, {
    double ax = 0,
    double ay = 0,
    required Color color,
  }) {
    final tp = _labels.putIfAbsent(
      '$s ${color.toARGB32()}',
      () => TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: 'Menlo',
            fontFamilyFallback: const ['monospace'],
            fontSize: 9.5,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    tp.paint(c, at - Offset(tp.width * (ax + 1) / 2, tp.height * (ay + 1) / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final an = e.a;
    if (an == null || e.curX.length != an.m) return;
    final p = an.path, m = an.m;
    final two = !e.one;
    // When the settings panel covers the bottom of the sheet, the drawing shrinks into the visible
    // part.
    final vh =
        size.height * (1 - e.cover) -
        (kFormulaSum + kFormulaLine * (two ? 2 : 1) + kFormulaBottom + 4);
    // The two signals over time take a strip on the right (imaginary part, or y) and one at the
    // bottom (real part, or x). With two chains they are exactly what each chain produces.
    final signals = e.showSignals;
    final sw = signals ? size.width * 0.24 : 0.0,
        sh = signals ? vh * 0.17 : 0.0;
    // The framing follows the background (every contour), not just the path being drawn.
    final gb = an.gbox;
    final gw = math.max(1.0, gb[2] - gb[0]), gh = math.max(1.0, gb[3] - gb[1]);
    // Share of its area the figure takes. With two chains the bands already keep it clear of the
    // edges, so it can take more.
    final fill = two ? 0.94 : (signals ? 0.84 : 0.8);
    // A band at the top is kept free for the counters, so that the vertical axis and its label do
    // not touch them.
    const header = kCounters;
    double left, top, sc;
    _size = size;
    if (two) {
      // With two chains: a band at the top (x chain) and one on the left (y chain). Each holds
      // the whole reach of its chain away from the figure and part of the reach towards it; the
      // rest overlaps the figure area. The band widths depend on the scale and the scale on the
      // room left by the bands, so the scale is solved from both constraints at once.
      // The y chain is drawn turned by 90°, which maps the positive side of its reach to the left.
      final rx = _reach(an.cx), ry = _reach(an.cy);
      const keep = 1 - _bandOverlap;
      final dx = rx[0] + rx[1] * keep, dy = ry[1] + ry[0] * keep;
      sc = math.max(
        0.0,
        math.min(
          (size.width - sw - _bandEdge) / (gw / fill + dy),
          (vh - sh - header) / (gh / fill + dx),
        ),
      );
      left = _bandEdge + dy * sc;
      top = header + dx * sc;
    } else {
      left = 0.0;
      top = header;
      sc = fill * math.min((size.width - sw) / gw, (vh - top - sh) / gh);
    }
    var aw = size.width - left - sw, ah = vh - top - sh;
    var cx = left + aw / 2 - (gb[0] + gb[2]) / 2 * sc;
    var cy = top + ah / 2 - (gb[1] + gb[3]) / 2 * sc;
    var xs0 = size.width - sw + 12, xs1 = size.width - 10;
    var ys0 = vh - sh + 12, ys1 = vh - 10;

    // Zoom: the whole sheet is seen through a camera centred on the pen (plus the offset set by
    // dragging), so the view follows the pen as it moves. Only positions and lengths are scaled,
    // by transforming the layout; line widths and labels keep their size. Between zoom 1 and 2
    // the pen slides from its own place to the centre of the sheet, so zooming in is continuous.
    final z = e.zoom;
    if (z > 1) {
      // Pen position on the unzoomed sheet, interpolated between samples to move smoothly.
      final u = e.t * m,
          j0 = u.floor() % m,
          j1 = (j0 + 1) % m,
          fr = u - u.floor();
      final fx =
          cx + (e.curX[j0] + (e.curX[j1] - e.curX[j0]) * fr) * sc + e.panX;
      final fy =
          cy + (e.curY[j0] + (e.curY[j1] - e.curY[j0]) * fr) * sc + e.panY;
      final s = math.min(1.0, z - 1);
      final ax = fx + (size.width / 2 - fx) * s, ay = fy + (vh / 2 - fy) * s;
      double mx(double x) => (x - fx) * z + ax;
      double my(double y) => (y - fy) * z + ay;
      left = mx(left);
      top = my(top);
      cx = mx(cx);
      cy = my(cy);
      xs0 = mx(xs0);
      xs1 = mx(xs1);
      ys0 = my(ys0);
      ys1 = my(ys1);
      aw *= z;
      ah *= z;
      sc *= z;
    }
    final l = _Layout(
      left: left,
      top: top,
      aw: aw,
      ah: ah,
      sc: sc,
      cx: cx,
      cy: cy,
      xs0: xs0,
      xs1: xs1,
      ys0: ys0,
      ys1: ys1,
    );

    _paintBackground(canvas, an, l);
    if (e.showAxes) _paintAxes(canvas, an, l, two);

    // The curve of the previous turn stays, dimmed, while the pen traces the new one.
    if (e.building && e.hasPrev) {
      canvas.drawPath(
        _polyline(
          p.pen,
          m,
          m,
          (j) => cx + e.prevX[j] * sc,
          (j) => cy + e.prevY[j] * sc,
        ),
        _prev,
      );
    }

    // While building, the curve is traced up to where the pen has got in this turn; afterwards it
    // is complete.
    final upTo = e.building ? math.min(m, (e.t * m).floor() + 1) : m;
    final curve = _polyline(
      p.pen,
      m,
      upTo,
      (j) => cx + e.curX[j] * sc,
      (j) => cy + e.curY[j] * sc,
    );
    canvas.drawPath(curve, _glow);
    canvas.drawPath(curve, _curve);
    // Figure completed: a wave of light runs over the whole outline. Width and blur are fixed and
    // only the intensity changes.
    if (e.doneGlow > 0) {
      canvas.drawPath(
        curve,
        _finish
          ..color = kCurve.withValues(alpha: 0.9 * _pulse(1 - e.doneGlow, 0.2)),
      );
    }

    if (signals) _paintSignals(canvas, an, l, two, upTo);

    Offset pen;
    if (two) {
      // The origin of each chain sits where its far reach just touches the edge of its band.
      const keep = 1 - _bandOverlap;
      final topY = top - _reach(an.cx)[1] * keep * sc;
      final leftX = left - _reach(an.cy)[0] * keep * sc;
      final a = _chain(
        canvas,
        an.cx,
        cx + an.dc[2] * sc,
        topY,
        sc,
        false,
        tint: kRe,
      );
      final b = _chain(
        canvas,
        an.cy,
        leftX,
        cy + an.dc[3] * sc,
        sc,
        true,
        tint: kIm,
      );
      pen = Offset(a.dx, b.dy);
      _dashed(canvas, a, pen, kRe);
      _dashed(canvas, b, pen, kIm);
    } else {
      pen = _chain(
        canvas,
        an.one,
        cx + an.dc[0] * sc,
        cy + an.dc[1] * sc,
        sc,
        false,
      );
    }

    // Projections of the pen: onto the two signals, at the current time, and onto the axes.
    // The real value is read horizontally (cyan), the imaginary one vertically (violet).
    final markRe = Paint()..color = kRe, markIm = Paint()..color = kIm;
    if (signals) {
      final nowIm = Offset(l.xs0 + (l.xs1 - l.xs0) * e.t, pen.dy),
          nowRe = Offset(pen.dx, l.ys0 + (l.ys1 - l.ys0) * e.t);
      _dashed(canvas, pen, nowIm, kIm);
      _dashed(canvas, pen, nowRe, kRe);
      canvas.drawCircle(nowIm, 2.6, markIm);
      canvas.drawCircle(nowRe, 2.6, markRe);
    }
    if (e.showAxes) {
      final onX = Offset(pen.dx, cy), onY = Offset(cx, pen.dy);
      if (!signals && !two) {
        _dashed(canvas, pen, onX, kRe);
        _dashed(canvas, pen, onY, kIm);
      }
      canvas.drawCircle(onX, 2.2, markRe);
      canvas.drawCircle(onY, 2.2, markIm);
    }

    canvas.drawCircle(pen, 9, Paint()..color = const Color(0x338FA8FF));
    canvas.drawCircle(pen, 2.8, Paint()..color = kInk);

    if (z > 1) {
      _text(
        canvas,
        '×${z.toStringAsFixed(z < 10 ? 1 : 0)} · double tap to reset',
        Offset(size.width - 14, kCounters - 2),
        ax: 1,
        ay: -1,
        color: kAccent,
      );
    }
  }

  /// Under the drawing: the chosen image, translucent, or just its outline.
  void _paintBackground(Canvas canvas, Analysis an, _Layout l) {
    final p = an.path;
    final ph = e.photo, g = e.src;
    if (e.bgImage && ph != null && g != null) {
      canvas.save();
      canvas.translate(l.cx, l.cy);
      canvas.rotate(p.rot);
      canvas.drawImageRect(
        ph,
        Rect.fromLTWH(0, 0, ph.width.toDouble(), ph.height.toDouble()),
        Rect.fromLTWH(-p.ox * l.sc, -p.oy * l.sc, g.w * l.sc, g.h * l.sc),
        Paint()
          ..color = const Color(0xA6FFFFFF)
          ..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawPath(_ghostPath(an, l.cx, l.cy, l.sc), _ghost);
    }
  }

  /// Axes of the complex plane, with the origin and unit of the equation: the unit is the radius
  /// of the first, largest circle. The horizontal axis carries the real values (or x), the
  /// vertical one the imaginary values (or y). They end at the edge of the figure area: the signal
  /// strips have their own, separate time lines.
  void _paintAxes(Canvas canvas, Analysis an, _Layout l, bool two) {
    final cx = l.cx, cy = l.cy;
    final unit = an.one.r[0] * l.sc;
    final x0 = l.left + 6, y0 = l.top + 4;
    final xEnd = l.left + l.aw - 6, yEnd = l.top + l.ah - 4;
    final reAxis = kRe.withValues(alpha: 0.6),
        imAxis = kIm.withValues(alpha: 0.6);
    canvas.drawLine(Offset(x0, cy), Offset(xEnd, cy), _axis..color = reAxis);
    canvas.drawLine(Offset(cx, y0), Offset(cx, yEnd), _axis..color = imAxis);
    // Evenly spaced ticks along the whole axis. The step is half a unit if there is room,
    // otherwise 1, 2, 5… so that the numbers do not overlap when the figure is much larger than
    // the first circle. When zoomed in, finer steps become available.
    final steps = e.zoom > 1
        ? const [
            0.01,
            0.02,
            0.05,
            0.1,
            0.2,
            0.5,
            1.0,
            2.0,
            5.0,
            10.0,
            20.0,
            50.0,
          ]
        : const [0.5, 1.0, 2.0, 5.0, 10.0, 20.0, 50.0];
    var step = steps.first;
    for (final c in steps) {
      step = c;
      if (c * unit >= 34) break;
    }
    final digits = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2);
    String tick(double v) {
      final a = v.abs();
      final whole = a == a.roundToDouble();
      return '${v < 0 ? '−' : ''}${a.toStringAsFixed(whole ? 0 : digits)}';
    }

    // Only the ticks that fall on the sheet are drawn.
    final gap = step * unit;
    final w = _size.width, h = _size.height;
    for (var i = ((0 - cx) / gap).floor(); i <= ((w - cx) / gap).ceil(); i++) {
      final v = i * step, x = cx + v * unit;
      if (i == 0 || x <= x0 + 8 || x >= xEnd - 14) continue;
      canvas.drawLine(
        Offset(x, cy - 3),
        Offset(x, cy + 3),
        _axis..color = reAxis,
      );
      _text(canvas, tick(v), Offset(x, cy + 5), ay: -1, color: kRe);
    }
    for (var i = ((cy - h) / gap).floor(); i <= (cy / gap).ceil(); i++) {
      final v = i * step, y = cy - v * unit;
      if (i == 0 || y <= y0 + 12 || y >= yEnd - 6) continue;
      canvas.drawLine(
        Offset(cx - 3, y),
        Offset(cx + 3, y),
        _axis..color = imAxis,
      );
      _text(canvas, tick(v), Offset(cx - 6, y), ax: 1, color: kIm);
    }
    _text(
      canvas,
      two ? 'x' : 'Re',
      Offset(xEnd, cy - 4),
      ax: 1,
      ay: 1,
      color: kRe,
    );
    _text(
      canvas,
      two ? 'y' : 'Im',
      Offset(cx + 5, y0),
      ax: -1,
      ay: -1,
      color: kIm,
    );
  }

  /// The two signals that generate the figure, over one full period: on the right the imaginary
  /// part (time runs rightwards, same vertical scale as the figure), at the bottom the real part
  /// (time runs downwards, same horizontal scale). They are traced up to sample [upTo].
  void _paintSignals(
    Canvas canvas,
    Analysis an,
    _Layout l,
    bool two,
    int upTo,
  ) {
    final p = an.path, m = an.m;
    final cx = l.cx, cy = l.cy, sc = l.sc;
    final xs0 = l.xs0, xs1 = l.xs1, ys0 = l.ys0, ys1 = l.ys1;
    final step = math.max(1, m ~/ 360);
    Path trace(int a, int b, double Function(int) px, double Function(int) py) {
      final path = Path();
      var up = true;
      for (var j = a; j < b; j += step) {
        if (p.pen[j] == 0) {
          up = true;
          continue;
        }
        if (up) {
          path.moveTo(px(j), py(j));
          up = false;
        } else {
          path.lineTo(px(j), py(j));
        }
      }
      return path;
    }

    // Time line of each strip (the zero level of the signal), neutral, with an arrowhead giving
    // the direction of time.
    final timeAxis = _axis..color = const Color(0x38FFFFFF);
    canvas.drawLine(Offset(xs0 - 4, cy), Offset(xs1 + 4, cy), timeAxis);
    canvas.drawLine(Offset(xs1 + 4, cy), Offset(xs1, cy - 3), timeAxis);
    canvas.drawLine(Offset(xs1 + 4, cy), Offset(xs1, cy + 3), timeAxis);
    canvas.drawLine(Offset(cx, ys0 - 4), Offset(cx, ys1 + 4), timeAxis);
    canvas.drawLine(Offset(cx, ys1 + 4), Offset(cx - 3, ys1), timeAxis);
    canvas.drawLine(Offset(cx, ys1 + 4), Offset(cx + 3, ys1), timeAxis);

    double tx(int j) => xs0 + (xs1 - xs0) * j / m;
    double ty(int j) => ys0 + (ys1 - ys0) * j / m;
    double fx(int j) => cx + e.curX[j] * sc;
    double fy(int j) => cy + e.curY[j] * sc;
    // As in the figure: while building, the signal of the previous turn stays underneath, dimmed,
    // and the new one is traced over it.
    if (e.building && e.hasPrev) {
      double pfx(int j) => cx + e.prevX[j] * sc;
      double pfy(int j) => cy + e.prevY[j] * sc;
      canvas.drawPath(
        trace(0, m, tx, pfy),
        _signalDim..color = kIm.withValues(alpha: 0.35),
      );
      canvas.drawPath(
        trace(0, m, pfx, ty),
        _signalDim..color = kRe.withValues(alpha: 0.35),
      );
    }
    canvas.drawPath(trace(0, upTo, tx, fy), _signal..color = kIm);
    canvas.drawPath(trace(0, upTo, fx, ty), _signal..color = kRe);
    // Each label sits next to its strip and clear of the signal: above the strip on the right, and
    // beside the one at the bottom, in the corner that is always empty.
    _text(
      canvas,
      two ? 'y(t)' : 'Im z(t)',
      Offset(xs0, l.top + 12),
      ax: -1,
      ay: -1,
      color: kIm,
    );
    _text(
      canvas,
      two ? 'x(t)' : 'Re z(t)',
      Offset(xs0, (ys0 + ys1) / 2),
      ax: -1,
      color: kRe,
    );
  }

  @override
  bool shouldRepaint(covariant EpiPainter oldDelegate) => true;
}
