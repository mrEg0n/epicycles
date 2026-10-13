// The equation on the drawing screen: compact form, full sheet and spectrum.

part of 'draw_page.dart';

/// Counter line shown on the stage: arms in use, circles, and the maximum
/// deviation from the outline as a percentage of the shape's longer side.
String _counters(Engine e) {
  if (e.a == null) return e.noContours || e.src == null ? '' : 'Preparing…';
  final n = e.shown, c = e.one ? n : 2 * n;
  final err = 100 * e.errorAt(n);
  return '$n of ${e.k} arms${e.one ? '' : ' per chain'} · $c ${c == 1 ? 'circle' : 'circles'} · '
      'error ${err.toStringAsFixed(err < 1 ? 2 : 1)}%';
}

/// [n] in subscript digits (for r₅, f₅, φ₅).
String _subscript(int n) =>
    '$n'.split('').map((c) => '₀₁₂₃₄₅₆₇₈₉'[int.parse(c)]).join();

/// [v] with [d] decimals and a typographic minus sign.
String _num(double v, int d) =>
    '${v < 0 ? '−' : ''}${v.abs().toStringAsFixed(d)}';

/// [v] as a signed addend: " + 1.23" or " − 1.23".
String _pm(double v, int d) =>
    '${v < 0 ? ' − ' : ' + '}${v.abs().toStringAsFixed(d)}';

/// [child] raised as a superscript of text set at [size].
InlineSpan _sup(InlineSpan child, double size) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Transform.translate(
    offset: Offset(0, -size * 0.38),
    child: Text.rich(
      child,
      style: kMath.copyWith(fontSize: size * 0.74, height: 1),
    ),
  ),
);

/// Left-hand side of an equation line: "x(t) = ".
List<InlineSpan> _head(EqLine ln) {
  return [
    TextSpan(text: ln.name, style: _itInk),
    const TextSpan(
      text: '(',
      style: TextStyle(color: kInk),
    ),
    const TextSpan(text: 't', style: _itInk),
    const TextSpan(
      text: ') = ',
      style: TextStyle(color: kInk),
    ),
  ];
}

/// One term of the expanded equation, preceded by a plus sign unless it is
/// the [first]. With [one] chain it is a complex exponential, otherwise a cosine.
List<InlineSpan> _term(EqTerm q, bool one, double size, {bool first = false}) {
  final arg = <InlineSpan>[
    TextSpan(text: '${q.f < 0 ? '−' : ''}2π·'),
    TextSpan(
      text: '${q.f.abs()}',
      style: const TextStyle(color: kAccent),
    ),
    const TextSpan(text: 't', style: _it),
    TextSpan(text: _pm(q.p, 2)),
  ];
  return [
    TextSpan(
      text: '${first ? '' : '  +  '}${one ? '' : '${q.a.toStringAsFixed(4)} '}',
    ),
    if (one)
      // Coefficient, "e" and exponent form one unbreakable block, so a line
      // break never splits them.
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${q.a.toStringAsFixed(4)} '),
              const TextSpan(text: 'e', style: _it),
              _sup(
                TextSpan(
                  children: [
                    const TextSpan(text: 'i', style: _it),
                    const TextSpan(text: '('),
                    ...arg,
                    const TextSpan(text: ')'),
                  ],
                ),
                size,
              ),
            ],
          ),
          softWrap: false,
          style: kMath.copyWith(fontSize: size),
        ),
      )
    else
      TextSpan(
        children: [
          const TextSpan(text: 'cos('),
          ...arg,
          const TextSpan(text: ')'),
        ],
      ),
  ];
}

/// One line of the expanded equation, limited to its first [maxTerms] terms.
TextSpan _lineSpan(EqLine ln, int maxTerms, double size) {
  final one = ln.complex;
  return TextSpan(
    style: kMath.copyWith(fontSize: size),
    children: [
      ..._head(ln),
      for (var i = 0; i < ln.terms.length && i < maxTerms; i++)
        ..._term(ln.terms[i], one, size, first: i == 0),
    ],
  );
}

/// Summation sign with its bounds: from k = 1 to [n], the number of arms in use.
InlineSpan _sigma(int n, double size, Color nColor) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$n',
          style: kMono.copyWith(
            fontSize: size * 0.58,
            color: nColor,
            height: 1,
          ),
        ),
        Text(
          '∑',
          style: kMath.copyWith(
            fontSize: size * 1.3,
            color: kInk,
            height: 1.05,
          ),
        ),
        Text(
          'k = 1',
          style: kMath.copyWith(
            fontSize: size * 0.52,
            color: kMuted,
            height: 1,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    ),
  ),
);

/// Compact form of the equation; [n] is the number of terms currently in use.
TextSpan _compactSpan(bool one, int n, double size, Color nColor) {
  final st = kMath.copyWith(fontSize: size, color: kInk, height: 1.3);
  if (one) {
    return TextSpan(
      style: st,
      children: [
        const TextSpan(text: 'z', style: _it),
        const TextSpan(text: '('),
        const TextSpan(text: 't', style: _it),
        const TextSpan(text: ') = '),
        _sigma(n, size, nColor),
        const TextSpan(text: ' rₖ e', style: _it),
        _sup(const TextSpan(text: 'i(2π fₖ t + φₖ)', style: _it), size),
      ],
    );
  }
  return TextSpan(
    style: st,
    children: [
      const TextSpan(text: 'x', style: _it),
      const TextSpan(text: ', '),
      const TextSpan(text: 'y', style: _it),
      const TextSpan(text: ' = '),
      _sigma(n, size, nColor),
      const TextSpan(text: ' Aₖ', style: _it),
      const TextSpan(text: ' cos(2π '),
      const TextSpan(text: 'fₖ t', style: _it),
      const TextSpan(text: ' + '),
      const TextSpan(text: 'φₖ', style: _it),
      const TextSpan(text: ')'),
    ],
  );
}

/// General form of the equation, without bounds: the heading of the equation sheet.
TextSpan _generalSpan(bool one, double size) {
  final st = kMath.copyWith(fontSize: size, color: kInk, height: 1.3);
  if (one) {
    return TextSpan(
      style: st,
      children: [
        const TextSpan(text: 'z', style: _it),
        const TextSpan(text: '('),
        const TextSpan(text: 't', style: _it),
        const TextSpan(text: ') = '),
        const TextSpan(text: '∑ '),
        const TextSpan(text: 'rₖ e', style: _it),
        _sup(const TextSpan(text: 'i(2π fₖ t + φₖ)', style: _it), size),
      ],
    );
  }
  return TextSpan(
    style: st,
    children: const [
      TextSpan(text: 'x', style: _it),
      TextSpan(text: '('),
      TextSpan(text: 't', style: _it),
      TextSpan(text: '), '),
      TextSpan(text: 'y', style: _it),
      TextSpan(text: '('),
      TextSpan(text: 't', style: _it),
      TextSpan(text: ') = '),
      TextSpan(text: '∑ '),
      TextSpan(text: 'Aₖ', style: _it),
      TextSpan(text: ' cos(2π '),
      TextSpan(text: 'fₖ t', style: _it),
      TextSpan(text: ' + '),
      TextSpan(text: 'φₖ', style: _it),
      TextSpan(text: ')'),
    ],
  );
}

/// The equation overlaid on the stage, in compact form: it gains one term for each arm added.
class _EquationPreview extends StatefulWidget {
  const _EquationPreview({required this.engine});
  final Engine engine;

  @override
  State<_EquationPreview> createState() => _EquationPreviewState();
}

class _EquationPreviewState extends State<_EquationPreview> {
  int _shown = -1;
  bool _building = false;
  bool _glowing = false;

  // The engine clock fires every frame; rebuild only when the number of arms
  // or the building state changes, or on every frame while the completion
  // glow lasts.
  void _onTick() {
    final e = widget.engine;
    final g = e.doneGlow > 0;
    if (e.shown != _shown || e.building != _building || g || _glowing) {
      setState(() {});
    }
    _glowing = g;
  }

  @override
  void initState() {
    super.initState();
    widget.engine.clock.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.engine.clock.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    _shown = e.shown;
    _building = e.building;
    final ready = e.a != null;
    final lines = ready ? e.equation : const <EqLine>[];
    final n = _shown;
    final hi = ready ? kAccent : kMuted;

    // Values of the latest term: radius (or amplitude), frequency, phase.
    // One line per coordinate. Letters are white; only what changes with each
    // circle, index and value, takes the accent colour.
    final sub = _subscript(n);
    const white = TextStyle(color: kInk);
    // Plain space as separator: a dot could read as a multiplication.
    const sep = TextSpan(text: '      ');
    final values = <List<InlineSpan>>[];
    for (final ln in lines) {
      if (n < 1 || n > ln.terms.length) continue;
      final q = ln.terms[n - 1];
      final one = ln.complex;
      values.add([
        if (!one)
          TextSpan(
            text: '${ln.name}:   ',
            style: _it.copyWith(color: kMuted),
          ),
        TextSpan(text: one ? 'r' : 'A', style: _itInk),
        TextSpan(text: sub),
        const TextSpan(text: ' = ', style: white),
        TextSpan(
          text: q.a < 0.001
              ? q.a.toStringAsExponential(1)
              : q.a.toStringAsFixed(4),
        ),
        sep,
        const TextSpan(text: 'f', style: _itInk),
        TextSpan(text: sub),
        const TextSpan(text: ' = ', style: white),
        TextSpan(text: _num(q.f.toDouble(), 0)),
        sep,
        const TextSpan(text: 'φ', style: _itInk),
        TextSpan(text: sub),
        const TextSpan(text: ' = ', style: white),
        TextSpan(text: _num(q.p, 2)),
      ]);
    }

    return IgnorePointer(
      child: _Glow(
        amount: e.doneGlow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Compact form: only the term count above the summation changes.
            // The full numbers are in the sheet opened by the button beside it.
            SizedBox(
              height: kFormulaSum,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text.rich(_compactSpan(e.one, ready ? n : 0, 16, hi)),
              ),
            ),
            for (var r = 0; r < (e.one ? 1 : 2); r++)
              SizedBox(
                height: kFormulaLine,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text.rich(
                    TextSpan(
                      style: kMath.copyWith(
                        fontSize: 12.5,
                        height: 1.2,
                        color: kAccent,
                      ),
                      children: r < values.length ? values[r] : const [],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Completion glow on text: an accent halo around the glyphs that rises and
/// fades, following the same envelope as the flash on the outline. [amount]
/// runs from 1 (just lit) to 0 (off).
class _Glow extends StatelessWidget {
  const _Glow({required this.amount, required this.child});
  final double amount;
  final Widget child;

  static double _smooth(double x) {
    final v = x.clamp(0.0, 1.0);
    return v * v * (3 - 2 * v);
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return child;
    final q = 1 - amount;
    final env = q < 0.2 ? _smooth(q / 0.2) : 1 - _smooth((q - 0.2) / 0.8);
    // Shadows are inherited by all descendant text, including the summation
    // sign and the exponent. Radii are fixed; only the opacity follows the
    // envelope.
    return DefaultTextStyle.merge(
      style: TextStyle(
        shadows: [
          for (final r in const [3.0, 6.0, 10.0, 16.0, 24.0, 34.0])
            Shadow(
              color: kAccent.withValues(alpha: env),
              blurRadius: r,
            ),
          Shadow(
            color: Colors.white.withValues(alpha: 0.8 * env),
            blurRadius: 4,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Bottom sheet with the full equation, as a coefficient table or written out.
class _EquationSheet extends StatefulWidget {
  const _EquationSheet({required this.engine});
  final Engine engine;

  @override
  State<_EquationSheet> createState() => _EquationSheetState();
}

class _EquationSheetState extends State<_EquationSheet> {
  // Beyond this many terms the expanded form is too heavy to lay out.
  static const _maxWritten = 300;
  bool _copied = false;
  // 0 = expanded sums, 1 = table of coefficients, 2 = spectrum.
  int _view = 0;
  bool get _table => _view == 1;

  static const _cols = [44.0, 84.0, 96.0];

  Future<void> _copyAll() async {
    await Clipboard.setData(
      ClipboardData(text: equationText(widget.engine.equation)),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    // Back to the normal label after a moment.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Writes the spectrum to a text file and hands it to the system share sheet.
  Future<void> _exportSpectrum(BuildContext context, List<EqLine> lines) async {
    final messenger = ScaffoldMessenger.of(context);
    // The share sheet is anchored to the button (required on large screens).
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/epicycles-spectrum.txt');
      await file.writeAsString(spectrumTable(lines));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Couldn’t export the spectrum.')),
      );
    }
  }

  Widget _cells(String a, String b, String c, String d, {bool head = false}) {
    final st = kMono.copyWith(
      fontSize: head ? 10.5 : 12.5,
      color: head ? kFaint : kMathInk,
      height: 1.7,
    );
    return Row(
      children: [
        SizedBox(
          width: _cols[0],
          child: Text(a, style: st),
        ),
        SizedBox(
          width: _cols[1],
          child: Text(b, style: st),
        ),
        SizedBox(
          width: _cols[2],
          child: Text(c, style: st),
        ),
        Expanded(child: Text(d, style: st)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    final lines = e.equation;

    // Flat list of table rows, so the list view can build them lazily.
    // Each entry is (equation line, term index); index -1 is a header row.
    final rows = <(int, int)>[];
    if (_table) {
      for (var l = 0; l < lines.length; l++) {
        rows.add((l, -1));
        for (var i = 0; i < lines[l].terms.length; i++) {
          rows.add((l, i));
        }
      }
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(_generalSpan(e.one, 22)),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                '${e.one ? 'z = x + iy · ' : ''}${e.k} ${e.one ? 'terms' : 'terms per coordinate'} · t ∈ [0, 1)\n'
                'y axis up · origin at the centroid · first circle radius = 1',
                style: kMono.copyWith(fontSize: 11, color: kMuted, height: 1.6),
              ),
            ),
            const SizedBox(width: 10),
            // On the spectrum the button exports the table; elsewhere it copies the
            // equation.
            if (_view == 2)
              Builder(
                builder: (context) => Pill(
                  label: 'Export',
                  onTap: () => _exportSpectrum(context, lines),
                ),
              )
            else
              Pill(label: _copied ? 'Copied' : 'Copy all', onTap: _copyAll),
          ],
        ),
        const SizedBox(height: 16),
        // The three views, as wide as the sheet, in the same style as the mode switch.
        Segmented(
          labels: const ['Expanded', 'Coefficients', 'Spectrum'],
          index: _view,
          onChanged: (i) => setState(() => _view = i),
          expand: true,
        ),
        const SizedBox(height: 14),
      ],
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
        itemCount: 1 + (_table ? rows.length : lines.length),
        itemBuilder: (context, index) {
          if (index == 0) return header;
          if (_view == 2) {
            return _Spectrum(
              engine: e,
              line: lines[index - 1],
              titled: lines.length > 1,
            );
          }
          if (!_table) {
            final ln = lines[index - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(_lineSpan(ln, _maxWritten, 16)),
                  if (ln.terms.length > _maxWritten)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '+ ${ln.terms.length - _maxWritten} more terms: they are all in “Coefficients” and “Copy all”',
                        style: kMono.copyWith(fontSize: 11, color: kFaint),
                      ),
                    ),
                ],
              ),
            );
          }
          final (l, i) = rows[index - 1];
          final ln = lines[l];
          final one = ln.complex;
          if (i == -1) {
            return Padding(
              padding: EdgeInsets.only(top: l == 0 ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lines.length > 1)
                    Text.rich(
                      TextSpan(
                        text: '${ln.name}(t)',
                        style: kMath.copyWith(
                          fontSize: 17,
                          color: kInk,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  _cells(
                    'k',
                    'frequency',
                    one ? 'radius' : 'amplitude',
                    'phase (rad)',
                    head: true,
                  ),
                ],
              ),
            );
          }
          final q = ln.terms[i];
          return _cells(
            '${i + 1}',
            '${q.f}',
            q.a < 0.001 ? q.a.toStringAsExponential(2) : q.a.toStringAsFixed(5),
            _num(q.p, 4),
          );
        },
      ),
    );
  }
}

/// Line spectrum of one equation: the amplitude of each term against its frequency, on a
/// logarithmic scale. The terms already in the drawing are lit, the others dimmed.
class _Spectrum extends StatelessWidget {
  const _Spectrum({
    required this.engine,
    required this.line,
    required this.titled,
  });

  final Engine engine;
  final EqLine line;
  final bool titled;

  @override
  Widget build(BuildContext context) {
    final color = switch (line.name) {
      'x' => kRe,
      'y' => kIm,
      _ => kAccent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titled)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${line.name}(t)',
                style: kMath.copyWith(
                  fontSize: 17,
                  color: kInk,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          SizedBox(
            height: 220,
            width: double.infinity,
            // Repaints as arms enter the drawing behind the sheet.
            child: ListenableBuilder(
              listenable: Listenable.merge([engine, engine.clock]),
              builder: (_, _) => CustomPaint(
                painter: _SpectrumPainter(line, engine.shown, color),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${line.complex ? 'radius' : 'amplitude'} (log scale) against frequency, in turns per loop'
            '${line.complex ? ' · negative = clockwise' : ''}\n'
            'the ${line.terms.length} terms of the equation · lit = already in the drawing',
            style: kMono.copyWith(fontSize: 10.5, color: kFaint, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// The spectrum under the drawing: one plot for z(t), or x(t) and y(t) side by side. The lines
/// light up as the arms enter.
class _SpectrumStrip extends StatelessWidget {
  const _SpectrumStrip({required this.engine});

  final Engine engine;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: SizedBox(
          height: 84,
          child: ListenableBuilder(
            listenable: engine.clock,
            builder: (_, _) {
              final lines = engine.a == null
                  ? const <EqLine>[]
                  : engine.equation;
              return Row(
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _SpectrumPainter(
                          lines[i],
                          engine.shown,
                          switch (lines[i].name) {
                            'x' => kRe,
                            'y' => kIm,
                            _ => kAccent,
                          },
                          compact: true,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.line, this.lit, this.color, {this.compact = false});

  final EqLine line;

  /// Tighter margins and fewer labels, for the strip under the drawing.
  final bool compact;

  /// Number of terms, from the largest, that are in the drawing.
  final int lit;
  final Color color;

  void _label(Canvas c, String s, Offset at, {double ax = 0, double ay = 0}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: kMono.copyWith(fontSize: 9.5, color: kMuted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at - Offset(tp.width * (ax + 1) / 2, tp.height * (ay + 1) / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final terms = line.terms;
    if (terms.isEmpty) return;
    var fMax = 1, aMax = 0.0, aMin = double.infinity;
    for (final q in terms) {
      fMax = math.max(fMax, q.f.abs());
      aMax = math.max(aMax, q.a);
      if (q.a > 0) aMin = math.min(aMin, q.a);
    }
    if (aMax <= 0) return;
    // Whole decades, from the one above the largest amplitude to the one below the smallest. An
    // amplitude just over a decade (the unit is the largest circle, so often 1) does not open a
    // new one: its line simply rises a little above the top grid line.
    final top = (math.log(aMax) / math.ln10 - 0.2).ceil().toDouble();
    final bottom = math.min(
      top - 1,
      (math.log(aMin) / math.ln10).floor().toDouble(),
    );
    final padL = compact ? 38.0 : 34.0, padT = compact ? 8.0 : 22.0;
    const padR = 6.0, padB = 18.0;
    final w = size.width - padL - padR, h = size.height - padT - padB;
    final f0 = line.complex ? -fMax : 0, span = fMax - f0;
    double px(int f) => padL + w * (f - f0) / span;
    double py(double a) =>
        padT + h * (top - math.log(a) / math.ln10) / (top - bottom);

    final grid = Paint()
      ..color = kLine
      ..strokeWidth = 1;
    for (var d = top; d >= bottom; d--) {
      final y = padT + h * (top - d) / (top - bottom);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
      final exp = d.toInt();
      // In the strip there is room for every other decade only.
      if (compact && (top - d).toInt().isOdd) continue;
      _label(
        canvas,
        exp >= 0 ? '1${'0' * exp}' : '0.${'0' * (-exp - 1)}1',
        Offset(padL - 5, y),
        ax: 1,
      );
    }
    // Frequency labels: the ends and, for the signed axis, zero.
    final base = padT + h;
    for (final f in line.complex ? [-fMax, 0, fMax] : [0, fMax]) {
      canvas.drawLine(Offset(px(f), base), Offset(px(f), base + 3), grid);
      _label(
        canvas,
        '${f < 0 ? '−' : ''}${f.abs()}',
        Offset(px(f), base + 5),
        ay: -1,
      );
    }

    final width = (w / (span + 1) * 0.7).clamp(1.0, 3.0);
    final on = Paint()
      ..color = color
      ..strokeWidth = width;
    final off = Paint()
      ..color = color.withValues(alpha: 0.28)
      ..strokeWidth = width;
    // Dimmed first, so the lit lines stay on top where they are close together.
    for (var i = terms.length - 1; i >= 0; i--) {
      final q = terms[i];
      if (q.a <= 0) continue;
      final x = px(q.f);
      canvas.drawLine(Offset(x, base), Offset(x, py(q.a)), i < lit ? on : off);
    }
    // The line of the latest arm stands out in white.
    if (lit >= 1 && lit <= terms.length && terms[lit - 1].a > 0) {
      final q = terms[lit - 1], x = px(q.f);
      canvas.drawLine(
        Offset(x, base),
        Offset(x, py(q.a)),
        Paint()
          ..color = kInk
          ..strokeWidth = math.max(width, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter old) =>
      old.lit != lit ||
      !identical(old.line, line) ||
      old.color != color ||
      old.compact != compact;
}
