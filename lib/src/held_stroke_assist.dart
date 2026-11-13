// Public entry point. Implementation modules share this library so private
// state and existing import paths keep their original visibility.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'held_curve_fitter.dart';
import 'held_curve_fairer.dart';
import 'smooth_stroke.dart';
import 'streaming_stroke_modeler.dart';

part 'engine/assist/held_bezier_quality.dart';
part 'engine/assist/hold_classifier.dart';
part 'engine/assist/hold_controller.dart';
part 'engine/assist/hold_curve_generation.dart';
part 'engine/assist/hold_curve_sampling.dart';
part 'engine/assist/hold_geometry.dart';
part 'engine/assist/hold_refiner.dart';
part 'engine/assist/hold_shape_fits.dart';
part 'engine/assist/hold_shape_fitting.dart';
part 'engine/assist/hold_types.dart';
