// Colours, text styles and small widgets shared by the two modes of the app.

import 'package:flutter/material.dart';

const kBg = Color(0xFF050506);
const kStage = Color(0xFF08090B);
const kSheet = Color(0xFF0D0E11);
const kMuted = Color(0xFF8A8E98);
const kFaint = Color(0xFF55585F);
const kLine = Color(0x17FFFFFF);
const kFill = Color(0x0FFFFFFF);
const kMathInk = Color(0xFFC9CCD3);

const kInk = Color(0xFFF2F3F5);
const kAccent = Color(0xFF8FA8FF);

// Colour coding. The curve is drawn in the accent blue. Its two components sit on either side of
// it, cyan for the real part and violet for the imaginary part: their per-channel average is
// exactly that blue ((95,208,255) and (191,128,255) give (143,168,255)).
const kRe = Color(0xFF5FD0FF);
const kIm = Color(0xFFBF80FF);
const kCurve = kAccent;
// Arms are a soft warm yellow, complementary to the blue of the curve. Circles stay white.
const kArm = Color(0xFFFFDC85);

const kMono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['monospace'],
  fontFeatures: [FontFeature.tabularFigures()],
);
const kMath = TextStyle(
  fontFamily: 'Times New Roman',
  fontFamilyFallback: ['Noto Serif', 'serif'],
  color: kMathInk,
  height: 1.6,
);

ThemeData appTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary: kInk,
    onPrimary: kBg,
    secondary: kAccent,
    surface: kBg,
  ),
  splashFactory: NoSplash.splashFactory,
  sliderTheme: const SliderThemeData(
    trackHeight: 1,
    activeTrackColor: kInk,
    inactiveTrackColor: Color(0x38FFFFFF),
    thumbColor: kInk,
    overlayColor: Color(0x14FFFFFF),
    thumbShape: RoundSliderThumbShape(
      enabledThumbRadius: 6,
      elevation: 0,
      pressedElevation: 0,
    ),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
  ),
);
