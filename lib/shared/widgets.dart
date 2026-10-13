// Small widgets shared by the two modes of the app.

import 'package:flutter/material.dart';

import 'theme.dart';

/// Small pill-shaped text button.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.onTap});
  final String label;

  /// Null disables the chip.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: kFill,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// Single choice as one segmented pill.
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.expand = false,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Fills the available width, with segments of equal size.
  final bool expand;

  Widget _segment(int i) {
    return Semantics(
      button: true,
      selected: i == index,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(
            color: i == index ? kInk : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            labels[i],
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 12,
              fontWeight: i == index ? FontWeight.w600 : FontWeight.w400,
              color: i == index ? kBg : kMuted,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: kFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            if (expand) Expanded(child: _segment(i)) else _segment(i),
        ],
      ),
    );
  }
}

/// Dialog asking for a name; pops the typed text, or null on cancel.
/// It owns its text controller, so the controller lives until the closing animation has finished.
class NameDialog extends StatefulWidget {
  const NameDialog({
    super.key,
    required this.initial,
    this.title = 'Save this shape',
    this.confirm = 'Save',
  });

  final String initial;
  final String title, confirm;

  @override
  State<NameDialog> createState() => NameDialogState();
}

class NameDialogState extends State<NameDialog> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSheet,
      title: Text(widget.title, style: const TextStyle(fontSize: 17)),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctl.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
