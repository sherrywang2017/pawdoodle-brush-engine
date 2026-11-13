// Public entry point. Implementation modules share this library so private
// state and existing import paths keep their original visibility.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'brush_behavior.dart';
import 'brush_kernel.dart';
import 'brush_raster_resource.dart';
import 'brush_shape_field.dart';
import 'drawing_raster.dart' show DrawingTool;
import 'smooth_stroke.dart';
import 'streaming_dab_brush.dart';
import 'unified_brush_program.dart';

export 'brush_kernel.dart' show PawBrushKernelKind;
export 'unified_brush_program.dart';

part 'engine/presets/brush_preset_catalog.dart';
part 'engine/presets/brush_preset_compiler.dart';
part 'engine/presets/brush_preset_json.dart';
part 'engine/presets/brush_program_compiler.dart';
part 'engine/presets/compiled_brush_preset.dart';
part 'engine/presets/user_brush_preset_v1.dart';
part 'engine/presets/user_brush_preset_v2.dart';
