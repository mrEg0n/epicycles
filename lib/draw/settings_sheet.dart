// The settings sheet of the drawing screen and its controls.

part of 'draw_page.dart';

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.engine, required this.onHome});
  final Engine engine;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final e = engine;
    return SafeArea(
      child: ListenableBuilder(
        listenable: e,
        builder: (context, _) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!e.isMask) ...[
                  _Toggle(
                    label: 'Main outline only',
                    value: e.single,
                    onChanged: (v) => _set(() => e.single = v),
                  ),
                  _SliderRow(
                    label: 'Brightness threshold',
                    value: '${e.thr}',
                    trailing: Pill(label: 'Auto', onTap: e.autoThreshold),
                    slider: Slider(
                      value: e.thr.toDouble(),
                      min: 4,
                      max: 251,
                      onChanged: (v) => _set(() => e.thr = v.round()),
                    ),
                  ),
                  _SliderRow(
                    label: 'Outline levels',
                    value: '${e.levels}',
                    slider: Slider(
                      value: e.levels.toDouble(),
                      min: 1,
                      max: 4,
                      divisions: 3,
                      onChanged: (v) => _set(() => e.levels = v.round()),
                    ),
                  ),
                  _SliderRow(
                    label: 'Blur',
                    value: '${e.blur} px',
                    slider: Slider(
                      value: e.blur.toDouble(),
                      min: 0,
                      max: 6,
                      divisions: 6,
                      onChanged: (v) => _set(() => e.blur = v.round()),
                    ),
                  ),
                  _SliderRow(
                    label: 'Drop outlines shorter than',
                    value: '${e.minLen.round()} px',
                    slider: Slider(
                      value: e.minLen,
                      min: 0,
                      max: 150,
                      onChanged: (v) =>
                          _set(() => e.minLen = v.roundToDouble()),
                    ),
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text('Build pace', style: _label),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _Choices(
                    labels: const ['One by one', 'Blocks', 'Fast blocks'],
                    index: e.pace,
                    onChanged: e.setPace,
                  ),
                ),
                const SizedBox(height: 12),
                _SliderRow(
                  label: 'One full turn in',
                  value: '${e.dur.round()} s',
                  slider: Slider(
                    value: e.dur,
                    min: 4,
                    max: 90,
                    onChanged: (v) {
                      e.dur = v.roundToDouble();
                      e.touch();
                    },
                  ),
                ),
                _Toggle(
                  label: 'Show circles',
                  value: e.showCircles,
                  onChanged: (v) {
                    e.showCircles = v;
                    e.touch();
                  },
                ),
                _Toggle(
                  label: 'Show axes',
                  value: e.showAxes,
                  onChanged: (v) {
                    e.showAxes = v;
                    e.touch();
                  },
                ),
                _Toggle(
                  label: 'Show signals over time',
                  value: e.showSignals,
                  onChanged: (v) {
                    e.showSignals = v;
                    e.touch();
                  },
                ),
                // What stays in the background under the curve: the shape's
                // outline or the cut-out photo.
                if (e.photo != null) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('Background', style: _label),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _Choices(
                      labels: const ['Outline', 'Photo'],
                      index: e.bgImage ? 1 : 0,
                      onChanged: (i) {
                        e.bgImage = i == 1;
                        e.touch();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Back to the intro screen: centred and set apart from the options.
                const SizedBox(height: 22),
                Center(
                  child: GestureDetector(
                    onTap: onHome,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: kFill,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.home_outlined, size: 18, color: kInk),
                          SizedBox(width: 8),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Applies a change to the outline settings and shows the full curve at
  // once, without replaying the build.
  void _set(VoidCallback change) {
    change();
    engine.reprocess(animate: false);
  }
}

/// A settings row: label, current value, optional trailing widget, and a
/// slider underneath.
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.slider,
    this.trailing,
  });
  final String label, value;
  final Widget slider;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            children: [
              Text(label, style: _label),
              const Spacer(),
              Text(value, style: kMono.copyWith(fontSize: 12)),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: Transform.translate(
            offset: const Offset(-14, 0),
            child: slider,
          ),
        ),
      ],
    );
  }
}

/// A settings row with a label and a switch.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Text(label, style: _label),
          const Spacer(),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: kAccent,
          ),
        ],
      ),
    );
  }
}

/// Round icon button for the bottom bar: dark by default, inverted when [light].
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.light = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      constraints: const BoxConstraints(minWidth: 46, minHeight: 46),
      style: IconButton.styleFrom(
        backgroundColor: light ? kInk : kFill,
        foregroundColor: light ? kBg : kInk,
      ),
    );
  }
}

/// Small round button at either end of the arm slider.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;

  /// Null disables the button.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      style: IconButton.styleFrom(backgroundColor: kFill),
    );
  }
}

/// Single choice among separate pills: the active one is filled, the others
/// are outlined.
class _Choices extends StatelessWidget {
  const _Choices({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            button: true,
            selected: i == index,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: i == index ? kInk : kFill,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: i == index ? kInk : const Color(0x33FFFFFF),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                    color: i == index ? kBg : kInk,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
