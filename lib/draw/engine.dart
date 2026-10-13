// State of the drawing machine: parameters, current analysis, time and reconstructed curve.
// Structural changes (new analysis, number of circles, mode) go through notifyListeners();
// frame-by-frame progress goes through [clock], so only the canvas repaints at 60 Hz.
//
// The "build" proceeds in turns. In each turn the chain has a given number of arms, makes one full
// rotation and the pen traces the best curve those arms can draw; at the end of the turn arms are
// added and it starts again, until all are present. The rhythm is selectable ([pace]): one arm per
// turn, or growing blocks, with turns of equal or decreasing duration.

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/equation.dart';
import '../core/fourier_core.dart';
import '../core/gray_image.dart';
import '../shared/prefs.dart';

export '../core/gray_image.dart';

/// Number of arms in the chain at each turn, up to [k].
/// By default one more per turn. With [blocks]: one at a time up to the sixth, then groups growing by 25%.
List<int> buildStages(int k, {bool blocks = false}) {
  if (!blocks) return List<int>.generate(k, (i) => i + 1);
  final s = <int>[];
  var n = 1.0;
  var last = 0;
  while (last < k) {
    final v = math.min(k, math.max(last + 1, n.round()));
    s.add(v);
    last = v;
    n = math.max(n + 1, n * 1.25);
  }
  return s;
}

class Engine extends ChangeNotifier {
  /// Incremented by [tick] whenever the frame to draw has changed.
  final ValueNotifier<int> clock = ValueNotifier<int>(0);

  /// Restores the persisted options (those that do not depend on the image).
  Engine() {
    one = Prefs.flag('one', one);
    pace = Prefs.integer('pace', pace).clamp(0, 2);
    dur = Prefs.number('dur', dur).clamp(4.0, 90.0);
    showCircles = Prefs.flag('showCircles', showCircles);
    showAxes = Prefs.flag('showAxes', showAxes);
    showSignals = Prefs.flag('showSignals', showSignals);
    bgImage = Prefs.flag('bgImage', bgImage);
  }

  void _save() {
    Prefs.setFlag('one', one);
    Prefs.setInteger('pace', pace);
    Prefs.setNumber('dur', dur);
    Prefs.setFlag('showCircles', showCircles);
    Prefs.setFlag('showAxes', showAxes);
    Prefs.setFlag('showSignals', showSignals);
    Prefs.setFlag('bgImage', bgImage);
  }

  /// The field the contours are extracted from; null when no image is loaded.
  GrayImage? src;

  /// Image shown under the drawing: the photo, cropped to the selected area.
  ui.Image? photo;

  /// Current analysis; null until one is available or when no contour was found.
  Analysis? a;

  /// The last analysis found no contour with the current parameters.
  bool noContours = false;

  // --- Contour extraction ---

  /// Threshold, number of threshold levels and blur radius.
  int thr = 128, levels = 1, blur = 1;

  /// Contours shorter than this are discarded.
  double minLen = 14;

  /// Keep only the longest contour: one closed line, no jumps.
  bool single = true;

  /// The source is the mask of a selected object rather than a whole photo.
  bool isMask = false;

  /// Rotation of the shape, in radians.
  double rot = 0;

  // --- Machine ---

  /// true = one complex chain, false = two chains (x and y).
  bool one = true;

  /// Number of arms chosen by hand with the slider; null = all.
  int? _scrub;

  /// Slider position set by hand; null while the build drives it.
  double? _scrubPos;

  /// Arms present before the current turn.
  int _stageFrom = 0;

  /// Glows, from 1 (just lit) to 0 (off): [flash] on the arms that just entered, [doneGlow] on the
  /// contour when the shape is complete.
  double flash = 0, doneGlow = 0;

  /// Number of arms the shape needs (per chain).
  int k = 1;

  /// Seconds per turn once the build is complete.
  double dur = 24;

  bool playing = true;

  /// Build rhythm: 0 = one arm per turn; 1 = blocks, equal turns; 2 = blocks, turns that speed up.
  int pace = 0;

  bool showCircles = true;

  /// Axes of the complex plane, with the projections of the pen.
  bool showAxes = true;

  /// The two traces over time, real and imaginary part (single chain only).
  bool showSignals = true;

  /// Fraction of the canvas, from the bottom, hidden by the settings panel.
  double cover = 0;

  /// Magnification of the view (1 = the whole sheet). When above 1 the view is centred on the pen,
  /// shifted by ([panX], [panY]) screen points at zoom 1, so it follows the pen as it moves.
  double zoom = 1;
  double panX = 0, panY = 0;

  static const maxZoom = 16.0;

  /// Back to the whole sheet.
  void resetView() {
    zoom = 1;
    panX = panY = 0;
  }

  /// Under the drawing: the translucent image (true) or just the contour (false).
  bool bgImage = false;

  /// Time, as a fraction of the current turn.
  double t = 0;

  // --- Build in turns ---

  bool building = false;

  /// Arms present at each turn (see [buildStages]) and the index of the current turn.
  List<int> stages = const [];
  int stage = 0;

  /// Arms from this index on entered during the current turn.
  int newFrom = 0;

  /// Whether [prevX], [prevY] hold the curve of the previous turn.
  bool hasPrev = false;
  Float32List prevX = Float32List(0), prevY = Float32List(0);

  /// Number of arms currently summed into [_accX], [_accY] over all samples.
  int nFull = 0;
  Float64List _accX = Float64List(0), _accY = Float64List(0);

  /// The curve to display.
  Float32List curX = Float32List(0), curY = Float32List(0);

  /// The displayed curve is not yet the sum of the target number of arms.
  bool _dirty = true;

  List<EqLine> equation = const [];

  bool _running = false, _again = false;

  /// Number of samples of the path.
  int get m => a?.m ?? 0;

  /// Number of arms available per chain.
  int get kMax => one ? m - 1 : m ~/ 2;

  /// Arms present right now (per chain).
  int get shown => math.min(k, nFull);

  /// Loads a new source and analyses it. With [mask] the source is an already clean mask: a
  /// single contour is enough, blurred by [maskBlur].
  Future<void> setSource(
    GrayImage g, {
    ui.Image? photo,
    bool mask = false,
    int maskBlur = 2,
    double rot = 0,
  }) {
    this.rot = rot;
    resetView();
    src = g;
    _replacePhoto(photo);
    isMask = mask;
    // Contour settings belong to the image: every new source starts from the defaults.
    blur = mask ? maskBlur : 1;
    levels = 1;
    single = true;
    minLen = 14;
    thr = otsu(boxBlur(g.gray, g.w, g.h, blur));
    return reprocess();
  }

  /// Swaps the background photo, releasing the previous one.
  void _replacePhoto(ui.Image? next) {
    final old = photo;
    photo = next;
    if (old != null && !identical(old, next)) old.dispose();
  }

  @override
  void dispose() {
    clock.dispose();
    photo?.dispose();
    super.dispose();
  }

  /// Back to the initial state: no image loaded.
  void clear() {
    src = null;
    a = null;
    _replacePhoto(null);
    noContours = false;
    notifyListeners();
  }

  /// Sets the threshold with Otsu's method and recomputes.
  void autoThreshold() {
    final g = src;
    if (g == null) return;
    thr = otsu(boxBlur(g.gray, g.w, g.h, blur));
    reprocess(animate: false);
  }

  static Future<Analysis?> _run(ProcessParams p) =>
      Isolate.run(() => process(p));

  bool _animate = true;

  /// Recomputes contours and spectrum in an isolate. A request arriving while one is running
  /// triggers a single rerun at the end. With [animate] false (used for parameter adjustments)
  /// the complete curve appears immediately, without replaying the build.
  Future<void> reprocess({bool animate = true}) async {
    final g = src;
    if (g == null) return;
    _animate = animate;
    notifyListeners();
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        final res = await _run(
          ProcessParams(
            g.gray,
            g.w,
            g.h,
            isMask ? 128 : thr,
            levels,
            blur,
            minLen,
            single,
            rot,
          ),
        );
        if (src != g) break;
        a = res;
        noContours = res == null;
        if (res != null) {
          _syncK();
          _startBuild();
          if (!_animate) _endBuild();
        }
        notifyListeners();
      } while (_again);
    } catch (_) {
      // The analysis failed (for example out of memory): show the empty state instead of stalling.
      a = null;
      noContours = true;
      notifyListeners();
    } finally {
      _running = false;
    }
    if (src != g) return reprocess();
  }

  void _syncK() {
    if (m == 0) return;
    // The number of arms is what this shape needs: the first that follows the contour within tolerance.
    k = ((one ? a!.errOne : a!.errTwo).length - 1).clamp(1, kMax);
    equation = equationLines(a!, one: one, k: k);
  }

  /// Resets the sum and restarts the build from the first turn, with a single arm.
  void _startBuild() {
    final n = m;
    _accX = Float64List(n);
    _accY = Float64List(n);
    curX = Float32List(n);
    curY = Float32List(n);
    prevX = Float32List(n);
    prevY = Float32List(n);
    nFull = 0;
    t = 0;
    stages = buildStages(k, blocks: pace != 0);
    stage = 0;
    newFrom = 0;
    hasPrev = false;
    _scrub = null;
    _scrubPos = null;
    _stageFrom = 0;
    flash = 1;
    doneGlow = 0;
    building = playing;
    _dirty = true;
  }

  /// Duration of build turn [i], scaled by the speed setting [dur]: the same for every turn,
  /// except with pace 2, where the first turns are slow and later ones get shorter.
  double _stageDur(int i) =>
      (pace == 2 ? math.max(1.4, 3.6 * math.pow(0.9, i)) : 2.6) * dur / 24;

  /// Marks the build as complete: all arms present, no previous curve to show.
  void _endBuild() {
    building = false;
    hasPrev = false;
    newFrom = k;
  }

  /// Shows the shape with [n] arms and stops the automatic build.
  void _setArms(int n) {
    final v = n.clamp(1, k);
    if (v != _scrub) flash = 1;
    _scrub = v;
    building = false;
    hasPrev = false;
    newFrom = v - 1; // keep the last arm highlighted
    doneGlow = 0;
    _dirty = true;
    notifyListeners();
  }

  /// Adds ([d] > 0) or removes ([d] < 0) arms by hand.
  void stepArm(int d) {
    if (m == 0) return;
    final n = ((_scrub ?? shown) + d).clamp(1, k);
    _scrubPos = n / k;
    _setArms(n);
  }

  /// Slider position, from 0 to 1: the fraction of arms present, so every arm gets the same
  /// travel. During the build it advances smoothly within a turn, following the rotation.
  double get progress {
    final p = _scrubPos;
    if (p != null) return p;
    if (a == null) return 0;
    if (!building || stages.isEmpty) return 1;
    return ((_stageFrom + t * (stages[stage] - _stageFrom)) / k).clamp(
      0.0,
      1.0,
    );
  }

  /// Sets the number of arms from slider position [pos] (0 to 1).
  void scrubTo(double pos) {
    if (m == 0) return;
    _scrubPos = pos;
    _setArms((pos * k).ceil());
  }

  /// Error with [n] arms: the maximum deviation between curve and contour (uniform norm), as a
  /// fraction of the longer side of the shape. It decreases down to the tolerance at which the
  /// build stops.
  double errorAt(int n) {
    final an = a;
    if (an == null) return 0;
    final errs = one ? an.errOne : an.errTwo;
    return errs[n.clamp(0, errs.length - 1)] / math.max(an.path.bw, an.path.bh);
  }

  /// Switches between one complex chain and two real chains, and restarts the build.
  void setMode({required bool oneChain}) {
    one = oneChain;
    resetView();
    _save();
    _syncK();
    _startBuild();
    notifyListeners();
  }

  /// Changes the build rhythm and restarts the build.
  void setPace(int v) {
    if (v == pace) return;
    pace = v;
    _save();
    if (a != null) {
      playing = true;
      _startBuild();
    }
    notifyListeners();
  }

  void togglePlay() {
    playing = !playing;
    _dirty = true;
    notifyListeners();
  }

  /// Whether the build is stopped partway, with fewer arms shown than the shape needs.
  bool get canResume => a != null && !building && shown < k;

  /// Play/pause button: resumes a build stopped partway, otherwise toggles the animation.
  void playPause() {
    if (canResume) {
      resume();
    } else {
      togglePlay();
    }
  }

  /// Resumes the build from the number of arms currently shown, up to the full equation.
  void resume() {
    if (!canResume || stages.isEmpty) return;
    final n = shown;
    var s = 0;
    while (s < stages.length - 1 && stages[s] <= n) {
      s++;
    }
    prevX.setAll(0, curX);
    prevY.setAll(0, curY);
    hasPrev = true;
    stage = s;
    _stageFrom = n;
    newFrom = n;
    t = 0;
    _scrub = null;
    _scrubPos = null;
    flash = 1;
    doneGlow = 0;
    building = true;
    playing = true;
    _dirty = true;
    notifyListeners();
  }

  /// Replays the build from the start.
  void restart() {
    if (a == null) return;
    playing = true;
    _startBuild();
    notifyListeners();
  }

  /// To be called after changing a display option directly: persists it and repaints.
  void touch() {
    _save();
    _dirty = true;
    notifyListeners();
  }

  /// Adds ([sign] = 1) or removes ([sign] = -1) the contribution of arm [i] over all samples.
  void _add(Analysis an, int i, double sign) {
    final m = an.m, cosT = an.cosT, sinT = an.sinT;
    if (one) {
      final ch = an.one, f = ch.f[i];
      final re = ch.re[i] * sign, im = ch.im[i] * sign;
      var q = 0;
      for (var j = 0; j < m; j++) {
        final c = cosT[q], s = sinT[q];
        _accX[j] += re * c - im * s;
        _accY[j] += re * s + im * c;
        q = (q + f) % m;
      }
    } else {
      final fx = an.cx.f[i], fy = an.cy.f[i];
      final xr = an.cx.re[i] * sign, xi = an.cx.im[i] * sign;
      final yr = an.cy.re[i] * sign, yi = an.cy.im[i] * sign;
      var qx = 0, qy = 0;
      for (var j = 0; j < m; j++) {
        _accX[j] += xr * cosT[qx] - xi * sinT[qx];
        _accY[j] += yr * cosT[qy] - yi * sinT[qy];
        qx = (qx + fx) % m;
        qy = (qy + fy) % m;
      }
    }
  }

  /// Curve to display: constant term + sum of the arms present.
  void _compose(Analysis an) {
    final x0 = one ? an.dc[0] : an.dc[2], y0 = one ? an.dc[1] : an.dc[3];
    for (var j = 0; j < an.m; j++) {
      curX[j] = _accX[j] + x0;
      curY[j] = _accY[j] + y0;
    }
  }

  /// Advances by [dt] seconds. Arms are added to or removed from the sum within a per-frame
  /// budget, so a large change is spread over several frames.
  void tick(double dt) {
    final an = a;
    if (an == null || _accX.length != an.m) return;
    var changed = _dirty;
    if (flash > 0 || doneGlow > 0) {
      flash = math.max(0, flash - dt / 1.1);
      doneGlow = math.max(0, doneGlow - dt / 2.2);
      changed = true;
    }
    if (playing) {
      changed = true;
      if (building) {
        t += dt / _stageDur(stage);
        if (t >= 1) {
          if (stage >= stages.length - 1) {
            // Last turn done: the curve is complete and the chain keeps rotating.
            _endBuild();
            t -= 1;
            doneGlow = 1;
          } else {
            // Turn done: the curve just traced stays in the background and the new arms enter.
            prevX.setAll(0, curX);
            prevY.setAll(0, curY);
            hasPrev = true;
            newFrom = stages[stage];
            _stageFrom = stages[stage];
            stage++;
            t = 0;
            flash = 1;
          }
        }
      } else {
        t += dt / dur;
        if (t >= 1) t -= 1;
      }
    }
    final target = building ? stages[stage] : math.min(k, _scrub ?? k);
    final budget = math.max(1, 3000000 ~/ an.m);
    var steps = 0;
    while (nFull < target && steps < budget) {
      _add(an, nFull, 1);
      nFull++;
      steps++;
    }
    while (nFull > target && steps < budget) {
      nFull--;
      _add(an, nFull, -1);
      steps++;
    }
    if (steps > 0 || _dirty) {
      _compose(an);
      changed = true;
    }
    _dirty = nFull != target;
    if (changed) clock.value++;
  }
}
