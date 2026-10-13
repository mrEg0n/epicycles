// Choosing what to draw: the subjects detected by the system, retouchable with a brush (erase /
// add), or the whole image. A second step rotates the chosen shape.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/fourier_core.dart';
import '../core/gray_image.dart';
import '../core/select.dart';
import 'camera_page.dart';
import 'image_source.dart';
import 'prefs.dart';
import 'theme.dart';

/// The outcome of the selection.
class Selection {
  Selection(
    this.gray, {
    required this.isMask,
    this.cutout,
    this.blur = 2,
    this.rot = 0,
  });

  /// Rotation chosen for the shape, in radians.
  final double rot;

  /// The field the contours are extracted from.
  final GrayImage gray;

  /// Whether [gray] is a silhouette (dark object on a light background) rather than a photo.
  final bool isMask;

  /// The photo with only the chosen area, the rest transparent.
  final ui.Image? cutout;

  /// Softness chosen for the outline, in working-image pixels.
  final int blur;
}

class SelectPage extends StatefulWidget {
  const SelectPage({
    super.key,
    required this.photo,
    required this.path,
    this.confirmLabel = 'Draw',
    this.rotateHint = 'Turn the shape the way you want it drawn.',
    this.reticle = false,
    this.rotateSteps = 72,
  });
  final ui.Image photo;
  final String path;

  /// Label of the button that ends the selection, and the hint shown on the rotation step.
  final String confirmLabel, rotateHint;

  /// Draws a cross-hair over the shape on the rotation step, to align it by eye.
  final bool reticle;

  /// Number of steps of the rotation slider over the full turn (72 = 5 degrees each).
  final int rotateSteps;

  @override
  State<SelectPage> createState() => _SelectPageState();
}

class _SelectPageState extends State<SelectPage> {
  static const _channel = MethodChannel('epicicli/subjects');
  static const _muted = Color(0xFF8A8E98);
  static const _fill = Color(0x0FFFFFFF);
  // Brush radius, in screen points. Adjustable, and remembered from one photo to the next.
  double _brush = Prefs.number('brush', 18).clamp(6.0, _brushMax);
  static const _brushMax = 40.0;
  // The photo box, used to convert finger positions.
  final _imgKey = GlobalKey();
  // The brush sits just above the finger: the bottom of its circle stays 4 points above the
  // touched point, whatever its size.
  double get _lift => _brush + 4;

  WorkImage? _work;
  bool _loading = true;

  // One mask per detected subject, and which of them are selected.
  List<Uint8List> _subjects = const [];
  final Set<int> _picked = {};

  // Brush retouches: 1 = added, -1 = erased, 0 = untouched.
  Int8List _edit = Int8List(0);
  bool _edited = false;
  // 0 = choosing the shape, 1 = rotating it.
  bool _confirming =
      false; // the cut-out is being rendered: ignore further taps on Draw
  int _step = 0;
  // Rotation of the shape, in degrees (positive = clockwise).
  double _rotDeg = 0;
  // Screen points per point of the photo box, as last measured by [_measure].
  double _viewScale = 1;
  // Active tool: erase (true) or add (false).
  bool _erase = true;
  // Last brush point, in working-image pixels.
  Offset? _last;
  // Centre of the brush circle, in points of the photo box; null when it is hidden.
  Offset? _cursor;

  // Use the whole image instead of a silhouette.
  bool _whole = false;
  // Contours of the whole image, longest first; computed on first use.
  List<Float32List>? _wholeContours;

  // How much to soften the edge where it was retouched by hand, in working-image pixels.
  double _soft = Prefs.number('soft', 4).clamp(0.0, 12.0);
  // Outline detail: 10 = fine (no blur), 0 = very soft.
  double _detail = Prefs.number('detail', 8).clamp(0.0, 10.0);
  int get _blur => (10 - _detail).round();
  // The outline that will be drawn, in working-image pixels.
  Float32List? _contour;

  // The silhouette, 0-255, at the size of the working image, and whether it is non-empty.
  Uint8List _mask = Uint8List(0);
  bool _any = false;
  // The veil shown over the photo, and the state of its asynchronous refresh.
  ui.Image? _overlay;
  bool _veilBusy = false, _veilDirty = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    // Brush and outline settings are kept for the next photo.
    Prefs.setNumber('brush', _brush);
    Prefs.setNumber('soft', _soft);
    Prefs.setNumber('detail', _detail);
    _overlay?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final WorkImage work;
    try {
      work = await workFromImage(widget.photo);
    } catch (_) {
      // The photo cannot be read: there is nothing to select, so leave the page.
      if (mounted) Navigator.of(context).pop();
      return;
    }
    var subjects = <Uint8List>[];
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>('detect', {
        'path': widget.path,
        'maxSide': procSize,
      });
      final mw = (res?['width'] as int?) ?? 0,
          mh = (res?['height'] as int?) ?? 0;
      final masks = (res?['masks'] as List<Object?>?) ?? const [];
      if (mw > 1 && mh > 1) {
        subjects = [
          for (final m in masks)
            resampleMask(m as Uint8List, mw, mh, work.w, work.h),
        ];
      }
    } catch (_) {
      // No channel on this platform, or detection unavailable: continue without subjects.
    }
    if (!mounted) return;
    _work = work;
    _mask = Uint8List(work.w * work.h);
    _edit = Int8List(work.w * work.h);
    _subjects = subjects;
    _picked.addAll(List.generate(subjects.length, (i) => i));
    // With no detected subject, start from the whole image, with the brush set to add.
    _whole = subjects.isEmpty;
    _erase = subjects.isNotEmpty;
    _loading = false;
    _rebuild();
  }

  /// Recomputes the silhouette (selected subjects plus retouches, largest piece only), its outline
  /// and the veil.
  void _rebuild() {
    final work = _work;
    if (work == null) return;
    final n = work.w * work.h;
    _mask.fillRange(0, n, 0);
    for (final i in _picked) {
      final s = _subjects[i];
      for (var p = 0; p < n; p++) {
        if (s[p] > _mask[p]) _mask[p] = s[p];
      }
    }
    if (_edited) {
      for (var p = 0; p < n; p++) {
        final v = _edit[p];
        if (v != 0) _mask[p] = v > 0 ? 255 : 0;
      }
    }
    if (_edited) smoothEdits(_mask, _edit, work.w, work.h, _soft.round());
    keepLargest(_mask, work.w, work.h);
    _any = _mask.any((v) => v > 127);
    _recontour();
    _refreshVeil();
    setState(() {});
  }

  /// Rebuilds the dark veil covering what lies outside the silhouette. Only one rebuild runs at a
  /// time; a request arriving meanwhile triggers one more when it finishes.
  void _refreshVeil() {
    final work = _work;
    if (work == null) return;
    if (_veilBusy) {
      _veilDirty = true;
      return;
    }
    _veilBusy = true;
    final n = work.w * work.h;
    final veil = Uint8List(n * 4);
    for (var p = 0; p < n; p++) {
      veil[p * 4 + 3] = ((255 - _mask[p]) * 0.72).round();
    }
    ui.decodeImageFromPixels(veil, work.w, work.h, ui.PixelFormat.rgba8888, (
      img,
    ) {
      _veilBusy = false;
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() {
        _overlay?.dispose();
        _overlay = img;
      });
      if (_veilDirty) {
        _veilDirty = false;
        _refreshVeil();
      }
    });
  }

  /// The outline that will be drawn, computed the same way as for the drawing (blur, then the
  /// mid-level iso-line), keeping the longest contour.
  void _recontour() {
    final work = _work;
    _contour = null;
    if (work == null || !_any) return;
    final g = boxBlur(
      grayFromMask(_mask, work.w, work.h).gray,
      work.w,
      work.h,
      _blur,
    );
    final cs = marching(g, work.w, work.h, 128);
    if (cs.isEmpty) return;
    cs.sort((a, b) => b.len.compareTo(a.len));
    _contour = cs.first.p;
  }

  /// The contours of the whole image, as the drawing will extract them (automatic threshold),
  /// longest first.
  List<Float32List> _contoursOfWhole() {
    final cached = _wholeContours;
    if (cached != null) return cached;
    final work = _work!;
    final g = boxBlur(grayFromWork(work).gray, work.w, work.h, 1);
    final cs = marching(g, work.w, work.h, otsu(g).toDouble())
      ..sort((a, b) => b.len.compareTo(a.len));
    return _wholeContours = [for (final c in cs.take(120)) c.p];
  }

  Offset _toWork(Offset pos, Size box) {
    final work = _work!;
    return Offset(pos.dx / box.width * work.w, pos.dy / box.height * work.h);
  }

  /// A tap on a subject excludes it or brings it back.
  void _tap(Offset pos, Size box) {
    final work = _work;
    if (work == null || _whole) return;
    final q = _toWork(pos, box);
    final p =
        q.dy.floor().clamp(0, work.h - 1) * work.w +
        q.dx.floor().clamp(0, work.w - 1);
    for (var i = 0; i < _subjects.length; i++) {
      if (_subjects[i][p] > 127) {
        if (!_picked.remove(i)) _picked.add(i);
        _rebuild();
        break;
      }
    }
  }

  /// Shows the brush circle as soon as the finger touches the screen, before it starts moving, so
  /// that one can see where it will act and adjust before painting.
  /// [global] is the finger position on the screen; the circle is lifted above it by [_lift].
  void _hover(Offset global) {
    final rb = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || _loading || _whole) return;
    _measure(rb);
    setState(() => _cursor = rb.globalToLocal(global - Offset(0, _lift)));
  }

  /// The brush: dragging erases from or adds to the silhouette along the path of the finger, at
  /// screen position [global].
  void _pan(Offset global, {required bool start}) {
    final rb = _imgKey.currentContext?.findRenderObject() as RenderBox?;
    if (rb == null || _loading) return;
    _measure(rb);
    _stroke(rb.globalToLocal(global - Offset(0, _lift)), rb.size, start: start);
  }

  /// Measures how many screen points one point of the photo box spans, so that the brush keeps its
  /// on-screen size if an ancestor scales the page.
  void _measure(RenderBox rb) {
    final d =
        (rb.localToGlobal(const Offset(1, 0)) - rb.localToGlobal(Offset.zero))
            .distance;
    _viewScale = d > 0 ? d : 1;
  }

  /// Stamps the brush from the previous point of the stroke to [pos], which is in points of the
  /// photo box (of size [box]) and already lifted above the finger.
  void _stroke(Offset pos, Size box, {required bool start}) {
    final work = _work;
    if (work == null || _whole) return;
    final q = _toWork(pos, box);
    final r = (_brush / _viewScale * work.w / box.width).clamp(3.0, 120.0);
    final from = start ? q : (_last ?? q);
    final steps = ((q - from).distance / (r / 2)).ceil().clamp(1, 200);
    for (var i = 0; i <= steps; i++) {
      final c = Offset.lerp(from, q, i / steps)!;
      stampDisc(_edit, work.w, work.h, c.dx, c.dy, r, _erase ? -1 : 1);
    }
    _last = q;
    _cursor = pos;
    _edited = true;
    _rebuild();
  }

  void _reset() {
    _edit.fillRange(0, _edit.length, 0);
    _edited = false;
    _picked
      ..clear()
      ..addAll(List.generate(_subjects.length, (i) => i));
    _rebuild();
  }

  /// Cuts the photo, at full resolution, to the chosen area: outside the selection it is
  /// transparent.
  Future<ui.Image> _cutout(WorkImage work) async {
    final n = work.w * work.h;
    final alpha = Uint8List(n * 4);
    for (var p = 0; p < n; p++) {
      alpha[p * 4 + 3] = _mask[p];
    }
    final buf = await ui.ImmutableBuffer.fromUint8List(alpha);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: work.w,
      height: work.h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final maskImg =
        (await (await desc.instantiateCodec()).getNextFrame()).image;
    final photo = widget.photo;
    final full = Rect.fromLTWH(
      0,
      0,
      photo.width.toDouble(),
      photo.height.toDouble(),
    );
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.saveLayer(full, Paint());
    c.drawImage(photo, Offset.zero, Paint());
    c.drawImageRect(
      maskImg,
      Rect.fromLTWH(0, 0, work.w.toDouble(), work.h.toDouble()),
      full,
      // The silhouette is low-resolution: a slight blur removes the staircase from the cutout edge.
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: photo.width / work.w * 1.3,
          sigmaY: photo.width / work.w * 1.3,
        ),
    );
    c.restore();
    final pic = rec.endRecording();
    final out = await pic.toImage(photo.width, photo.height);
    pic.dispose();
    maskImg.dispose();
    return out;
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    _confirming = true;
    final work = _work!;
    final nav = Navigator.of(context);
    if (_whole) {
      nav.pop(
        Selection(
          grayFromWork(work),
          isMask: false,
          rot: _rotDeg * math.pi / 180,
        ),
      );
      return;
    }
    ui.Image? cut;
    try {
      cut = await _cutout(work);
    } catch (_) {
      // Without the cut-out the shape is still drawn; only the photo background is missing.
    }
    if (!mounted) {
      cut?.dispose();
      return;
    }
    nav.pop(
      Selection(
        grayFromMask(_mask, work.w, work.h),
        isMask: true,
        cutout: cut,
        blur: _blur,
        rot: _rotDeg * math.pi / 180,
      ),
    );
  }

  String get _hint {
    if (_loading) return 'Looking for subjects…';
    if (_whole) {
      return _subjects.isEmpty
          ? 'No subject found. This is the outline of the whole image; you can also paint a shape yourself.'
          : 'The whole image: the highlighted outline is the one that will be drawn.';
    }
    if (!_any) return 'Paint the shape with your finger, then press Draw.';
    return _erase
        ? 'Drag to erase parts of the shape. If you cut it in two, the larger piece is kept.'
        : 'Drag to add to the shape.';
  }

  /// Second step: the chosen shape alone, on a black background, to be rotated before drawing.
  Widget _rotateStep(BuildContext context) {
    final work = _work!;
    final outline = _whole
        ? (_contoursOfWhole().isEmpty ? null : _contoursOfWhole().first)
        : _contour;
    void turn(double d) => setState(() {
      var v = _rotDeg + d;
      if (v > 180) v -= 360;
      if (v < -180) v += 360;
      _rotDeg = v;
    });
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _step = 0),
                    child: const Text('Back', style: TextStyle(color: _muted)),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: outline == null ? null : _confirm,
                    child: Text(widget.confirmLabel),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: outline == null
                    ? const SizedBox()
                    : CustomPaint(
                        painter: _ShapePainter(
                          outline,
                          widget.photo,
                          work.w,
                          work.h,
                          _rotDeg * math.pi / 180,
                          reticle: widget.reticle,
                        ),
                        child: const SizedBox.expand(),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                widget.rotateHint,
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.4,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Rotate',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
                  Expanded(
                    child: Slider(
                      value: _rotDeg,
                      min: -180,
                      max: 180,
                      divisions: widget.rotateSteps,
                      onChanged: (v) => setState(() => _rotDeg = v),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${_rotDeg.round()}°',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'Menlo',
                        fontFamilyFallback: ['monospace'],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Wrap(
                spacing: 8,
                children: [
                  _pill('−90°', () => turn(-90)),
                  _pill('+90°', () => turn(90)),
                  if (_rotDeg != 0)
                    _pill('Reset', () => setState(() => _rotDeg = 0)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 1 && _work != null) return _rotateStep(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: _muted),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: !_loading && (_whole || _any)
                        ? () => setState(() => _step = 1)
                        : null,
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
            Expanded(child: _photoArea()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              // Fixed height (two lines), so that the photo does not move when the text changes.
              child: SizedBox(
                height: 38,
                child: Text(
                  _hint,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            // Each slider keeps its place even when hidden, for the same reason.
            Visibility(
              visible: !_loading && !_whole && _any,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                child: Row(
                  children: [
                    const Text(
                      'Detail',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                    Expanded(
                      child: Slider(
                        value: _detail,
                        min: 0,
                        max: 10,
                        divisions: 10,
                        onChanged: (v) => setState(() {
                          _detail = v;
                          _recontour();
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Brush size. While the slider moves, the brush circle is shown at the centre of the photo.
            Visibility(
              visible: !_loading && !_whole,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                child: SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      const Text(
                        'Brush size',
                        style: TextStyle(fontSize: 13, color: _muted),
                      ),
                      Expanded(
                        child: Slider(
                          value: _brush,
                          min: 6,
                          max: _brushMax,
                          onChanged: (v) => setState(() {
                            _brush = v;
                            final rb =
                                _imgKey.currentContext?.findRenderObject()
                                    as RenderBox?;
                            _cursor = rb?.size.center(Offset.zero);
                          }),
                          onChangeEnd: (_) => setState(() => _cursor = null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Smoothing of the hand-retouched areas only, to blend them into the detected outline.
            Visibility(
              visible: !_loading && !_whole && _edited,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                child: Row(
                  children: [
                    const Text(
                      'Brush smoothing',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                    Expanded(
                      child: Slider(
                        value: _soft,
                        min: 0,
                        max: 12,
                        divisions: 12,
                        onChanged: (v) {
                          _soft = v;
                          _rebuild();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _toolRow(),
          ],
        ),
      ),
    );
  }

  /// The photo with the veil, the outline and the brush circle, and the gestures acting on it.
  Widget _photoArea() {
    final photo = widget.photo;
    final work = _work;
    // Dragging works over this whole area, not just the photo: the brush sits above the finger, so
    // to reach the bottom edge the finger must be able to go below the photo.
    return Listener(
      // The circle follows the finger from the moment it touches, before the drag is recognised.
      onPointerDown: (e) => _hover(e.position),
      onPointerMove: (e) => _hover(e.position),
      onPointerUp: (_) => setState(() => _cursor = null),
      onPointerCancel: (_) => setState(() => _cursor = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The stroke starts where the finger first touched, which is where the circle was shown.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => _pan(d.globalPosition, start: true),
        onPanUpdate: (d) => _pan(d.globalPosition, start: false),
        child: Padding(
          // A free band below the photo, tall enough for the largest lift of the brush.
          padding: const EdgeInsets.fromLTRB(12, 0, 12, _brushMax + 18),
          child: Center(
            child: AspectRatio(
              aspectRatio: photo.width / photo.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    onTapUp: _loading
                        ? null
                        : (d) => _tap(d.localPosition, box.biggest),
                    child: Stack(
                      key: _imgKey,
                      fit: StackFit.expand,
                      children: [
                        RawImage(image: photo, fit: BoxFit.fill),
                        if (_whole && work != null)
                          CustomPaint(
                            painter: _WholePainter(
                              _contoursOfWhole(),
                              work.w,
                              work.h,
                            ),
                          )
                        else ...[
                          if (_overlay != null)
                            RawImage(
                              image: _overlay,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                          if (work != null)
                            CustomPaint(
                              painter: _ContourPainter(
                                _contour,
                                work.w,
                                work.h,
                                _cursor,
                                _brush / _viewScale,
                                _erase,
                              ),
                            ),
                        ],
                        if (_loading)
                          const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kInk,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The brush tools and the switch between subject and whole image.
  Widget _toolRow() => Container(
    height: 104, // always room for two rows of buttons
    alignment: Alignment.topLeft,
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!_loading && !_whole) ...[
          _toolPill('Erase', _erase, () => setState(() => _erase = true)),
          _toolPill('Add', !_erase, () => setState(() => _erase = false)),
          if (_edited || _picked.length != _subjects.length)
            _pill('Reset', _reset),
        ],
        if (!_loading)
          _pill(
            _whole
                ? (_subjects.isEmpty ? 'Paint a shape' : 'Back to the subject')
                : 'Use the whole image',
            () => setState(() {
              _whole = !_whole;
              if (!_whole && _subjects.isEmpty) _erase = false;
            }),
          ),
      ],
    ),
  );

  Widget _pill(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
  );

  /// Button for a brush tool: light when it is the active one.
  Widget _toolPill(String label, bool active, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: active ? kInk : _fill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? const Color(0xFF050506) : kInk,
            ),
          ),
        ),
      );
}

/// The chosen outline, traced over the photo, and the brush circle at [cursor].
class _ContourPainter extends CustomPainter {
  _ContourPainter(
    this.pts,
    this.w,
    this.h,
    this.cursor,
    this.brush,
    this.erase,
  );
  final Float32List? pts;
  final int w, h;
  final Offset? cursor;
  final double brush;
  final bool erase;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final c = pts;
    if (c != null && c.length >= 4) {
      final sx = size.width / w, sy = size.height / h;
      final path = Path()..moveTo(c[0] * sx, c[1] * sy);
      for (var i = 2; i < c.length; i += 2) {
        path.lineTo(c[i] * sx, c[i + 1] * sy);
      }
      path.close();
      canvas.drawPath(
        path,
        line
          ..color = const Color(0x808FA8FF)
          ..strokeWidth = 5,
      );
      canvas.drawPath(
        path,
        line
          ..color = kInk
          ..strokeWidth = 1.6,
      );
    }
    final at = cursor;
    if (at != null) {
      canvas.drawCircle(
        at,
        brush,
        line
          ..color = erase ? const Color(0xF2FFFFFF) : kAccent
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ContourPainter old) => true;
}

/// The contours of the whole image: the one that will be drawn (the longest) highlighted, the
/// others faint.
class _WholePainter extends CustomPainter {
  _WholePainter(this.contours, this.w, this.h);
  final List<Float32List> contours;
  final int w, h;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / w, sy = size.height / h;
    Path pathOf(Float32List c) {
      final path = Path()..moveTo(c[0] * sx, c[1] * sy);
      for (var i = 2; i < c.length; i += 2) {
        path.lineTo(c[i] * sx, c[i + 1] * sy);
      }
      return path..close();
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0x73000000),
    );
    for (var i = contours.length - 1; i >= 1; i--) {
      canvas.drawPath(
        pathOf(contours[i]),
        line
          ..color = const Color(0x59FFFFFF)
          ..strokeWidth = 0.8,
      );
    }
    if (contours.isNotEmpty) {
      final main = pathOf(contours.first);
      canvas.drawPath(
        main,
        line
          ..color = const Color(0x808FA8FF)
          ..strokeWidth = 5,
      );
      canvas.drawPath(
        main,
        line
          ..color = kInk
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WholePainter old) =>
      !identical(old.contours, contours);
}

/// The chosen shape alone on a black background: the photo clipped to the outline, with the
/// outline on top, rotated by [rot] radians about the centre. The scale is set from the diagonal of
/// the bounding box, so it does not change while rotating.
class _ShapePainter extends CustomPainter {
  _ShapePainter(
    this.pts,
    this.photo,
    this.w,
    this.h,
    this.rot, {
    this.reticle = false,
  });
  final Float32List pts;
  final ui.Image photo;
  final int w, h;
  final double rot;

  /// Cross-hair through the centre, open in the middle, as a guide for aligning the shape.
  final bool reticle;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.length < 6) return;
    var x0 = double.infinity,
        y0 = double.infinity,
        x1 = -double.infinity,
        y1 = -double.infinity;
    final path = Path()..moveTo(pts[0], pts[1]);
    for (var i = 0; i < pts.length; i += 2) {
      if (i > 0) path.lineTo(pts[i], pts[i + 1]);
      x0 = math.min(x0, pts[i]);
      x1 = math.max(x1, pts[i]);
      y0 = math.min(y0, pts[i + 1]);
      y1 = math.max(y1, pts[i + 1]);
    }
    path.close();
    final diag = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    if (diag <= 0) return;
    final sc = 0.92 * math.min(size.width, size.height) / diag;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rot);
    canvas.scale(sc);
    canvas.translate(-(x0 + x1) / 2, -(y0 + y1) / 2);
    // The photo, visible only inside the shape.
    canvas.save();
    canvas.clipPath(path);
    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      path,
      line
        ..color = const Color(0x808FA8FF)
        ..strokeWidth = 5 / sc,
    );
    canvas.drawPath(
      path,
      line
        ..color = kInk
        ..strokeWidth = 1.6 / sc,
    );
    canvas.restore();
    if (reticle) const ReticlePainter().paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) =>
      old.rot != rot || !identical(old.pts, pts);
}
