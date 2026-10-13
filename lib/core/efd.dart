// Elliptic Fourier descriptors of a closed outline (Kuhl & Giardina, 1982) and their normalisation.
// Pure Dart.
//
// For each harmonic n the outline is described by four coefficients:
//   x(t) = sum a_n cos(2 pi n t) + b_n sin(2 pi n t)
//   y(t) = sum c_n cos(2 pi n t) + d_n sin(2 pi n t),   t in [0, 1)
// The y axis points up and the outline is traversed counter-clockwise.

import 'dart:math' as math;
import 'dart:typed_data';

/// The coefficients of the first [n] harmonics; index 0 holds harmonic 1.
class Efd {
  Efd(this.a, this.b, this.c, this.d);
  final Float64List a, b, c, d;
  int get n => a.length;
}

/// The samples of an outline in image coordinates (y down) turned into an upright,
/// counter-clockwise polygon: y is flipped and, if needed, the order of the points reversed.
/// Returns x and y.
(Float64List, Float64List) uprightCounterClockwise(
  Float64List sx,
  Float64List sy,
) {
  final m = sx.length;
  final x = Float64List.fromList(sx), y = Float64List(m);
  for (var j = 0; j < m; j++) {
    y[j] = -sy[j];
  }
  // Twice the signed area: negative means clockwise.
  var area = 0.0;
  for (var j = 0; j < m; j++) {
    final k = (j + 1) % m;
    area += x[j] * y[k] - x[k] * y[j];
  }
  if (area < 0) {
    for (var j = 1, k = m - 1; j < k; j++, k--) {
      final tx = x[j], ty = y[j];
      x[j] = x[k];
      y[j] = y[k];
      x[k] = tx;
      y[k] = ty;
    }
  }
  return (x, y);
}

/// Coefficients of the closed polygon through the samples ([sx], [sy]), which must be equally
/// spaced along the outline. Image coordinates (y down) are expected: see
/// [uprightCounterClockwise].
///
/// The values are those of the Kuhl-Giardina integral over the polygon: for equal steps it equals
/// the discrete Fourier transform of the samples times sinc^2(pi n / m).
Efd efdOfPath(Float64List sx, Float64List sy, int harmonics) {
  final m = sx.length;
  final (x, y) = uprightCounterClockwise(sx, sy);
  final n = math.min(harmonics, m ~/ 2 - 1);
  final a = Float64List(n),
      b = Float64List(n),
      c = Float64List(n),
      d = Float64List(n);
  for (var h = 1; h <= n; h++) {
    var sa = 0.0, sb = 0.0, sc = 0.0, sd = 0.0;
    final w = 2 * math.pi * h / m;
    for (var j = 0; j < m; j++) {
      final co = math.cos(w * j), si = math.sin(w * j);
      sa += x[j] * co;
      sb += x[j] * si;
      sc += y[j] * co;
      sd += y[j] * si;
    }
    final u = math.pi * h / m, sinc = math.sin(u) / u;
    final k = 2 / m * sinc * sinc;
    a[h - 1] = sa * k;
    b[h - 1] = sb * k;
    c[h - 1] = sc * k;
    d[h - 1] = sd * k;
  }
  return Efd(a, b, c, d);
}

/// A closed outline given as x0, y0, x1, y1… resampled to [m] points equally spaced along it and
/// centred on their mean. Returns x and y. The points may be unevenly spaced and the outline may
/// or may not repeat its first point at the end.
(Float64List, Float64List) resampleOutline(Float64List xy, int m) {
  var n = xy.length ~/ 2;
  if (n > 1 && xy[0] == xy[2 * n - 2] && xy[1] == xy[2 * n - 1]) n--;
  // Length of the side leaving each point; the last one closes the outline.
  final side = Float64List(n);
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    final k = (i + 1) % n;
    final dx = xy[2 * k] - xy[2 * i], dy = xy[2 * k + 1] - xy[2 * i + 1];
    side[i] = math.sqrt(dx * dx + dy * dy);
    total += side[i];
  }
  final x = Float64List(m), y = Float64List(m);
  var i = 0, before = 0.0, mx = 0.0, my = 0.0;
  for (var j = 0; j < m; j++) {
    final s = total * j / m;
    while (i < n - 1 && before + side[i] < s) {
      before += side[i];
      i++;
    }
    final k = (i + 1) % n;
    final u = side[i] > 0 ? ((s - before) / side[i]).clamp(0.0, 1.0) : 0.0;
    x[j] = xy[2 * i] + (xy[2 * k] - xy[2 * i]) * u;
    y[j] = xy[2 * i + 1] + (xy[2 * k + 1] - xy[2 * i + 1]) * u;
    mx += x[j] / m;
    my += y[j] / m;
  }
  for (var j = 0; j < m; j++) {
    x[j] -= mx;
    y[j] -= my;
  }
  return (x, y);
}

/// Coefficients of an upright outline (y up) given as x0, y0, x1, y1…, with points at any
/// spacing: it is first resampled to [samples] equal steps. Also returns the resampled outline.
(Efd, Float64List) efdOfOutline(
  Float64List xy,
  int harmonics, {
  int samples = 1024,
}) {
  final (x, y) = resampleOutline(xy, samples);
  final down = Float64List(samples);
  for (var j = 0; j < samples; j++) {
    down[j] = -y[j];
  }
  final (ux, uy) = uprightCounterClockwise(x, down);
  final outline = Float64List(samples * 2);
  for (var j = 0; j < samples; j++) {
    outline[2 * j] = ux[j];
    outline[2 * j + 1] = uy[j];
  }
  return (efdOfPath(x, down, harmonics), outline);
}

/// Normalised coefficients, with what was removed.
class NormalisedEfd {
  NormalisedEfd(this.efd, this.size, this.theta, this.psi);
  final Efd efd;

  /// Semi-major axis of the first ellipse, in the units of the input: the unit of the result.
  final double size;

  /// Phase shift applied to move the starting point, in radians.
  final double theta;

  /// Rotation removed, in radians (0 when the orientation is kept).
  final double psi;
}

/// Removes size and starting point, and optionally orientation, using the ellipse of the first
/// harmonic.
///
/// With [keepOrientation] false this is the classical normalisation (as in Momocs' efourier_norm):
/// the starting point moves to an end of the major axis of the first ellipse and the shape is
/// rotated so that this axis lies along x. Which end is taken is not determined by the ellipse, so
/// nearly symmetric shapes can come out turned by 180 degrees.
///
/// With [keepOrientation] true the shape is left as the operator oriented it, and the starting
/// point is taken from that orientation: the point where the first ellipse is straight above its
/// centre. Size is still the semi-major axis of the first ellipse.
NormalisedEfd normaliseEfd(Efd e, {required bool keepOrientation}) {
  final a1 = e.a[0], b1 = e.b[0], c1 = e.c[0], d1 = e.d[0];
  // atan2 rather than atan of the ratio: when the first harmonic is a circle both terms vanish,
  // and the angle is then 0 instead of undefined.
  var theta =
      (0.5 *
          math.atan2(
            2 * (a1 * b1 + c1 * d1),
            a1 * a1 + c1 * c1 - b1 * b1 - d1 * d1,
          )) %
      math.pi;
  // Of the two axes found, take the major one.
  final ct = math.cos(theta), st = math.sin(theta);
  final v1 = math.pow(a1 * ct + b1 * st, 2) + math.pow(c1 * ct + d1 * st, 2);
  final v2 = math.pow(-a1 * st + b1 * ct, 2) + math.pow(-c1 * st + d1 * ct, 2);
  if (v1 < v2) theta += math.pi / 2;
  theta = (theta + math.pi / 2) % math.pi - math.pi / 2;
  final aa = a1 * math.cos(theta) + b1 * math.sin(theta);
  final cc = c1 * math.cos(theta) + d1 * math.sin(theta);
  final scale = math.sqrt(aa * aa + cc * cc);
  var psi = 0.0;
  if (keepOrientation) {
    // Start where the first ellipse crosses the vertical through its centre, on the upper side.
    // Unlike an end of the major axis, this point stays put when the ellipse is close to a
    // circle, as it is for shapes about as wide as they are tall.
    theta = math.atan2(-a1, b1);
    if (c1 * math.cos(theta) + d1 * math.sin(theta) < 0) theta += math.pi;
  } else {
    psi = math.atan(cc / aa) % math.pi;
    if (aa < 0) psi += math.pi;
  }
  final cp = math.cos(psi), sp = math.sin(psi);
  final n = e.n;
  final a = Float64List(n),
      b = Float64List(n),
      c = Float64List(n),
      d = Float64List(n);
  for (var i = 0; i < n; i++) {
    final h = i + 1;
    final ch = math.cos(h * theta), sh = math.sin(h * theta);
    // Phase shift of the starting point, then rotation by -psi, then scaling.
    final pa = e.a[i] * ch + e.b[i] * sh, pb = -e.a[i] * sh + e.b[i] * ch;
    final pc = e.c[i] * ch + e.d[i] * sh, pd = -e.c[i] * sh + e.d[i] * ch;
    a[i] = (cp * pa + sp * pc) / scale;
    b[i] = (cp * pb + sp * pd) / scale;
    c[i] = (-sp * pa + cp * pc) / scale;
    d[i] = (-sp * pb + cp * pd) / scale;
  }
  return NormalisedEfd(Efd(a, b, c, d), scale, theta, psi);
}

/// Points of the outline rebuilt from the first [harmonics] of [e], as x0, y0, x1, y1…
Float64List efdOutline(Efd e, int harmonics, int points) {
  final n = math.min(harmonics, e.n);
  final out = Float64List(points * 2);
  for (var j = 0; j < points; j++) {
    final t = 2 * math.pi * j / points;
    var x = 0.0, y = 0.0;
    for (var i = 0; i < n; i++) {
      final co = math.cos((i + 1) * t), si = math.sin((i + 1) * t);
      x += e.a[i] * co + e.b[i] * si;
      y += e.c[i] * co + e.d[i] * si;
    }
    out[2 * j] = x;
    out[2 * j + 1] = y;
  }
  return out;
}
