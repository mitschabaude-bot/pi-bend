import Base
import ./f64.bend as F
import ./u64.bend as W
import ./big-nat.bend as B

# Reference-quality shortest decimal conversion using exact rounding intervals.
# All comparisons and divisions are integer operations. No floating estimates,
# host formatting or precision truncation participate in digit selection.
# Exponents/decimal positions are stored with bias 400, covering binary64's range.
type Interval is Data:
  Interval{lower: B.BigNat, center: B.BigNat, upper: B.BigNat, denominator: B.BigNat, inclusive: Bool, exponent: Nat}

type Decimal is Data:
  Decimal{digits: String, position: Nat}

def fromWord(word: W.U64) -> B.BigNat:
  match word:
    case W.U64{high, low}: B.add(B.shiftLeft(B.fromU32(high), 32n), B.fromU32(low))

def scaleBinary(positive: Bool, exponent: U32, lower: B.BigNat, center: B.BigNat, upper: B.BigNat, inclusive: Bool) -> Interval:
  match positive:
    case True{}:
      +shift = U32.to_nat((exponent - 1077 : U32))
      Interval{B.shiftLeft(lower, shift), B.shiftLeft(center, shift), B.shiftLeft(upper, shift), B.one(), inclusive, 400n}
    case False{}: Interval{lower, center, upper, B.shiftLeft(B.one(), U32.to_nat((1077 - exponent : U32))), inclusive, 400n}

# 4*m times 2^(e-2) is the original value. At a normal power-of-two boundary
# the lower neighbour is half as far away; at the subnormal boundary it is not.
def interval(+exponent: U32, +significand: W.U64) -> Interval:
  +center = W.shiftLeft(significand, 2n)
  lowerGap = Bool.pick(U32, U32.is_gt(exponent, 1) && W.equal(significand, W.U64{1048576, 0}), 1, 2)
  inclusive = W.equal(W.bitAnd(significand, W.one()), W.zero())
  scaleBinary(U32.is_ge(exponent, 1077), exponent, fromWord(W.subtract(center, W.fromU32(lowerGap))), fromWord(center), fromWord(W.add(center, W.fromU32(2))), inclusive)

# LT means below one; GT means at least ten; EQ is normalized to [1,10).
def directionOrders(atOne: Cmp, atTen: Cmp) -> Cmp:
  match atOne atTen:
    case LT{} _: LT{}
    case _ LT{}: EQ{}
    case _ _: GT{}

def directionOf(state: Interval) -> Cmp:
  match state:
    case Interval{_, +center, _, +denominator, _, _}:
      directionOrders(B.compare(center, denominator), B.compare(center, B.multiplyU32(denominator, 10)))

# The normalization bound is derived from binary64's maximum denominator bit
# count (1076), which exceeds the required decimal rescalings (at most 324).
def normalize(fuel: Nat, direction: Cmp, state: Interval) -> Maybe<&2, Interval>:
  match fuel direction state:
    case _ EQ{} state: Some{state}
    case 0n _ _: None{}
    case 1n+n LT{} Interval{lower, center, upper, denominator, inclusive, exponent}:
      +next = {Interval{B.multiplyU32(lower, 10), B.multiplyU32(center, 10), B.multiplyU32(upper, 10), denominator, inclusive, (exponent - 1n : Nat)} : Interval}
      normalize(n, directionOf(next), next)
    case 1n+n GT{} Interval{lower, center, upper, denominator, inclusive, exponent}:
      +next = {Interval{lower, center, upper, B.multiplyU32(denominator, 10), inclusive, (exponent + 1n : Nat)} : Interval}
      normalize(n, directionOf(next), next)

def withinBounds(lower: Cmp, upper: Cmp, inclusive: Bool) -> Bool:
  match lower upper:
    case LT{} _: False{}
    case _ GT{}: False{}
    case GT{} LT{}: True{}
    case _ _: inclusive

def admissible(candidate: B.BigNat, state: Interval) -> Bool:
  match state:
    case Interval{lower, _, upper, denominator, inclusive, _}:
      +scaled = B.multiply(candidate, denominator)
      withinBounds(B.compare(scaled, lower), B.compare(scaled, upper), inclusive)

def even(value: B.BigNat) -> Bool:
  match value:
    case B.BigNat{Nil{}}: True{}
    case B.BigNat{head <> _}: U32.is_eq(U32.and(head, 1), 0)

def nearest(order: Cmp, +down: B.BigNat, up: B.BigNat) -> B.BigNat:
  match order:
    case LT{}: down
    case GT{}: up
    case EQ{}: Bool.pick(B.BigNat, even(down), down, up)

def chooseCandidates(downValid: Bool, upValid: Bool, down: B.BigNat, up: B.BigNat, remainder: B.BigNat, denominator: B.BigNat) -> Maybe<&2, B.BigNat>:
  match downValid upValid:
    case False{} False{}: None{}
    case True{} False{}: Some{down}
    case False{} True{}: Some{up}
    case True{} True{}: Some{nearest(B.compare(B.shiftLeft(remainder, 1n), denominator), down, up)}

def candidates(+state: Interval, denominator: B.BigNat, divided: Maybe<&2, B.Division>) -> Maybe<&2, B.BigNat>:
  match divided:
    case None{}: None{}
    case Some{B.Division{+down, remainder}}:
      +up = B.add(down, B.one())
      chooseCandidates(admissible(down, state), admissible(up, state), down, up, remainder, denominator)

def select(+state: Interval) -> Maybe<&2, B.BigNat>:
  match state:
    case Interval{_, center, _, +denominator, _, _}: candidates(state, denominator, B.divide(center, denominator))

def stripHead(head: Char, tail: String) -> String:
  match head tail:
    case Chr{48} SNil{}: ""
    case head tail: SCon{head, tail}

def stripTrailingZeros(digits: String) -> String:
  match digits:
    case SNil{}: ""
    case SCon{head, tail}: stripHead(head, stripTrailingZeros(tail))

def decimalResult(coefficient: B.BigNat, places: Nat, exponent: Nat) -> Decimal:
  +digits = B.toDecimal(coefficient)
  Decimal{stripTrailingZeros(digits), exponent + 1n + String.length(digits) - places}

# Binary64 always has a round-tripping decimal with at most seventeen digits.
# An explicit None exposes any violated internal invariant instead of returning
# a guessed or truncated number. Both adjacent decimal candidates are checked.
def search(fuel: Nat, places: Nat, state: Interval, candidate: Maybe<&2, B.BigNat>) -> Maybe<&2, Decimal>:
  match fuel state candidate:
    case _ Interval{_, _, _, _, _, exponent} Some{coefficient}: Some{decimalResult(coefficient, places, exponent)}
    case 0n _ None{}: None{}
    case 1n+n Interval{lower, center, upper, denominator, inclusive, exponent} None{}:
      +next = {Interval{B.multiplyU32(lower, 10), B.multiplyU32(center, 10), B.multiplyU32(upper, 10), denominator, inclusive, exponent} : Interval}
      search(n, places + 1n, next, select(next))

def shortest(normalized: Maybe<&2, Interval>) -> Maybe<&2, Decimal>:
  match normalized:
    case None{}: None{}
    case Some{+state}: search(16n, 1n, state, select(state))

def zeros(count: Nat) -> String:
  match count:
    case 0n: ""
    case 1n+n: SCon{Chr{48}, zeros(n)}

def scientificMantissa(digits: String) -> String:
  match digits:
    case SNil{}: ""
    case SCon{head, SNil{}}: SCon{head, SNil{}}
    case SCon{head, tail}: SCon{head, SCon{Chr{46}, tail}}

def scientific(negative: Bool, digits: String, position: Nat) -> String:
  match negative:
    case True{}: scientificMantissa(digits) ++ "e-" ++ Nat.show(401n - position)
    case False{}: scientificMantissa(digits) ++ "e+" ++ Nat.show(position - 401n)

def positiveFixed(enoughPlaces: Bool, +digits: String, +position: Nat) -> String:
  match enoughPlaces:
    case True{}: digits ++ zeros(position - String.length(digits))
    case False{}: String.take(digits, position) ++ "." ++ String.drop(digits, position)

def renderForm(form: U32, +digits: String, +position: Nat) -> String:
  match form:
    case 0: "0." ++ zeros(400n - position) ++ digits
    case 1: positiveFixed(Nat.is_ge(position - 400n, String.length(digits)), digits, position - 400n)
    case 2: scientific(True{}, digits, position)
    case _: scientific(False{}, digits, position)

def render(decimal: Decimal) -> String:
  match decimal:
    case Decimal{digits, +position}:
      form = Bool.pick(U32, Nat.is_le(position, 394n), 2,
        Bool.pick(U32, Nat.is_le(position, 400n), 0,
          Bool.pick(U32, Nat.is_le(position, 421n), 1, 3)))
      renderForm(form, digits, position)

def renderSigned(negative: Bool, result: Maybe<&2, Decimal>) -> Maybe<&2, String>:
  match result:
    case None{}: None{}
    case Some{decimal}: Some{Bool.pick(String, negative, "-", "") ++ render(decimal)}

def finite(zero: Bool, negative: Bool, exponent: U32, significand: W.U64) -> Maybe<&2, String>:
  match zero:
    case True{}: Some{"0"}
    case False{}:
      +state = interval(exponent, significand)
      renderSigned(negative, shortest(normalize(U32.to_nat(1077), directionOf(state), state)))

def decoded(value: F.Decoded) -> Maybe<&2, String>:
  match value:
    case F.NotANumber{}: Some{"NaN"}
    case F.Infinity{negative}: Some{Bool.pick(String, negative, "-Infinity", "Infinity")}
    case F.Finite{negative, exponent, +significand}: finite(W.equal(significand, W.zero()), negative, exponent, significand)

# Base-10 ECMAScript-style number spelling. This is not a locale formatter.
def toDecimal(value: F.F64) -> Maybe<&2, String>: decoded(F.decode(value))

# JSON serializes non-finite numeric values as null. Finite values use the same
# decimal spelling; negative zero therefore becomes 0 in both public helpers.
def jsonDecoded(value: F.Decoded) -> Maybe<&2, String>:
  match value:
    case F.NotANumber{}: Some{"null"}
    case F.Infinity{_}: Some{"null"}
    case value: decoded(value)

def toJsonNumber(value: F.F64) -> Maybe<&2, String>: jsonDecoded(F.decode(value))
