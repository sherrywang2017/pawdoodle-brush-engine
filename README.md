# PawDoodle Brush Engine

The Flutter brush engine extracted from PawDoodle, a pet portrait drawing app. It turns pointer samples into a live stroke using the same modeling and material pipeline for built-in and custom brushes.

- **Round and Marker** use continuous swept coverage.
- **Crayon** models dry wax deposition and drag over stationary paper grain.
- **Soft** builds a continuous airbrush density field, including while the pointer is held.
- **Ink** models wet contact, paper absorption, and pigment deposition.
- **Fur** carries procedural bristle filaments along the stroke.
- **Custom brushes** combine tip shape, grain, pressure response, taper, and material parameters. The compiler accepts both V1 and V2 presets.

## Run the demo

Use Flutter 3.44.8 or later and Chrome. The demo runs locally without an account or backend.

```sh
git clone https://github.com/sherrywang2017/pawdoodle-brush-engine.git
cd pawdoodle-brush-engine/example
flutter pub get
flutter run -d chrome
```

Choose a preset, color, and size, then draw. Select **Samples** to render the same synthetic path with each preset or **Clear** to start over. The **Custom** preset uses a flat tip and fixed paper grain. Pressure comes from the device when available.

## Use it in a Flutter app

Add the Git dependency to your app's `pubspec.yaml` and run `flutter pub get`.

```yaml
dependencies:
  pawdoodle_brush_engine:
    git:
      url: https://github.com/sherrywang2017/pawdoodle-brush-engine.git
      ref: v0.1.0
```

Prepare the preset after Flutter initializes and before accepting input. Start an interaction with the first pointer sample, then call `appendSample` on pointer moves. Pass the interaction to a `CustomPainter` and call `paint` with the logical canvas size and physical target raster scale. On pointer-up, call `stroke.freeze()` and keep painting the interaction, or use `PawStrokeCommitter` to composite it into a `DrawingRaster`. Dispose of the interaction when it leaves the canvas.

```dart
import 'package:pawdoodle_brush_engine/pawdoodle_brush_engine.dart';

final preset = PawBrushProgramCompiler.compileUserV2(
  const PawStudioSettings(tip: PawStudioTip.flat, flow: .65, texture: .55)
      .toPreset('paper-flat', 1),
);
await PawDabResource.prepareAsync(
  preset.definition,
  rasterProgram: preset.rasterProgram,
);
final backend = PawDabStreamingBackend.forPreset(preset);
```

For complete pointer, painting, and disposal code, see the [example app](example/lib/main.dart).

## Engine structure

`DrawingInputSample` → modeled centerline → arc-length emission → material commands → live paint or raster output.

The model seals stable geometry and keeps a mutable tail for recent input. The renderer consumes the resulting segments and reuses work from the stable prefix. Presets select geometry, grain, and deposition behavior before a stroke begins. The [engine modules](lib/src/engine/) contain the modeler, preset compiler, emission, material passes, and rendering caches. The package also includes draw-and-hold geometry assistance and an eraser mask path for host applications.

This edition uses a newly generated, tileable noise lattice for the contact shader. The paper pattern differs from the PawDoodle app's bundled texture.

## Development

From the repository root:

```sh
flutter pub get
flutter analyze
flutter test
```

The tests use synthetic input to cover preset serialization, brush size, render-cache ownership, material continuity, and bounded streaming work.

## Credits and license

MIT licensed. See [LICENSE](LICENSE). The [design references](docs/references.md) cover stroke modeling, brush parameters, and material rendering.
