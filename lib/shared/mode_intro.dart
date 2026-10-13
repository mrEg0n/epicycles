// The first screen of a mode. Both modes use it, so that they read as two parallel ways through
// the app: a title, what the mode does, the two ways to bring in a photo and a link to what was
// kept from earlier sessions.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'mode_glyphs.dart';
import 'theme.dart';

class ModeIntro extends StatelessWidget {
  const ModeIntro({
    super.key,
    required this.mode,
    required this.title,
    required this.caption,
    required this.onPick,
    required this.linkIcon,
    required this.linkLabel,
    required this.onLink,
    this.note,
  });

  /// The mode, for its mark above the title.
  final Mode mode;
  final String title, caption;
  final void Function(ImageSource) onPick;
  final IconData linkIcon;
  final String linkLabel;
  final VoidCallback onLink;

  /// Shown under the caption, for what is specific to the mode.
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded, size: 22),
              padding: EdgeInsets.zero,
              alignment: Alignment.centerLeft,
            ),
          ),
          const Spacer(flex: 3),
          Center(child: ModeGlyph(mode, size: 104)),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: kMuted, height: 1.4),
          ),
          if (note != null) ...[
            const SizedBox(height: 18),
            Center(child: note),
          ],
          const Spacer(flex: 3),
          FilledButton.icon(
            onPressed: () => onPick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 20),
            label: const Text('Take a photo'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => onPick(ImageSource.gallery),
            icon: const Icon(Icons.photo_outlined, size: 20),
            label: const Text('Choose from library'),
            style: FilledButton.styleFrom(
              backgroundColor: kFill,
              foregroundColor: kInk,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: onLink,
            icon: Icon(linkIcon, size: 18),
            label: Text(linkLabel),
            style: TextButton.styleFrom(
              foregroundColor: kInk,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
