// A measured outline and the table exported from a set of them. Pure Dart.

import 'dart:convert';
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

/// Identifies a collection file and the version of its layout.
const kCollectionFormat = 'epicycles-collection';
const kCollectionVersion = 1;

/// A collection as one JSON document, to move it to another device or share it. Each specimen
/// carries its outline and its raw descriptors.
String collectionFile(String name, List<Specimen> specimens) {
  return jsonEncode({
    'format': kCollectionFormat,
    'version': kCollectionVersion,
    'name': name,
    'units': 'pixels',
    'specimens': [for (final s in specimens) s.toJson()],
  });
}

/// What was read from a collection file.
class ImportedCollection {
  ImportedCollection(this.name, this.specimens, this.skipped);
  final String name;
  final List<Specimen> specimens;

  /// Entries that could not be read.
  final int skipped;
}

/// Reads a collection file. Files written by other software are accepted too: a specimen needs
/// only an `outline` (x0, y0, x1, y1…, y up, any spacing); its descriptors are then computed here.
/// Name, group and date are optional. Throws a [FormatException] if the text is not a collection.
ImportedCollection parseCollectionFile(String text, {DateTime? now}) {
  final Object? doc;
  try {
    doc = jsonDecode(text);
  } catch (_) {
    throw const FormatException('not JSON');
  }
  if (doc is! Map ||
      doc['format'] != kCollectionFormat ||
      doc['specimens'] is! List) {
    throw const FormatException('not a collection');
  }
  final stamp = now ?? DateTime.now();
  final out = <Specimen>[];
  var skipped = 0;
  final list = doc['specimens'] as List;
  for (var i = 0; i < list.length; i++) {
    try {
      final j = Map<String, Object?>.from(list[i] as Map);
      Float64List numbers(Object? v) => Float64List.fromList([
        for (final e in v as List) (e as num).toDouble(),
      ]);
      var outline = numbers(j['outline']);
      if (outline.length < 6 || outline.length.isOdd) {
        throw const FormatException('outline');
      }
      final Efd efd;
      if (j['a'] is List &&
          j['b'] is List &&
          j['c'] is List &&
          j['d'] is List) {
        final a = numbers(j['a']),
            b = numbers(j['b']),
            c = numbers(j['c']),
            d = numbers(j['d']);
        if (a.isEmpty ||
            b.length != a.length ||
            c.length != a.length ||
            d.length != a.length) {
          throw const FormatException('coefficients');
        }
        efd = Efd(a, b, c, d);
      } else {
        final (e, resampled) = efdOfOutline(outline, kStoredHarmonics);
        efd = e;
        outline = resampled;
      }
      if (![...efd.a, ...efd.b, ...efd.c, ...efd.d].every((v) => v.isFinite)) {
        throw const FormatException('coefficients');
      }
      final date =
          DateTime.tryParse('${j['date']}') ??
          stamp.add(Duration(milliseconds: i));
      out.add(
        Specimen(
          // A fresh id, unique within the imported collection.
          id: '${stamp.microsecondsSinceEpoch + i}',
          name: (j['name'] as String?)?.trim().isNotEmpty == true
              ? (j['name'] as String).trim()
              : 'Specimen ${i + 1}',
          group: (j['group'] as String?)?.trim() ?? '',
          date: date,
          detail: (j['detail'] as num?)?.toInt() ?? 0,
          rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
          outline: outline,
          efd: efd,
        ),
      );
    } catch (_) {
      skipped++;
    }
  }
  final name = doc['name'];
  return ImportedCollection(
    name is String && name.trim().isNotEmpty
        ? name.trim()
        : 'Imported collection',
    out,
    skipped,
  );
}
