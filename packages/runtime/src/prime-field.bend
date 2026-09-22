import Base
import ./big-nat.bend as Big

# Ordinary, canonical NIST prime-field elements. Limbs are little-endian base
# 2^16; P256 leaves the last eight zero. Fixed records keep multiplication's
# inner loop free of limb-list allocation. These operations handle public data.
type Prime is Data:
  P256{}
  P384{}

type Field is Data:
  Field{x0: U32, x1: U32, x2: U32, x3: U32, x4: U32, x5: U32, x6: U32, x7: U32, x8: U32, x9: U32, x10: U32, x11: U32, x12: U32, x13: U32, x14: U32, x15: U32, x16: U32, x17: U32, x18: U32, x19: U32, x20: U32, x21: U32, x22: U32, x23: U32}

type Carried is Data:
  Carried{value: Field, carry: U32}

type WideProduct is Data:
  WideProduct{low: Field, high: Field}

type Row is Data:
  Row{low: U32, rest: Field}

def zero() -> Field: Field{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
def one() -> Field: Field{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}

# The caller has checked 0 <= value < the selected prime. This conversion does
# not reduce arbitrary integers; boundary validation must precede it.
def padded(count: Nat, limbs: List<&2,U32>) -> List<&2,U32>:
  match count limbs:
    case 0n _: Nil{}
    case 1n+n Nil{}: 0 <> padded(n,Nil{})
    case 1n+n x <> xs: x <> padded(n,xs)

def packed(limbs: List<&2,U32>) -> Field:
  match limbs:
    case x0 <> x1 <> x2 <> x3 <> x4 <> x5 <> x6 <> x7 <> x8 <> x9 <> x10 <> x11 <> x12 <> x13 <> x14 <> x15 <> x16 <> x17 <> x18 <> x19 <> x20 <> x21 <> x22 <> x23 <> Nil{}: Field{x0, x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19, x20, x21, x22, x23}
    case _: zero()

def fromBig(selected: Prime, value: Big.BigNat) -> Field:
  match value:
    case Big.BigNat{limbs}: packed(padded(24n,limbs))

def toBig(value: Field) -> Big.BigNat:
  match value:
    case Field{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15, +x16, +x17, +x18, +x19, +x20, +x21, +x22, +x23}: Big.BigNat{Big.trim(x0 <> x1 <> x2 <> x3 <> x4 <> x5 <> x6 <> x7 <> x8 <> x9 <> x10 <> x11 <> x12 <> x13 <> x14 <> x15 <> x16 <> x17 <> x18 <> x19 <> x20 <> x21 <> x22 <> x23 <> Nil{})}

def equal(a: Field, b: Field) -> Bool:
  match a b:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, +a16, +a17, +a18, +a19, +a20, +a21, +a22, +a23} Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, +b16, +b17, +b18, +b19, +b20, +b21, +b22, +b23}: U32.is_eq(a0,b0) && U32.is_eq(a1,b1) && U32.is_eq(a2,b2) && U32.is_eq(a3,b3) && U32.is_eq(a4,b4) && U32.is_eq(a5,b5) && U32.is_eq(a6,b6) && U32.is_eq(a7,b7) && U32.is_eq(a8,b8) && U32.is_eq(a9,b9) && U32.is_eq(a10,b10) && U32.is_eq(a11,b11) && U32.is_eq(a12,b12) && U32.is_eq(a13,b13) && U32.is_eq(a14,b14) && U32.is_eq(a15,b15) && U32.is_eq(a16,b16) && U32.is_eq(a17,b17) && U32.is_eq(a18,b18) && U32.is_eq(a19,b19) && U32.is_eq(a20,b20) && U32.is_eq(a21,b21) && U32.is_eq(a22,b22) && U32.is_eq(a23,b23)

def isZero(value: Field) -> Bool: equal(value,zero())

def choose256(negative: Bool, candidate: Field, original: Field) -> Field:
  match negative:
    case True{}: original
    case False{}: candidate

def canonical256(+value: Field, carry: U32) -> Field:
  match value:
    case Field{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15, _, _, _, _, _, _, _, _}:
      +t0 = (x0 - 65535 : U32)
      +t1 = (x1 - 65535 - U32.shrn(t0,31n) : U32)
      +t2 = (x2 - 65535 - U32.shrn(t1,31n) : U32)
      +t3 = (x3 - 65535 - U32.shrn(t2,31n) : U32)
      +t4 = (x4 - 65535 - U32.shrn(t3,31n) : U32)
      +t5 = (x5 - 65535 - U32.shrn(t4,31n) : U32)
      +t6 = (x6 - 0 - U32.shrn(t5,31n) : U32)
      +t7 = (x7 - 0 - U32.shrn(t6,31n) : U32)
      +t8 = (x8 - 0 - U32.shrn(t7,31n) : U32)
      +t9 = (x9 - 0 - U32.shrn(t8,31n) : U32)
      +t10 = (x10 - 0 - U32.shrn(t9,31n) : U32)
      +t11 = (x11 - 0 - U32.shrn(t10,31n) : U32)
      +t12 = (x12 - 1 - U32.shrn(t11,31n) : U32)
      +t13 = (x13 - 0 - U32.shrn(t12,31n) : U32)
      +t14 = (x14 - 65535 - U32.shrn(t13,31n) : U32)
      +t15 = (x15 - 65535 - U32.shrn(t14,31n) : U32)
      choose256(U32.is_gt(U32.shrn(t15,31n),carry),Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0},value)

def fold256(state: Carried) -> Carried:
  match state:
    case Carried{Field{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15, _, _, _, _, _, _, _, _},+carry}:
      +t0 = (x0 + carry : U32)
      +t1 = (x1 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (x2 + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (x3 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (x4 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (x5 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (x6 - carry + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (x7 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (x8 + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (x9 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (x10 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (x11 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (x12 - carry + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (x13 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (x14 + carry + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (x15 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0}, (U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)}

def finish256(state: Carried) -> Field:
  match state:
    case Carried{value,carry}: canonical256(value,carry)

def add256(+a: Field, b: Field) -> Field:
  match a b:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, _, _, _, _, _, _, _, _} Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, _, _, _, _, _, _, _, _}:
      +t0 = (a0  + b0 : U32)
      +t1 = (a1  + b1 + U32.shrn(t0,16n) : U32)
      +t2 = (a2  + b2 + U32.shrn(t1,16n) : U32)
      +t3 = (a3  + b3 + U32.shrn(t2,16n) : U32)
      +t4 = (a4  + b4 + U32.shrn(t3,16n) : U32)
      +t5 = (a5  + b5 + U32.shrn(t4,16n) : U32)
      +t6 = (a6  + b6 + U32.shrn(t5,16n) : U32)
      +t7 = (a7  + b7 + U32.shrn(t6,16n) : U32)
      +t8 = (a8  + b8 + U32.shrn(t7,16n) : U32)
      +t9 = (a9  + b9 + U32.shrn(t8,16n) : U32)
      +t10 = (a10  + b10 + U32.shrn(t9,16n) : U32)
      +t11 = (a11  + b11 + U32.shrn(t10,16n) : U32)
      +t12 = (a12  + b12 + U32.shrn(t11,16n) : U32)
      +t13 = (a13  + b13 + U32.shrn(t12,16n) : U32)
      +t14 = (a14  + b14 + U32.shrn(t13,16n) : U32)
      +t15 = (a15  + b15 + U32.shrn(t14,16n) : U32)
      finish256(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0}, (U32.shrn(t15,16n) : U32)})

def sub256(+a: Field, b: Field) -> Field:
  match a b:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, _, _, _, _, _, _, _, _} Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, _, _, _, _, _, _, _, _}:
      +t0 = (a0 + 65535 - b0 : U32)
      +t1 = (a1 + 65535 - b1 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (a2 + 65535 - b2 + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (a3 + 65535 - b3 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (a4 + 65535 - b4 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (a5 + 65535 - b5 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (a6 + 0 - b6 + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (a7 + 0 - b7 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (a8 + 0 - b8 + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (a9 + 0 - b9 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (a10 + 0 - b10 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (a11 + 0 - b11 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (a12 + 1 - b12 + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (a13 + 0 - b13 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (a14 + 65535 - b14 + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (a15 + 65535 - b15 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      finish256(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0}, (U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)})

def scale256(+a: Field, k: U32) -> Field:
  match a:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, _, _, _, _, _, _, _, _}:
      +factor = k
      +t0 = (a0 * factor : U32)
      +t1 = (a1 * factor + U32.shrn(t0,16n) : U32)
      +t2 = (a2 * factor + U32.shrn(t1,16n) : U32)
      +t3 = (a3 * factor + U32.shrn(t2,16n) : U32)
      +t4 = (a4 * factor + U32.shrn(t3,16n) : U32)
      +t5 = (a5 * factor + U32.shrn(t4,16n) : U32)
      +t6 = (a6 * factor + U32.shrn(t5,16n) : U32)
      +t7 = (a7 * factor + U32.shrn(t6,16n) : U32)
      +t8 = (a8 * factor + U32.shrn(t7,16n) : U32)
      +t9 = (a9 * factor + U32.shrn(t8,16n) : U32)
      +t10 = (a10 * factor + U32.shrn(t9,16n) : U32)
      +t11 = (a11 * factor + U32.shrn(t10,16n) : U32)
      +t12 = (a12 * factor + U32.shrn(t11,16n) : U32)
      +t13 = (a13 * factor + U32.shrn(t12,16n) : U32)
      +t14 = (a14 * factor + U32.shrn(t13,16n) : U32)
      +t15 = (a15 * factor + U32.shrn(t14,16n) : U32)
      finish256(fold256(fold256(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0}, (U32.shrn(t15,16n) : U32)})))

def row256(+a: U32, b: Field, acc: Field) -> Row:
  match b acc:
    case Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, _, _, _, _, _, _, _, _} Field{+c0, +c1, +c2, +c3, +c4, +c5, +c6, +c7, +c8, +c9, +c10, +c11, +c12, +c13, +c14, +c15, _, _, _, _, _, _, _, _}:
      +t0 = (a * b0 + c0 : U32)
      +t1 = (a * b1 + c1 + U32.shrn(t0,16n) : U32)
      +t2 = (a * b2 + c2 + U32.shrn(t1,16n) : U32)
      +t3 = (a * b3 + c3 + U32.shrn(t2,16n) : U32)
      +t4 = (a * b4 + c4 + U32.shrn(t3,16n) : U32)
      +t5 = (a * b5 + c5 + U32.shrn(t4,16n) : U32)
      +t6 = (a * b6 + c6 + U32.shrn(t5,16n) : U32)
      +t7 = (a * b7 + c7 + U32.shrn(t6,16n) : U32)
      +t8 = (a * b8 + c8 + U32.shrn(t7,16n) : U32)
      +t9 = (a * b9 + c9 + U32.shrn(t8,16n) : U32)
      +t10 = (a * b10 + c10 + U32.shrn(t9,16n) : U32)
      +t11 = (a * b11 + c11 + U32.shrn(t10,16n) : U32)
      +t12 = (a * b12 + c12 + U32.shrn(t11,16n) : U32)
      +t13 = (a * b13 + c13 + U32.shrn(t12,16n) : U32)
      +t14 = (a * b14 + c14 + U32.shrn(t13,16n) : U32)
      +t15 = (a * b15 + c15 + U32.shrn(t14,16n) : U32)
      Row{U32.and(t0,65535),Field{U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.shrn(t15,16n), 0, 0, 0, 0, 0, 0, 0, 0}}

def reduce256(product: WideProduct) -> Field:
  match product:
    case WideProduct{Field{+x0,+x1,+x2,+x3,+x4,+x5,+x6,+x7,+x8,+x9,+x10,+x11,+x12,+x13,+x14,+x15,_,_,_,_,_,_,_,_},Field{+x16,+x17,+x18,+x19,+x20,+x21,+x22,+x23,+x24,+x25,+x26,+x27,+x28,+x29,+x30,+x31,_,_,_,_,_,_,_,_}}:
      +t0 = (1048560 + x0 + x16 + x18 - x22 - x24 - x26 - x28 : U32)
      +t1 = (1048560 + x1 + x17 + x19 - x23 - x25 - x27 - x29 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (1048560 + x2 + x18 + x20 - x24 - x26 - x28 - x30 + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (1048560 + x3 + x19 + x21 - x25 - x27 - x29 - x31 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (1048560 + x4 + x20 + x22 - x26 - x28 - x30 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (1048560 + x5 + x21 + x23 - x27 - x29 - x31 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (0 + x6 - x16 - x18 + x22 * 2 + x24 * 2 + x26 - x30 + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (0 + x7 - x17 - x19 + x23 * 2 + x25 * 2 + x27 - x31 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (0 + x8 - x18 - x20 + x24 * 2 + x26 * 2 + x28 + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (0 + x9 - x19 - x21 + x25 * 2 + x27 * 2 + x29 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (0 + x10 - x20 - x22 + x26 * 2 + x28 * 2 + x30 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (0 + x11 - x21 - x23 + x27 * 2 + x29 * 2 + x31 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (16 + x12 - x16 - x18 + x26 + x28 * 3 + x30 * 2 + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (0 + x13 - x17 - x19 + x27 + x29 * 3 + x31 * 2 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (1048560 + x14 + x16 - x20 - x22 - x24 - x26 + x30 * 3 + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (1048560 + x15 + x17 - x21 - x23 - x25 - x27 + x31 * 3 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      finish256(fold256(fold256(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), 0, 0, 0, 0, 0, 0, 0, 0}, (U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)})))

def choose384(negative: Bool, candidate: Field, original: Field) -> Field:
  match negative:
    case True{}: original
    case False{}: candidate

def canonical384(+value: Field, carry: U32) -> Field:
  match value:
    case Field{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15, +x16, +x17, +x18, +x19, +x20, +x21, +x22, +x23}:
      +t0 = (x0 - 65535 : U32)
      +t1 = (x1 - 65535 - U32.shrn(t0,31n) : U32)
      +t2 = (x2 - 0 - U32.shrn(t1,31n) : U32)
      +t3 = (x3 - 0 - U32.shrn(t2,31n) : U32)
      +t4 = (x4 - 0 - U32.shrn(t3,31n) : U32)
      +t5 = (x5 - 0 - U32.shrn(t4,31n) : U32)
      +t6 = (x6 - 65535 - U32.shrn(t5,31n) : U32)
      +t7 = (x7 - 65535 - U32.shrn(t6,31n) : U32)
      +t8 = (x8 - 65534 - U32.shrn(t7,31n) : U32)
      +t9 = (x9 - 65535 - U32.shrn(t8,31n) : U32)
      +t10 = (x10 - 65535 - U32.shrn(t9,31n) : U32)
      +t11 = (x11 - 65535 - U32.shrn(t10,31n) : U32)
      +t12 = (x12 - 65535 - U32.shrn(t11,31n) : U32)
      +t13 = (x13 - 65535 - U32.shrn(t12,31n) : U32)
      +t14 = (x14 - 65535 - U32.shrn(t13,31n) : U32)
      +t15 = (x15 - 65535 - U32.shrn(t14,31n) : U32)
      +t16 = (x16 - 65535 - U32.shrn(t15,31n) : U32)
      +t17 = (x17 - 65535 - U32.shrn(t16,31n) : U32)
      +t18 = (x18 - 65535 - U32.shrn(t17,31n) : U32)
      +t19 = (x19 - 65535 - U32.shrn(t18,31n) : U32)
      +t20 = (x20 - 65535 - U32.shrn(t19,31n) : U32)
      +t21 = (x21 - 65535 - U32.shrn(t20,31n) : U32)
      +t22 = (x22 - 65535 - U32.shrn(t21,31n) : U32)
      +t23 = (x23 - 65535 - U32.shrn(t22,31n) : U32)
      choose384(U32.is_gt(U32.shrn(t23,31n),carry),Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)},value)

def fold384(state: Carried) -> Carried:
  match state:
    case Carried{Field{+x0, +x1, +x2, +x3, +x4, +x5, +x6, +x7, +x8, +x9, +x10, +x11, +x12, +x13, +x14, +x15, +x16, +x17, +x18, +x19, +x20, +x21, +x22, +x23},+carry}:
      +t0 = (x0 + carry : U32)
      +t1 = (x1 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (x2 - carry + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (x3 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (x4 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (x5 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (x6 + carry + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (x7 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (x8 + carry + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (x9 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (x10 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (x11 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (x12 + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (x13 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (x14 + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (x15 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      +t16 = (x16 + U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)
      +t17 = (x17 + U32.shrn(t16,16n) - U32.shln(U32.shrn(t16,31n),16n) : U32)
      +t18 = (x18 + U32.shrn(t17,16n) - U32.shln(U32.shrn(t17,31n),16n) : U32)
      +t19 = (x19 + U32.shrn(t18,16n) - U32.shln(U32.shrn(t18,31n),16n) : U32)
      +t20 = (x20 + U32.shrn(t19,16n) - U32.shln(U32.shrn(t19,31n),16n) : U32)
      +t21 = (x21 + U32.shrn(t20,16n) - U32.shln(U32.shrn(t20,31n),16n) : U32)
      +t22 = (x22 + U32.shrn(t21,16n) - U32.shln(U32.shrn(t21,31n),16n) : U32)
      +t23 = (x23 + U32.shrn(t22,16n) - U32.shln(U32.shrn(t22,31n),16n) : U32)
      Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)}, (U32.shrn(t23,16n) - U32.shln(U32.shrn(t23,31n),16n) : U32)}

def finish384(state: Carried) -> Field:
  match state:
    case Carried{value,carry}: canonical384(value,carry)

def add384(+a: Field, b: Field) -> Field:
  match a b:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, +a16, +a17, +a18, +a19, +a20, +a21, +a22, +a23} Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, +b16, +b17, +b18, +b19, +b20, +b21, +b22, +b23}:
      +t0 = (a0  + b0 : U32)
      +t1 = (a1  + b1 + U32.shrn(t0,16n) : U32)
      +t2 = (a2  + b2 + U32.shrn(t1,16n) : U32)
      +t3 = (a3  + b3 + U32.shrn(t2,16n) : U32)
      +t4 = (a4  + b4 + U32.shrn(t3,16n) : U32)
      +t5 = (a5  + b5 + U32.shrn(t4,16n) : U32)
      +t6 = (a6  + b6 + U32.shrn(t5,16n) : U32)
      +t7 = (a7  + b7 + U32.shrn(t6,16n) : U32)
      +t8 = (a8  + b8 + U32.shrn(t7,16n) : U32)
      +t9 = (a9  + b9 + U32.shrn(t8,16n) : U32)
      +t10 = (a10  + b10 + U32.shrn(t9,16n) : U32)
      +t11 = (a11  + b11 + U32.shrn(t10,16n) : U32)
      +t12 = (a12  + b12 + U32.shrn(t11,16n) : U32)
      +t13 = (a13  + b13 + U32.shrn(t12,16n) : U32)
      +t14 = (a14  + b14 + U32.shrn(t13,16n) : U32)
      +t15 = (a15  + b15 + U32.shrn(t14,16n) : U32)
      +t16 = (a16  + b16 + U32.shrn(t15,16n) : U32)
      +t17 = (a17  + b17 + U32.shrn(t16,16n) : U32)
      +t18 = (a18  + b18 + U32.shrn(t17,16n) : U32)
      +t19 = (a19  + b19 + U32.shrn(t18,16n) : U32)
      +t20 = (a20  + b20 + U32.shrn(t19,16n) : U32)
      +t21 = (a21  + b21 + U32.shrn(t20,16n) : U32)
      +t22 = (a22  + b22 + U32.shrn(t21,16n) : U32)
      +t23 = (a23  + b23 + U32.shrn(t22,16n) : U32)
      finish384(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)}, (U32.shrn(t23,16n) : U32)})

def sub384(+a: Field, b: Field) -> Field:
  match a b:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, +a16, +a17, +a18, +a19, +a20, +a21, +a22, +a23} Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, +b16, +b17, +b18, +b19, +b20, +b21, +b22, +b23}:
      +t0 = (a0 + 65535 - b0 : U32)
      +t1 = (a1 + 65535 - b1 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (a2 + 0 - b2 + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (a3 + 0 - b3 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (a4 + 0 - b4 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (a5 + 0 - b5 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (a6 + 65535 - b6 + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (a7 + 65535 - b7 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (a8 + 65534 - b8 + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (a9 + 65535 - b9 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (a10 + 65535 - b10 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (a11 + 65535 - b11 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (a12 + 65535 - b12 + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (a13 + 65535 - b13 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (a14 + 65535 - b14 + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (a15 + 65535 - b15 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      +t16 = (a16 + 65535 - b16 + U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)
      +t17 = (a17 + 65535 - b17 + U32.shrn(t16,16n) - U32.shln(U32.shrn(t16,31n),16n) : U32)
      +t18 = (a18 + 65535 - b18 + U32.shrn(t17,16n) - U32.shln(U32.shrn(t17,31n),16n) : U32)
      +t19 = (a19 + 65535 - b19 + U32.shrn(t18,16n) - U32.shln(U32.shrn(t18,31n),16n) : U32)
      +t20 = (a20 + 65535 - b20 + U32.shrn(t19,16n) - U32.shln(U32.shrn(t19,31n),16n) : U32)
      +t21 = (a21 + 65535 - b21 + U32.shrn(t20,16n) - U32.shln(U32.shrn(t20,31n),16n) : U32)
      +t22 = (a22 + 65535 - b22 + U32.shrn(t21,16n) - U32.shln(U32.shrn(t21,31n),16n) : U32)
      +t23 = (a23 + 65535 - b23 + U32.shrn(t22,16n) - U32.shln(U32.shrn(t22,31n),16n) : U32)
      finish384(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)}, (U32.shrn(t23,16n) - U32.shln(U32.shrn(t23,31n),16n) : U32)})

def scale384(+a: Field, k: U32) -> Field:
  match a:
    case Field{+a0, +a1, +a2, +a3, +a4, +a5, +a6, +a7, +a8, +a9, +a10, +a11, +a12, +a13, +a14, +a15, +a16, +a17, +a18, +a19, +a20, +a21, +a22, +a23}:
      +factor = k
      +t0 = (a0 * factor : U32)
      +t1 = (a1 * factor + U32.shrn(t0,16n) : U32)
      +t2 = (a2 * factor + U32.shrn(t1,16n) : U32)
      +t3 = (a3 * factor + U32.shrn(t2,16n) : U32)
      +t4 = (a4 * factor + U32.shrn(t3,16n) : U32)
      +t5 = (a5 * factor + U32.shrn(t4,16n) : U32)
      +t6 = (a6 * factor + U32.shrn(t5,16n) : U32)
      +t7 = (a7 * factor + U32.shrn(t6,16n) : U32)
      +t8 = (a8 * factor + U32.shrn(t7,16n) : U32)
      +t9 = (a9 * factor + U32.shrn(t8,16n) : U32)
      +t10 = (a10 * factor + U32.shrn(t9,16n) : U32)
      +t11 = (a11 * factor + U32.shrn(t10,16n) : U32)
      +t12 = (a12 * factor + U32.shrn(t11,16n) : U32)
      +t13 = (a13 * factor + U32.shrn(t12,16n) : U32)
      +t14 = (a14 * factor + U32.shrn(t13,16n) : U32)
      +t15 = (a15 * factor + U32.shrn(t14,16n) : U32)
      +t16 = (a16 * factor + U32.shrn(t15,16n) : U32)
      +t17 = (a17 * factor + U32.shrn(t16,16n) : U32)
      +t18 = (a18 * factor + U32.shrn(t17,16n) : U32)
      +t19 = (a19 * factor + U32.shrn(t18,16n) : U32)
      +t20 = (a20 * factor + U32.shrn(t19,16n) : U32)
      +t21 = (a21 * factor + U32.shrn(t20,16n) : U32)
      +t22 = (a22 * factor + U32.shrn(t21,16n) : U32)
      +t23 = (a23 * factor + U32.shrn(t22,16n) : U32)
      finish384(fold384(fold384(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)}, (U32.shrn(t23,16n) : U32)})))

def row384(+a: U32, b: Field, acc: Field) -> Row:
  match b acc:
    case Field{+b0, +b1, +b2, +b3, +b4, +b5, +b6, +b7, +b8, +b9, +b10, +b11, +b12, +b13, +b14, +b15, +b16, +b17, +b18, +b19, +b20, +b21, +b22, +b23} Field{+c0, +c1, +c2, +c3, +c4, +c5, +c6, +c7, +c8, +c9, +c10, +c11, +c12, +c13, +c14, +c15, +c16, +c17, +c18, +c19, +c20, +c21, +c22, +c23}:
      +t0 = (a * b0 + c0 : U32)
      +t1 = (a * b1 + c1 + U32.shrn(t0,16n) : U32)
      +t2 = (a * b2 + c2 + U32.shrn(t1,16n) : U32)
      +t3 = (a * b3 + c3 + U32.shrn(t2,16n) : U32)
      +t4 = (a * b4 + c4 + U32.shrn(t3,16n) : U32)
      +t5 = (a * b5 + c5 + U32.shrn(t4,16n) : U32)
      +t6 = (a * b6 + c6 + U32.shrn(t5,16n) : U32)
      +t7 = (a * b7 + c7 + U32.shrn(t6,16n) : U32)
      +t8 = (a * b8 + c8 + U32.shrn(t7,16n) : U32)
      +t9 = (a * b9 + c9 + U32.shrn(t8,16n) : U32)
      +t10 = (a * b10 + c10 + U32.shrn(t9,16n) : U32)
      +t11 = (a * b11 + c11 + U32.shrn(t10,16n) : U32)
      +t12 = (a * b12 + c12 + U32.shrn(t11,16n) : U32)
      +t13 = (a * b13 + c13 + U32.shrn(t12,16n) : U32)
      +t14 = (a * b14 + c14 + U32.shrn(t13,16n) : U32)
      +t15 = (a * b15 + c15 + U32.shrn(t14,16n) : U32)
      +t16 = (a * b16 + c16 + U32.shrn(t15,16n) : U32)
      +t17 = (a * b17 + c17 + U32.shrn(t16,16n) : U32)
      +t18 = (a * b18 + c18 + U32.shrn(t17,16n) : U32)
      +t19 = (a * b19 + c19 + U32.shrn(t18,16n) : U32)
      +t20 = (a * b20 + c20 + U32.shrn(t19,16n) : U32)
      +t21 = (a * b21 + c21 + U32.shrn(t20,16n) : U32)
      +t22 = (a * b22 + c22 + U32.shrn(t21,16n) : U32)
      +t23 = (a * b23 + c23 + U32.shrn(t22,16n) : U32)
      Row{U32.and(t0,65535),Field{U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535), U32.shrn(t23,16n)}}

def reduce384(product: WideProduct) -> Field:
  match product:
    case WideProduct{Field{+x0,+x1,+x2,+x3,+x4,+x5,+x6,+x7,+x8,+x9,+x10,+x11,+x12,+x13,+x14,+x15,+x16,+x17,+x18,+x19,+x20,+x21,+x22,+x23},Field{+x24,+x25,+x26,+x27,+x28,+x29,+x30,+x31,+x32,+x33,+x34,+x35,+x36,+x37,+x38,+x39,+x40,+x41,+x42,+x43,+x44,+x45,+x46,+x47}}:
      +t0 = (1048560 + x0 + x24 + x40 + x42 - x46 : U32)
      +t1 = (1048560 + x1 + x25 + x41 + x43 - x47 + U32.shrn(t0,16n) - U32.shln(U32.shrn(t0,31n),16n) : U32)
      +t2 = (0 + x2 - x24 + x26 - x40 + x44 + x46 + U32.shrn(t1,16n) - U32.shln(U32.shrn(t1,31n),16n) : U32)
      +t3 = (0 + x3 - x25 + x27 - x41 + x45 + x47 + U32.shrn(t2,16n) - U32.shln(U32.shrn(t2,31n),16n) : U32)
      +t4 = (0 + x4 - x26 + x28 - x42 + x46 + U32.shrn(t3,16n) - U32.shln(U32.shrn(t3,31n),16n) : U32)
      +t5 = (0 + x5 - x27 + x29 - x43 + x47 + U32.shrn(t4,16n) - U32.shln(U32.shrn(t4,31n),16n) : U32)
      +t6 = (1048560 + x6 + x24 - x28 + x30 + x40 + x42 - x44 - x46 + U32.shrn(t5,16n) - U32.shln(U32.shrn(t5,31n),16n) : U32)
      +t7 = (1048560 + x7 + x25 - x29 + x31 + x41 + x43 - x45 - x47 + U32.shrn(t6,16n) - U32.shln(U32.shrn(t6,31n),16n) : U32)
      +t8 = (1048544 + x8 + x24 + x26 - x30 + x32 + x40 + x42 * 2 + x44 - x46 * 2 + U32.shrn(t7,16n) - U32.shln(U32.shrn(t7,31n),16n) : U32)
      +t9 = (1048560 + x9 + x25 + x27 - x31 + x33 + x41 + x43 * 2 + x45 - x47 * 2 + U32.shrn(t8,16n) - U32.shln(U32.shrn(t8,31n),16n) : U32)
      +t10 = (1048560 + x10 + x26 + x28 - x32 + x34 + x42 + x44 * 2 + x46 + U32.shrn(t9,16n) - U32.shln(U32.shrn(t9,31n),16n) : U32)
      +t11 = (1048560 + x11 + x27 + x29 - x33 + x35 + x43 + x45 * 2 + x47 + U32.shrn(t10,16n) - U32.shln(U32.shrn(t10,31n),16n) : U32)
      +t12 = (1048560 + x12 + x28 + x30 - x34 + x36 + x44 + x46 * 2 + U32.shrn(t11,16n) - U32.shln(U32.shrn(t11,31n),16n) : U32)
      +t13 = (1048560 + x13 + x29 + x31 - x35 + x37 + x45 + x47 * 2 + U32.shrn(t12,16n) - U32.shln(U32.shrn(t12,31n),16n) : U32)
      +t14 = (1048560 + x14 + x30 + x32 - x36 + x38 + x46 + U32.shrn(t13,16n) - U32.shln(U32.shrn(t13,31n),16n) : U32)
      +t15 = (1048560 + x15 + x31 + x33 - x37 + x39 + x47 + U32.shrn(t14,16n) - U32.shln(U32.shrn(t14,31n),16n) : U32)
      +t16 = (1048560 + x16 + x32 + x34 - x38 + x40 + U32.shrn(t15,16n) - U32.shln(U32.shrn(t15,31n),16n) : U32)
      +t17 = (1048560 + x17 + x33 + x35 - x39 + x41 + U32.shrn(t16,16n) - U32.shln(U32.shrn(t16,31n),16n) : U32)
      +t18 = (1048560 + x18 + x34 + x36 - x40 + x42 + U32.shrn(t17,16n) - U32.shln(U32.shrn(t17,31n),16n) : U32)
      +t19 = (1048560 + x19 + x35 + x37 - x41 + x43 + U32.shrn(t18,16n) - U32.shln(U32.shrn(t18,31n),16n) : U32)
      +t20 = (1048560 + x20 + x36 + x38 - x42 + x44 + U32.shrn(t19,16n) - U32.shln(U32.shrn(t19,31n),16n) : U32)
      +t21 = (1048560 + x21 + x37 + x39 - x43 + x45 + U32.shrn(t20,16n) - U32.shln(U32.shrn(t20,31n),16n) : U32)
      +t22 = (1048560 + x22 + x38 + x40 - x44 + x46 + U32.shrn(t21,16n) - U32.shln(U32.shrn(t21,31n),16n) : U32)
      +t23 = (1048560 + x23 + x39 + x41 - x45 + x47 + U32.shrn(t22,16n) - U32.shln(U32.shrn(t22,31n),16n) : U32)
      finish384(fold384(fold384(Carried{Field{U32.and(t0,65535), U32.and(t1,65535), U32.and(t2,65535), U32.and(t3,65535), U32.and(t4,65535), U32.and(t5,65535), U32.and(t6,65535), U32.and(t7,65535), U32.and(t8,65535), U32.and(t9,65535), U32.and(t10,65535), U32.and(t11,65535), U32.and(t12,65535), U32.and(t13,65535), U32.and(t14,65535), U32.and(t15,65535), U32.and(t16,65535), U32.and(t17,65535), U32.and(t18,65535), U32.and(t19,65535), U32.and(t20,65535), U32.and(t21,65535), U32.and(t22,65535), U32.and(t23,65535)}, (U32.shrn(t23,16n) - U32.shln(U32.shrn(t23,31n),16n) : U32)})))

# The fixed-width row sequence keeps the complete product in two records.
# Explicit rows avoid heap-allocated input/output lists and recursive
# continuations in this hot path; the arithmetic remains in row256/row384.
def rowLow(value: Row) -> U32:
  match value:
    case Row{low,_}: low

def rowRest(value: Row) -> Field:
  match value:
    case Row{_,rest}: rest

def mul256(a: Field, +b: Field) -> Field:
  match a:
    case Field{a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,_,_,_,_,_,_,_,_}:
      +r0 = row256(a0,b,zero())
      +r1 = row256(a1,b,rowRest(r0))
      +r2 = row256(a2,b,rowRest(r1))
      +r3 = row256(a3,b,rowRest(r2))
      +r4 = row256(a4,b,rowRest(r3))
      +r5 = row256(a5,b,rowRest(r4))
      +r6 = row256(a6,b,rowRest(r5))
      +r7 = row256(a7,b,rowRest(r6))
      +r8 = row256(a8,b,rowRest(r7))
      +r9 = row256(a9,b,rowRest(r8))
      +r10 = row256(a10,b,rowRest(r9))
      +r11 = row256(a11,b,rowRest(r10))
      +r12 = row256(a12,b,rowRest(r11))
      +r13 = row256(a13,b,rowRest(r12))
      +r14 = row256(a14,b,rowRest(r13))
      +r15 = row256(a15,b,rowRest(r14))
      reduce256(WideProduct{Field{rowLow(r0),rowLow(r1),rowLow(r2),rowLow(r3),rowLow(r4),rowLow(r5),rowLow(r6),rowLow(r7),rowLow(r8),rowLow(r9),rowLow(r10),rowLow(r11),rowLow(r12),rowLow(r13),rowLow(r14),rowLow(r15),0,0,0,0,0,0,0,0},rowRest(r15)})

def mul384(a: Field, +b: Field) -> Field:
  match a:
    case Field{a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11,a12,a13,a14,a15,a16,a17,a18,a19,a20,a21,a22,a23}:
      +r0 = row384(a0,b,zero())
      +r1 = row384(a1,b,rowRest(r0))
      +r2 = row384(a2,b,rowRest(r1))
      +r3 = row384(a3,b,rowRest(r2))
      +r4 = row384(a4,b,rowRest(r3))
      +r5 = row384(a5,b,rowRest(r4))
      +r6 = row384(a6,b,rowRest(r5))
      +r7 = row384(a7,b,rowRest(r6))
      +r8 = row384(a8,b,rowRest(r7))
      +r9 = row384(a9,b,rowRest(r8))
      +r10 = row384(a10,b,rowRest(r9))
      +r11 = row384(a11,b,rowRest(r10))
      +r12 = row384(a12,b,rowRest(r11))
      +r13 = row384(a13,b,rowRest(r12))
      +r14 = row384(a14,b,rowRest(r13))
      +r15 = row384(a15,b,rowRest(r14))
      +r16 = row384(a16,b,rowRest(r15))
      +r17 = row384(a17,b,rowRest(r16))
      +r18 = row384(a18,b,rowRest(r17))
      +r19 = row384(a19,b,rowRest(r18))
      +r20 = row384(a20,b,rowRest(r19))
      +r21 = row384(a21,b,rowRest(r20))
      +r22 = row384(a22,b,rowRest(r21))
      +r23 = row384(a23,b,rowRest(r22))
      reduce384(WideProduct{Field{rowLow(r0),rowLow(r1),rowLow(r2),rowLow(r3),rowLow(r4),rowLow(r5),rowLow(r6),rowLow(r7),rowLow(r8),rowLow(r9),rowLow(r10),rowLow(r11),rowLow(r12),rowLow(r13),rowLow(r14),rowLow(r15),rowLow(r16),rowLow(r17),rowLow(r18),rowLow(r19),rowLow(r20),rowLow(r21),rowLow(r22),rowLow(r23)},rowRest(r23)})

# Addition/subtraction stay below 2*p: their carry participates directly in
# conditional subtraction. Products/scales first fold into this same range.
# Sparse prime identities (b = 2^16):
# P256: b^16 = b^14 - b^12 - b^6 + 1 (mod p).
# P384: b^24 = b^8 + b^6 - b^2 + 1 (mod p).
# reduce distributes high coefficients, adding 16*p to make the signed sum
# nonnegative: before carrying the polynomial lies in [11*R,21*R) for
# P256 and [15*R,20*R) for P384, where R=b^16 or b^24. Each coefficient
# accumulator fits signed 32 bits. The carry is at most 20. Folding it once
# leaves at most one carry; if that carry is one, the low part is <20*(R-p).
# A second fold cannot overflow, and one subtraction gives a canonical residue.
# The same two folds handle addition/subtraction and factors <=65535: even
# 65535*(R-p) is much smaller than p. No division or per-bit reduction.
def mul(selected: Prime, a: Field, b: Field) -> Field:
  match selected:
    case P256{}: mul256(a,b)
    case P384{}: mul384(a,b)

def square(selected: Prime, +a: Field) -> Field: mul(selected,a,a)

def add(selected: Prime, a: Field, b: Field) -> Field:
  match selected:
    case P256{}: add256(a,b)
    case P384{}: add384(a,b)

def sub(selected: Prime, a: Field, b: Field) -> Field:
  match selected:
    case P256{}: sub256(a,b)
    case P384{}: sub384(a,b)

# Small factors only: k <= 65535. Curve formulas use 2, 3, 4 and 8.
def scale(selected: Prime, a: Field, k: U32) -> Field:
  match selected:
    case P256{}: scale256(a,k)
    case P384{}: scale384(a,k)

