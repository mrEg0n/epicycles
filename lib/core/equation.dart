// The equation produced by the analysis, as structured terms and as plain text.
// Normalisation (that of Fourier descriptors): the origin is the centroid of the contour, so the
// constant term is zero and is omitted; the unit is the radius of the largest circle, which is 1.
// t is in [0, 1). The y axis points up (on screen it grows downwards), so the shape comes out
// upright when plotted elsewhere.

import 'dart:math' as math;

import 'fourier_core.dart';

/// One term: a·exp(i(2 pi f t + p)) in the complex form, a·cos(2 pi f t + p) in the real one.
class EqTerm {
  EqTerm(this.a, this.f, this.p);

  /// Amplitude.
  final double a;

  /// Frequency.
  final int f;

  /// Phase in radians, in (-pi, pi].
  final double p;
}

/// One equation: z(t) in the complex form, x(t) or y(t) in the real one.
class EqLine {
  EqLine(this.name, this.terms, {required this.complex});

  /// 'x', 'y' or 'z'.
  final String name;

  /// True for z(t), a sum of complex exponentials; false for x(t) and y(t), sums of cosines.
  /// There is no constant term in either form, because the origin is the centroid.
  final bool complex;

  final List<EqTerm> terms;
}

double _wrapPi(double p) {
  while (p > math.pi) {
    p -= 2 * math.pi;
  }
  while (p <= -math.pi) {
    p += 2 * math.pi;
  }
  return p;
}

/// The first [k] terms of the series: one line z(t) with [one], otherwise x(t) and y(t).
/// To flip the y axis the complex form is conjugated and y(t) is negated (phase shifted by pi).
List<EqLine> equationLines(Analysis a, {required bool one, required int k}) {
  final r0 = a.one.r[0];
  final u = r0 > 0
      ? 1 / r0
      : 1.0; // a degenerate path has no largest circle to use as the unit
  if (one) {
    final ch = a.one;
    final t = <EqTerm>[
      for (var i = 0; i < k; i++)
        EqTerm(ch.r[i] * u, -ch.f[i], _wrapPi(-math.atan2(ch.im[i], ch.re[i]))),
    ];
    return [EqLine('z', t, complex: true)];
  }
  EqLine line(Chain ch, bool flip, String name) {
    final t = <EqTerm>[
      for (var i = 0; i < k; i++)
        EqTerm(
          ch.r[i] * u,
          ch.f[i],
          _wrapPi(math.atan2(ch.im[i], ch.re[i]) + (flip ? math.pi : 0)),
        ),
    ];
    return EqLine(name, t, complex: false);
  }

  return [line(a.cx, false, 'x'), line(a.cy, true, 'y')];
}

String _pm(double v, int d) =>
    '${v < 0 ? ' - ' : ' + '}${v.abs().toStringAsFixed(d)}';

/// All terms as plain text that can be pasted into Python, Desmos and the like.
String equationText(List<EqLine> lines) {
  final sb = StringBuffer();
  for (final ln in lines) {
    final one = ln.complex;
    sb.write('${ln.name}(t) = ');
    for (var i = 0; i < ln.terms.length; i++) {
      final q = ln.terms[i];
      final arg = '2*pi*${q.f < 0 ? '(${q.f})' : q.f}*t${_pm(q.p, 4)}';
      sb.write(
        '${i == 0 ? '' : ' + '}${q.a.toStringAsFixed(5)}${one ? '*exp(i*($arg))' : '*cos($arg)'}',
      );
    }
    sb.write('\n');
  }
  return sb.toString();
}

/// The line spectrum as a tab-separated table: one row per term, sorted by frequency within each
/// component (z, or x and y). Lines starting with # are comments.
String spectrumTable(List<EqLine> lines) {
  final sb = StringBuffer();
  final complex = lines.isNotEmpty && lines.first.complex;
  sb.writeln('# Line spectrum of the outline');
  sb.writeln(
    complex
        ? '# z(t) = sum of amplitude * exp(i * (2*pi*frequency*t + phase)), t in [0, 1)'
        : '# x(t), y(t) = sum of amplitude * cos(2*pi*frequency*t + phase), t in [0, 1)',
  );
  sb.writeln(
    '# frequency in turns per loop${complex ? ' (negative = clockwise)' : ''}; '
    'amplitude in units of the largest circle; phase in radians',
  );
  sb.writeln('component\tfrequency\tamplitude\tphase');
  for (final ln in lines) {
    final terms = [...ln.terms]..sort((a, b) => a.f.compareTo(b.f));
    for (final q in terms) {
      sb.writeln(
        '${ln.name}\t${q.f}\t${q.a.toStringAsExponential(6)}\t${q.p.toStringAsFixed(6)}',
      );
    }
  }
  return sb.toString();
}
