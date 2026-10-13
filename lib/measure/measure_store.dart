// Collections of specimens, stored in the app documents directory:
//   collections/<id>/collection.json   name and creation date
//   collections/<id>/<specimen id>.json one file per specimen

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'specimen.dart';

class Collection {
  Collection(this.id, this.name, this.created, this.dir, this.count);
  final String id, name;
  final DateTime created;
  final Directory dir;

  /// Number of specimens.
  final int count;
}

class MeasureStore {
  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/collections');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Iterable<File> _specimenFiles(Directory dir) =>
      dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json') && !f.path.endsWith('collection.json'),
      );

  /// All collections, most recent first. Unreadable ones are skipped.
  static Future<List<Collection>> collections() async {
    final root = await _root();
    final out = <Collection>[];
    await for (final e in root.list()) {
      if (e is! Directory) continue;
      try {
        final j = jsonDecode(
          await File('${e.path}/collection.json').readAsString(),
        ) as Map<String, Object?>;
        out.add(
          Collection(
            j['id'] as String,
            j['name'] as String,
            DateTime.parse(j['created'] as String),
            e,
            _specimenFiles(e).length,
          ),
        );
      } catch (_) {
        // Not a collection, or damaged: leave it alone.
      }
    }
    out.sort((a, b) => b.created.compareTo(a.created));
    return out;
  }

  static Future<Collection> create(String name) async {
    final root = await _root();
    final now = DateTime.now();
    final id = now.millisecondsSinceEpoch.toString();
    final dir = Directory('${root.path}/$id');
    await dir.create();
    await File('${dir.path}/collection.json').writeAsString(
      jsonEncode({'id': id, 'name': name, 'created': now.toIso8601String()}),
      flush: true,
    );
    return Collection(id, name, now, dir, 0);
  }

  static Future<void> delete(Collection c) => c.dir.delete(recursive: true);

  /// Gives [c] a new name and returns it as renamed.
  static Future<Collection> rename(Collection c, String name) async {
    await File('${c.dir.path}/collection.json').writeAsString(
      jsonEncode({
        'id': c.id,
        'name': name,
        'created': c.created.toIso8601String(),
      }),
      flush: true,
    );
    return Collection(c.id, name, c.created, c.dir, c.count);
  }

  /// The specimens of [c], oldest first. Unreadable files are skipped.
  static Future<List<Specimen>> specimens(Collection c) async {
    final out = <Specimen>[];
    for (final f in _specimenFiles(c.dir)) {
      try {
        out.add(
          Specimen.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, Object?>,
          ),
        );
      } catch (_) {
        // A damaged file does not hide the others.
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static Future<void> save(Collection c, Specimen s) =>
      File('${c.dir.path}/${s.id}.json')
          .writeAsString(jsonEncode(s.toJson()), flush: true);

  static Future<void> remove(Collection c, Specimen s) =>
      File('${c.dir.path}/${s.id}.json').delete();
}
