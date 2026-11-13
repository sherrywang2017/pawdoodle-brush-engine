import 'package:flutter_test/flutter_test.dart';
import 'package:pawdoodle_brush_engine/src/brush_arithmetic.dart';

void main() {
  test('brush noise multiplication preserves low bits on VM and Web', () {
    final mask = BigInt.from(0xffffffff);
    for (final a in [
      0,
      1,
      -1,
      0x80000000,
      0xffffffff,
      0x85ebca6b,
      0x1fffffffff
    ]) {
      for (final b in [
        0,
        1,
        -1,
        0x7feb352d,
        0x45d9f3b,
        0xffffffff,
        0x27d4eb2d
      ]) {
        final expected = ((BigInt.from(a) * BigInt.from(b)) & mask).toInt();
        expect(pawMultiplyUint32(a, b), expected, reason: '$a * $b');
      }
    }
  });
}
