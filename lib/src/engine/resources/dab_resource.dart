part of '../../streaming_dab_brush.dart';

class _PawDabCachedAtlas {
  _PawDabCachedAtlas({
    required this.image,
    required this.variantRects,
    required this.pixelsPerLogicalUnit,
    required this.textureTile,
  });

  final ui.Image image;
  final List<Rect> variantRects;
  final double pixelsPerLogicalUnit;
  final ui.Image textureTile;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
    textureTile.dispose();
    PawDabResource._ownerImageDisposalCount++;
  }
}

class _PawDabAtlasRecording {
  const _PawDabAtlasRecording({
    required this.picture,
    required this.width,
    required this.height,
    required this.variantRects,
    required this.pixelsPerLogicalUnit,
  });

  final ui.Picture picture;
  final int width;
  final int height;
  final List<Rect> variantRects;
  final double pixelsPerLogicalUnit;
}

class _PawDabCachedRasterTexture {
  _PawDabCachedRasterTexture(this.image);

  final ui.Image image;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    image.dispose();
  }
}

class PawDabResource {
  PawDabResource._({
    required this.key,
    required ui.Image atlas,
    required ui.Image textureTile,
    required this.variantRects,
    required this.pixelsPerLogicalUnit,
    required FilterQuality textureFilterQuality,
  })  : _atlas = atlas,
        _textureTile = textureTile,
        _atlasShader = ui.ImageShader(
          atlas,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        ),
        _textureShader = ui.ImageShader(
          textureTile,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().storage,
          filterQuality: textureFilterQuality,
        );

  static const int cacheCapacity = 8;
  static const int _atlasCellPixels = 160;
  static const int _atlasGutterPixels = 4;
  static const int _atlasCellStride = _atlasCellPixels + _atlasGutterPixels * 2;
  static const int _atlasMaximumColumns = 8;
  // The cached micro texture is deliberately much larger than a brush tip.
  // Its coordinates are selected by the grain program: paper/wax can remain
  // canvas-fixed while dragged fibers follow absolute arc through a turn.
  static const int _textureTilePixels = 256;
  static const int _rasterTextureCacheCapacity = 8;

  static final Map<String, _PawDabCachedAtlas> _cache =
      <String, _PawDabCachedAtlas>{};
  static final Map<(String, PawPreparedBrushRasterProgram),
          _PawDabCachedRasterTexture> _rasterTextureCache =
      <(String, PawPreparedBrushRasterProgram), _PawDabCachedRasterTexture>{};
  static final Map<(String, PawPreparedBrushRasterProgram?), Future<void>>
      _asyncPreparations =
      <(String, PawPreparedBrushRasterProgram?), Future<void>>{};
  static int _cacheGeneration = 0;
  static int _atlasCreationCount = 0;
  static int _evictionCount = 0;
  static int _ownerImageDisposalCount = 0;
  static int _liveLeaseCount = 0;
  static int _leaseImageDisposalCount = 0;

  final String key;
  final ui.Image _atlas;
  final ui.Image _textureTile;
  final ui.ImageShader _atlasShader;
  final ui.ImageShader _textureShader;
  final List<Rect> variantRects;
  final double pixelsPerLogicalUnit;
  bool _disposed = false;

  int get variantCount => variantRects.length;

  ui.Image get atlas {
    if (_disposed) throw StateError('Dab atlas lease is disposed.');
    return _atlas;
  }

  ui.ImageShader get textureShader {
    if (_disposed) throw StateError('Dab texture tile lease is disposed.');
    return _textureShader;
  }

  static PawDabResourceCacheDiagnostics get diagnostics =>
      PawDabResourceCacheDiagnostics(
        entryCount: _cache.length,
        capacity: cacheCapacity,
        atlasCreationCount: _atlasCreationCount,
        evictionCount: _evictionCount,
        ownerImageDisposalCount: _ownerImageDisposalCount,
        liveLeaseCount: _liveLeaseCount,
        leaseImageDisposalCount: _leaseImageDisposalCount,
        keys: List<String>.unmodifiable(_cache.keys),
      );

  static int get _creationCount => _atlasCreationCount;

  static Future<void> prewarm() async {
    for (final definition in <PawDabBrushDefinition>[
      PawDabBrushDefinitions.round,
      PawDabBrushDefinitions.crayon,
      PawDabBrushDefinitions.marker,
      PawDabBrushDefinitions.soft,
      PawDabBrushDefinitions.ink,
      PawDabBrushDefinitions.fur,
      PawDabBrushDefinitions.eraser,
    ]) {
      definition.validate();
      await prepareAsync(definition);
    }
  }

  static String _key(PawDabBrushDefinition definition) =>
      '${definition.id}|${definition.revision}';

  static bool _usesContactPixelTransfer(
    PawDabBrushDefinition definition, {
    PawPreparedBrushRasterProgram? rasterProgram,
  }) =>
      rasterProgram?.hasHighFrequencyCoverage != true &&
      definition.grain.coordinate == PawDabGrainCoordinate.canvasFixed &&
      definition.grain.movement == 0 &&
      ((definition.dryWax.enabled &&
              definition.grain.structure ==
                  PawDabGrainStructure.waxAggregate) ||
          (definition.wetMedia.enabled &&
              definition.grain.structure ==
                  PawDabGrainStructure.absorbentWash));

  /// Returns true only when the complete material required by the preset is
  /// ready for synchronous acquisition by the live renderer.
  static bool isPrepared(
    PawDabBrushDefinition definition, {
    PawPreparedBrushRasterProgram? rasterProgram,
  }) {
    if (_usesContactPixelTransfer(definition, rasterProgram: rasterProgram) &&
        !PawContactMaterialPrograms.isReady) {
      return false;
    }
    final key = _key(definition);
    if (!_cache.containsKey(key)) return false;
    if (rasterProgram?.hasHighFrequencyCoverage == true) {
      return _rasterTextureCache.containsKey((key, rasterProgram));
    }
    return true;
  }

  /// Materializes a brush with the platform-safe asynchronous image APIs.
  ///
  /// The synchronous [prepare] method remains for deterministic offline tests
  /// and native callers that explicitly need it. Production Web startup and
  /// tool selection use this method, so `Picture.toImageSync` is never on the
  /// boot path.
  static Future<void> prepareAsync(
    PawDabBrushDefinition definition, {
    PawPreparedBrushRasterProgram? rasterProgram,
  }) {
    definition.validate();
    if (isPrepared(definition, rasterProgram: rasterProgram)) {
      return Future<void>.value();
    }
    final key = _key(definition);
    final preparationKey = (key, rasterProgram);
    final pending = _asyncPreparations[preparationKey];
    if (pending != null) return pending;
    final generation = _cacheGeneration;
    final future = _prepareAsync(
      definition,
      rasterProgram: rasterProgram,
      generation: generation,
    );
    _asyncPreparations[preparationKey] = future;
    future.then<void>(
      (_) {
        if (identical(_asyncPreparations[preparationKey], future)) {
          _asyncPreparations.remove(preparationKey);
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_asyncPreparations[preparationKey], future)) {
          _asyncPreparations.remove(preparationKey);
        }
      },
    );
    return future;
  }

  static Future<void> _prepareAsync(
    PawDabBrushDefinition definition, {
    required PawPreparedBrushRasterProgram? rasterProgram,
    required int generation,
  }) async {
    // Let the caller return to the frame/event loop before recording any
    // atlas, texture tile, or high-frequency raster picture.
    await Future<void>.value();
    if (_usesContactPixelTransfer(definition, rasterProgram: rasterProgram) &&
        !PawContactMaterialPrograms.isReady) {
      await PawContactMaterialPrograms.prepare();
    }
    if (isPrepared(definition, rasterProgram: rasterProgram)) return;

    final key = _key(definition);
    if (!_cache.containsKey(key)) {
      final atlas = await _DabAtlasFactory._createAtlasAsync(definition);
      if (generation != _cacheGeneration) {
        atlas.dispose();
        throw StateError('Dab resource cache changed during async prepare.');
      }
      if (_cache.containsKey(key)) {
        atlas.dispose();
      } else {
        _storeAtlas(key, atlas);
      }
    }

    if (rasterProgram?.hasHighFrequencyCoverage == true &&
        !_rasterTextureCache.containsKey((key, rasterProgram))) {
      final baseTexture = _cache[key]!.textureTile;
      final texture = await _DabRasterTexture._createRasterTextureAsync(
        baseTexture: baseTexture,
        rasterProgram: rasterProgram!,
      );
      if (generation != _cacheGeneration) {
        texture.dispose();
        throw StateError('Dab resource cache changed during async prepare.');
      }
      final rasterKey = (key, rasterProgram);
      final existing = _rasterTextureCache[rasterKey];
      if (existing == null) {
        _rasterTextureCache[rasterKey] = _PawDabCachedRasterTexture(texture);
        _trimRasterTextureCache();
      } else {
        texture.dispose();
      }
    }
  }

  static void prepare(
    PawDabBrushDefinition definition, {
    PawPreparedBrushRasterProgram? rasterProgram,
  }) {
    definition.validate();
    final key = _key(definition);
    final existing = _cache.remove(key);
    if (existing != null) {
      _cache[key] = existing;
    } else {
      _storeAtlas(key, _DabAtlasFactory._createAtlas(definition));
    }
    if (rasterProgram?.hasHighFrequencyCoverage == true) {
      final rasterKey = (key, rasterProgram!);
      final cachedTexture = _rasterTextureCache.remove(rasterKey);
      if (cachedTexture != null) {
        _rasterTextureCache[rasterKey] = cachedTexture;
      } else {
        _rasterTextureCache[rasterKey] = _PawDabCachedRasterTexture(
          _DabRasterTexture._createRasterTexture(
            baseTexture: _cache[key]!.textureTile,
            rasterProgram: rasterProgram,
          ),
        );
        _trimRasterTextureCache();
      }
    }
  }

  static void _storeAtlas(String key, _PawDabCachedAtlas atlas) {
    _cache[key] = atlas;
    _atlasCreationCount++;
    while (_cache.length > cacheCapacity) {
      final oldestKey = _cache.keys.first;
      final evicted = _cache.remove(oldestKey)!;
      _evictionCount++;
      evicted.dispose();
    }
  }

  static void _trimRasterTextureCache() {
    while (_rasterTextureCache.length > _rasterTextureCacheCapacity) {
      final oldestKey = _rasterTextureCache.keys.first;
      _rasterTextureCache.remove(oldestKey)!.dispose();
    }
  }

  static PawDabResource acquirePrepared(
    PawDabBrushDefinition definition, {
    PawPreparedBrushRasterProgram? rasterProgram,
  }) {
    final key = _key(definition);
    final cached = _cache.remove(key);
    if (cached == null) {
      throw StateError(
        'Dab atlas $key was not prepared before the render cache acquired it.',
      );
    }
    _cache[key] = cached;
    final rasterTexture = rasterProgram?.hasHighFrequencyCoverage == true
        ? _rasterTextureCache[(key, rasterProgram)]
        : null;
    if (rasterProgram?.hasHighFrequencyCoverage == true &&
        rasterTexture == null) {
      throw StateError(
        'Dab raster texture $key was not prepared before acquisition.',
      );
    }
    _liveLeaseCount++;
    return PawDabResource._(
      key: key,
      atlas: cached.image.clone(),
      textureTile: (rasterTexture?.image ?? cached.textureTile).clone(),
      variantRects: cached.variantRects,
      pixelsPerLogicalUnit: cached.pixelsPerLogicalUnit,
      textureFilterQuality:
          rasterProgram?.detailFilterQuality ?? FilterQuality.medium,
    );
  }

  ui.ImageShader get atlasShader {
    if (_disposed) throw StateError('Dab atlas shader lease is disposed.');
    return _atlasShader;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _atlasShader.dispose();
    _textureShader.dispose();
    // CanvasKit's CkImageShader takes ownership of the exact CkImage handle
    // passed to its constructor and disposes it with the shader. Native and
    // Skwasm shaders do not dispose the Dart image wrapper, so the resource
    // remains its sole explicit owner on those backends.
    if (!kIsWeb || kIsWasm) {
      _atlas.dispose();
      _textureTile.dispose();
    }
    _liveLeaseCount--;
    _leaseImageDisposalCount++;
  }

  @visibleForTesting
  static void debugResetCache() {
    _cacheGeneration++;
    _asyncPreparations.clear();
    if (_liveLeaseCount != 0) {
      throw StateError('Cannot reset the Dab atlas cache with live leases.');
    }
    for (final cached in _cache.values) {
      cached.dispose();
    }
    _cache.clear();
    for (final cached in _rasterTextureCache.values) {
      cached.dispose();
    }
    _rasterTextureCache.clear();
    _atlasCreationCount = 0;
    _evictionCount = 0;
    _ownerImageDisposalCount = 0;
    _leaseImageDisposalCount = 0;
  }

  static int _hash(int seed, int index) {
    var value = (seed ^ pawMultiplyUint32(index, 0x85ebca6b)) & 0xffffffff;
    value ^= value >> 16;
    value = pawMultiplyUint32(value, 0x7feb352d);
    value ^= value >> 15;
    return value;
  }

  static double _unit(int value) => (value & 0xffff) / 0xffff;

  static double _unitWindow(int value, int shift) {
    final windowShift = shift & 31;
    if (windowShift == 0) return _unit(value);
    final masked = value & 0xffffffff;
    final rotated = ((masked >> windowShift) |
            ((masked << (32 - windowShift)) & 0xffffffff)) &
        0xffffffff;
    return _unit(rotated);
  }

  static double _valueNoise2D(double x, double y, int seed) {
    final left = x.floor();
    final top = y.floor();
    final tx = _smoothStep(x - left);
    final ty = _smoothStep(y - top);
    double lattice(int cellX, int cellY) => _unit(
          _hash(seed ^ cellX * 0x45d9f3b, cellY * 0x27d4eb2d),
        );
    final a = lattice(left, top), b = lattice(left + 1, top);
    final c = lattice(left, top + 1), d = lattice(left + 1, top + 1);
    final upper = a + (b - a) * tx;
    final lower = c + (d - c) * tx;
    return upper + (lower - upper) * ty;
  }
}
