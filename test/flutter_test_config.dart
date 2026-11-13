import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/pawdoodle_brush_engine.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await PawContactMaterialPrograms.prepare();
  await testMain();
}
