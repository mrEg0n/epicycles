// How to use the app: a page of plain instructions for the two modes.

import 'package:flutter/material.dart';

import 'shared/mode_glyphs.dart';
import 'shared/theme.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                  const Text(
                    'How it works',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 28),
                children: const [
                  _Text(
                    'Any closed outline can be written as a sum of circles turning at whole-number '
                    'speeds: its Fourier series. The app takes the outline of an object from a '
                    'photo and uses that series in two ways.',
                  ),
                  _Section(Mode.draw, 'Draw'),
                  _Text(
                    'Shows the outline being drawn by a chain of circles, one more at each turn, '
                    'from the largest to the smallest.',
                  ),
                  _Steps([
                    'Take a photo or choose one. The app proposes the subjects it finds: tap the '
                        'one you want, retouch it with the brush if needed, then turn it as you like.',
                    'Watch the curve close in on the outline. The counters show how many arms are '
                        'in and how far the curve still is from the outline.',
                    'Drag the bar, or use − and +, to add and remove arms yourself.',
                    'Pinch to zoom in on the pen and see the smallest arms. Drag to move, double '
                        'tap to go back.',
                    'Under the drawing, the spectrum shows the size of each circle against its '
                        'speed. “Expand equation” opens the full equation, the table of '
                        'coefficients and the spectrum, which can be copied or exported.',
                    'The settings change the pace and what is shown. Save keeps a shape for later.',
                  ]),
                  _Section(Mode.measure, 'Measure'),
                  _Text(
                    'Turns outlines into numbers that can be compared: the elliptic Fourier '
                    'descriptors used in shape analysis. One outline alone says little; the '
                    'information is in how the outlines of a collection differ.',
                  ),
                  _Steps([
                    'Photograph one object at a time, flat, from straight above, on a plain '
                        'background without hard shadows.',
                    'Fill the frame, and line the object up with the cross-hair in the same way '
                        'every time, for example the midrib of a leaf along the vertical line. You '
                        'can refine the alignment on the next screen.',
                    'Leave out parts that vary for no reason, such as the stalk of a leaf: cut '
                        'them off or erase them with the brush. Keep “Detail” the same for the '
                        'whole collection.',
                    'Give each specimen a name and a group: the group is the question you ask, '
                        'such as the site, the plant or the treatment.',
                    'To learn how much the measurement itself varies, photograph the same object '
                        'a few times as separate specimens.',
                  ]),
                  _Text(
                    'Overlay draws every outline at the same size and centre, with the mean shape '
                    'of each group. Statistics shows the mean shape coloured by how much the '
                    'specimens deviate from it at each point, a principal component analysis of '
                    'the descriptors with the scores of the specimens, the variance of each '
                    'component, and the modes of variation: the mean shape with the shapes two '
                    'standard deviations either side of it along the first components. Export '
                    'gives a table with one row per specimen, to analyse elsewhere.',
                  ),
                  _Text(
                    'Size and position are removed, so only shape is compared. Orientation is the '
                    'one you give: specimens turned differently will look like different shapes.',
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

class _Section extends StatelessWidget {
  const _Section(this.mode, this.title);
  final Mode mode;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 4),
      child: Row(
        children: [
          ModeGlyph(mode, size: 34),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, color: kMathInk, height: 1.5),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps(this.steps);
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${i + 1}',
                    style: kMono.copyWith(
                      fontSize: 13,
                      color: kAccent,
                      height: 1.7,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    steps[i],
                    style: const TextStyle(
                      fontSize: 15,
                      color: kMathInk,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
