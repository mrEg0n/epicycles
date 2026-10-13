// What a collection shows about its specimens: the outlines overlaid with the mean shape of each
// group, and the map of shapes on the first two principal components.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/efd.dart';
import '../core/pca.dart';
import '../shared/theme.dart';
import 'specimen.dart';

/// Harmonics used by the views.
const kViewHarmonics = 20;

const _groupColours = [
  kAccent,
  kArm,
  Color(0xFF7FE0A8),
  Color(0xFFFF9D8A),
  kRe,
  kIm,
  Color(0xFFE6E08A),
  Color(0xFFB0B4BD),
];

/// The groups of [specimens] in order of first appearance, each with its colour.
Map<String, Color> groupColours(List<Specimen> specimens) {
  final out = <String, Color>{};
  for (final s in specimens) {
    out.putIfAbsent(
      s.group,
      () => _groupColours[out.length % _groupColours.length],
    );
  }
  return out;
}

/// The descriptors of a specimen as one vector: a, b, c, d of the first [kViewHarmonics]
/// harmonics, normalised for position, size and starting point, in the operator's orientation.
Float64List shapeVector(Specimen s) {
  final e = normaliseEfd(s.efd, keepOrientation: true).efd;
  final n = math.min(kViewHarmonics, e.n);
  final v = Float64List(4 * n);
  for (var i = 0; i < n; i++) {
    v[i] = e.a[i];
    v[n + i] = e.b[i];
    v[2 * n + i] = e.c[i];
    v[3 * n + i] = e.d[i];
  }
  return v;
}

/// The outline described by a shape vector, as x0, y0, x1, y1…
Float64List vectorOutline(Float64List v, {int points = 200}) {
  final n = v.length ~/ 4;
  return efdOutline(
    Efd(
      Float64List.sublistView(v, 0, n),
      Float64List.sublistView(v, n, 2 * n),
      Float64List.sublistView(v, 2 * n, 3 * n),
      Float64List.sublistView(v, 3 * n, 4 * n),
    ),
    n,
    points,
  );
}

Float64List _mean(Iterable<Float64List> vs) {
  final list = vs.toList();
  final m = Float64List(list.first.length);
  for (final v in list) {
    for (var j = 0; j < m.length; j++) {
      m[j] += v[j] / list.length;
    }
  }
  return m;
}

Path _path(Float64List p, double cx, double cy, double sc) {
  final out = Path()..moveTo(cx + p[0] * sc, cy - p[1] * sc);
  for (var i = 2; i < p.length; i += 2) {
    out.lineTo(cx + p[i] * sc, cy - p[i + 1] * sc);
  }
  return out..close();
}

Widget _legend(Map<String, Color> colours, List<Specimen> specimens) {
  return Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final g in colours.entries)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: g.value, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${g.key.isEmpty ? 'no group' : g.key} (${specimens.where((s) => s.group == g.key).length})',
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ),
    ],
  );
}

Widget _stage(Widget child) => Container(
  margin: const EdgeInsets.symmetric(horizontal: 12),
  clipBehavior: Clip.antiAlias,
  decoration: BoxDecoration(
    color: kStage,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: kLine),
  ),
  child: child,
);

Widget _note(String text) => Center(
  child: Padding(
    padding: const EdgeInsets.all(36),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: kMuted, height: 1.5),
    ),
  ),
);

/// Every outline of the collection, at the same size and centred, coloured by group, with the
/// mean shape of each group drawn heavier.
class OverlayView extends StatelessWidget {
  const OverlayView({super.key, required this.specimens});
  final List<Specimen> specimens;

  @override
  Widget build(BuildContext context) {
    if (specimens.isEmpty) return _note('Add specimens to see them overlaid.');
    final colours = groupColours(specimens);
    final vectors = [for (final s in specimens) shapeVector(s)];
    final outlines = [for (final v in vectors) vectorOutline(v)];
    final means = <String, Float64List>{
      for (final g in colours.keys)
        g: vectorOutline(
          _mean([
            for (var i = 0; i < specimens.length; i++)
              if (specimens[i].group == g) vectors[i],
          ]),
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _stage(
            CustomPaint(
              size: Size.infinite,
              painter: _OverlayPainter(specimens, outlines, means, colours),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: _legend(colours, specimens),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
          child: Text(
            'thin: specimens  ·  thick: group means\n'
            'normalised for size and position  ·  $kViewHarmonics harmonics',
            style: kMono.copyWith(fontSize: 10.5, color: kFaint, height: 1.6),
          ),
        ),
      ],
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.specimens, this.outlines, this.means, this.colours);
  final List<Specimen> specimens;
  final List<Float64List> outlines;
  final Map<String, Float64List> means;
  final Map<String, Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    var x0 = double.infinity,
        x1 = -double.infinity,
        y0 = double.infinity,
        y1 = -double.infinity;
    for (final o in outlines) {
      for (var i = 0; i < o.length; i += 2) {
        x0 = math.min(x0, o[i]);
        x1 = math.max(x1, o[i]);
        y0 = math.min(y0, o[i + 1]);
        y1 = math.max(y1, o[i + 1]);
      }
    }
    final sc =
        0.86 *
        math.min(
          size.width / math.max(1e-9, x1 - x0),
          size.height / math.max(1e-9, y1 - y0),
        );
    final cx = size.width / 2 - (x0 + x1) / 2 * sc,
        cy = size.height / 2 + (y0 + y1) / 2 * sc;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < outlines.length; i++) {
      thin.color = colours[specimens[i].group]!.withValues(alpha: 0.38);
      canvas.drawPath(_path(outlines[i], cx, cy, sc), thin);
    }
    final thick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    for (final g in means.entries) {
      thick.color = colours[g.key]!;
      canvas.drawPath(_path(g.value, cx, cy, sc), thick);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      !identical(old.outlines, outlines);
}

/// Statistics of the shapes in a collection, as a page to scroll: the map of the specimens on
/// the first two principal components, the share of variance of each component, and what each of
/// the first three changes in the shape.
class StatisticsView extends StatelessWidget {
  const StatisticsView({super.key, required this.specimens});
  final List<Specimen> specimens;

  @override
  Widget build(BuildContext context) {
    if (specimens.length < 3) {
      return _note('Statistics need at least three specimens.');
    }
    final colours = groupColours(specimens);
    final vectors = [for (final s in specimens) shapeVector(s)];
    final r = pca(vectors, components: 8);
    if (r.axes.isEmpty) return _note('These specimens have the same shape.');
    double share(int i) => 100 * r.variance[i] / r.totalVariance;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Text(
        t,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
    Widget caption(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
      child: Text(
        t,
        style: kMono.copyWith(fontSize: 10.5, color: kFaint, height: 1.6),
      ),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        title('Outline variability'),
        SizedBox(
          height: 320,
          child: _stage(
            CustomPaint(
              size: Size.infinite,
              painter: _VariationPainter([
                for (final v in vectors) vectorOutline(v),
              ], vectorOutline(r.mean)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: Row(
            children: [
              Text('low', style: kMono.copyWith(fontSize: 10.5, color: kMuted)),
              const SizedBox(width: 8),
              Container(
                width: 96,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(colors: _heat),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'high',
                style: kMono.copyWith(fontSize: 10.5, color: kMuted),
              ),
            ],
          ),
        ),
        caption(
          'mean shape  ·  colour and band: RMS deviation of the\n'
          'specimens from the mean at each point of the outline',
        ),
        title('Principal component analysis'),
        SizedBox(
          height: 340,
          child: _stage(
            CustomPaint(
              size: Size.infinite,
              painter: _MapPainter(specimens, r, colours),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          child: _legend(colours, specimens),
        ),
        caption(
          'scores on PC1 and PC2  ·  numbered as in the list\n'
          'outlines at the ends of the axes: mean ± 2 SD',
        ),
        title('Variance'),
        SizedBox(
          height: 150,
          child: _stage(
            CustomPaint(size: Size.infinite, painter: _ScreePainter(r)),
          ),
        ),
        caption(
          'proportion of variance per component\n'
          'n = ${specimens.length}  ·  $kViewHarmonics harmonics  ·  covariance matrix',
        ),
        title('Modes of variation'),
        for (var k = 0; k < math.min(3, r.axes.length); k++) ...[
          SizedBox(
            height: 230,
            child: _stage(
              CustomPaint(size: Size.infinite, painter: _AxisPainter(r, k)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            child: Text.rich(
              TextSpan(
                style: kMono.copyWith(
                  fontSize: 10.5,
                  color: kFaint,
                  height: 1.6,
                ),
                children: [
                  TextSpan(
                    text: 'PC${k + 1}  ·  ${share(k).toStringAsFixed(0)}%   ',
                  ),
                  const TextSpan(
                    text: '−2 SD',
                    style: TextStyle(color: kRe),
                  ),
                  const TextSpan(
                    text: '   mean',
                    style: TextStyle(color: kInk),
                  ),
                  const TextSpan(
                    text: '   +2 SD',
                    style: TextStyle(color: kArm),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// From little to much variation.
const _heat = [kAccent, kArm, Color(0xFFFF6B5E)];

Color _heatColour(double v) => v < 0.5
    ? Color.lerp(_heat[0], _heat[1], v * 2)!
    : Color.lerp(_heat[1], _heat[2], v * 2 - 1)!;

/// The mean outline, coloured and thickened at each point by the spread of the specimens there:
/// the root mean square distance between their outlines and the mean at the same position along
/// the path. Shows which parts of the shape vary and which are constant.
class _VariationPainter extends CustomPainter {
  _VariationPainter(this.outlines, this.mean);
  final List<Float64List> outlines;
  final Float64List mean;

  @override
  void paint(Canvas canvas, Size size) {
    final n = mean.length ~/ 2;
    final spread = Float64List(n);
    var top = 0.0, low = double.infinity;
    for (var j = 0; j < n; j++) {
      var s = 0.0;
      for (final o in outlines) {
        final dx = o[2 * j] - mean[2 * j], dy = o[2 * j + 1] - mean[2 * j + 1];
        s += dx * dx + dy * dy;
      }
      spread[j] = math.sqrt(s / outlines.length);
      top = math.max(top, spread[j]);
      low = math.min(low, spread[j]);
    }
    var x0 = double.infinity,
        x1 = -double.infinity,
        y0 = double.infinity,
        y1 = -double.infinity;
    for (var i = 0; i < mean.length; i += 2) {
      x0 = math.min(x0, mean[i]);
      x1 = math.max(x1, mean[i]);
      y0 = math.min(y0, mean[i + 1]);
      y1 = math.max(y1, mean[i + 1]);
    }
    final sc =
        0.78 *
        math.min(
          size.width / math.max(1e-9, x1 - x0),
          size.height / math.max(1e-9, y1 - y0),
        );
    final cx = size.width / 2 - (x0 + x1) / 2 * sc,
        cy = size.height / 2 + (y0 + y1) / 2 * sc;
    Offset at(int j) =>
        Offset(cx + mean[2 * (j % n)] * sc, cy - mean[2 * (j % n) + 1] * sc);
    // The colour runs from the least to the most variable point of this outline.
    double level(double v) =>
        top > low ? ((v - low) / (top - low)).clamp(0.0, 1.0) : 0.0;
    // Unit normal of the outline at each point, from its two neighbours.
    Offset normal(int j) {
      final d = at(j + 1) - at(j + n - 1);
      final len = d.distance;
      return len > 0 ? Offset(-d.dy, d.dx) / len : Offset.zero;
    }

    // A band as wide as the spread itself, built from one quadrilateral per step so that
    // neighbouring pieces meet edge to edge.
    for (var j = 0; j < n; j++) {
      final k = (j + 1) % n;
      final a = at(j), b = at(k);
      final na = normal(j) * (spread[j] * sc),
          nb = normal(k) * (spread[k] * sc);
      canvas.drawPath(
        Path()..addPolygon([a + na, b + nb, b - nb, a - na], true),
        Paint()
          ..isAntiAlias = false
          ..color = _heatColour(level((spread[j] + spread[k]) / 2))
              .withValues(alpha: 0.3),
      );
    }
    // The mean outline on top.
    for (var j = 0; j < n; j++) {
      canvas.drawLine(
        at(j),
        at(j + 1),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.4
          ..color = _heatColour(level((spread[j] + spread[(j + 1) % n]) / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VariationPainter old) =>
      !identical(old.mean, mean);
}

/// The shape vector found [sd] standard deviations from the mean along component [axis].
Float64List _alongAxis(Pca r, int axis, double sd) {
  final v = Float64List.fromList(r.mean);
  final k = sd * math.sqrt(r.variance[axis]);
  for (var j = 0; j < v.length; j++) {
    v[j] += k * r.axes[axis][j];
  }
  return v;
}

/// Bars with the share of variance of each component.
class _ScreePainter extends CustomPainter {
  _ScreePainter(this.r);
  final Pca r;

  @override
  void paint(Canvas canvas, Size size) {
    final n = r.variance.length;
    const padL = 18.0, padR = 18.0, padT = 22.0, padB = 22.0;
    final w = size.width - padL - padR, h = size.height - padT - padB;
    final top = r.variance[0] / r.totalVariance;
    final slot = w / n;
    for (var i = 0; i < n; i++) {
      final share = r.variance[i] / r.totalVariance;
      final bh = h * share / top;
      final x = padL + slot * i + slot * 0.18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, padT + h - bh, slot * 0.64, bh),
          const Radius.circular(2),
        ),
        Paint()..color = kAccent.withValues(alpha: i < 2 ? 1 : 0.45),
      );
      void text(String s, double y, Color c) {
        final tp = TextPainter(
          text: TextSpan(
            text: s,
            style: kMono.copyWith(fontSize: 9.5, color: c),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + slot * 0.32 - tp.width / 2, y));
      }

      text('${(100 * share).toStringAsFixed(0)}%', padT + h - bh - 14, kMuted);
      text('${i + 1}', padT + h + 5, kFaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScreePainter old) => !identical(old.r, r);
}

/// The mean shape with the shapes two standard deviations either side of it along one component.
class _AxisPainter extends CustomPainter {
  _AxisPainter(this.r, this.axis);
  final Pca r;
  final int axis;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = [
      (vectorOutline(_alongAxis(r, axis, -2)), kRe),
      (vectorOutline(_alongAxis(r, axis, 2)), kArm),
      (vectorOutline(r.mean), kInk),
    ];
    var x0 = double.infinity,
        x1 = -double.infinity,
        y0 = double.infinity,
        y1 = -double.infinity;
    for (final (o, _) in shapes) {
      for (var i = 0; i < o.length; i += 2) {
        x0 = math.min(x0, o[i]);
        x1 = math.max(x1, o[i]);
        y0 = math.min(y0, o[i + 1]);
        y1 = math.max(y1, o[i + 1]);
      }
    }
    final sc =
        0.86 *
        math.min(
          size.width / math.max(1e-9, x1 - x0),
          size.height / math.max(1e-9, y1 - y0),
        );
    final cx = size.width / 2 - (x0 + x1) / 2 * sc,
        cy = size.height / 2 + (y0 + y1) / 2 * sc;
    for (final (o, colour) in shapes) {
      canvas.drawPath(
        _path(o, cx, cy, sc),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AxisPainter old) =>
      !identical(old.r, r) || old.axis != axis;
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.specimens, this.r, this.colours);
  final List<Specimen> specimens;
  final Pca r;
  final Map<String, Color> colours;

  // Room kept at each side for the shapes drawn at the ends of the axes.
  static const _margin = 62.0;

  void _shape(Canvas canvas, Float64List vector, Offset at) {
    final o = vectorOutline(vector, points: 120);
    var ext = 0.0;
    for (final v in o) {
      ext = math.max(ext, v.abs());
    }
    canvas.drawPath(
      _path(o, at.dx, at.dy, 0.42 * _margin / math.max(ext, 1e-9)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round
        ..color = kInk,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final two = r.axes.length > 1;
    final w = size.width - 2 * _margin, h = size.height - 2 * _margin;
    final cx = size.width / 2, cy = size.height / 2;
    // Same scale on both axes, so that distances on the map are distances between shapes.
    var mx = 1e-12, my = 1e-12;
    for (final s in r.scores) {
      mx = math.max(mx, s[0].abs());
      if (two) my = math.max(my, s[1].abs());
    }
    final sc = 0.92 * math.min(w / 2 / mx, h / 2 / my);
    final axis = Paint()
      ..color = const Color(0x38FFFFFF)
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(_margin, cy),
      Offset(size.width - _margin, cy),
      axis,
    );
    canvas.drawLine(
      Offset(cx, _margin),
      Offset(cx, size.height - _margin),
      axis,
    );

    _shape(canvas, _alongAxis(r, 0, -2), Offset(_margin / 2, cy));
    _shape(canvas, _alongAxis(r, 0, 2), Offset(size.width - _margin / 2, cy));
    if (two) {
      _shape(canvas, _alongAxis(r, 1, 2), Offset(cx, _margin / 2));
      _shape(
        canvas,
        _alongAxis(r, 1, -2),
        Offset(cx, size.height - _margin / 2),
      );
    }
    void label(String s, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: kMono.copyWith(fontSize: 9.5, color: kMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    label('PC1', Offset(size.width - _margin - 22, cy - 15));
    if (two) label('PC2', Offset(cx + 5, _margin));

    final dot = Paint();
    for (var i = 0; i < specimens.length; i++) {
      final s = r.scores[i];
      final at = Offset(cx + s[0] * sc, cy - (two ? s[1] : 0) * sc);
      canvas.drawCircle(
        at,
        6,
        dot..color = colours[specimens[i].group]!.withValues(alpha: 0.25),
      );
      canvas.drawCircle(at, 3.4, dot..color = colours[specimens[i].group]!);
      label('${i + 1}', at + const Offset(6, -12));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => !identical(old.r, r);
}
