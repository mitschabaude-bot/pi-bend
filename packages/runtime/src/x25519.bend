import Base

# X25519, RFC 7748. Field elements are sixteen little-endian 16-bit limbs in a
# fixed record, holding any value below 2^256; `canonical` reduces below
# p = 2^255 - 19 only for output. Every limb product with its carries fits a
# U32 exactly, and 2^256 = 38 (mod p) folds overflow. Secret-dependent choices
# use masks: no scalar bit or field value selects a branch or a table entry.
type Error is Data:
  InvalidLength{}
  InvalidByte{}
  LowOrderPoint{}

def repeat(count: Nat, +byte: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: repeat(rest, byte, byte <> tail)

# The 32-byte little-endian encoding of a small number (TLS uses small(0)).
def small(+value: U32) -> List<&2, U32>:
  U32.and(value, 255) <> U32.and(U32.shrn(value, 8n), 255) <> U32.and(U32.shrn(value, 16n), 255) <> U32.shrn(value, 24n) <> repeat(28n, 0, Nil{})

type Fe is Data:
  Fe{l0: U32, l1: U32, l2: U32, l3: U32, l4: U32, l5: U32, l6: U32, l7: U32, l8: U32, l9: U32, l10: U32, l11: U32, l12: U32, l13: U32, l14: U32, l15: U32}

type Row is Data:
  Row{low: U32, rest: Fe}

def zero() -> Fe: Fe{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
def one() -> Fe: Fe{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

# Limbs below 2^31 in, limbs below 2^16 out: two carry passes fold each
# overflow of 2^256 as 38. After the second pass overflows, the low value is
# below 2^21, so the last fold touches only limbs 0 and 1.
def settle(value: Fe) -> Fe:
  match value:
    case Fe{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15}:
      +c0 = x0
      +c1 = (x1 + U32.shrn(c0, 16n) : U32)
      +c2 = (x2 + U32.shrn(c1, 16n) : U32)
      +c3 = (x3 + U32.shrn(c2, 16n) : U32)
      +c4 = (x4 + U32.shrn(c3, 16n) : U32)
      +c5 = (x5 + U32.shrn(c4, 16n) : U32)
      +c6 = (x6 + U32.shrn(c5, 16n) : U32)
      +c7 = (x7 + U32.shrn(c6, 16n) : U32)
      +c8 = (x8 + U32.shrn(c7, 16n) : U32)
      +c9 = (x9 + U32.shrn(c8, 16n) : U32)
      +c10 = (x10 + U32.shrn(c9, 16n) : U32)
      +c11 = (x11 + U32.shrn(c10, 16n) : U32)
      +c12 = (x12 + U32.shrn(c11, 16n) : U32)
      +c13 = (x13 + U32.shrn(c12, 16n) : U32)
      +c14 = (x14 + U32.shrn(c13, 16n) : U32)
      +c15 = (x15 + U32.shrn(c14, 16n) : U32)
      +d0 = (U32.and(c0, 65535) + U32.shrn(c15, 16n) * 38 : U32)
      +d1 = (U32.and(c1, 65535) + U32.shrn(d0, 16n) : U32)
      +d2 = (U32.and(c2, 65535) + U32.shrn(d1, 16n) : U32)
      +d3 = (U32.and(c3, 65535) + U32.shrn(d2, 16n) : U32)
      +d4 = (U32.and(c4, 65535) + U32.shrn(d3, 16n) : U32)
      +d5 = (U32.and(c5, 65535) + U32.shrn(d4, 16n) : U32)
      +d6 = (U32.and(c6, 65535) + U32.shrn(d5, 16n) : U32)
      +d7 = (U32.and(c7, 65535) + U32.shrn(d6, 16n) : U32)
      +d8 = (U32.and(c8, 65535) + U32.shrn(d7, 16n) : U32)
      +d9 = (U32.and(c9, 65535) + U32.shrn(d8, 16n) : U32)
      +d10 = (U32.and(c10, 65535) + U32.shrn(d9, 16n) : U32)
      +d11 = (U32.and(c11, 65535) + U32.shrn(d10, 16n) : U32)
      +d12 = (U32.and(c12, 65535) + U32.shrn(d11, 16n) : U32)
      +d13 = (U32.and(c13, 65535) + U32.shrn(d12, 16n) : U32)
      +d14 = (U32.and(c14, 65535) + U32.shrn(d13, 16n) : U32)
      +d15 = (U32.and(c15, 65535) + U32.shrn(d14, 16n) : U32)
      +e0 = (U32.and(d0, 65535) + U32.shrn(d15, 16n) * 38 : U32)
      Fe{U32.and(e0, 65535), (U32.and(d1, 65535) + U32.shrn(e0, 16n) : U32), U32.and(d2, 65535), U32.and(d3, 65535), U32.and(d4, 65535), U32.and(d5, 65535), U32.and(d6, 65535), U32.and(d7, 65535), U32.and(d8, 65535), U32.and(d9, 65535), U32.and(d10, 65535), U32.and(d11, 65535), U32.and(d12, 65535), U32.and(d13, 65535), U32.and(d14, 65535), U32.and(d15, 65535)}

def add(a: Fe, b: Fe) -> Fe:
  match a b:
    case Fe{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15} Fe{b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15}:
      settle(Fe{(a0 + b0 : U32), (a1 + b1 : U32), (a2 + b2 : U32), (a3 + b3 : U32), (a4 + b4 : U32), (a5 + b5 : U32), (a6 + b6 : U32), (a7 + b7 : U32), (a8 + b8 : U32), (a9 + b9 : U32), (a10 + b10 : U32), (a11 + b11 : U32), (a12 + b12 : U32), (a13 + b13 : U32), (a14 + b14 : U32), (a15 + b15 : U32)})

# Adds 4p = 2^257 - 76 in limbs of at least 2^17 - 76, so no limb goes negative.
def sub(a: Fe, b: Fe) -> Fe:
  match a b:
    case Fe{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15} Fe{b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15}:
      settle(Fe{(a0 + 130996 - b0 : U32), (a1 + 131070 - b1 : U32), (a2 + 131070 - b2 : U32), (a3 + 131070 - b3 : U32), (a4 + 131070 - b4 : U32), (a5 + 131070 - b5 : U32), (a6 + 131070 - b6 : U32), (a7 + 131070 - b7 : U32), (a8 + 131070 - b8 : U32), (a9 + 131070 - b9 : U32), (a10 + 131070 - b10 : U32), (a11 + 131070 - b11 : U32), (a12 + 131070 - b12 : U32), (a13 + 131070 - b13 : U32), (a14 + 131070 - b14 : U32), (a15 + 131070 - b15 : U32)})

# 65535 * 65535 + 65535 + 65535 = 2^32 - 1: a row never overflows.
def row(+a: U32, b: Fe, acc: Fe) -> Row:
  match b acc:
    case Fe{b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12, b13, b14, b15} Fe{c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15}:
      +t0 = (a * b0 + c0 : U32)
      +t1 = (a * b1 + c1 + U32.shrn(t0, 16n) : U32)
      +t2 = (a * b2 + c2 + U32.shrn(t1, 16n) : U32)
      +t3 = (a * b3 + c3 + U32.shrn(t2, 16n) : U32)
      +t4 = (a * b4 + c4 + U32.shrn(t3, 16n) : U32)
      +t5 = (a * b5 + c5 + U32.shrn(t4, 16n) : U32)
      +t6 = (a * b6 + c6 + U32.shrn(t5, 16n) : U32)
      +t7 = (a * b7 + c7 + U32.shrn(t6, 16n) : U32)
      +t8 = (a * b8 + c8 + U32.shrn(t7, 16n) : U32)
      +t9 = (a * b9 + c9 + U32.shrn(t8, 16n) : U32)
      +t10 = (a * b10 + c10 + U32.shrn(t9, 16n) : U32)
      +t11 = (a * b11 + c11 + U32.shrn(t10, 16n) : U32)
      +t12 = (a * b12 + c12 + U32.shrn(t11, 16n) : U32)
      +t13 = (a * b13 + c13 + U32.shrn(t12, 16n) : U32)
      +t14 = (a * b14 + c14 + U32.shrn(t13, 16n) : U32)
      +t15 = (a * b15 + c15 + U32.shrn(t14, 16n) : U32)
      Row{U32.and(t0, 65535), Fe{U32.and(t1, 65535), U32.and(t2, 65535), U32.and(t3, 65535), U32.and(t4, 65535), U32.and(t5, 65535), U32.and(t6, 65535), U32.and(t7, 65535), U32.and(t8, 65535), U32.and(t9, 65535), U32.and(t10, 65535), U32.and(t11, 65535), U32.and(t12, 65535), U32.and(t13, 65535), U32.and(t14, 65535), U32.and(t15, 65535), U32.shrn(t15, 16n)}}

def rowLow(value: Row) -> U32:
  match value:
    case Row{low, _}: low

def rowRest(value: Row) -> Fe:
  match value:
    case Row{_, rest}: rest

# The high half folds as 38 times itself: below 2^16 + 38 * 2^16 per limb.
def reduce(low: Fe, high: Fe) -> Fe:
  match low high:
    case Fe{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15} Fe{y0, y1, y2, y3, y4, y5, y6, y7, y8, y9, y10, y11, y12, y13, y14, y15}:
      settle(Fe{(x0 + y0 * 38 : U32), (x1 + y1 * 38 : U32), (x2 + y2 * 38 : U32), (x3 + y3 * 38 : U32), (x4 + y4 * 38 : U32), (x5 + y5 * 38 : U32), (x6 + y6 * 38 : U32), (x7 + y7 * 38 : U32), (x8 + y8 * 38 : U32), (x9 + y9 * 38 : U32), (x10 + y10 * 38 : U32), (x11 + y11 * 38 : U32), (x12 + y12 * 38 : U32), (x13 + y13 * 38 : U32), (x14 + y14 * 38 : U32), (x15 + y15 * 38 : U32)})

def mul(a: Fe, +b: Fe) -> Fe:
  match a:
    case Fe{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15}:
      +r0 = row(a0, b, zero())
      +r1 = row(a1, b, rowRest(r0))
      +r2 = row(a2, b, rowRest(r1))
      +r3 = row(a3, b, rowRest(r2))
      +r4 = row(a4, b, rowRest(r3))
      +r5 = row(a5, b, rowRest(r4))
      +r6 = row(a6, b, rowRest(r5))
      +r7 = row(a7, b, rowRest(r6))
      +r8 = row(a8, b, rowRest(r7))
      +r9 = row(a9, b, rowRest(r8))
      +r10 = row(a10, b, rowRest(r9))
      +r11 = row(a11, b, rowRest(r10))
      +r12 = row(a12, b, rowRest(r11))
      +r13 = row(a13, b, rowRest(r12))
      +r14 = row(a14, b, rowRest(r13))
      +r15 = row(a15, b, rowRest(r14))
      reduce(Fe{rowLow(r0), rowLow(r1), rowLow(r2), rowLow(r3), rowLow(r4), rowLow(r5), rowLow(r6), rowLow(r7), rowLow(r8), rowLow(r9), rowLow(r10), rowLow(r11), rowLow(r12), rowLow(r13), rowLow(r14), rowLow(r15)}, rowRest(r15))

# mask is 0 or 2^32 - 1; the choice never branches on a secret.
def select(+mask: U32, a: Fe, b: Fe) -> Fe:
  match a b:
    case Fe{a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15} Fe{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15}:
      Fe{U32.xor(b0, U32.and(mask, U32.xor(a0, b0))), U32.xor(b1, U32.and(mask, U32.xor(a1, b1))), U32.xor(b2, U32.and(mask, U32.xor(a2, b2))), U32.xor(b3, U32.and(mask, U32.xor(a3, b3))), U32.xor(b4, U32.and(mask, U32.xor(a4, b4))), U32.xor(b5, U32.and(mask, U32.xor(a5, b5))), U32.xor(b6, U32.and(mask, U32.xor(a6, b6))), U32.xor(b7, U32.and(mask, U32.xor(a7, b7))), U32.xor(b8, U32.and(mask, U32.xor(a8, b8))), U32.xor(b9, U32.and(mask, U32.xor(a9, b9))), U32.xor(b10, U32.and(mask, U32.xor(a10, b10))), U32.xor(b11, U32.and(mask, U32.xor(a11, b11))), U32.xor(b12, U32.and(mask, U32.xor(a12, b12))), U32.xor(b13, U32.and(mask, U32.xor(a13, b13))), U32.xor(b14, U32.and(mask, U32.xor(a14, b14))), U32.xor(b15, U32.and(mask, U32.xor(a15, b15)))}

# Subtracts p when that does not borrow. Values below 2^256 < 3p need two.
def reduceOnce(value: Fe) -> Fe:
  match value:
    case Fe{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15}:
      +t0 = (x0 - 65517 : U32)
      +t1 = (x1 - 65535 - U32.shrn(t0, 31n) : U32)
      +t2 = (x2 - 65535 - U32.shrn(t1, 31n) : U32)
      +t3 = (x3 - 65535 - U32.shrn(t2, 31n) : U32)
      +t4 = (x4 - 65535 - U32.shrn(t3, 31n) : U32)
      +t5 = (x5 - 65535 - U32.shrn(t4, 31n) : U32)
      +t6 = (x6 - 65535 - U32.shrn(t5, 31n) : U32)
      +t7 = (x7 - 65535 - U32.shrn(t6, 31n) : U32)
      +t8 = (x8 - 65535 - U32.shrn(t7, 31n) : U32)
      +t9 = (x9 - 65535 - U32.shrn(t8, 31n) : U32)
      +t10 = (x10 - 65535 - U32.shrn(t9, 31n) : U32)
      +t11 = (x11 - 65535 - U32.shrn(t10, 31n) : U32)
      +t12 = (x12 - 65535 - U32.shrn(t11, 31n) : U32)
      +t13 = (x13 - 65535 - U32.shrn(t12, 31n) : U32)
      +t14 = (x14 - 65535 - U32.shrn(t13, 31n) : U32)
      +t15 = (x15 - 32767 - U32.shrn(t14, 31n) : U32)
      select((U32.shrn(t15, 31n) - 1 : U32), Fe{U32.and(t0, 65535), U32.and(t1, 65535), U32.and(t2, 65535), U32.and(t3, 65535), U32.and(t4, 65535), U32.and(t5, 65535), U32.and(t6, 65535), U32.and(t7, 65535), U32.and(t8, 65535), U32.and(t9, 65535), U32.and(t10, 65535), U32.and(t11, 65535), U32.and(t12, 65535), U32.and(t13, 65535), U32.and(t14, 65535), U32.and(t15, 65535)}, Fe{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15})


def canonical(value: Fe) -> Fe: reduceOnce(reduceOnce(value))

def square(+a: Fe) -> Fe: mul(a, a)

def squareTimes(count: Nat, a: Fe) -> Fe:
  match count:
    case 0n: a
    case 1n+rest: squareTimes(rest, square(a))

# a^(p-2) = a^(2^255 - 21) by the usual chain of 254 squarings and 11
# multiplications. The exponent is public; zero maps to zero.
def invert(+z: Fe) -> Fe:
  +z2 = square(z)
  +z9 = mul(z, squareTimes(2n, z2))
  +z11 = mul(z2, z9)
  +z5 = mul(square(z11), z9)
  +z10 = mul(squareTimes(5n, z5), z5)
  +z20 = mul(squareTimes(10n, z10), z10)
  +z40 = mul(squareTimes(20n, z20), z20)
  +z50 = mul(squareTimes(10n, z40), z10)
  +z100 = mul(squareTimes(50n, z50), z50)
  +z200 = mul(squareTimes(100n, z100), z100)
  +z250 = mul(squareTimes(50n, z200), z50)
  mul(squareTimes(5n, z250), z11)

def pairs(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case a <> b <> rest: pairs(rest, (a + b * 256 : U32) <> reversed)
    case _: List.reverse(&2, U32, reversed)

def packed(limbs: List<&2, U32>) -> Fe:
  match limbs:
    case x0 <> x1 <> x2 <> x3 <> x4 <> x5 <> x6 <> x7 <> x8 <> x9 <> x10 <> x11 <> x12 <> x13 <> x14 <> x15 <> Nil{}: Fe{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15}
    case _: zero()

# Exactly 32 valid bytes, little-endian.
def fromBytes(bytes: List<&2, U32>) -> Fe: packed(pairs(bytes, Nil{}))

def limbBytes(+limb: U32, tail: List<&2, U32>) -> List<&2, U32>:
  U32.and(limb, 255) <> U32.shrn(limb, 8n) <> tail

def encoded(value: Fe) -> List<&2, U32>:
  match value:
    case Fe{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15}:
      limbBytes(x0, limbBytes(x1, limbBytes(x2, limbBytes(x3, limbBytes(x4, limbBytes(x5, limbBytes(x6, limbBytes(x7, limbBytes(x8, limbBytes(x9, limbBytes(x10, limbBytes(x11, limbBytes(x12, limbBytes(x13, limbBytes(x14, limbBytes(x15, Nil{}))))))))))))))))

def toBytes(value: Fe) -> List<&2, U32>: encoded(canonical(value))

# Field operations on 32-byte little-endian encodings, for tests.
def fieldAdd(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: toBytes(add(fromBytes(a), fromBytes(b)))
def fieldSubtract(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: toBytes(sub(fromBytes(a), fromBytes(b)))
def fieldMultiply(a: List<&2, U32>, b: List<&2, U32>) -> List<&2, U32>: toBytes(mul(fromBytes(a), fromBytes(b)))
def fieldInverse(a: List<&2, U32>) -> List<&2, U32>: toBytes(invert(fromBytes(a)))

# (A + 2) / 4 for Curve25519's A = 486662.
def a24() -> Fe: Fe{56129, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

type Ladder is Data:
  Ladder{x2: Fe, z2: Fe, x3: Fe, z3: Fe, previous: U32}

def swap(state: Ladder, +bit: U32) -> Ladder:
  match state:
    case Ladder{+x2, +z2, +x3, +z3, previous}:
      +mask = (0 - U32.xor(bit, previous) : U32)
      Ladder{select(mask, x3, x2), select(mask, z3, z2), select(mask, x2, x3), select(mask, z2, z3), bit}

# RFC 7748 section 5's ladder step.
def step(base: Fe, state: Ladder) -> Ladder:
  match state:
    case Ladder{+x2, +z2, +x3, +z3, bit}:
      +a = add(x2, z2)
      +aa = square(a)
      +b = sub(x2, z2)
      +bb = square(b)
      +e = sub(aa, bb)
      +da = mul(sub(x3, z3), a)
      +cb = mul(add(x3, z3), b)
      Ladder{mul(aa, bb), mul(e, add(aa, mul(a24(), e))), square(add(da, cb)), mul(base, square(sub(da, cb))), bit}

def finish(state: Ladder) -> List<&2, U32>:
  match state:
    case Ladder{+x2, +z2, x3, z3, previous}:
      +mask = (0 - previous : U32)
      toBytes(mul(select(mask, x3, x2), invert(select(mask, z3, z2))))

def ladder(scalarBits: List<&2, U32>, +base: Fe, state: Ladder) -> List<&2, U32>:
  match scalarBits:
    case Nil{}: finish(state)
    case bit <> rest: ladder(rest, base, step(base, swap(state, bit)))

# Bit lists are most significant first. Their length and access schedule are
# fixed for valid inputs.
def byteBits(count: Nat, +byte: U32, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: byteBits(rest, U32.shr(byte), U32.and(byte, 1) <> tail)

def bits(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case head <> rest: bits(rest, byteBits(8n, head, reversed))

def highByte(bytes: List<&2, U32>, +set: U32) -> List<&2, U32>:
  match bytes:
    case Nil{}: Nil{}
    case byte <> Nil{}: U32.or(U32.and(byte, 127), set) <> Nil{}
    case head <> rest: head <> highByte(rest, set)

def clamp(bytes: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: Nil{}
    case head <> rest: U32.and(head, 248) <> highByte(rest, 64)

def valid(bytes: List<&2, U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case head <> rest: U32.is_le(head, 255) && valid(rest)

def checked(length: Bool, bytesValid: Bool, scalar: List<&2, U32>, point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  match length bytesValid:
    case False{} _: Fail{InvalidLength{}}
    case True{} False{}: Fail{InvalidByte{}}
    case True{} True{}:
      +base = fromBytes(highByte(point, 0))
      Done{ladder(List.drop(&2, U32, bits(clamp(scalar), Nil{}), 1n), base, Ladder{one(), zero(), base, one(), 0})}

# RFC 7748 requires masking the point's top bit and accepting noncanonical
# encodings modulo p. Raw multiplication can return zero; TLS must reject it.
def scalarMult(+scalar: List<&2, U32>, +point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  checked(Nat.is_eq(List.length(&2, U32, scalar), 32n) && Nat.is_eq(List.length(&2, U32, point), 32n), valid(scalar) && valid(point), scalar, point)

def publicKey(scalar: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  scalarMult(scalar, small(9))

def nonzero(bytes: List<&2, U32>, accumulated: U32) -> Bool:
  match bytes:
    case Nil{}: U32.is_ne(accumulated, 0)
    case head <> rest: nonzero(rest, U32.or(head, accumulated))

def sharedSecret(scalar: List<&2, U32>, point: List<&2, U32>) -> Result<&2, &2, Error, List<&2, U32>>:
  Result.bind(&2, &2, Error, List<&2, U32>, List<&2, U32>, scalarMult(scalar, point), +value =>
    Bool.pick(Result<&2, &2, Error, List<&2, U32>>, nonzero(value, 0), Done{value}, Fail{LowOrderPoint{}}))
