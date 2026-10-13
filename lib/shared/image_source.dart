// From the photo picked by the user to the working image and the luminance field the core operates on.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../core/gray_image.dart';

/// Longer side of the working image, in pixels.
const int procSize = 480;

/// The colour working image (RGBA, longer side at most [procSize]).
class WorkImage {
  WorkImage(this.rgba, this.w, this.h);
  final Uint8List rgba;
  final int w, h;
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  codec.dispose();
  return img;
}

/// Scales the photo to [procSize] on its longer side (upscaling at most 3x), over a white background.
Future<WorkImage> workFromImage(ui.Image img) async {
  final sc = math.min(3.0, procSize / math.max(img.width, img.height));
  final w = math.max(8, (img.width * sc).round()),
      h = math.max(8, (img.height * sc).round());
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  c.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final pic = rec.endRecording();
  final small = await pic.toImage(w, h);
  final bd = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
  small.dispose();
  pic.dispose();
  if (bd == null) throw StateError('could not read the image pixels');
  return WorkImage(
    bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes),
    w,
    h,
  );
}

/// Rec. 709 luminance of the working image.
GrayImage grayFromWork(WorkImage wk) {
  final g = Float32List(wk.w * wk.h);
  for (var i = 0, j = 0; i < g.length; i++, j += 4) {
    g[i] =
        0.2126 * wk.rgba[j] + 0.7152 * wk.rgba[j + 1] + 0.0722 * wk.rgba[j + 2];
  }
  return GrayImage(g, wk.w, wk.h);
}

/// From a mask (255 = object) to the field the core operates on: dark object on a light background.
GrayImage grayFromMask(Uint8List mask, int w, int h) {
  final g = Float32List(w * h);
  for (var i = 0; i < g.length; i++) {
    g[i] = 255.0 - mask[i];
  }
  return GrayImage(g, w, h);
}
