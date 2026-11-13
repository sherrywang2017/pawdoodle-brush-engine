import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// Pixel transfer is applied to the complete stroke contact in each tile,
/// after neighboring geometry chunks have been composed. Paper can remove a
/// contact or change its wet boundary instead of merely tinting a soft ribbon.
class PawContactMaterialPrograms {
  static ui.FragmentProgram? _program;
  static ui.Image? _noise;
  static Future<void>? _loading;
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> prepare() =>
      isReady ? Future<void>.value() : (_loading ??= _load());

  static Future<void> _load() async {
    try {
      const paperAsset = 'assets/brush_resources/paper_noise.png';
      const packagePrefix = 'packages/pawdoodle_brush_engine/';
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final prefix = manifest.listAssets().contains('$packagePrefix$paperAsset')
          ? packagePrefix
          : '';
      _program = await ui.FragmentProgram.fromAsset(
        '${prefix}assets/shaders/contact_material.frag',
      );
      final bytes = await rootBundle.load('$prefix$paperAsset');
      final codec = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      try {
        _noise = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      await _warmRasterPipelines();
      _ready = true;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  // Loading a FragmentProgram does not execute the mask -> runtime shader ->
  // image pipeline. Exercise both material branches before a tool is ready,
  // to reduce deferred GPU compilation during the first moving contact.
  static Future<void> _warmRasterPipelines() async {
    final vertices = ui.Vertices(
      ui.VertexMode.triangleStrip,
      const [
        ui.Offset(20, 20),
        ui.Offset(160, 20),
        ui.Offset(20, 76),
        ui.Offset(160, 76),
      ],
      colors: const [
        ui.Color(0x88ff80ff),
        ui.Color(0x99ee90ff),
        ui.Color(0x77ff8080),
        ui.Color(0x99ff90ff),
      ],
      textureCoordinates: const [
        ui.Offset.zero,
        ui.Offset.zero,
        ui.Offset.zero,
        ui.Offset.zero,
      ],
    );
    try {
      for (final wet in [false, true]) {
        final surface = PawContactMaterialSurface();
        try {
          final recorder = ui.PictureRecorder();
          surface.paint(
            canvas: ui.Canvas(recorder),
            revision: 1,
            targetRasterScale: 2,
            logicalSize: const ui.Size(192, 96),
            dirtyBounds: const [ui.Rect.fromLTWH(0, 0, 192, 96)],
            settings: PawContactMaterialSettings(
              wet: wet,
              scale: 1,
              strength: .6,
              density: 5,
              dilution: .5,
              bleed: .5,
              diffusion: 1,
              granulation: .5,
              opacity: .6,
              residue: .2,
              seed: 17,
              detail: .4,
              rotation: 0,
              fineScale: 1,
            ),
            paintContact: (canvas, _) => canvas.drawVertices(
              vertices,
              ui.BlendMode.dst,
              ui.Paint()..isAntiAlias = false,
            ),
          );
          final picture = recorder.endRecording();
          try {
            final image = await picture.toImage(192, 96);
            try {
              // Force completion; a lazy image handle alone leaves GPU work
              // for the first user stroke. This readback is preparation only.
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
          }
        } finally {
          surface.dispose();
        }
      }
    } finally {
      vertices.dispose();
    }
  }
}

class PawContactMaterialSettings {
  const PawContactMaterialSettings({
    required this.wet,
    required this.scale,
    required this.strength,
    required this.density,
    required this.dilution,
    required this.bleed,
    required this.diffusion,
    required this.granulation,
    required this.opacity,
    required this.residue,
    required this.seed,
    required this.detail,
    required this.rotation,
    required this.fineScale,
    this.coverageGain = 1,
    this.color = const ui.Color(0xff000000),
    this.dragStrength = 0,
    this.dragLength = 1,
    this.dragWidth = 1,
  });

  final bool wet;
  final double scale, strength, density;
  final double dilution, bleed, diffusion, granulation;
  final double opacity, residue, detail;
  final double rotation, fineScale;
  final double coverageGain;
  final ui.Color color;
  final double dragStrength, dragLength, dragWidth;
  final int seed;
}

/// One canonical contact texture per stroke. A single synchronous mask
/// snapshot avoids serial GPU readbacks and surface resizes for every dirty
/// tile. The material stays a GPU picture and reconstructs document texels.
class PawContactMaterialSurface {
  ui.Image? _contact;
  ui.FragmentShader? _shader;
  ui.Picture? _material;
  int? _revision;
  ui.Size? _logicalSize;
  ui.Rect _paintBounds = ui.Rect.zero;
  int lastUpdatedTileCount = 0;
  int lastRasterBatchCount = 0;

  int get rgbaBytes =>
      _contact == null ? 0 : _contact!.width * _contact!.height * 4;
  // Keep the diagnostic accessor compatible: this backend owns one complete
  // document tile instead of a grid of independently snapshotted regions.
  int get tileCount => _contact == null ? 0 : 1;

  void paint({
    required ui.Canvas canvas,
    required int revision,
    required double targetRasterScale,
    required ui.Size logicalSize,
    required Iterable<ui.Rect> dirtyBounds,
    required PawContactMaterialSettings settings,
    bool cropToContact = false,
    ui.Rect? contactBounds,
    required void Function(ui.Canvas canvas, ui.Rect bounds) paintContact,
  }) {
    final program = PawContactMaterialPrograms._program;
    if (program == null) {
      throw StateError(
        'Contact material program must be prepared before paint.',
      );
    }
    const rasterScale = 2.0;
    lastUpdatedTileCount = lastRasterBatchCount = 0;
    final changes = dirtyBounds.where((bounds) => !bounds.isEmpty).toList();
    if (_material != null && _logicalSize == logicalSize && changes.isEmpty) {
      // Freeze/promotion can change the revision without changing contact.
      // Ownership transfer must not schedule another GPU readback.
      _revision = revision;
    }
    if (_revision != revision || _logicalSize != logicalSize) {
      final document = ui.Offset.zero & logicalSize;
      if (_logicalSize != logicalSize) _paintBounds = ui.Rect.zero;
      for (final bounds in changes) {
        _paintBounds = _paintBounds.isEmpty
            ? bounds
            : _paintBounds.expandToInclude(bounds);
      }
      // A complete swept mask can shrink as a tap becomes a tapered stroke.
      // Use its current support, not the historical dirty union, so fresh and
      // retained renders choose the same crop origin and raster rounding.
      if (cropToContact && contactBounds != null) _paintBounds = contactBounds;
      // One image, aligned to the same 2x document lattice. Empty document
      // pixels need no GPU readback; the gutter includes every wet lookup.
      // Keep one contiguous mask so there are no tile interpolation seams.
      // Retained triangle pictures keep their original fixed-origin raster.
      // Rebasing those pictures introduces mask rounding amplified by wax
      // transfer. The continuous path backend opts into cropped contact.
      final occupied = cropToContact
          ? _paintBounds.inflate(4).intersect(document.inflate(4))
          : document.inflate(4);
      final padded = ui.Rect.fromLTRB(
        (occupied.left * rasterScale).floor() / rasterScale,
        (occupied.top * rasterScale).floor() / rasterScale,
        (occupied.right * rasterScale).ceil() / rasterScale,
        (occupied.bottom * rasterScale).ceil() / rasterScale,
      );
      final width = (padded.width * rasterScale).ceil();
      final height = (padded.height * rasterScale).ceil();
      final recorder = ui.PictureRecorder();
      final mask = ui.Canvas(recorder)
        ..scale(rasterScale)
        ..translate(-padded.left, -padded.top)
        ..clipRect(padded, doAntiAlias: false);
      paintContact(mask, padded);
      final picture = recorder.endRecording();
      final ui.Image image;
      try {
        image = picture.toImageSync(width, height);
      } finally {
        picture.dispose();
      }
      final shader = program.fragmentShader();
      final values = <double>[
        padded.left,
        padded.top,
        padded.width,
        padded.height,
        width.toDouble(),
        height.toDouble(),
        settings.wet ? 1 : 0,
        settings.scale,
        settings.strength,
        settings.density,
        settings.dilution,
        settings.bleed,
        settings.diffusion,
        settings.granulation,
        settings.opacity,
        settings.residue,
        (settings.seed & 4095).toDouble(),
        settings.detail,
        settings.rotation,
        settings.fineScale,
        settings.coverageGain,
        settings.color.r,
        settings.color.g,
        settings.color.b,
        settings.dragStrength,
        settings.dragLength,
        settings.dragWidth,
      ];
      for (var i = 0; i < values.length; i++) {
        shader.setFloat(i, values[i]);
      }
      shader.setImageSampler(0, image, filterQuality: ui.FilterQuality.low);
      shader.setImageSampler(
        1,
        PawContactMaterialPrograms._noise!,
        filterQuality: ui.FilterQuality.low,
      );
      final output = ui.PictureRecorder();
      // Water can read outside contact, but cannot reach the entire empty
      // canvas. Include the maximum capillary displacement, radial water
      // gather and canonical interpolation support before clipping.
      final reach = settings.wet
          ? settings.diffusion * (.5 * (1 + settings.bleed) + 2.4) + 1
          : 1.0;
      ui.Canvas(output).drawRect(
        _paintBounds.inflate(reach).intersect(document),
        ui.Paint()
          ..isAntiAlias = false
          ..shader = shader,
      );
      final material = output.endRecording();
      _material?.dispose();
      _shader?.dispose();
      _contact?.dispose();
      _contact = image;
      _shader = shader;
      _material = material;
      _logicalSize = logicalSize;
      _revision = revision;
      lastUpdatedTileCount = tileCount;
      lastRasterBatchCount = 1;
    }
    canvas.drawPicture(_material!);
  }

  void clear() {
    _material?.dispose();
    _shader?.dispose();
    _contact?.dispose();
    _material = null;
    _shader = null;
    _contact = null;
    _revision = null;
    _logicalSize = null;
    _paintBounds = ui.Rect.zero;
    lastUpdatedTileCount = lastRasterBatchCount = 0;
  }

  void dispose() => clear();
}
