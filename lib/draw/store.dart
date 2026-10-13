// Shapes saved by the user, stored in the app documents directory, one subdirectory each:
//   meta.json  name, date, size and extraction parameters
//   field.bin  the field the contour is extracted from (mask or luminance), 8 bits per pixel
//   photo.png  the cropped photo shown under the drawing (optional)
//   thumb.png  thumbnail for the list
// The original photo is not saved: loading a shape goes straight back to the drawing.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../shared/image_source.dart';
import 'engine.dart';

/// Metadata of a saved shape and the directory holding its files.
class SavedShape {
  SavedShape(
    this.id,
    this.name,
    this.date,
    this.w,
    this.h,
    this.isMask,
    this.blur,
    this.rot,
    this.dir,
  );
  final String id, name;
  final DateTime date;
  final int w, h;
  final bool isMask;
  final int blur;
  final double rot;
  final Directory dir;

  File get photo => File('${dir.path}/photo.png');
  File get thumb => File('${dir.path}/thumb.png');
}

class Store {
  static Future<Directory> _root() async {
    final d = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/shapes',
    );
    await d.create(recursive: true);
    return d;
  }

  /// Saved shapes, most recent first. Unreadable entries are skipped.
  static Future<List<SavedShape>> list() async {
    final out = <SavedShape>[];
    try {
      await for (final e in (await _root()).list()) {
        if (e is! Directory) continue;
        try {
          final m = jsonDecode(
            await File('${e.path}/meta.json').readAsString(),
          ) as Map<String, dynamic>;
          out.add(
            SavedShape(
              m['id'] as String,
              m['name'] as String,
              DateTime.parse(m['date'] as String),
              m['w'] as int,
              m['h'] as int,
              m['isMask'] as bool,
              m['blur'] as int,
              (m['rot'] as num?)?.toDouble() ?? 0,
              e,
            ),
          );
        } catch (_) {
          // Incomplete or unreadable directory: skip it.
        }
      }
    } catch (_) {
      // Storage unavailable: return what was read so far.
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  /// Saves a shape and returns its id. With the [id] of an existing shape, overwrites it.
  static Future<String> save({
    String? id,
    required String name,
    required GrayImage field,
    required bool isMask,
    required int blur,
    double rot = 0,
    ui.Image? photo,
  }) async {
    final now = DateTime.now();
    final key = id ?? '${now.millisecondsSinceEpoch}';
    final dir = Directory('${(await _root()).path}/$key');
    await dir.create(recursive: true);
    // The field is stored at 8 bits: a rounding error of half a level does not move the contour.
    final bytes = Uint8List(field.gray.length);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = field.gray[i].round().clamp(0, 255);
    }
    await File('${dir.path}/field.bin').writeAsBytes(bytes, flush: true);
    final png = await photo?.toByteData(format: ui.ImageByteFormat.png);
    final pf = File('${dir.path}/photo.png');
    if (png != null) {
      await pf.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
    } else if (await pf.exists()) {
      await pf.delete();
    }
    try {
      await File('${dir.path}/thumb.png')
          .writeAsBytes(await _thumb(bytes, field.w, field.h), flush: true);
    } catch (_) {
      // The thumbnail is optional.
    }
    await File('${dir.path}/meta.json').writeAsString(
      jsonEncode({
        'id': key,
        'name': name,
        'date': now.toIso8601String(),
        'w': field.w,
        'h': field.h,
        'isMask': isMask,
        'blur': blur,
        'rot': rot,
      }),
      flush: true,
    );
    return key;
  }

  /// PNG thumbnail: the dark areas of the field (the shape) become light on a transparent
  /// background, cropped to their bounding box.
  static Future<Uint8List> _thumb(Uint8List field, int w, int h) async {
    var x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (field[y * w + x] < 128) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) {
      x0 = 0;
      y0 = 0;
      x1 = w - 1;
      y1 = h - 1;
    }
    const pad = 6;
    x0 = (x0 - pad).clamp(0, w - 1);
    y0 = (y0 - pad).clamp(0, h - 1);
    x1 = (x1 + pad).clamp(0, w - 1);
    y1 = (y1 + pad).clamp(0, h - 1);
    final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
    final rgba = Uint8List(cw * ch * 4);
    for (var y = 0; y < ch; y++) {
      for (var x = 0; x < cw; x++) {
        final a = 255 - field[(y + y0) * w + x + x0], i = (y * cw + x) * 4;
        // Premultiplied off-white, opaque where the shape is.
        rgba[i] = (242 * a) ~/ 255;
        rgba[i + 1] = (243 * a) ~/ 255;
        rgba[i + 2] = (245 * a) ~/ 255;
        rgba[i + 3] = a;
      }
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(rgba);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: cw,
      height: ch,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final img = (await (await desc.instantiateCodec()).getNextFrame()).image;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null) throw StateError('could not encode the thumbnail');
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  }

  /// Loads a saved shape: the field to extract the contour from and, if present, the background photo.
  static Future<(GrayImage, ui.Image?)> load(SavedShape s) async {
    final bytes = await File('${s.dir.path}/field.bin').readAsBytes();
    if (bytes.length != s.w * s.h) throw const FormatException('field size');
    final g = Float32List(bytes.length);
    for (var i = 0; i < g.length; i++) {
      g[i] = bytes[i].toDouble();
    }
    ui.Image? photo;
    if (await s.photo.exists()) {
      try {
        photo = await decodeImage(await s.photo.readAsBytes());
      } catch (_) {
        // An unreadable background photo is not fatal: the shape itself is in the field.
      }
    }
    return (GrayImage(g, s.w, s.h), photo);
  }

  static Future<void> delete(SavedShape s) => s.dir.delete(recursive: true);
}
