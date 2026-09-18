import Base
import ./f64.bend as F
import ./u64.bend as W

# Binary64 fmod: remainder after truncating the quotient toward zero.
# Shift/subtract avoids overflow and quotient rounding, even across the full
# normal/subnormal exponent range. The dividend determines the result sign.
def subtractOnce(+value: W.U64, +divisor: W.U64) -> W.U64:
  Bool.pick(W.U64, W.atLeast(W.compare(value, divisor)), W.subtract(value, divisor), value)

def bits(steps: Nat, value: W.U64, +divisor: W.U64) -> W.U64:
  match steps:
    case Zero{}: subtractOnce(value, divisor)
    case Succ{rest}: bits(rest, W.shiftLeftOne(subtractOnce(value, divisor)), divisor)

def packed(negative: Bool, normalized: F.Normalized) -> F.F64:
  match normalized:
    case F.Normalized{+exponent, value}:
      F.roundExtended(U32.is_le(exponent, 2048), negative, exponent, W.shiftLeft(value, 3n))

def result(negative: Bool, exponent: U32, +value: W.U64) -> F.F64:
  packed(negative, F.normalizeOperand(52n, W.atLeast(W.compare(value, W.U64{1048576, 0})) || W.equal(value, W.zero()), exponent, value))

def ordered(smaller: Bool, original: F.F64, negative: Bool, ea: U32, ma: W.U64, +eb: U32, mb: W.U64) -> F.F64:
  match smaller:
    case True{}: original
    case False{}: result(negative, eb, bits(U32.to_nat(U32.sub(ea, eb)), ma, mb))

def normalized(original: F.F64, negative: Bool, left: F.Normalized, right: F.Normalized) -> F.F64:
  match left right:
    case F.Normalized{+ea, ma} F.Normalized{+eb, mb}:
      ordered(U32.is_lt(ea, eb), original, negative, ea, ma, eb, mb)

def finite(zeroDivisor: Bool, original: F.F64, negative: Bool, ea: U32, ma: W.U64, eb: U32, mb: W.U64) -> F.F64:
  match zeroDivisor:
    case True{}: F.nan()
    case False{}: normalized(original, negative, F.normalized(ea, ma), F.normalized(eb, mb))

def decoded(original: F.F64, left: F.Decoded, right: F.Decoded) -> F.F64:
  match left right:
    case F.Finite{negative, ea, ma} F.Finite{_, eb, +mb}: finite(W.equal(mb, W.zero()), original, negative, ea, ma, eb, mb)
    case F.Finite{_, _, _} F.Infinity{_}: original
    case _ _: F.nan()

def remainder(+left: F.F64, right: F.F64) -> F.F64:
  decoded(left, F.decode(left), F.decode(right))
