import 'dart:typed_data';

/// A luminance field (0-255), row-major, [w] x [h].
class GrayImage {
  GrayImage(this.gray, this.w, this.h);
  final Float32List gray;
  final int w, h;
}
