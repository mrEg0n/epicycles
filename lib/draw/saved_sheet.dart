// The list of saved shapes.

part of 'draw_page.dart';

/// List of saved shapes: a tap reloads one, the bin deletes it after confirmation.
class _SavedSheet extends StatefulWidget {
  const _SavedSheet({required this.onLoad});
  final void Function(SavedShape) onLoad;

  @override
  State<_SavedSheet> createState() => _SavedSheetState();
}

class _SavedSheetState extends State<_SavedSheet> {
  List<SavedShape>? _items;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    List<SavedShape> items;
    try {
      items = await Store.list();
    } catch (_) {
      items = const [];
    }
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(SavedShape s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kSheet,
        title: Text(
          'Delete “${s.name}”?',
          style: const TextStyle(fontSize: 17),
        ),
        content: const Text(
          'This can’t be undone.',
          style: TextStyle(color: kMuted),
        ),
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
      await Store.delete(s);
    } catch (_) {
      // Already gone or not removable: the refreshed list shows what is actually there.
    }
    await _refresh();
  }

  static String _date(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: items == null
            ? const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                ),
              )
            : items.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 40),
                child: Text(
                  'Nothing saved yet. Draw a shape and press Save to keep it here.',
                  style: TextStyle(color: kMuted, height: 1.5),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final s = items[i];
                  return ListTile(
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onLoad(s);
                    },
                    leading: Container(
                      width: 52,
                      height: 52,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: kStage,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: s.thumb.existsSync()
                          ? Image.file(
                              s.thumb,
                              fit: BoxFit.contain,
                              cacheWidth: 160,
                            )
                          : const Icon(Icons.gesture_rounded, color: kFaint),
                    ),
                    title: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _date(s.date),
                      style: kMono.copyWith(fontSize: 11, color: kMuted),
                    ),
                    trailing: IconButton(
                      onPressed: () => _delete(s),
                      tooltip: 'Delete',
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: kMuted,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
