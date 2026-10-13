// Computational core: grayscale image -> contours -> closed path -> Fourier series.
// Pure Dart (only dart:math and dart:typed_data), no Flutter dependency, so it can run in an isolate.

import 'dart:math' as math;
import 'dart:typed_data';

/// Time weight of a pen-up jump relative to a drawn segment of the same length.
const double jumpWeight = 0.3;

/// Upper bound on the number of contours kept, longest first.
const int maxContours = 500;

/// Luminance distance between consecutive threshold levels.
const double levelStep = 36;

int _clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Rotates the path by [rot] radians about its centroid, which is the origin of the samples.
/// Rotating the shape multiplies every coefficient of the series by e^{i·rot}.
PathSamples rotatePath(PathSamples p, double rot) {
  if (rot == 0) return p;
  final c = math.cos(rot), s = math.sin(rot);
  final sx = Float64List(p.m), sy = Float64List(p.m);
  var x0 = double.infinity,
      x1 = -double.infinity,
      y0 = double.infinity,
      y1 = -double.infinity;
  for (var j = 0; j < p.m; j++) {
    sx[j] = p.sx[j] * c - p.sy[j] * s;
    sy[j] = p.sx[j] * s + p.sy[j] * c;
    x0 = math.min(x0, sx[j]);
    x1 = math.max(x1, sx[j]);
    y0 = math.min(y0, sy[j]);
    y1 = math.max(y1, sy[j]);
  }
  return PathSamples(
    p.m,
    sx,
    sy,
    p.pen,
    math.max(1.0, x1 - x0),
    math.max(1.0, y1 - y0),
    p.ox,
    p.oy,
    rot,
  );
}

/// A closed polyline in working-image pixels.
class Contour {
  Contour(this.p, this.n, this.len);

  /// Interleaved coordinates: x0, y0, x1, y1, ...
  final Float32List p;

  /// Number of points.
  final int n;

  /// Perimeter.
  final double len;
}

/// Box blur of radius [r], applied twice per axis to approximate a Gaussian.
Float32List boxBlur(Float32List src, int w, int h, int r) {
  if (r < 1) return src;
  var a = src;
  final k = 1 / (2 * r + 1);
  for (var pass = 0; pass < 2; pass++) {
    final b = Float32List(w * h), c = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final o = y * w;
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += a[o + _clampInt(i, 0, w - 1)];
      }
      for (var x = 0; x < w; x++) {
        b[o + x] = s * k;
        s += a[o + math.min(w - 1, x + r + 1)] - a[o + math.max(0, x - r)];
      }
    }
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        s += b[_clampInt(i, 0, h - 1) * w + x];
      }
      for (var y = 0; y < h; y++) {
        c[y * w + x] = s * k;
        s +=
            b[math.min(h - 1, y + r + 1) * w + x] -
            b[math.max(0, y - r) * w + x];
      }
    }
    a = c;
  }
  return a;
}

/// Otsu threshold on luminance (0-255).
int otsu(Float32List g) {
  final hist = Float64List(256);
  for (var i = 0; i < g.length; i++) {
    hist[_clampInt(g[i].toInt(), 0, 255)]++;
  }
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var wB = 0.0, sB = 0.0, best = -1.0;
  var thr = 128;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = g.length - wB;
    if (wF == 0) break;
    sB += i * hist[i];
    final d = sB / wB - (sum - sB) / wF, v = wB * wF * d * d;
    if (v > best) {
      best = v;
      thr = i;
    }
  }
  return _clampInt(thr + 1, 4, 251);
}

/// Marching squares: closed iso-lines of luminance at threshold [thr], with subpixel precision.
List<Contour> marching(Float32List g, int w, int h, double thr) {
  // The field is padded by one pixel on every side.
  final pw = w + 2, ph = h + 2;
  final f = Float32List(pw * ph);
  var bs = 0.0;
  var bn = 0;
  for (var x = 0; x < w; x++) {
    bs += g[x] + g[(h - 1) * w + x];
    bn += 2;
  }
  for (var y = 0; y < h; y++) {
    bs += g[y * w] + g[y * w + w - 1];
    bn += 2;
  }
  // The padding takes the side of the threshold the image border is on (its mean luminance),
  // so every contour closes.
  f.fillRange(0, f.length, bs / bn < thr ? -1 : 256);
  for (var y = 0; y < h; y++) {
    f.setRange((y + 1) * pw + 1, (y + 1) * pw + 1 + w, g, y * w);
  }

  // Two candidate crossing points per grid node: on the edge to its right (index 2i) and on the
  // edge below it (2i + 1). Each crossing links to at most two neighbours, a1 and a2.
  final nE = 2 * pw * ph;
  final a1 = Int32List(nE)..fillRange(0, nE, -1);
  final a2 = Int32List(nE)..fillRange(0, nE, -1);
  final px = Float32List(nE), py = Float32List(nE);
  void link(int p, int q) {
    if (a1[p] < 0) {
      a1[p] = q;
    } else {
      a2[p] = q;
    }
    if (a1[q] < 0) {
      a1[q] = p;
    } else {
      a2[q] = p;
    }
  }

  for (var y = 0; y < ph - 1; y++) {
    for (var x = 0; x < pw - 1; x++) {
      final i = y * pw + x;
      // Cell corners, clockwise from top-left.
      final v0 = f[i], v1 = f[i + 1], v2 = f[i + pw + 1], v3 = f[i + pw];
      final b0 = v0 < thr, b1 = v1 < thr, b2 = v2 < thr, b3 = v3 < thr;
      final c = (b0 ? 8 : 0) | (b1 ? 4 : 0) | (b2 ? 2 : 0) | (b3 ? 1 : 0);
      if (c == 0 || c == 15) continue;
      final top = 2 * i,
          left = 2 * i + 1,
          bottom = 2 * (i + pw),
          right = 2 * (i + 1) + 1;
      if (b0 != b1) {
        px[top] = x + (thr - v0) / (v1 - v0);
        py[top] = y.toDouble();
      }
      if (b3 != b2) {
        px[bottom] = x + (thr - v3) / (v2 - v3);
        py[bottom] = y + 1.0;
      }
      if (b0 != b3) {
        px[left] = x.toDouble();
        py[left] = y + (thr - v0) / (v3 - v0);
      }
      if (b1 != b2) {
        px[right] = x + 1.0;
        py[right] = y + (thr - v1) / (v2 - v1);
      }
      switch (c) {
        case 1:
        case 14:
          link(left, bottom);
        case 2:
        case 13:
          link(bottom, right);
        case 3:
        case 12:
          link(left, right);
        case 4:
        case 11:
          link(top, right);
        case 6:
        case 9:
          link(top, bottom);
        case 7:
        case 8:
          link(top, left);
        case 5:
          link(top, left);
          link(bottom, right);
        case 10:
          link(top, right);
          link(left, bottom);
      }
    }
  }

  final seen = Uint8List(nE);
  final out = <Contour>[];
  for (var e = 0; e < nE; e++) {
    if (a1[e] < 0 || seen[e] != 0) continue;
    final pts = <double>[];
    var prev = -1, cur = e;
    while (cur >= 0 && seen[cur] == 0) {
      seen[cur] = 1;
      // Back to unpadded image coordinates.
      pts.add(px[cur] - 1);
      pts.add(py[cur] - 1);
      final nx = a1[cur] != prev ? a1[cur] : a2[cur];
      prev = cur;
      cur = nx;
    }
    final n = pts.length ~/ 2;
    if (n < 3) continue;
    var len = 0.0;
    for (var k = 0; k < n; k++) {
      final m = (k + 1) % n;
      final dx = pts[2 * m] - pts[2 * k], dy = pts[2 * m + 1] - pts[2 * k + 1];
      len += math.sqrt(dx * dx + dy * dy);
    }
    out.add(Contour(Float32List.fromList(pts), n, len));
  }
  return out;
}

/// A closed path resampled at constant step, centred on its centroid.
class PathSamples {
  PathSamples(
    this.m,
    this.sx,
    this.sy,
    this.pen,
    this.bw,
    this.bh,
    this.ox,
    this.oy, [
    this.rot = 0,
  ]);

  /// Number of samples, a power of two.
  final int m;

  /// Sample coordinates relative to the centroid, in working-image pixels.
  final Float64List sx, sy;

  /// 1 where the pen is down, 0 on a jump between contours.
  final Uint8List pen;

  /// Bounding-box width and height (at least 1).
  final double bw, bh;

  /// The centroid, in working-image pixels.
  final double ox, oy;

  /// Rotation applied about the centroid, in radians (positive = clockwise on screen).
  final double rot;
}

/// Joins the contours into a single closed path (starting from the first, then always jumping to
/// the nearest unused one) and resamples it at constant step on a power-of-two number of samples.
PathSamples buildPath(List<Contour> cs) {
  final used = Uint8List(cs.length);
  final xs = <double>[], ys = <double>[];
  final pens = <int>[];
  var ci = 0, start = 0;
  for (var step = 0; step < cs.length; step++) {
    final c = cs[ci];
    used[ci] = 1;
    for (var k = 0; k <= c.n; k++) {
      final j = ((start + k) % c.n) * 2;
      xs.add(c.p[j]);
      ys.add(c.p[j + 1]);
      pens.add(k == 0 ? 0 : 1);
    }
    final x0 = c.p[start * 2], y0 = c.p[start * 2 + 1];
    var best = double.infinity;
    var bi = -1, bj = 0;
    for (var i = 0; i < cs.length; i++) {
      if (used[i] != 0) continue;
      final p = cs[i].p;
      final m = cs[i].n, st = m > 400 ? 2 : 1;
      for (var j = 0; j < m; j += st) {
        final dx = p[2 * j] - x0, dy = p[2 * j + 1] - y0, d = dx * dx + dy * dy;
        if (d < best) {
          best = d;
          bi = i;
          bj = j;
        }
      }
    }
    if (bi < 0) break;
    ci = bi;
    start = bj;
  }

  // Weighted length of the segment ending at each point: jumps count [jumpWeight] of their length.
  final n = xs.length;
  final wl = Float64List(n);
  var wt = 0.0, drawn = 0.0;
  for (var i = 0; i < n; i++) {
    final a = (i + n - 1) % n;
    final dx = xs[i] - xs[a],
        dy = ys[i] - ys[a],
        l = math.sqrt(dx * dx + dy * dy);
    wl[i] = l * (pens[i] != 0 ? 1 : jumpWeight);
    wt += wl[i];
    if (pens[i] != 0) drawn += l;
  }
  // About one sample per drawn pixel, between 1024 and 8192.
  var m = 1024;
  while (m < drawn && m < 8192) {
    m *= 2;
  }
  final sx = Float64List(m), sy = Float64List(m);
  final pen = Uint8List(m);
  var seg = 1 % n, guard = 0;
  var acc = 0.0;
  for (var j = 0; j < m; j++) {
    final s = j * wt / m;
    while (acc + wl[seg] < s && guard < 4 * n) {
      acc += wl[seg];
      seg = (seg + 1) % n;
      guard++;
    }
    final a = (seg + n - 1) % n;
    final u = wl[seg] > 0 ? ((s - acc) / wl[seg]).clamp(0.0, 1.0) : 0.0;
    sx[j] = xs[a] + (xs[seg] - xs[a]) * u;
    sy[j] = ys[a] + (ys[seg] - ys[a]) * u;
    pen[j] = pens[seg];
  }
  var x0 = double.infinity,
      x1 = -double.infinity,
      y0 = double.infinity,
      y1 = -double.infinity;
  for (var j = 0; j < m; j++) {
    x0 = math.min(x0, sx[j]);
    x1 = math.max(x1, sx[j]);
    y0 = math.min(y0, sy[j]);
    y1 = math.max(y1, sy[j]);
  }
  // The origin is the centroid of the path: the mean of the samples, i.e. the zero-frequency term
  // of the series, which therefore vanishes. This is the canonical normalisation for position.
  var mx = 0.0, my = 0.0;
  for (var j = 0; j < m; j++) {
    mx += sx[j];
    my += sy[j];
  }
  mx /= m;
  my /= m;
  for (var j = 0; j < m; j++) {
    sx[j] -= mx;
    sy[j] -= my;
  }
  return PathSamples(
    m,
    sx,
    sy,
    pen,
    math.max(1.0, x1 - x0),
    math.max(1.0, y1 - y0),
    mx,
    my,
  );
}

/// In-place radix-2 FFT: X_k = sum_j x_j e^{-2 pi i jk/n}. The length must be a power of two.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      var t = re[i];
      re[i] = re[j];
      re[j] = t;
      t = im[i];
      im[i] = im[j];
      im[j] = t;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len, wr = math.cos(ang), wi = math.sin(ang);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < half; k++) {
        final a = i + k, b = a + half;
        final xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
        re[b] = re[a] - xr;
        im[b] = im[a] - xi;
        re[a] += xr;
        im[a] += xi;
        final t = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = t;
      }
    }
  }
}

/// A chain of circles: terms sorted by decreasing radius, so the first K are the K largest.
class Chain {
  Chain(this.n, this.f, this.re, this.im, this.r);

  /// Number of terms.
  final int n;

  /// Integer frequency of each term (turns per cycle).
  final Int32List f;

  /// Complex coefficient of each term.
  final Float64List re, im;

  /// Radius of each circle: the modulus of the coefficient.
  final Float64List r;
}

/// Builds a [Chain] from terms with frequencies [freqs] and coefficients [res] + i·[ims].
Chain makeChain(List<int> freqs, List<double> res, List<double> ims) {
  final n = freqs.length;
  final r0 = Float64List(n);
  final idx = List<int>.generate(n, (i) => i);
  for (var i = 0; i < n; i++) {
    r0[i] = math.sqrt(res[i] * res[i] + ims[i] * ims[i]);
  }
  idx.sort((a, b) => r0[b].compareTo(r0[a]));
  final f = Int32List(n);
  final re = Float64List(n), im = Float64List(n), r = Float64List(n);
  for (var i = 0; i < n; i++) {
    final q = idx[i];
    f[i] = freqs[q];
    re[i] = res[q];
    im[i] = ims[q];
    r[i] = r0[q];
  }
  return Chain(n, f, re, im, r);
}

/// The shape counts as reached when the maximum deviation of the curve from the path drops below
/// this fraction of the longer side of its bounding box.
const double fitTolerance = 0.003;

/// Maximum deviation between the curve and the pen-down part of the path as arms are added.
///
/// With [b] null there is a single complex chain; otherwise [a] gives x and [b] gives y, one arm
/// for each at every step. ([x0], [y0]) is the constant term. Returns the deviations with
/// 0, 1, 2, ... arms, made non-increasing, stopping at the first one not above [tol].
Float32List fitErrors(
  PathSamples p,
  double x0,
  double y0,
  Float64List cosT,
  Float64List sinT,
  Chain a,
  Chain? b,
  double tol,
) {
  final m = p.m, stride = m > 2048 ? 4 : (m > 1024 ? 2 : 1);
  final idx = <int>[];
  for (var j = 0; j < m; j += stride) {
    if (p.pen[j] != 0) idx.add(j);
  }
  final n = idx.length;
  final rx = Float64List(n), ry = Float64List(n);
  var worst = 0.0;
  for (var u = 0; u < n; u++) {
    rx[u] = p.sx[idx[u]] - x0;
    ry[u] = p.sy[idx[u]] - y0;
    worst = math.max(worst, rx[u] * rx[u] + ry[u] * ry[u]);
  }
  final errs = <double>[math.sqrt(worst)];
  final count = b == null ? a.n : math.min(a.n, b.n);
  for (var i = 0; i < count && errs.last > tol; i++) {
    worst = 0.0;
    if (b == null) {
      final f = a.f[i];
      final re = a.re[i], im = a.im[i];
      for (var u = 0; u < n; u++) {
        final q = (f * idx[u]) % m;
        final c = cosT[q], s = sinT[q];
        rx[u] -= re * c - im * s;
        ry[u] -= re * s + im * c;
        final d = rx[u] * rx[u] + ry[u] * ry[u];
        if (d > worst) worst = d;
      }
    } else {
      final fa = a.f[i], fb = b.f[i];
      for (var u = 0; u < n; u++) {
        final qa = (fa * idx[u]) % m, qb = (fb * idx[u]) % m;
        rx[u] -= a.re[i] * cosT[qa] - a.im[i] * sinT[qa];
        ry[u] -= b.re[i] * cosT[qb] - b.im[i] * sinT[qb];
        final d = rx[u] * rx[u] + ry[u] * ry[u];
        if (d > worst) worst = d;
      }
    }
    errs.add(math.min(errs.last, math.sqrt(worst)));
  }
  return Float32List.fromList(errs);
}

/// Everything the app needs about one shape: its path, its Fourier chains and how well they fit.
class Analysis {
  Analysis(
    this.contours,
    this.path,
    this.one,
    this.cx,
    this.cy,
    this.dc,
    this.cosT,
    this.sinT,
    this.ghost,
    this.gbox,
    this.tol,
    this.errOne,
    this.errTwo,
  );

  /// Number of contours joined into [path].
  final int contours;

  /// Deviation from the contour, in working-image pixels, below which the shape counts as reached.
  final double tol;

  /// Maximum deviation from the contour with 0, 1, 2, ... arms, up to the first one not above
  /// [tol]: the length minus one is the number of arms this shape needs. [errOne] is for the
  /// single complex chain, [errTwo] for the x and y chains.
  final Float32List errOne, errTwo;

  /// Every contour found in the image, in path coordinates; drawn as the background.
  final List<Float32List> ghost;

  /// Bounding box of [ghost]: [x0, y0, x1, y1].
  final Float64List gbox;

  final PathSamples path;

  /// z(t) = x + i y, with positive and negative frequencies.
  final Chain one;

  /// x(t) and y(t) as real sums of cosines.
  final Chain cx, cy;

  /// Constant terms: [re z0, im z0, x0, y0].
  final Float64List dc;

  /// cos and sin of 2 pi q / m for q = 0 .. m - 1.
  final Float64List cosT, sinT;

  int get m => path.m;
}

/// Fourier analysis of path [p], built from [contours] contours. [all] are the contours to keep
/// as background.
Analysis analyze(int contours, PathSamples p, List<Contour> all) {
  final ghost = <Float32List>[];
  final gc = math.cos(p.rot), gs = math.sin(p.rot);
  final gbox = Float64List.fromList([
    double.infinity,
    double.infinity,
    -double.infinity,
    -double.infinity,
  ]);
  for (final c in all) {
    final g = Float32List(c.n * 2);
    for (var i = 0; i < c.n; i++) {
      final ux = c.p[2 * i] - p.ox, uy = c.p[2 * i + 1] - p.oy;
      // The background rotates with the path.
      final x = ux * gc - uy * gs, y = ux * gs + uy * gc;
      g[2 * i] = x;
      g[2 * i + 1] = y;
      gbox[0] = math.min(gbox[0], x);
      gbox[1] = math.min(gbox[1], y);
      gbox[2] = math.max(gbox[2], x);
      gbox[3] = math.max(gbox[3], y);
    }
    ghost.add(g);
  }
  final m = p.m;
  final dc = Float64List(4);
  final re = Float64List.fromList(p.sx), im = Float64List.fromList(p.sy);
  fft(re, im);
  final freqs = <int>[];
  final res = <double>[], ims = <double>[];
  for (var k = 1; k < m; k++) {
    freqs.add(k <= m ~/ 2 ? k : k - m);
    res.add(re[k] / m);
    ims.add(im[k] / m);
  }
  final one = makeChain(freqs, res, ims);
  dc[0] = re[0] / m;
  dc[1] = im[0] / m;

  // One-sided spectrum of a real signal: each term is the pair of conjugate frequencies +-k
  // (hence the factor 2, except at the Nyquist frequency).
  Chain real(Float64List sig, int slot) {
    final a = Float64List.fromList(sig), b = Float64List(m);
    fft(a, b);
    final freqs = <int>[];
    final res = <double>[], ims = <double>[];
    for (var k = 1; k <= m ~/ 2; k++) {
      final s = (k == m ~/ 2 ? 1 : 2) / m;
      freqs.add(k);
      res.add(a[k] * s);
      ims.add(b[k] * s);
    }
    dc[slot] = a[0] / m;
    return makeChain(freqs, res, ims);
  }

  final cx = real(p.sx, 2), cy = real(p.sy, 3);
  final cosT = Float64List(m), sinT = Float64List(m);
  for (var q = 0; q < m; q++) {
    cosT[q] = math.cos(2 * math.pi * q / m);
    sinT[q] = math.sin(2 * math.pi * q / m);
  }
  final tol = math.max(0.5, fitTolerance * math.max(p.bw, p.bh));
  return Analysis(
    contours,
    p,
    one,
    cx,
    cy,
    dc,
    cosT,
    sinT,
    ghost,
    gbox,
    tol,
    fitErrors(p, dc[0], dc[1], cosT, sinT, one, null, tol),
    fitErrors(p, dc[2], dc[3], cosT, sinT, cx, cy, tol),
  );
}

/// Input of [process]; a plain object so it can be sent to an isolate.
class ProcessParams {
  ProcessParams(
    this.gray,
    this.w,
    this.h,
    this.thr,
    this.levels,
    this.blur,
    this.minLen,
    this.single, [
    this.rot = 0,
  ]);

  /// Luminance (0-255), row-major, [w] x [h].
  final Float32List gray;
  final int w, h;

  /// Central threshold, number of threshold levels ([levelStep] apart) and blur radius.
  final int thr, levels, blur;

  /// Contours shorter than this are discarded.
  final double minLen;

  /// Keep only the longest contour: one closed line, no jumps.
  final bool single;

  /// Rotation of the shape, in radians.
  final double rot;
}

/// The whole pipeline. Returns null if these parameters yield no contour.
Analysis? process(ProcessParams p) {
  final g = boxBlur(p.gray, p.w, p.h, p.blur);
  var cs = <Contour>[];
  for (var i = 0; i < p.levels; i++) {
    final t = (p.thr + (i - (p.levels - 1) / 2) * levelStep).clamp(4.0, 251.0);
    cs.addAll(marching(g, p.w, p.h, t));
  }
  cs = cs.where((c) => c.len >= p.minLen).toList()
    ..sort((a, b) => b.len.compareTo(a.len));
  if (cs.length > maxContours) cs = cs.sublist(0, maxContours);
  if (cs.isEmpty) return null;
  final drawn = p.single ? [cs.first] : cs;
  return analyze(drawn.length, rotatePath(buildPath(drawn), p.rot), cs);
}
