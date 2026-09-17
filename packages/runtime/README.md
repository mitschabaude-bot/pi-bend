# Bend runtime foundations

This package supplies primitives missing from Bend 2.0.4 that the faithful pi library port requires. Implementations are pure Bend. The compiler's normal native backend is used without prototype C effects, host numeric callbacks or JavaScript runtime support.

`src/u64.bend` implements unsigned fixed-width arithmetic modulo 2^64, bit operations, logical shifts, rotations, comparison, and quotient/remainder division. Values use two U32 limbs, ordered high then low. Division by zero returns `None`; shifts of at least 64 bits produce zero; rotations reduce their count modulo 64. `multiplyWords` exposes the exact 32-by-32-bit product needed by wider arithmetic.

`src/f64.bend` represents every IEEE-754 binary64 bit pattern and implements addition and subtraction with round-to-nearest, ties-to-even. It retains signed zeros and subnormal results. Arithmetic NaNs become a canonical quiet NaN; payload preservation is not an API guarantee. Alignment retains guard, round and sticky bits, and subtraction normalizes cancellation before rounding. Operations never pass through F32. Multiplication, division, comparison, numeric/decimal conversion and formatting remain to be implemented before this can support pi's number APIs.

Run the independent vector tests from the repository root:

```sh
python3 tests/u64_vectors.py
python3 tests/f64_vectors.py
```

Python generates expected results from arbitrary-precision integers and host binary64 arithmetic. It writes constant input/output vectors, then compiles and executes Bend assertions. Python supplies no behavior to the implementation or native executable. The tests currently cover 272 unsigned arithmetic vectors and 821 floating-point vectors. These tests supplement, rather than replace, the future port of pi's numeric and model-cost tests.
