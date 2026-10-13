// From a photo source to a selected shape: picks the image and opens the selection screen.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_page.dart';
import 'image_source.dart';
import 'select_page.dart';
import 'theme.dart';

/// Lets the user choose between the camera and the photo library; null if dismissed.
Future<ImageSource?> chooseImageSource(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
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
              onTap: () => Navigator.of(sheet).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(sheet).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Picks an image from [source] and lets the user select and orient a shape in it. Returns null
/// if the user gives up; failures are reported with a snack bar.
Future<Selection?> pickSelection(
  BuildContext context,
  ImageSource source, {
  required String confirmLabel,
  required String rotateHint,
  bool reticle = false,
  int rotateSteps = 72,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  void fail(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));
  final XFile? file;
  if (reticle && source == ImageSource.camera) {
    // Our own camera screen, which shows the cross-hair while framing.
    final path = await navigator.push<String>(
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );
    file = path == null ? null : XFile(path);
  } else {
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
      return null;
    }
  }
  if (file == null) return null;
  try {
    final photo = await decodeImage(await file.readAsBytes());
    final sel = await navigator.push<Selection>(
      MaterialPageRoute(
        builder: (_) => SelectPage(
          photo: photo,
          path: file!.path,
          confirmLabel: confirmLabel,
          rotateHint: rotateHint,
          reticle: reticle,
          rotateSteps: rotateSteps,
        ),
      ),
    );
    // Only the selected field is needed here, not the pictures. They are released once the
    // selection screen, which still shows them while it slides away, has gone.
    Future.delayed(const Duration(seconds: 1), () {
      photo.dispose();
      sel?.cutout?.dispose();
    });
    return sel;
  } catch (_) {
    fail('Can’t read this image.');
    return null;
  }
}
