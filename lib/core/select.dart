// Operations on the mask of the object picked by the user. Pure Dart.

import 'dart:typed_data';

/// Resamples a mask from [sw] x [sh] to [dw] x [dh] by nearest neighbour.
Uint8List resampleMask(Uint8List src, int sw, int sh, int dw, int dh) {
  if (sw == dw && sh == dh) return src;
  final out = Uint8List(dw * dh);
  for (var y = 0; y < dh; y++) {
    final yy = (y * sh ~/ dh) * sw;
    for (var x = 0; x < dw; x++) {
      out[y * dw + x] = src[yy + x * sw ~/ dw];
    }
  }
  return out;
}

/// Brush: writes [value] into the edit layer over a disc of centre ([cx], [cy]) and radius [r].
/// In the layer 1 = added by hand, -1 = removed by hand, 0 = untouched.
void stampDisc(
  Int8List layer,
  int w,
  int h,
  double cx,
  double cy,
  double r,
  int value,
) {
  final x0 = (cx - r).floor().clamp(0, w - 1),
      x1 = (cx + r).ceil().clamp(0, w - 1);
  final y0 = (cy - r).floor().clamp(0, h - 1),
      y1 = (cy + r).ceil().clamp(0, h - 1);
  final r2 = r * r;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      final dx = x - cx, dy = y - cy;
      if (dx * dx + dy * dy <= r2) layer[y * w + x] = value;
    }
  }
}

/// Keeps only the largest 4-connected component of the mask (pixels above 127) and clears the
/// others, so that a cut splitting the mask leaves just its main part.
void keepLargest(Uint8List mask, int w, int h) {
  final n = w * h;
  final label = Int32List(n); // 0 = not visited or outside the mask
  final stack = Int32List(n);
  var next = 0, best = 0, bestSize = 0;
  for (var s = 0; s < n; s++) {
    if (mask[s] <= 127 || label[s] != 0) continue;
    next++;
    var top = 0, size = 0;
    stack[top++] = s;
    label[s] = next;
    while (top > 0) {
      final p = stack[--top];
      size++;
      final x = p % w;
      if (x > 0 && mask[p - 1] > 127 && label[p - 1] == 0) {
        label[p - 1] = next;
        stack[top++] = p - 1;
      }
      if (x < w - 1 && mask[p + 1] > 127 && label[p + 1] == 0) {
        label[p + 1] = next;
        stack[top++] = p + 1;
      }
      if (p >= w && mask[p - w] > 127 && label[p - w] == 0) {
        label[p - w] = next;
        stack[top++] = p - w;
      }
      if (p < n - w && mask[p + w] > 127 && label[p + w] == 0) {
        label[p + w] = next;
        stack[top++] = p + w;
      }
    }
    if (size > bestSize) {
      bestSize = size;
      best = next;
    }
  }
  if (next <= 1) return;
  // The kept component also owns its soft edge (values at or below 127), reached by growing from
  // it through non-zero pixels. Everything else, including the halo of the discarded components,
  // is cleared.
  final keep = Uint8List(n);
  var top = 0;
  for (var p = 0; p < n; p++) {
    if (label[p] == best) {
      keep[p] = 1;
      stack[top++] = p;
    }
  }
  while (top > 0) {
    final p = stack[--top];
    final x = p % w;
    void visit(int q) {
      if (keep[q] == 0 && mask[q] > 0 && mask[q] <= 127) {
        keep[q] = 1;
        stack[top++] = q;
      }
    }

    if (x > 0) visit(p - 1);
    if (x < w - 1) visit(p + 1);
    if (p >= w) visit(p - w);
    if (p < n - w) visit(p + w);
  }
  for (var p = 0; p < n; p++) {
    if (keep[p] == 0) mask[p] = 0;
  }
}

/// Mean of each pixel over a square of side 2r+1, using a summed-area table (cost independent of r).
Float32List _boxMean(Float32List src, int w, int h, int r) {
  final sat = Float64List((w + 1) * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0.0;
    for (var x = 0; x < w; x++) {
      row += src[y * w + x];
      sat[(y + 1) * (w + 1) + x + 1] = sat[y * (w + 1) + x + 1] + row;
    }
  }
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = (y - r).clamp(0, h), y1 = (y + r + 1).clamp(0, h);
    for (var x = 0; x < w; x++) {
      final x0 = (x - r).clamp(0, w), x1 = (x + r + 1).clamp(0, w);
      final s =
          sat[y1 * (w + 1) + x1] -
          sat[y0 * (w + 1) + x1] -
          sat[y1 * (w + 1) + x0] +
          sat[y0 * (w + 1) + x0];
      out[y * w + x] = s / ((x1 - x0) * (y1 - y0));
    }
  }
  return out;
}

/// Softens the edge of the mask only where it was edited by hand, leaving the rest untouched.
///
/// The brush leaves hard edges made of circular arcs, with corners where strokes meet, whereas the
/// mask detected by the system has a soft edge. Around edited pixels ([edit] non-zero) the mask
/// value is replaced by its local mean over radius [r]: the edge becomes a gradient and the
/// contour, which runs along its half level, is rounded.
void smoothEdits(Uint8List mask, Int8List edit, int w, int h, int r) {
  if (r < 1) return;
  final n = w * h;
  final hard = Float32List(n), touched = Float32List(n);
  for (var p = 0; p < n; p++) {
    hard[p] = mask[p] > 127 ? 1 : 0;
    touched[p] = edit[p] != 0 ? 1 : 0;
  }
  // Two mean passes: a rounder kernel than a single square.
  final soft = _boxMean(_boxMean(hard, w, h, r), w, h, r);
  // Non-zero where at least one edited pixel lies within reach of the smoothing kernel.
  final near = _boxMean(touched, w, h, 2 * r + 1);
  for (var p = 0; p < n; p++) {
    if (near[p] > 0) mask[p] = (soft[p] * 255).round().clamp(0, 255);
  }
}
