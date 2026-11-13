import 'dart:js_interop';

@JS('Math.imul')
external JSNumber _multiplyInt32(JSNumber a, JSNumber b);

/// Exact low bits using the browser's integer multiply instruction.
int pawMultiplyUint32(int a, int b) =>
    _multiplyInt32(a.toJS, b.toJS).toDartInt & 0xffffffff;
