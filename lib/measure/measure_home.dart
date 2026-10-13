// Measure mode: collections of outlines, the review of a new specimen, and the export of the
// shape descriptors.

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/efd.dart';
import '../core/fourier_core.dart';

import 'package:image_picker/image_picker.dart';

import '../shared/mode_glyphs.dart';
import '../shared/mode_intro.dart';
import '../shared/pick.dart';
import '../shared/prefs.dart';
import '../shared/theme.dart';
import '../shared/widgets.dart';
import 'collection_views.dart';
import 'measure_store.dart';
import 'specimen.dart';

/// Harmonics drawn over the outline when a specimen is reviewed.
const _previewHarmonics = 20;

/// Extracts the outline of a selected shape and its raw descriptors. Null if no outline is found.
/// Takes plain data only, so that it can run in a background isolate.
(Float64List, Efd)? _measure(
  Float32List gray,
  int w,
  int h,
  bool isMask,
  int detail,
  double rot,
) {
  final blur = isMask ? detail : 1;
  final thr = isMask ? 128 : otsu(boxBlur(gray, w, h, blur));
  final an = process(ProcessParams(gray, w, h, thr, 1, blur, 14, true, rot));
  if (an == null) return null;
  final p = an.path;
  final (x, y) = uprightCounterClockwise(p.sx, p.sy);
  final outline = Float64List(p.m * 2);
  for (var j = 0; j < p.m; j++) {
    outline[2 * j] = x[j];
    outline[2 * j + 1] = y[j];
  }
  return (outline, efdOfPath(p.sx, p.sy, kStoredHarmonics));
}

/// Runs [_measure] in a background isolate. A top-level function, so that the closure sent to
/// the isolate holds only the plain arguments.
Future<(Float64List, Efd)?> _measureInBackground(
  Float32List gray,
  int w,
  int h,
  bool isMask,
  int detail,
  double rot,
) => Isolate.run(() => _measure(gray, w, h, isMask, detail, rot));

Widget _header(BuildContext context, String title, {Widget? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, size: 22),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Adds a specimen to [collection] from a photo taken with [source]: selection, measurement,
/// review. Returns true if a specimen was saved. Failures are reported with a snack bar.
Future<bool> addSpecimen(
  BuildContext context,
  Collection collection,
  ImageSource source,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final sel = await pickSelection(
      context,
      source,
      confirmLabel: 'Measure',
      rotateHint: 'Align the shape with the cross-hair, the same way for every specimen.',
      reticle: true,
      rotateSteps: 360,
    );
    if (sel == null) return false;
    final g = sel.gray;
    final res = await _measureInBackground(
      g.gray,
      g.w,
      g.h,
      sel.isMask,
      sel.blur,
      sel.rot,
    );
    if (res == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No outline found in this shape.')),
      );
      return false;
    }
    final items = await MeasureStore.specimens(collection);
    final saved = await navigator.push<Specimen>(
      MaterialPageRoute(
        builder: (_) => SpecimenPage(
          outline: res.$1,
          efd: res.$2,
          detail: sel.isMask ? sel.blur : 1,
          rotation: sel.rot,
          suggestedName: 'Specimen ${items.length + 1}',
          suggestedGroup: items.isEmpty ? '' : items.last.group,
        ),
      ),
    );
    if (saved == null) return false;
    await MeasureStore.save(collection, saved);
    return true;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Couldn’t add this specimen.')),
    );
    return false;
  }
}

const _currentKey = 'measure.collection';

/// First screen of the Measure mode: photos go into the current collection.
class MeasureHome extends StatefulWidget {
  const MeasureHome({super.key});

  @override
  State<MeasureHome> createState() => _MeasureHomeState();
}

class _MeasureHomeState extends State<MeasureHome> {
  List<Collection> _all = const [];
  Collection? _current;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Reads the collections again; the current one is the last used, or the most recent.
  Future<void> _reload() async {
    List<Collection> all;
    try {
      all = await MeasureStore.collections();
    } catch (_) {
      all = [];
    }
    if (!mounted) return;
    final id = Prefs.text(_currentKey);
    setState(() {
      _all = all;
      _current = all.isEmpty
          ? null
          : all.firstWhere((c) => c.id == id, orElse: () => all.first);
    });
  }

  Future<Collection?> _create() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const NameDialog(
        initial: '',
        title: 'New collection',
        confirm: 'Create',
      ),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty) return null;
    final Collection c;
    try {
      c = await MeasureStore.create(clean);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t create the collection.')),
      );
      return null;
    }
    Prefs.setText(_currentKey, c.id);
    await _reload();
    return c;
  }

  /// Reads a collection file chosen by the user and adds it as a new collection.
  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Collection',
            extensions: ['json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null) return;
      final ImportedCollection read;
      try {
        read = parseCollectionFile(await file.readAsString());
      } on FormatException {
        say('This file is not a collection.');
        return;
      }
      if (read.specimens.isEmpty) {
        say('No specimen could be read from this file.');
        return;
      }
      // An existing name is kept apart rather than merged into.
      final taken = _all.any((c) => c.name == read.name);
      final c = await MeasureStore.create(
        taken ? '${read.name} (imported)' : read.name,
      );
      for (final s in read.specimens) {
        await MeasureStore.save(c, s);
      }
      Prefs.setText(_currentKey, c.id);
      await _reload();
      final n = read.specimens.length;
      say(
        'Imported $n ${n == 1 ? 'specimen' : 'specimens'}'
        '${read.skipped > 0 ? ', ${read.skipped} skipped' : ''}.',
      );
      final current = _current;
      if (mounted && current != null) await _open(current);
    } catch (_) {
      say('Couldn’t import this file.');
    }
  }

  Future<void> _open(Collection c) async {
    Prefs.setText(_currentKey, c.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CollectionPage(collection: c)),
    );
    _reload();
  }

  /// A photo becomes a specimen of the current collection, created first if there is none.
  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    _busy = true;
    try {
      final c = _current ?? await _create();
      if (c == null || !mounted) return;
      final added = await addSpecimen(context, c, source);
      if (added && mounted) await _open(c);
    } finally {
      _busy = false;
    }
  }

  void _showCollections() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_all.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(28, 4, 28, 12),
                  child: Text(
                    'A collection holds the outlines you want to compare.',
                    style: TextStyle(color: kMuted, height: 1.5),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _all)
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 22,
                          ),
                          title: Text(c.name),
                          subtitle: Text(
                            '${c.count} ${c.count == 1 ? 'specimen' : 'specimens'}',
                            style: kMono.copyWith(fontSize: 11, color: kFaint),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: kFaint,
                          ),
                          onTap: () {
                            Navigator.of(sheet).pop();
                            _open(c);
                          },
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                child: Row(
                  children: [
                    Pill(
                      label: 'New collection',
                      onTap: () async {
                        Navigator.of(sheet).pop();
                        final c = await _create();
                        if (c != null && mounted) _open(c);
                      },
                    ),
                    const SizedBox(width: 10),
                    Pill(
                      label: 'Import from file',
                      onTap: () {
                        Navigator.of(sheet).pop();
                        _import();
                      },
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

  @override
  Widget build(BuildContext context) {
    final c = _current;
    return Scaffold(
      body: SafeArea(
        child: ModeIntro(
          mode: Mode.measure,
          title: 'Measure',
          caption: 'Collect outlines and export shape descriptors',
          // Where the next photo goes; tapping opens it.
          note: c == null
              ? null
              : Pill(
                  label:
                      '${c.name}  ·  ${c.count} ${c.count == 1 ? 'specimen' : 'specimens'}',
                  onTap: () => _open(c),
                ),
          onPick: _pick,
          linkIcon: Icons.folder_outlined,
          linkLabel: 'Collections',
          onLink: _showCollections,
        ),
      ),
    );
  }
}

/// The specimens of one collection.
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.collection});
  final Collection collection;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List<Specimen>? _items;
  bool _busy = false;

  // 0 = list of specimens, 1 = outlines overlaid, 2 = statistics.
  int _view = 0;

  // The collection as last renamed.
  late Collection _c = widget.collection;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    List<Specimen> items;
    try {
      items = await MeasureStore.specimens(_c);
    } catch (_) {
      items = [];
    }
    if (mounted) setState(() => _items = items);
  }

  Future<void> _add() async {
    if (_busy) return;
    final source = await chooseImageSource(context);
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    try {
      if (await addSpecimen(context, _c, source)) await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameCollection() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        initial: _c.name,
        title: 'Rename collection',
        confirm: 'Rename',
      ),
    );
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || clean == _c.name) return;
    try {
      final c = await MeasureStore.rename(_c, clean);
      if (mounted) setState(() => _c = c);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t rename the collection.')),
      );
    }
  }

  /// Changes the name and the group of a specimen.
  Future<void> _edit(Specimen s) async {
    final messenger = ScaffoldMessenger.of(context);
    final edited = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _SpecimenDialog(name: s.name, group: s.group),
    );
    if (edited == null) return;
    final name = edited.$1.trim(), group = edited.$2.trim();
    if (name.isEmpty || (name == s.name && group == s.group)) return;
    try {
      await MeasureStore.save(_c, s.renamed(name, group));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t save the change.')),
      );
    }
    _reload();
  }

  Future<void> _remove(Specimen s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kSheet,
        title: const Text(
          'Delete this specimen?',
          style: TextStyle(fontSize: 17),
        ),
        content: Text('“${s.name}” will be removed from the collection.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MeasureStore.remove(_c, s);
    } catch (_) {
      // Already gone: the reload below shows the current state.
    }
    _reload();
  }

  Future<void> _deleteCollection() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kSheet,
        title: const Text(
          'Delete this collection?',
          style: TextStyle(fontSize: 17),
        ),
        content: Text('“${_c.name}” and all its specimens will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MeasureStore.delete(_c);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t delete this collection.')),
      );
      return;
    }
    navigator.pop();
  }

  void _export() {
    final items = _items;
    if (items == null || items.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSheet,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ExportSheet(collection: _c, specimens: items),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(
              context,
              _c.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _renameCollection,
                    tooltip: 'Rename collection',
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 20,
                      color: kMuted,
                    ),
                  ),
                  IconButton(
                    onPressed: _deleteCollection,
                    tooltip: 'Delete collection',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: kMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Segmented(
                labels: const ['Specimens', 'Overlay', 'Statistics'],
                index: _view,
                onChanged: (i) => setState(() => _view = i),
                expand: true,
              ),
            ),
            Expanded(
              child: items == null
                  ? const SizedBox()
                  : _view == 1
                  ? OverlayView(specimens: items)
                  : _view == 2
                  ? StatisticsView(specimens: items)
                  : items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(36),
                        child: Text(
                          'No specimens yet.\nAdd one from a photo.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kMuted, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final s = items[i];
                        return ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(
                            22,
                            2,
                            10,
                            2,
                          ),
                          leading: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: kStage,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: CustomPaint(
                              painter: _OutlinePainter(s.outline, null),
                            ),
                          ),
                          onTap: () => _edit(s),
                          title: Text('${i + 1}  ·  ${s.name}'),
                          subtitle: Text(
                            [
                              if (s.group.isNotEmpty) s.group,
                              s.date.toIso8601String().substring(0, 10),
                            ].join('  ·  '),
                            style: kMono.copyWith(fontSize: 11, color: kFaint),
                          ),
                          trailing: IconButton(
                            onPressed: () => _remove(s),
                            tooltip: 'Delete',
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: kMuted,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _add,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add specimen'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: items == null || items.isEmpty
                          ? null
                          : _export,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Export'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kFill,
                        foregroundColor: kInk,
                        disabledBackgroundColor: kFill,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog to change the name and the group of a specimen; pops (name, group), or null on cancel.
class _SpecimenDialog extends StatefulWidget {
  const _SpecimenDialog({required this.name, required this.group});
  final String name, group;

  @override
  State<_SpecimenDialog> createState() => _SpecimenDialogState();
}

class _SpecimenDialogState extends State<_SpecimenDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _group = TextEditingController(text: widget.group);

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSheet,
      title: const Text('Specimen', style: TextStyle(fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _group,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Group'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop((_name.text, _group.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Review of a new specimen before it is saved: the extracted outline with the curve of the
/// first harmonics over it, and its name and group. Pops the [Specimen], or null.
class SpecimenPage extends StatefulWidget {
  const SpecimenPage({
    super.key,
    required this.outline,
    required this.efd,
    required this.detail,
    required this.rotation,
    required this.suggestedName,
    required this.suggestedGroup,
  });

  final Float64List outline;
  final Efd efd;
  final int detail;
  final double rotation;
  final String suggestedName, suggestedGroup;

  @override
  State<SpecimenPage> createState() => _SpecimenPageState();
}

class _SpecimenPageState extends State<SpecimenPage> {
  late final _name = TextEditingController(text: widget.suggestedName);
  late final _group = TextEditingController(text: widget.suggestedGroup);
  late final _fit = efdOutline(widget.efd, _previewHarmonics, 512);

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final now = DateTime.now();
    Navigator.of(context).pop(
      Specimen(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        group: _group.text.trim(),
        date: now,
        detail: widget.detail,
        rotation: widget.rotation,
        outline: widget.outline,
        efd: widget.efd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = normaliseEfd(widget.efd, keepOrientation: true).size;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, 'New specimen'),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: kStage,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kLine),
                ),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _OutlinePainter(widget.outline, _fit),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Text(
                'white: outline  ·  blue: first $_previewHarmonics harmonics\n'
                '${widget.outline.length ~/ 2} points  ·  size ${size.toStringAsFixed(1)} px',
                style: kMono.copyWith(
                  fontSize: 10.5,
                  color: kFaint,
                  height: 1.6,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _group,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Group'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Save specimen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws an outline fitted to the canvas (y up) and, optionally, a second curve over it in the
/// accent colour, at the same scale.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this.outline, this.fit);
  final Float64List outline;
  final Float64List? fit;

  @override
  void paint(Canvas canvas, Size size) {
    if (outline.length < 6) return;
    var x0 = double.infinity,
        x1 = -double.infinity,
        y0 = double.infinity,
        y1 = -double.infinity;
    for (var i = 0; i < outline.length; i += 2) {
      x0 = math.min(x0, outline[i]);
      x1 = math.max(x1, outline[i]);
      y0 = math.min(y0, outline[i + 1]);
      y1 = math.max(y1, outline[i + 1]);
    }
    final sc =
        0.82 *
        math.min(
          size.width / math.max(1, x1 - x0),
          size.height / math.max(1, y1 - y0),
        );
    final cx = size.width / 2 - (x0 + x1) / 2 * sc,
        cy = size.height / 2 + (y0 + y1) / 2 * sc;
    Path path(Float64List p) {
      final out = Path()..moveTo(cx + p[0] * sc, cy - p[1] * sc);
      for (var i = 2; i < p.length; i += 2) {
        out.lineTo(cx + p[i] * sc, cy - p[i + 1] * sc);
      }
      return out..close();
    }

    final thumb = fit == null;
    canvas.drawPath(
      path(outline),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thumb ? 1.1 : 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = thumb ? kInk : const Color(0xB3FFFFFF),
    );
    final f = fit;
    if (f != null) {
      canvas.drawPath(
        path(f),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..color = kAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OutlinePainter old) =>
      !identical(old.outline, outline) || !identical(old.fit, fit);
}

/// Options of the export and the export itself.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.collection, required this.specimens});
  final Collection collection;
  final List<Specimen> specimens;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  static const _counts = [10, 20, 30, 40];
  int _count = 1;
  bool _keepOrientation = true;

  /// Shares the whole collection as one file that the app can import.
  Future<void> _shareCollection(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.collection.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final file = File(
        '${dir.path}/${safe.isEmpty ? 'collection' : safe}.epicycles.json',
      );
      await file.writeAsString(
        collectionFile(widget.collection.name, widget.specimens),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t export the collection.')),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final dir = await getTemporaryDirectory();
      final safe = widget.collection.name
          .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final file = File(
        '${dir.path}/${safe.isEmpty ? 'collection' : safe}-efd.txt',
      );
      await file.writeAsString(
        efdTable(
          widget.specimens,
          harmonics: _counts[_count],
          keepOrientation: _keepOrientation,
        ),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t export the table.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(fontSize: 13, color: kMuted);
    final n = widget.specimens.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$n ${n == 1 ? 'specimen' : 'specimens'}  ·  ${4 * _counts[_count]} coefficients each',
              style: kMono.copyWith(fontSize: 11, color: kMuted),
            ),
            const SizedBox(height: 16),
            const Text('Harmonics', style: label),
            const SizedBox(height: 8),
            Segmented(
              labels: [for (final c in _counts) '$c'],
              index: _count,
              onChanged: (i) => setState(() => _count = i),
              expand: true,
            ),
            const SizedBox(height: 16),
            const Text('Orientation', style: label),
            const SizedBox(height: 8),
            Segmented(
              labels: const ['As oriented', 'First ellipse'],
              index: _keepOrientation ? 0 : 1,
              onChanged: (i) => setState(() => _keepOrientation = i == 0),
              expand: true,
            ),
            const SizedBox(height: 8),
            Text(
              _keepOrientation
                  ? 'Shapes keep the orientation you gave them. Position, size and starting point are removed.'
                  : 'Shapes are also rotated onto the major axis of their first ellipse, as in Momocs. '
                        'Nearly symmetric shapes can come out turned by 180°.',
              style: const TextStyle(fontSize: 12, color: kFaint, height: 1.45),
            ),
            const SizedBox(height: 18),
            Builder(
              builder: (context) => FilledButton.icon(
                onPressed: () => _share(context),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Export table'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text('Whole collection', style: label),
            const SizedBox(height: 6),
            const Text(
              'One file with every outline and its descriptors, to keep, to send to someone '
              'else or to import on another device.',
              style: TextStyle(fontSize: 12, color: kFaint, height: 1.45),
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) => FilledButton.icon(
                onPressed: () => _shareCollection(context),
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Export collection'),
                style: FilledButton.styleFrom(
                  backgroundColor: kFill,
                  foregroundColor: kInk,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
