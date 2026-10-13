// A measured outline and the table exported from a set of them. Pure Dart.

import 'dart:typed_data';

import '../core/efd.dart';

/// Harmonics computed and stored for every specimen; exports can use fewer.
const kStoredHarmonics = 40;

/// One outline with its raw descriptors.
class Specimen {
  Specimen({
    required this.id,
    required this.name,
    required this.group,
    required this.date,
    required this.detail,
    required this.rotation,
    required this.outline,
    required this.efd,
  });

  final String id;
  final String name, group;
  final DateTime date;

  /// Edge smoothing used when the outline was extracted (the Detail setting).
  final int detail;

  /// Rotation applied by the operator, in radians.
  final double rotation;

  /// The outline, upright, as x0, y0, x1, y1… in pixels of the working image, centred on the
  /// centroid.
  final Float64List outline;

  /// Raw coefficients in the same units: not normalised, so nothing is lost.
  final Efd efd;

  /// The same specimen under another name and group.
  Specimen renamed(String name, String group) => Specimen(
    id: id,
    name: name,
    group: group,
    date: date,
    detail: detail,
    rotation: rotation,
    outline: outline,
    efd: efd,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'group': group,
    'date': date.toIso8601String(),
    'detail': detail,
    'rotation': rotation,
    'outline': [for (final v in outline) double.parse(v.toStringAsFixed(3))],
    'a': efd.a.toList(),
    'b': efd.b.toList(),
    'c': efd.c.toList(),
    'd': efd.d.toList(),
  };

  static Specimen fromJson(Map<String, Object?> j) {
    Float64List list(String k) => Float64List.fromList([
      for (final v in j[k] as List) (v as num).toDouble(),
    ]);
    final a = list('a'), b = list('b'), c = list('c'), d = list('d');
    final outline = list('outline');
    if (a.isEmpty ||
        b.length != a.length ||
        c.length != a.length ||
        d.length != a.length) {
      throw const FormatException('coefficients');
    }
    if (outline.length.isOdd) throw const FormatException('outline');
    return Specimen(
      id: j['id'] as String,
      name: j['name'] as String,
      group: (j['group'] as String?) ?? '',
      date: DateTime.parse(j['date'] as String),
      detail: (j['detail'] as num).toInt(),
      rotation: (j['rotation'] as num).toDouble(),
      outline: outline,
      efd: Efd(a, b, c, d),
    );
  }
}

/// The descriptors of [specimens] as a tab-separated table, one row per specimen: name, group,
/// date, size, then A1…An, B1…Bn, C1…Cn, D1…Dn (the column order used by Momocs). Lines starting
/// with # are comments.
String efdTable(
  List<Specimen> specimens, {
  required int harmonics,
  required bool keepOrientation,
}) {
  final sb = StringBuffer();
  sb.writeln(
    '# Elliptic Fourier descriptors (Kuhl & Giardina 1982), $harmonics harmonics',
  );
  sb.writeln(
    '# x(t) = sum A_n cos(2 pi n t) + B_n sin(2 pi n t); y(t) = sum C_n cos(2 pi n t) + D_n sin(2 pi n t)',
  );
  sb.writeln(
    keepOrientation
        ? '# normalised for position, size and starting point; orientation as set by the operator'
        : '# normalised for position, size, starting point and orientation on the first ellipse',
  );
  sb.writeln(
    '# size = semi-major axis of the first ellipse, in pixels of the working image (not a physical length)',
  );
  final head = ['name', 'group', 'date', 'size'];
  for (final l in ['A', 'B', 'C', 'D']) {
    for (var n = 1; n <= harmonics; n++) {
      head.add('$l$n');
    }
  }
  sb.writeln(head.join('\t'));
  // Tabs and line breaks would split the row; # and quotes are read as comments and string
  // delimiters by R's read.table.
  String clean(String s) => s.replaceAll(RegExp(r'''[\t\r\n#"']'''), ' ');
  for (final s in specimens) {
    final n = normaliseEfd(s.efd, keepOrientation: keepOrientation);
    final row = [
      clean(s.name),
      clean(s.group),
      s.date.toIso8601String().substring(0, 10),
      n.size.toStringAsFixed(3),
    ];
    for (final l in [n.efd.a, n.efd.b, n.efd.c, n.efd.d]) {
      for (var i = 0; i < harmonics; i++) {
        row.add(i < l.length ? l[i].toStringAsExponential(6) : 'NA');
      }
    }
    sb.writeln(row.join('\t'));
  }
  return sb.toString();
}
