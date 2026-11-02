# Epicycles

*A Fourier machine.*

Epicycles is an iPhone app that takes the outline of an object from a photo and
writes it as a Fourier series. It is meant more as a tool for curiosity and
experimentation than as a fully fledged scientific package, though it could serve
as a starting point for more serious applications. It is built in Flutter. It runs on iPhone, iOS 17 or
later, and is available on the [App Store](https://apps.apple.com/app/id6822249885). The Android version has not been built yet.

The series can be used in two ways: to draw the outline with a chain of rotating
circles, and to measure it, turning shapes into numbers that can be compared.

<p>
  <img src="docs/01-home.png" width="190" alt="Start screen">
  <img src="docs/02-draw-intro.png" width="190" alt="Draw">
  <img src="docs/06-measure-intro.png" width="190" alt="Measure">
</p>

## Draw mode

<p>
  <img src="docs/03-draw.png" width="190" alt="A hand traced by 31 circles, over the photo">
  <img src="docs/04-zoom.png" width="190" alt="Zoomed in on the pen">
  <img src="docs/05-two-chains.png" width="190" alt="Two chains, one for x(t) and one for y(t)">
</p>

Pick a photo, tap the subject detected by the phone, retouch the silhouette with a
brush if needed and rotate it the way you like. The outline is then drawn by a
chain of circles, one circle at first, then one more at each turn, from the
largest to the smallest, until the drawn curve fits the original outline.

While it runs, the screen shows the arms and circles, the two components of the
motion over time, the equation as each new term is added, and the spectrum with
the lines lighting up as the circles appear. You can drag through the arms, zoom
in on the pen to see the smallest ones, read the full equation and copy it, or
export the spectrum as a table.

A second view separates the motion into x(t) and y(t), each drawn by its own chain.

## Measure mode

<p>
  <img src="docs/07-outline.png" width="150" alt="The outline found in a photo of an ivy leaf">
  <img src="docs/08-overlay.png" width="150" alt="Nine ivy leaves overlaid, with their mean">
  <img src="docs/09-variability.png" width="150" alt="Outline variability">
  <img src="docs/10-pca.png" width="150" alt="Principal component analysis of the leaves">
  <img src="docs/11-modes.png" width="150" alt="Variance and modes of variation">
</p>

A single outline says little. What matters is how outlines differ across a
collection. Measure stores each outline as elliptic Fourier descriptors (Kuhl and
Giardina, 1982), a standard representation in outline morphometrics.

Here you can photograph the objects one at a time, align them, and give each a
name and a group. A collection then shows:

- every outline overlaid at the same size, with the mean shape of each group;
- outline variability as the mean shape coloured by the RMS deviation of the
  specimens at each point;
- a principal component analysis of the descriptors: scores on PC1 and PC2, with
  the outline found at each end of the axes;
- the variance of each component and the modes of variation, as the mean shape
  with the shapes two standard deviations either side of it along PC1 to PC3.

The descriptors can be exported as a tab-separated table, with one row per
specimen and coefficients in the column order used by the R package Momocs.

### Collection files

A collection can be exported as a single JSON file and imported again, on the same
phone or another one. The file can also be written by other software, making it
possible to import outlines from existing image archives:

```json
{
  "format": "epicycles-collection",
  "version": 1,
  "name": "Ivy leaves",
  "specimens": [
    { "name": "Leaf 1", "group": "north", "outline": [x0, y0, x1, y1, ...] }
  ]
}
```

Only `outline` is required: a closed outline with y pointing up, in any unit and
with points at any spacing. It is resampled to 1024 equal steps and its descriptors
are computed on import. Files exported by the app also carry the raw coefficients
(`a`, `b`, `c`, `d`, 40 harmonics), which are then used as they are.

An example collection of 50 trilobite head shields in four growth stages, along
with a Python script that reproduces the app's analysis, can be found in
[examples/trilobites](examples/trilobites).

## How it works

The photo is reduced to 480 px, and the silhouette is traced using marching squares
at sub-pixel precision. The contour is resampled at equal intervals along its
length (1024 to 8192 points) and treated as a periodic complex signal
z(t) = x(t) + i y(t). An FFT gives its coefficients: each one describes a circle,
with a radius, an integer number of turns per loop, and a starting angle.

For drawing, the terms are sorted by radius, giving the best approximation in the
least-squares sense for any number of terms. Arms are added until the largest gap
between the curve and the outline falls below 0.3% of the longer side. The number
of circles is therefore determined by the shape, rather than fixed in advance. The
origin is the centroid, and the unit is the radius of the largest circle.

For measuring, the same series is written as four coefficients per harmonic and
normalised. Position and size are always removed. Orientation is either the one set
by the operator, which the app uses for its own views, or the major axis of the
first ellipse, as in Momocs. In the first case, the starting point is chosen where
the first ellipse lies above its centre, which, unlike the major axis, remains well
defined for shapes roughly as wide as they are tall.

## What has been checked

- The descriptors against Momocs 1.5.0, running its own `efourier` and
  `efourier_norm` on an outline produced by the app (one shape, 40 harmonics):
  raw coefficients agree within 4e-4 of the first radius, normalised ones within
  1e-3. The difference comes from the parametrisation at sharp corners.
- The principal components against numpy on the same data.
- The core has unit tests on synthetic shapes: exact reconstruction, the
  normalisations and their invariances, the exported tables.

What has not been checked: the interface has no automated tests; it has been
checked by hand, on the simulator and on an iPhone 17. The repeatability of a
measurement across photos of the same object has not been quantified yet.

## Limits

- Outlines come from a 480 px image. That is fine for drawing and coarse for
  measuring small objects.
- Size is in pixels, not a physical length.
- One outline per shape: holes and detached parts are ignored.
- The app describes collections (overlay, mean shapes, principal components) but
  does not test whether groups differ significantly. For significance tests, the
  table of descriptors can be exported and analysed in R, Python or similar;
  [examples/trilobites](examples/trilobites) shows one way.

## Building

Flutter 3.47 and Xcode.

```
flutter pub get
flutter test
flutter build ios --release
```

Note: subject detection and the camera do not work in the iOS Simulator.

If the project is in an iCloud-synced folder, code signing fails because of the
extended attributes iCloud adds to build products. Making `build` a symlink to a
folder outside iCloud avoids the problem.

## Layout

```
lib/core      contour extraction, Fourier series, descriptors, PCA (pure Dart)
lib/shared    photo to silhouette, camera, theme
lib/draw      the drawing screen
lib/measure   collections, statistics, export
test          tests of the core
tool          dumps an outline and its descriptors, to compare with other software
```

The Vision call that detects the subject is in `ios/Runner/AppDelegate.swift`.

## References

- F. P. Kuhl and C. R. Giardina, Elliptic Fourier features of a closed contour,
  *Computer Graphics and Image Processing* 18 (1982).
- V. Bonhomme et al., Momocs: outline analysis using R, *Journal of Statistical
  Software* 56 (2014).

## Privacy

The app collects no data. See [PRIVACY.md](PRIVACY.md).

## License

MIT. See [LICENSE](LICENSE). The one exception is the example data file
`examples/trilobites/Trilobites.epicycles.json`, redistributed under the GNU GPL,
version 3 or later (see that folder).
