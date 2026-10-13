// The app shell and its start screen, with the two modes: Draw and Measure.

import 'package:flutter/material.dart';

import 'draw/draw_page.dart';
import 'help_page.dart';
import 'measure/measure_home.dart';
import 'shared/logo.dart';
import 'shared/mode_glyphs.dart';
import 'shared/theme.dart';

class FourierApp extends StatelessWidget {
  const FourierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Epicycles',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      home: const StartPage(),
    );
  }
}

/// Start screen: the name of the app and the two ways in.
class StartPage extends StatelessWidget {
  const StartPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(child: EpicycleLogo(size: 210)),
              const SizedBox(height: 30),
              const Text(
                'Epicycles',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'A Fourier machine',
                textAlign: TextAlign.center,
                style: kMono.copyWith(fontSize: 17, color: kAccent),
              ),
              const Spacer(flex: 2),
              _Entrance(
                mode: Mode.draw,
                title: 'Draw',
                caption: 'Watch a shape being drawn, circle by circle',
                filled: true,
                onTap: () => _open(context, const DrawPage()),
              ),
              const SizedBox(height: 12),
              _Entrance(
                mode: Mode.measure,
                title: 'Measure',
                caption: 'Collect outlines and export shape descriptors',
                filled: false,
                onTap: () => _open(context, const MeasureHome()),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => _open(context, const HelpPage()),
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('How it works'),
                style: TextButton.styleFrom(
                  foregroundColor: kInk,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.mode,
    required this.title,
    required this.caption,
    required this.filled,
    required this.onTap,
  });

  final Mode mode;
  final String title, caption;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = filled ? kBg : kInk;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
          decoration: BoxDecoration(
            color: filled ? kInk : kFill,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              ModeGlyph(mode, size: 44, ink: ink),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: 13,
                        color: filled ? const Color(0xFF55585F) : kMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: ink),
            ],
          ),
        ),
      ),
    );
  }
}
