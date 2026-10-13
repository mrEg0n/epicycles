// Dumps the outline of a saved shape and its elliptic Fourier descriptors, for comparison with
// other implementations.
//
//   dart run tool/dump_efd.dart <field.bin> <width> <height> <blur> <out dir> [harmonics]
//
// Writes outline.txt (x y per line: the resampled closed path, upright and counter-clockwise),
// efd_raw.txt and efd_norm.txt (harmonic, a, b, c, d; the second after first-ellipse normalisation).

import 'dart:io';
import 'dart:typed_data';

import 'package:epicicli/core/efd.dart';
import 'package:epicicli/core/fourier_core.dart';

void main(List<String> args) {
  final bytes = File(args[0]).readAsBytesSync();
  final w = int.parse(args[1]),
      h = int.parse(args[2]),
      blur = int.parse(args[3]);
  final out = Directory(args[4])..createSync(recursive: true);
  final harmonics = args.length > 5 ? int.parse(args[5]) : 40;
  final gray = Float32List(bytes.length);
  for (var i = 0; i < gray.length; i++) {
    gray[i] = bytes[i].toDouble();
  }
  // Same parameters the app uses for a selected silhouette.
  final p = process(ProcessParams(gray, w, h, 128, 1, blur, 14, true))!.path;
  final (x, y) = uprightCounterClockwise(p.sx, p.sy);
  final o = StringBuffer();
  for (var j = 0; j < p.m; j++) {
    o.writeln('${x[j]} ${y[j]}');
  }
  File('${out.path}/outline.txt').writeAsStringSync(o.toString());

  void dump(String name, Efd e) {
    final b = StringBuffer();
    for (var i = 0; i < e.n; i++) {
      b.writeln('${i + 1} ${e.a[i]} ${e.b[i]} ${e.c[i]} ${e.d[i]}');
    }
    File('${out.path}/$name').writeAsStringSync(b.toString());
  }

  final raw = efdOfPath(p.sx, p.sy, harmonics);
  final norm = normaliseEfd(raw, keepOrientation: false);
  dump('efd_raw.txt', raw);
  dump('efd_norm.txt', norm.efd);
  stdout.writeln('samples ${p.m}, harmonics ${raw.n}, size ${norm.size}');
}
