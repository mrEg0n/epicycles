// A camera screen with a cross-hair over the preview, to frame every specimen the same way.
// Pops the path of the photo taken, or null.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _camera;
  bool _failed = false, _shooting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  // True while a controller is being opened, so that two are never opened at once.
  bool _starting = false;

  Future<void> _start() async {
    if (_starting || _camera != null) return;
    _starting = true;
    CameraController? camera;
    try {
      final all = await availableCameras();
      final back = all.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => all.first,
      );
      camera = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _failed = false;
      });
    } catch (_) {
      await camera?.dispose();
      if (mounted) setState(() => _failed = true);
    } finally {
      _starting = false;
    }
  }

  // The camera is released while the app is in the background and opened again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final camera = _camera;
      if (camera == null) return;
      _camera = null;
      camera.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final camera = _camera;
    if (camera == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      final file = await camera.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } catch (_) {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: kMuted),
                child: const Text('Cancel'),
              ),
            ),
            Expanded(
              child: Center(
                child: _failed
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Can’t open the camera. Check the permission in Settings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: kMuted, height: 1.5),
                        ),
                      )
                    : camera == null
                    ? const SizedBox()
                    : AspectRatio(
                        // The preview is reported in landscape; the screen is held upright.
                        aspectRatio: 1 / camera.value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CameraPreview(camera),
                            const IgnorePointer(
                              child: CustomPaint(painter: ReticlePainter()),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Semantics(
                button: true,
                label: 'Take the photo',
                child: GestureDetector(
                  onTap: _shoot,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kInk, width: 3),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _shooting || camera == null ? kFaint : kInk,
                      ),
                    ),
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

/// A vertical and a horizontal line through the centre, open in the middle.
class ReticlePainter extends CustomPainter {
  const ReticlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    const gap = 18.0;
    // A dark line under the light one keeps the guide visible on any background.
    for (final (colour, width) in const [
      (Color(0x66000000), 2.4),
      (Color(0xCCFFFFFF), 0.9),
    ]) {
      final guide = Paint()
        ..color = colour
        ..strokeWidth = width;
      canvas.drawLine(Offset(cx, 0), Offset(cx, cy - gap), guide);
      canvas.drawLine(Offset(cx, cy + gap), Offset(cx, size.height), guide);
      canvas.drawLine(Offset(0, cy), Offset(cx - gap, cy), guide);
      canvas.drawLine(Offset(cx + gap, cy), Offset(size.width, cy), guide);
    }
  }

  @override
  bool shouldRepaint(covariant ReticlePainter oldDelegate) => false;
}
