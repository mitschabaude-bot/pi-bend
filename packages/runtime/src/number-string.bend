import Base
import ./text.bend as Space
import ./f64.bend as F
import ./big-nat.bend as B
import ./f64.bend as Ratio

# ECMAScript StringNumericLiteral conversion. This is Number(string), not
# parseFloat: every non-whitespace character must belong to the grammar.
def whitespace(code: U32) -> Bool: Space.whitespace(code)

def reverseInto(text: String, result: String) -> String:
  match text:
    case SNil{}: result
    case SCon{char, rest}: reverseInto(rest, SCon{char, result})

def trimStart(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{+code}, +rest}: Bool.pick(String, whitespace(code), trimStart(rest), SCon{Chr{code}, rest})

def trim(text: String) -> String:
  reverseInto(trimStart(reverseInto(trimStart(text), SNil{})), SNil{})

def digit(+code: U32) -> Bool: U32.is_ge(code, 48) && U32.is_le(code, 57)
def atMost(+value: Nat, +limit: Nat) -> Nat: Bool.pick(Nat, Nat.is_lt(value, limit), value, limit)

type Exponent is Data:
  Exponent{negative: Bool, magnitude: Nat}

type Decimal is Data:
  Decimal{coefficient: B.BigNat, digits: Nat, fractional: Nat, exponent: Exponent}

# Saturation is relative to the mantissa's digit count, never a precision cap.
# Beyond digits+400, any nonzero value must round to zero or infinity.
def exponentDigits(text: String, +limit: Nat, value: Nat, seen: Bool) -> Maybe<&2, Nat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2, Nat>, seen, Some{value}, None{})
    case SCon{Chr{+code}, rest}:
      Bool.pick(Maybe<&2, Nat>, digit(code), exponentDigits(rest, limit, atMost(value * 10n + U32.to_nat((code - 48 : U32)), limit), True{}), None{})

def exponentResult(negative: Bool, result: Maybe<&2, Nat>) -> Maybe<&2, Exponent>:
  match result:
    case None{}: None{}
    case Some{value}: Some{Exponent{negative, value}}

def parseExponent(text: String, limit: Nat) -> Maybe<&2, Exponent>:
  match text:
    case SCon{Chr{43}, rest}: exponentResult(False{}, exponentDigits(rest, limit, 0n, False{}))
    case SCon{Chr{45}, rest}: exponentResult(True{}, exponentDigits(rest, limit, 0n, False{}))
    case text: exponentResult(False{}, exponentDigits(text, limit, 0n, False{}))

def finishDecimal(coefficient: B.BigNat, digits: Nat, fractional: Nat, exponent: Maybe<&2, Exponent>) -> Maybe<&2, Decimal>:
  match digits exponent:
    case 0n _: None{}
    case _ None{}: None{}
    case digits Some{power}: Some{Decimal{coefficient, digits, fractional, power}}

type MantissaToken is Data:
  DecimalDigit{value: U32}
  DecimalPoint{}
  ExponentTail{text: String}
  InvalidCharacter{}

def classify(+code: U32, rest: String) -> MantissaToken:
  Bool.pick(MantissaToken, U32.is_eq(code, 46), DecimalPoint{}, Bool.pick(MantissaToken, U32.is_eq(code, 101) || U32.is_eq(code, 69), ExponentTail{rest}, Bool.pick(MantissaToken, digit(code), DecimalDigit{(code - 48 : U32)}, InvalidCharacter{})))

def tokens(text: String) -> List<&2, MantissaToken>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{code}, +rest}: classify(code, rest) <> tokens(rest)

def mantissa(input: List<&2, MantissaToken>, coefficient: B.BigNat, +digits: Nat, fractional: Nat, +dot: Bool) -> Maybe<&2, Decimal>:
  match input:
    case Nil{}: finishDecimal(coefficient, digits, fractional, Some{Exponent{False{}, 0n}})
    case DecimalPoint{} <> rest: Bool.pick(Maybe<&2, Decimal>, dot, None{}, mantissa(rest, coefficient, digits, fractional, True{}))
    case ExponentTail{text} <> _: finishDecimal(coefficient, digits, fractional, parseExponent(text, digits + 400n))
    case DecimalDigit{value} <> rest: mantissa(rest, B.add(B.multiplyU32(coefficient, 10), B.fromU32(value)), digits + 1n, fractional + Bool.pick(Nat, dot, 1n, 0n), dot)
    case InvalidCharacter{} <> _: None{}

def ratioValue(value: Maybe<&2, F.F64>) -> F.F64:
  match value:
    case Some{number}: number
    case None{}: F.nan()

def scaleWithin(overflow: Bool, underflow: Bool, negative: Bool, coefficient: B.BigNat, positivePower: Nat, negativePower: Nat) -> F.F64:
  match overflow underflow:
    case True{} _: F.infinity(negative)
    case _ True{}: Ratio.signed(negative, F.fromU32(0))
    case False{} False{}: ratioValue(Ratio.fromRatio(negative, B.multiply(coefficient, B.power(B.fromU32(10), positivePower)), B.power(B.fromU32(10), negativePower)))

def scale(negative: Bool, coefficient: B.BigNat, digits: Nat, +positivePower: Nat, +negativePower: Nat) -> F.F64:
  match coefficient:
    case B.BigNat{Nil{}}: Ratio.signed(negative, F.fromU32(0))
    case B.BigNat{limb <> tail}: scaleWithin(Nat.is_ge(positivePower, 400n), Nat.is_ge(negativePower, digits + 400n), negative, B.BigNat{limb <> tail}, positivePower, negativePower)

def decimalValue(negative: Bool, value: Maybe<&2, Decimal>) -> F.F64:
  match value:
    case None{}: F.nan()
    case Some{Decimal{coefficient, digits, fractional, Exponent{True{}, exponent}}}: scale(negative, coefficient, digits, 0n, fractional + exponent)
    case Some{Decimal{coefficient, digits, +fractional, Exponent{False{}, +exponent}}}: scale(negative, coefficient, digits, Nat.sub(exponent, fractional), Nat.sub(fractional, exponent))

def decimalOrInfinity(infinite: Bool, negative: Bool, text: String) -> F.F64:
  match infinite:
    case True{}: F.infinity(negative)
    case False{}: decimalValue(negative, mantissa(tokens(text), B.zero(), 0n, 0n, False{}))

def signedDecimal(negative: Bool, +text: String) -> F.F64:
  decimalOrInfinity(String.eq(text, "Infinity"), negative, text)

def radixDigit(+code: U32) -> U32:
  Bool.pick(U32, digit(code), (code - 48 : U32), Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 70), (code - 55 : U32), Bool.pick(U32, U32.is_ge(code, 97) && U32.is_le(code, 102), (code - 87 : U32), 16)))

def radixDigits(text: String, +radix: U32, coefficient: B.BigNat, seen: Bool) -> Maybe<&2, B.BigNat>:
  match text:
    case SNil{}: Bool.pick(Maybe<&2, B.BigNat>, seen, Some{coefficient}, None{})
    case SCon{Chr{code}, rest}:
      +value = radixDigit(code)
      Bool.pick(Maybe<&2, B.BigNat>, U32.is_lt(value, radix), radixDigits(rest, radix, B.add(B.multiplyU32(coefficient, radix), B.fromU32(value)), True{}), None{})

def radixValue(value: Maybe<&2, B.BigNat>) -> F.F64:
  match value:
    case None{}: F.nan()
    case Some{number}: ratioValue(Ratio.fromRatio(False{}, number, B.one()))

def fromTrimmed(text: String) -> F.F64:
  match text:
    case SNil{}: F.fromU32(0)
    case SCon{Chr{43}, rest}: signedDecimal(False{}, rest)
    case SCon{Chr{45}, rest}: signedDecimal(True{}, rest)
    case SCon{Chr{48}, SCon{Chr{120}, rest}}: radixValue(radixDigits(rest, 16, B.zero(), False{}))
    case SCon{Chr{48}, SCon{Chr{88}, rest}}: radixValue(radixDigits(rest, 16, B.zero(), False{}))
    case SCon{Chr{48}, SCon{Chr{111}, rest}}: radixValue(radixDigits(rest, 8, B.zero(), False{}))
    case SCon{Chr{48}, SCon{Chr{79}, rest}}: radixValue(radixDigits(rest, 8, B.zero(), False{}))
    case SCon{Chr{48}, SCon{Chr{98}, rest}}: radixValue(radixDigits(rest, 2, B.zero(), False{}))
    case SCon{Chr{48}, SCon{Chr{66}, rest}}: radixValue(radixDigits(rest, 2, B.zero(), False{}))
    case text: signedDecimal(False{}, text)

def toNumber(text: String) -> F.F64: fromTrimmed(trim(text))
