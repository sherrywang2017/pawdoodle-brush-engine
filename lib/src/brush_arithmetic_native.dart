/// Native integer multiplication retains the low 32 bits, including overflow.
int pawMultiplyUint32(int a, int b) => (a * b) & 0xffffffff;
