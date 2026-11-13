// Public entry point. Implementation modules share this library so private
// state and existing import paths keep their original visibility.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'smooth_stroke.dart';
import 'streaming_stroke_parameters.dart';
import 'touch_path_conditioner.dart';

part 'engine/modeling/centerline_input.dart';
part 'engine/modeling/centerline_modeler.dart';
part 'engine/modeling/centerline_sampling.dart';
part 'engine/modeling/centerline_tail.dart';
part 'engine/modeling/centerline_turns.dart';
part 'engine/modeling/curvature_prediction.dart';
part 'engine/modeling/curve_geometry.dart';
part 'engine/modeling/local_geometry_evidence.dart';
part 'engine/modeling/streaming_segment.dart';
part 'engine/modeling/turn_geometry.dart';
