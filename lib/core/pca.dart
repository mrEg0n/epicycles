// Principal component analysis of a small table of samples. Pure Dart.

import 'dart:math' as math;
import 'dart:typed_data';

/// The result of [pca].
class Pca {
  Pca(this.mean, this.axes, this.variance, this.scores, this.totalVariance);

  /// Mean of each variable.
  final Float64List mean;

  /// Principal axes, one unit vector per component, in the space of the variables.
  final List<Float64List> axes;

  /// Variance of the samples along each axis.
  final Float64List variance;

  /// Coordinates of each sample on the axes: scores[sample][component].
  final List<Float64List> scores;

  /// Sum of the variances of all variables.
  final double totalVariance;
}

/// Eigenvalues and eigenvectors of the symmetric matrix [a] (n x n, row-major) by Jacobi
/// rotations. Returns the eigenvalues in decreasing order and the matching eigenvectors.
(Float64List, List<Float64List>) symmetricEigen(Float64List a, int n) {
  final m = Float64List.fromList(a);
  final v = Float64List(n * n);
  for (var i = 0; i < n; i++) {
    v[i * n + i] = 1;
  }
  for (var sweep = 0; sweep < 100; sweep++) {
    var off = 0.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        off += m[i * n + j] * m[i * n + j];
      }
    }
    if (off < 1e-22) break;
    for (var p = 0; p < n; p++) {
      for (var q = p + 1; q < n; q++) {
        final apq = m[p * n + q];
        if (apq.abs() < 1e-300) continue;
        final theta = (m[q * n + q] - m[p * n + p]) / (2 * apq);
        final t =
            (theta >= 0 ? 1 : -1) /
            (theta.abs() + math.sqrt(theta * theta + 1));
        final c = 1 / math.sqrt(t * t + 1), s = t * c;
        for (var k = 0; k < n; k++) {
          final akp = m[k * n + p], akq = m[k * n + q];
          m[k * n + p] = c * akp - s * akq;
          m[k * n + q] = s * akp + c * akq;
        }
        for (var k = 0; k < n; k++) {
          final apk = m[p * n + k], aqk = m[q * n + k];
          m[p * n + k] = c * apk - s * aqk;
          m[q * n + k] = s * apk + c * aqk;
        }
        for (var k = 0; k < n; k++) {
          final vkp = v[k * n + p], vkq = v[k * n + q];
          v[k * n + p] = c * vkp - s * vkq;
          v[k * n + q] = s * vkp + c * vkq;
        }
      }
    }
  }
  final order = List<int>.generate(n, (i) => i)
    ..sort((i, j) => m[j * n + j].compareTo(m[i * n + i]));
  final values = Float64List(n);
  final vectors = <Float64List>[];
  for (var r = 0; r < n; r++) {
    final k = order[r];
    values[r] = m[k * n + k];
    final e = Float64List(n);
    for (var i = 0; i < n; i++) {
      e[i] = v[i * n + k];
    }
    vectors.add(e);
  }
  return (values, vectors);
}

/// Principal components of [rows] (samples of equal length), on the covariance matrix: variables
/// are centred but not rescaled. At most [components] axes are returned, fewer if the samples do
/// not span that many.
///
/// The decomposition is done on the sample-by-sample matrix, which is small when there are fewer
/// samples than variables, as is usual here.
Pca pca(List<Float64List> rows, {int components = 2}) {
  final n = rows.length, p = rows.first.length;
  final mean = Float64List(p);
  for (final r in rows) {
    for (var j = 0; j < p; j++) {
      mean[j] += r[j] / n;
    }
  }
  final x = [
    for (final r in rows)
      Float64List.fromList([for (var j = 0; j < p; j++) r[j] - mean[j]]),
  ];
  final g = Float64List(n * n);
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    for (var k = i; k < n; k++) {
      var s = 0.0;
      for (var j = 0; j < p; j++) {
        s += x[i][j] * x[k][j];
      }
      g[i * n + k] = g[k * n + i] = s / (n - 1);
    }
    total += g[i * n + i];
  }
  final (values, vectors) = symmetricEigen(g, n);
  final axes = <Float64List>[];
  final variance = <double>[];
  for (var c = 0; c < math.min(components, n - 1); c++) {
    final lambda = values[c];
    if (lambda <= 1e-12 * math.max(total, 1e-300)) break;
    final w = Float64List(p);
    final k = 1 / math.sqrt((n - 1) * lambda);
    for (var i = 0; i < n; i++) {
      final u = vectors[c][i] * k;
      for (var j = 0; j < p; j++) {
        w[j] += x[i][j] * u;
      }
    }
    axes.add(w);
    variance.add(lambda);
  }
  final scores = [
    for (var i = 0; i < n; i++)
      Float64List.fromList([
        for (final w in axes)
          () {
            var s = 0.0;
            for (var j = 0; j < p; j++) {
              s += x[i][j] * w[j];
            }
            return s;
          }(),
      ]),
  ];
  return Pca(mean, axes, Float64List.fromList(variance), scores, total);
}
