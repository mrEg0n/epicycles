// Tests of the core on a synthetic image: a black ring and a black rectangle on white.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:epicicli/core/efd.dart';
import 'package:epicicli/core/equation.dart';
import 'package:epicicli/core/fourier_core.dart';
import 'package:epicicli/core/pca.dart';
import 'package:epicicli/core/select.dart';
import 'package:epicicli/draw/engine.dart';
import 'package:epicicli/measure/specimen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const w = 200, h = 160;
  final g = Float32List(w * h)..fillRange(0, w * h, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = math.sqrt((x - 70) * (x - 70) + (y - 80) * (y - 80));
      if (d < 50) g[y * w + x] = 0;
      if (d < 20) g[y * w + x] = 255;
      if ((x - 160).abs() < 15 && (y - 60).abs() < 30) g[y * w + x] = 0;
    }
  }
  final blurred = boxBlur(g, w, h, 1);
  final thr = otsu(blurred);

  test('contours have the expected perimeters', () {
    final cs = marching(blurred, w, h, thr.toDouble())
      ..sort((a, b) => b.len.compareTo(a.len));
    expect(cs.length, 3);
    expect(cs[0].len, closeTo(2 * math.pi * 50, 3)); // outer circle
    expect(cs[2].len, closeTo(2 * math.pi * 20, 3)); // hole
    expect(
      cs[1].len,
      inInclusiveRange(165, 180),
    ); // 30x60 rectangle, corners rounded by the blur
  });

  final an = process(ProcessParams(g, w, h, thr, 1, 1, 14, false))!;
  final m = an.m, p = an.path;

  double errOne(int k) {
    var e = 0.0;
    for (var j = 0; j < m; j += 7) {
      var x = an.dc[0], y = an.dc[1];
      for (var i = 0; i < k; i++) {
        final q = (an.one.f[i] * j) % m;
        x += an.one.re[i] * an.cosT[q] - an.one.im[i] * an.sinT[q];
        y += an.one.re[i] * an.sinT[q] + an.one.im[i] * an.cosT[q];
      }
      e = math.max(
        e,
        math.sqrt(math.pow(x - p.sx[j], 2) + math.pow(y - p.sy[j], 2)),
      );
    }
    return e;
  }

  test('with all circles the reconstruction is exact, in both modes', () {
    expect(errOne(m - 1), lessThan(1e-9));
    var e = 0.0;
    for (var j = 0; j < m; j += 7) {
      var x = an.dc[2], y = an.dc[3];
      for (var i = 0; i < m ~/ 2; i++) {
        var q = (an.cx.f[i] * j) % m;
        x += an.cx.re[i] * an.cosT[q] - an.cx.im[i] * an.sinT[q];
        q = (an.cy.f[i] * j) % m;
        y += an.cy.re[i] * an.cosT[q] - an.cy.im[i] * an.sinT[q];
      }
      e = math.max(
        e,
        math.sqrt(math.pow(x - p.sx[j], 2) + math.pow(y - p.sy[j], 2)),
      );
    }
    expect(e, lessThan(1e-9));
  });

  test('a few circles give an approximation', () {
    expect(errOne(50), inInclusiveRange(0.5, 8));
  });

  test('the two-chain equation reproduces the path, with y pointing up', () {
    final lines = equationLines(an, one: false, k: m ~/ 2);
    final u = 1 / an.one.r[0];
    double eval(EqLine ln, double t) {
      var v = 0.0;
      for (final q in ln.terms) {
        v += q.a * math.cos(2 * math.pi * q.f * t + q.p);
      }
      return v;
    }

    var e = 0.0;
    for (var j = 0; j < m; j += 37) {
      final x = eval(lines[0], j / m), y = eval(lines[1], j / m);
      e = math.max(
        e,
        math.sqrt(math.pow(x - p.sx[j] * u, 2) + math.pow(y + p.sy[j] * u, 2)),
      );
    }
    expect(e, lessThan(1e-9));
    expect(
      equationText(lines).split('\n').where((s) => s.isNotEmpty).length,
      2,
    );
  });

  test('the one-chain equation reproduces the path, with y pointing up', () {
    final ln = equationLines(an, one: true, k: m - 1).single;
    final u = 1 / an.one.r[0];
    var e = 0.0;
    for (var j = 0; j < m; j += 37) {
      var x = 0.0, y = 0.0;
      for (final q in ln.terms) {
        final th = 2 * math.pi * q.f * (j / m) + q.p;
        x += q.a * math.cos(th);
        y += q.a * math.sin(th);
      }
      e = math.max(
        e,
        math.sqrt(math.pow(x - p.sx[j] * u, 2) + math.pow(y + p.sy[j] * u, 2)),
      );
    }
    expect(e, lessThan(1e-9));
  });

  test('the build stages start at one arm, always grow and end at K', () {
    for (final k in [1, 2, 7, 147, 8191]) {
      final st = buildStages(k);
      expect(st.first, 1);
      expect(st.last, k);
      for (var i = 1; i < st.length; i++) {
        expect(st[i], greaterThan(st[i - 1]));
      }
    }
    expect(buildStages(147).length, 147); // one arm per turn
    expect(buildStages(147).take(8).toList(), [1, 2, 3, 4, 5, 6, 7, 8]);
    // blocks: one at a time up to the sixth, then growing groups, still ending at K
    final blocks = buildStages(147, blocks: true);
    expect(blocks.take(8).toList(), [1, 2, 3, 4, 5, 6, 8, 10]);
    expect(blocks.last, 147);
    expect(blocks.length, lessThan(30));
  });

  test(
    'the brush stamps a disc and a cut leaves only the largest component',
    () {
      const n = 60;
      // mask: a tall rectangle
      final mask = Uint8List(n * n);
      for (var y = 5; y < 55; y++) {
        for (var x = 20; x < 40; x++) {
          mask[y * n + x] = 255;
        }
      }
      // a horizontal eraser stroke at two thirds of the height removes a band and splits the mask in two
      final edit = Int8List(n * n);
      for (var x = 10.0; x <= 50; x += 2) {
        stampDisc(edit, n, n, x, 38, 3, -1);
      }
      for (var p = 0; p < n * n; p++) {
        if (edit[p] < 0) mask[p] = 0;
      }
      expect(mask[38 * n + 30], 0); // erased under the brush
      expect(mask[20 * n + 30], 255); // still set above the cut
      expect(mask[50 * n + 30], 255); // and below it, for now
      keepLargest(mask, n, n);
      expect(
        mask[20 * n + 30],
        255,
      ); // the largest component, above the cut, stays
      expect(mask[50 * n + 30], 0); // the component below the cut is cleared
      // the soft halo of a discarded component is cleared too, while that of the kept one stays
      final soft = Uint8List(n * n);
      for (var y = 5; y < 30; y++) {
        for (var x = 20; x < 40; x++) {
          soft[y * n + x] = 255;
        }
      }
      soft[30 * n + 30] = 90; // soft edge of the large component
      soft[50 * n + 30] = 255; // small component, with its halo
      soft[51 * n + 30] = 60;
      keepLargest(soft, n, n);
      expect(soft[30 * n + 30], 90);
      expect(soft[50 * n + 30], 0);
      expect(soft[51 * n + 30], 0);
      expect(resampleMask(mask, n, n, 30, 30).length, 900);
    },
  );

  test('the arms needed depend on the shape: few for a circle, more with corners', () {
    Analysis shape(bool Function(int x, int y) inside) {
      final im = Float32List(w * h)..fillRange(0, w * h, 255);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (inside(x, y)) im[y * w + x] = 0;
        }
      }
      return process(ProcessParams(im, w, h, 128, 1, 1, 14, true))!;
    }

    final circle = shape(
      (x, y) => (x - 100) * (x - 100) + (y - 80) * (y - 80) < 60 * 60,
    );
    final square = shape((x, y) => (x - 100).abs() < 55 && (y - 80).abs() < 55);
    final kc = circle.errOne.length - 1, ks = square.errOne.length - 1;
    expect(kc, lessThan(8));
    expect(ks, greaterThan(kc + 10));
    expect(circle.errOne.last, lessThanOrEqualTo(circle.tol));
    expect(square.errOne.last, lessThanOrEqualTo(square.tol));
    for (var i = 1; i < square.errOne.length; i++) {
      expect(square.errOne[i], lessThanOrEqualTo(square.errOne[i - 1]));
    }
    // ignore: avoid_print
    print(
      'arms needed: circle $kc, square $ks (tolerance ${circle.tol.toStringAsFixed(2)} px)',
    );
  });

  test('origin at the centroid and unit first circle', () {
    // the constant term of the series is zero: the path samples have zero mean
    var mx = 0.0, my = 0.0;
    for (var j = 0; j < m; j++) {
      mx += p.sx[j];
      my += p.sy[j];
    }
    expect(mx / m, closeTo(0, 1e-9));
    expect(my / m, closeTo(0, 1e-9));
    expect(an.dc[0].abs() + an.dc[1].abs(), lessThan(1e-9));
    // in the equation the first radius is 1 and the others are fractions of it
    final ln = equationLines(an, one: true, k: 20).single;
    expect(ln.terms.first.a, closeTo(1, 1e-12));
    expect(ln.terms[1].a, lessThan(1));
    expect(ln.complex, isTrue);
    expect(equationText([ln]).startsWith('z(t) = 1.00000*exp('), isTrue);
  });

  test('smoothing rounds the edge only where it was edited by hand', () {
    const n = 80;
    final mask = Uint8List(n * n);
    for (var y = 20; y < 60; y++) {
      for (var x = 20; x < 60; x++) {
        mask[y * n + x] = 255;
      }
    }
    // edit around the bottom-right corner; the top-left one is untouched
    final edit = Int8List(n * n);
    stampDisc(edit, n, n, 59, 59, 6, 1);
    smoothEdits(mask, edit, n, n, 4);
    expect(
      mask[59 * n + 59],
      lessThan(128),
    ); // the edited corner is rounded: its tip leaves the mask
    expect(mask[50 * n + 50], 255); // the interior stays full
    expect(mask[20 * n + 20], 255); // the unedited corner stays sharp
    expect(mask[19 * n + 19], 0);
    // radius zero changes nothing
    final before = Uint8List.fromList(mask);
    smoothEdits(mask, edit, n, n, 0);
    expect(mask, before);
  });

  test('rotating the shape rotates the series coefficients and leaves the radii unchanged', () {
    const rot = 0.6;
    final r = process(ProcessParams(g, w, h, thr, 1, 1, 14, false, rot))!;
    expect(r.m, an.m);
    expect(r.path.rot, rot);
    for (var i = 0; i < 12; i++) {
      // same arms, same frequency, same radius...
      expect(r.one.f[i], an.one.f[i]);
      expect(r.one.r[i], closeTo(an.one.r[i], 1e-9));
      // ...and every coefficient multiplied by e^{i·rot}
      final re = an.one.re[i] * math.cos(rot) - an.one.im[i] * math.sin(rot);
      final im = an.one.re[i] * math.sin(rot) + an.one.im[i] * math.cos(rot);
      expect(r.one.re[i], closeTo(re, 1e-9));
      expect(r.one.im[i], closeTo(im, 1e-9));
    }
    expect(r.errOne.length, an.errOne.length); // same number of arms needed
  });

  test('the spectrum table lists every term once, sorted by frequency', () {
    final ln = EqLine('z', [
      EqTerm(1, 1, 0.5),
      EqTerm(0.25, -2, -1),
      EqTerm(0.125, 3, 0),
    ], complex: true);
    final rows = spectrumTable([ln])
        .split('\n')
        .where((s) => s.isNotEmpty && !s.startsWith('#'))
        .toList();
    expect(rows.first, 'component\tfrequency\tamplitude\tphase');
    expect(rows.length, 4);
    expect(rows.sublist(1).map((r) => r.split('\t')[1]).toList(), [
      '-2',
      '1',
      '3',
    ]);
    final first = rows[1].split('\t');
    expect(first[0], 'z');
    expect(double.parse(first[2]), closeTo(0.25, 1e-9));
    expect(double.parse(first[3]), closeTo(-1, 1e-9));
  });

  // A test outline in image coordinates (y down): three harmonics, optionally rotated, scaled,
  // shifted along the path or traversed backwards.
  (Float64List, Float64List) outline({
    double rot = 0,
    double scale = 1,
    int shift = 0,
    bool reversed = false,
    int m = 512,
  }) {
    final sx = Float64List(m), sy = Float64List(m);
    for (var j = 0; j < m; j++) {
      final q = reversed ? (m - j) % m : j;
      final t = 2 * math.pi * ((q + shift) % m) / m;
      final x =
          3 * math.cos(t) + 0.4 * math.cos(2 * t + 0.7) + 0.2 * math.sin(3 * t);
      final y =
          2 * math.sin(t) +
          0.3 * math.sin(2 * t) -
          0.15 * math.cos(3 * t + 0.4);
      final xr = x * math.cos(rot) - y * math.sin(rot),
          yr = x * math.sin(rot) + y * math.cos(rot);
      sx[j] = scale * xr;
      sy[j] = -scale * yr; // image coordinates
    }
    return (sx, sy);
  }

  double maxDiff(Efd p, Efd q) {
    var d = 0.0;
    for (var i = 0; i < p.n; i++) {
      d = math.max(d, (p.a[i] - q.a[i]).abs());
      d = math.max(d, (p.b[i] - q.b[i]).abs());
      d = math.max(d, (p.c[i] - q.c[i]).abs());
      d = math.max(d, (p.d[i] - q.d[i]).abs());
    }
    return d;
  }

  test('elliptic descriptors of an ellipse are its semi-axes', () {
    const m = 512;
    final sx = Float64List(m), sy = Float64List(m);
    for (var j = 0; j < m; j++) {
      sx[j] = 3 * math.cos(2 * math.pi * j / m);
      sy[j] = -2 * math.sin(2 * math.pi * j / m);
    }
    final e = efdOfPath(sx, sy, 5);
    // The polygon through the samples differs from the ellipse by the sinc^2 factor.
    final k = math.pow(math.sin(math.pi / m) / (math.pi / m), 2);
    expect(e.a[0], closeTo(3 * k, 1e-12));
    expect(e.d[0], closeTo(2 * k, 1e-12));
    expect(e.b[0].abs() + e.c[0].abs(), lessThan(1e-12));
    for (var i = 1; i < 5; i++) {
      expect(
        e.a[i].abs() + e.b[i].abs() + e.c[i].abs() + e.d[i].abs(),
        lessThan(1e-12),
      );
    }
  });

  test('descriptors do not depend on the direction of travel', () {
    final (ax, ay) = outline();
    final (bx, by) = outline(reversed: true);
    expect(
      maxDiff(efdOfPath(ax, ay, 10), efdOfPath(bx, by, 10)),
      lessThan(1e-12),
    );
  });

  test(
    'first-ellipse normalisation removes size, rotation and starting point',
    () {
      final (ax, ay) = outline();
      final ref = normaliseEfd(efdOfPath(ax, ay, 10), keepOrientation: false);
      expect(ref.efd.a[0].abs(), closeTo(1, 1e-12));
      expect(ref.efd.b[0].abs() + ref.efd.c[0].abs(), lessThan(1e-12));
      final (bx, by) = outline(rot: 0.5, scale: 2.5, shift: 37);
      final other = normaliseEfd(efdOfPath(bx, by, 10), keepOrientation: false);
      expect(maxDiff(ref.efd, other.efd), lessThan(1e-9));
      expect(other.size / ref.size, closeTo(2.5, 1e-9));
    },
  );

  test('keeping the orientation still removes size and starting point', () {
    final (ax, ay) = outline(rot: 0.3);
    final ref = normaliseEfd(efdOfPath(ax, ay, 10), keepOrientation: true);
    final (bx, by) = outline(rot: 0.3, scale: 0.4, shift: 201);
    final other = normaliseEfd(efdOfPath(bx, by, 10), keepOrientation: true);
    expect(maxDiff(ref.efd, other.efd), lessThan(1e-9));
    expect(ref.psi, 0);
    // The rotation is still in the coefficients: a different one gives different descriptors.
    final (cx, cy) = outline(rot: 0.8);
    final turned = normaliseEfd(efdOfPath(cx, cy, 10), keepOrientation: true);
    expect(maxDiff(ref.efd, turned.efd), greaterThan(0.1));
  });

  test('with the orientation kept, a shape as wide as tall has a stable starting point', () {
    // A three-lobed shape whose first ellipse is almost a circle: slightly wider in one case,
    // slightly taller in the other. The major axis swaps between the two, the shape barely changes.
    (Float64List, Float64List) lobed(double wide, int shift) {
      const m = 512;
      final sx = Float64List(m), sy = Float64List(m);
      for (var j = 0; j < m; j++) {
        final t = 2 * math.pi * ((j + shift) % m) / m;
        final r = 1 + 0.25 * math.cos(3 * t + 0.4);
        sx[j] = wide * r * math.cos(t);
        sy[j] = -r * math.sin(t);
      }
      return (sx, sy);
    }

    final (ax, ay) = lobed(1.02, 0);
    final (bx, by) = lobed(0.98, 170);
    final p = normaliseEfd(efdOfPath(ax, ay, 10), keepOrientation: true);
    final q = normaliseEfd(efdOfPath(bx, by, 10), keepOrientation: true);
    expect(maxDiff(p.efd, q.efd), lessThan(0.05));
    // The first harmonic starts straight above the centre.
    expect(p.efd.a[0].abs(), lessThan(1e-12));
    expect(p.efd.c[0], greaterThan(0));
  });

  test(
    'a shape whose first harmonic is a circle still has finite descriptors',
    () {
      // Four-fold symmetry: the first ellipse is exactly a circle and has no major axis.
      const m = 512;
      final sx = Float64List(m), sy = Float64List(m);
      for (var j = 0; j < m; j++) {
        final t = 2 * math.pi * j / m;
        final r = 1 + 0.2 * math.cos(4 * t);
        sx[j] = r * math.cos(t);
        sy[j] = -r * math.sin(t);
      }
      for (final keep in [true, false]) {
        final n = normaliseEfd(efdOfPath(sx, sy, 8), keepOrientation: keep);
        expect(n.size.isFinite && n.size > 0, isTrue);
        for (var i = 0; i < 8; i++) {
          expect(n.efd.a[i].isFinite && n.efd.d[i].isFinite, isTrue);
        }
      }
    },
  );

  test(
    'the descriptor table has one row per specimen and 4 columns per harmonic',
    () {
      final (ax, ay) = outline();
      final s = Specimen(
        id: '1',
        name: 'Leaf\t1',
        group: 'A',
        date: DateTime(2026, 10, 13),
        detail: 2,
        rotation: 0,
        outline: Float64List(0),
        efd: efdOfPath(ax, ay, 12),
      );
      final rows = efdTable(
        [s, s],
        harmonics: 10,
        keepOrientation: true,
      ).split('\n').where((r) => r.isNotEmpty && !r.startsWith('#')).toList();
      expect(rows.length, 3);
      expect(rows[0].split('\t').length, 4 + 40);
      final cells = rows[1].split('\t');
      expect(cells.length, 4 + 40);
      expect(cells[0], 'Leaf 1'); // tabs in names cannot break the table
      expect(cells[2], '2026-10-13');
      final back = Specimen.fromJson(s.toJson());
      expect(maxDiff(back.efd, s.efd), lessThan(1e-12));
    },
  );

  test('principal components: variances, orthogonal unit axes, scores', () {
    // Twelve samples of five variables with a fixed pseudo-random pattern; the reference values
    // were computed with numpy (covariance with n - 1, eigenvalues in decreasing order).
    final rows = [
      for (var i = 0; i < 12; i++)
        Float64List.fromList([
          for (var j = 0; j < 5; j++)
            math.sin(1.3 * i + 0.7 * j) +
                0.5 * math.cos(0.4 * i * (j + 1)) +
                0.1 * j,
        ]),
    ];
    final r = pca(rows, components: 3);
    expect(r.axes.length, 3);
    expect(r.variance[0], closeTo(2.00410392598843, 1e-9));
    expect(r.variance[1], closeTo(1.8304013019072984, 1e-9));
    expect(r.variance[2], closeTo(0.1643352809771928, 1e-9));
    expect(r.totalVariance, closeTo(4.229132516405021, 1e-9));
    for (var a = 0; a < 3; a++) {
      for (var b = a; b < 3; b++) {
        var dot = 0.0;
        for (var j = 0; j < 5; j++) {
          dot += r.axes[a][j] * r.axes[b][j];
        }
        expect(dot, closeTo(a == b ? 1 : 0, 1e-9));
      }
    }
    // The variance of the scores along each axis is the eigenvalue.
    for (var a = 0; a < 3; a++) {
      var ss = 0.0;
      for (final s in r.scores) {
        ss += s[a] * s[a];
      }
      expect(ss / 11, closeTo(r.variance[a], 1e-9));
    }
  });
}
