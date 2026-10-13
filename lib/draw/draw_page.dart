import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/equation.dart';
import '../shared/image_source.dart';
import '../shared/mode_glyphs.dart';
import '../shared/mode_intro.dart';
import '../shared/select_page.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';
import 'engine.dart';
import 'painter.dart';
import 'store.dart';

part 'equation_views.dart';
part 'saved_sheet.dart';
part 'settings_sheet.dart';

const _it = TextStyle(fontStyle: FontStyle.italic);
const _itInk = TextStyle(fontStyle: FontStyle.italic, color: kInk);
const _label = TextStyle(fontSize: 13, color: kMuted);

class DrawPage extends StatefulWidget {
  const DrawPage({super.key});

  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage>
    with SingleTickerProviderStateMixin {
  final engine = Engine();
  Duration _last = Duration.zero;
  bool _motionChecked = false;
  bool _picking = false;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
      _last = elapsed;
      engine.tick(dt);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    engine.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionChecked) {
      _motionChecked = true;
      if (MediaQuery.of(context).disableAnimations) engine.playing = false;
    }
  }

  // Identity of the current shape once it has been saved or reloaded: it
  // pre-fills the name field and lets a save under the same name overwrite it.
  String? _shapeId, _shapeName;

  /// Asks for a name and stores the current shape.
  Future<void> _save() async {
    final src = engine.src;
    if (src == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(initial: _shapeName ?? ''),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) return;
    try {
      // Same name: overwrite the stored shape. New name: create another one.
      final id = await Store.save(
        id: clean == _shapeName ? _shapeId : null,
        name: clean,
        field: src,
        isMask: engine.isMask,
        blur: engine.blur,
        rot: engine.rot,
        photo: engine.photo,
      );
      _shapeId = id;
      _shapeName = clean;
      messenger.showSnackBar(SnackBar(content: Text('Saved “$clean”.')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t save this shape.')),
      );
    }
  }

  /// Opens the list of saved shapes.
  void _openSaved() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SavedSheet(onLoad: _loadSaved),
    );
  }

  Future<void> _loadSaved(SavedShape s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final (field, photo) = await Store.load(s);
      _shapeId = s.id;
      _shapeName = s.name;
      await engine.setSource(
        field,
        photo: photo,
        mask: s.isMask,
        maskBlur: s.blur,
        rot: s.rot,
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t open this shape.')),
      );
    }
  }

  /// Leaves the drawing and goes back to the first screen of the mode.
  void _leaveDrawing() {
    _shapeId = null;
    _shapeName = null;
    engine.clear();
  }

  /// Closes the settings sheet and returns to the start screen of the app.
  void _backToStart() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Lets the user choose between the camera and the photo library.
  void _chooseSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _pick(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Choose from library'),
                onTap: () {
                  Navigator.of(sheet).pop();
                  _pick(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(ImageSource source) async {
    if (_picking) return;
    _picking = true;
    final messenger = ScaffoldMessenger.of(context);
    void fail(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    try {
      final XFile? file;
      try {
        file = await ImagePicker().pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
        );
      } catch (_) {
        fail(
          source == ImageSource.camera
              ? 'Can’t open the camera. Check the permission in Settings.'
              : 'Can’t open the photo library.',
        );
        return;
      }
      if (file == null) return;
      try {
        final photo = await decodeImage(await file.readAsBytes());
        if (!mounted) return;
        final sel = await Navigator.of(context).push<Selection>(
          MaterialPageRoute(
            builder: (_) => SelectPage(photo: photo, path: file!.path),
          ),
        );
        if (sel == null) {
          photo.dispose();
          return;
        }
        // The cut-out replaces the full photo as background.
        if (sel.cutout != null) {
          photo.dispose();
        }
        // A new shape, not saved yet.
        _shapeId = null;
        _shapeName = null;
        await engine.setSource(
          sel.gray,
          photo: sel.cutout ?? photo,
          mask: sel.isMask,
          maskBlur: sel.blur,
          rot: sel.rot,
        );
      } catch (_) {
        fail('Can’t read this image.');
      }
    } finally {
      _picking = false;
    }
  }

  void _openEquation() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EquationSheet(engine: engine),
    );
  }

  final _stageKey = GlobalKey();

  // Zoom at the start of the pinch in progress.
  double _zoomStart = 1;

  /// Opens the settings sheet. It takes at most 40% of the screen and, while
  /// it is open, the drawing shrinks into the part of the stage left visible.
  Future<void> _openSettings() async {
    final screen = MediaQuery.of(context).size.height;
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final top = box.localToGlobal(Offset.zero).dy, h = box.size.height;
      // 40% of content plus the drag handle and margins.
      final sheetTop = screen * 0.6 - 56;
      engine.cover = ((top + h - sheetTop) / h).clamp(0.0, 0.8);
      engine.touch();
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: Colors.transparent,
      builder: (_) => _SettingsSheet(engine: engine, onHome: _backToStart),
    );
    engine.cover = 0;
    engine.touch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: engine,
          builder: (context, _) => engine.src == null
              ? ModeIntro(
                  mode: Mode.draw,
                  title: 'Draw',
                  caption: 'Watch a shape being drawn, circle by circle',
                  onPick: _pick,
                  linkIcon: Icons.bookmarks_outlined,
                  linkLabel: 'Saved shapes',
                  onLink: _openSaved,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 8, 16, 10),
                      child: Row(
                        children: [
                          // Back to the first screen of Draw, where a new photo or a
                          // saved shape can be chosen.
                          IconButton(
                            onPressed: _leaveDrawing,
                            tooltip: 'Back',
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 22,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          const Text(
                            'Epicycles',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const Spacer(),
                          Segmented(
                            labels: const ['One chain', 'Two chains'],
                            index: engine.one ? 0 : 1,
                            onChanged: (i) => engine.setMode(oneChain: i == 0),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Container(
                        key: _stageKey,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: kStage,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kLine),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              // Two fingers zoom, a drag moves the zoomed view, a double tap
                              // goes back to the whole sheet.
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (_) => _zoomStart = engine.zoom,
                                onScaleUpdate: (d) {
                                  final z = (_zoomStart * d.scale).clamp(
                                    1.0,
                                    Engine.maxZoom,
                                  );
                                  engine.zoom = z;
                                  if (z > 1) {
                                    const reach = 600.0;
                                    engine.panX =
                                        (engine.panX - d.focalPointDelta.dx / z)
                                            .clamp(-reach, reach);
                                    engine.panY =
                                        (engine.panY - d.focalPointDelta.dy / z)
                                            .clamp(-reach, reach);
                                  } else {
                                    engine.panX = engine.panY = 0;
                                  }
                                  engine.touch();
                                },
                                onDoubleTap: () {
                                  engine.resetView();
                                  engine.touch();
                                },
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: EpiPainter(engine),
                                  ),
                                ),
                              ),
                            ),
                            // Counters, overlaid at the top of the stage.
                            Positioned(
                              left: 14,
                              top: 9,
                              right: 14,
                              child: ValueListenableBuilder<int>(
                                valueListenable: engine.clock,
                                // Shrinks to fit on narrow screens instead of being cut.
                                builder: (_, _, _) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.center,
                                  child: Text(
                                    _counters(engine),
                                    maxLines: 1,
                                    style: kMono.copyWith(
                                      fontSize: 11,
                                      color: kAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // The equation in compact form, centred at the bottom of the
                            // stage. The side margins leave room for the label on the right
                            // and keep the formula centred.
                            Positioned(
                              left: 76,
                              bottom: kFormulaBottom,
                              right: 76,
                              child: Align(
                                alignment: Alignment.center,
                                child: _EquationPreview(engine: engine),
                              ),
                            ),
                            // Opens the full equation. Fixed at the right, level with the
                            // middle of the formula block, so it does not move when the
                            // formula changes width.
                            Positioned(
                              right: 10,
                              bottom: kFormulaBottom,
                              height:
                                  kFormulaSum +
                                  kFormulaLine * (engine.one ? 1 : 2),
                              child: Center(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: engine.a == null
                                      ? null
                                      : _openEquation,
                                  child: Semantics(
                                    button: true,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5,
                                      ),
                                      // On two lines, so it stays clear of the
                                      // formula on narrow screens.
                                      child: const Text(
                                        'Expand\nequation',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (engine.noContours)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Text(
                                    'No outline with these settings.\nMove the threshold or lower the minimum length.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: kMuted,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    _SpectrumStrip(engine: engine),
                    // Arm slider: from one arm to the full equation. It advances
                    // on its own, can be dragged, and the side buttons remove
                    // or add one arm.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                      child: Row(
                        children: [
                          _StepButton(
                            icon: Icons.remove_rounded,
                            tooltip: 'Remove an arm',
                            onTap: () => engine.stepArm(-1),
                          ),
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: engine.clock,
                              // Larger than the settings sliders: this is the main control.
                              builder: (context, _, _) => SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 10,
                                    elevation: 0,
                                    pressedElevation: 0,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 22,
                                  ),
                                ),
                                child: Slider(
                                  value: engine.progress,
                                  onChanged: engine.a == null
                                      ? null
                                      : engine.scrubTo,
                                ),
                              ),
                            ),
                          ),
                          _StepButton(
                            icon: Icons.add_rounded,
                            tooltip: 'Add an arm',
                            onTap: () => engine.stepArm(1),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _chooseSource,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 18,
                            ),
                            label: const Text('New'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(
                              Icons.bookmark_add_outlined,
                              size: 18,
                            ),
                            label: const Text('Save'),
                            style: FilledButton.styleFrom(
                              backgroundColor: kFill,
                              foregroundColor: kInk,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          _RoundButton(
                            icon: Icons.replay_rounded,
                            tooltip: 'Restart',
                            onTap: engine.restart,
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            icon: engine.playing && !engine.canResume
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            tooltip: engine.playing && !engine.canResume
                                ? 'Pause'
                                : 'Play',
                            onTap: engine.playPause,
                          ),
                          const SizedBox(width: 8),
                          _RoundButton(
                            icon: Icons.tune_rounded,
                            tooltip: 'Settings',
                            onTap: _openSettings,
                            // Opens a sheet, like New: light, to set it apart
                            // from the playback controls.
                            light: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
