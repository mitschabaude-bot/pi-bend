import Base
import ./number-string.bend as Number
import ./f64.bend as F

# Longest decimal prefix, used by provider retry headers. Numeric conversion
# reuses the correctly rounded binary64 codec; no host float/JS parsing.
type State is Data:
  IntegerPart{}
  FractionPart{}
  ExponentStart{}
  ExponentSign{}
  ExponentDigits{}

type Step is Data:
  Stop{}
  Continue{state: State, accepting: Bool}

def nonDigit(state: State, code: U32, seenDigit: Bool) -> Step:
  match state code:
    case IntegerPart{} 46: Continue{FractionPart{}, seenDigit}
    case IntegerPart{} 101: Bool.pick(Step, seenDigit, Continue{ExponentStart{}, False{}}, Stop{})
    case IntegerPart{} 69: Bool.pick(Step, seenDigit, Continue{ExponentStart{}, False{}}, Stop{})
    case FractionPart{} 101: Bool.pick(Step, seenDigit, Continue{ExponentStart{}, False{}}, Stop{})
    case FractionPart{} 69: Bool.pick(Step, seenDigit, Continue{ExponentStart{}, False{}}, Stop{})
    case ExponentStart{} 43: Continue{ExponentSign{}, False{}}
    case ExponentStart{} 45: Continue{ExponentSign{}, False{}}
    case _ _: Stop{}

def step(isDigit: Bool, state: State, code: U32, seenDigit: Bool) -> Step:
  match isDigit state:
    case True{} IntegerPart{}: Continue{IntegerPart{}, True{}}
    case True{} FractionPart{}: Continue{FractionPart{}, True{}}
    case True{} _: Continue{ExponentDigits{}, True{}}
    case False{} value: nonDigit(value, code, seenDigit)

def accepted(accepting: Bool, consumed: Nat, previous: Nat) -> Nat:
  match accepting:
    case True{}: consumed
    case False{}: previous

def prefixLength(chars: String, next: Step, +seenDigit: Bool, +consumed: Nat, previous: Nat) -> Nat:
  match chars next:
    case _ Stop{}: previous
    case SNil{} Continue{_, accepting}: accepted(accepting, consumed, previous)
    case SCon{Chr{+code}, rest} Continue{state, accepting}:
      prefixLength(rest, step(Number.digit(code), state, code, seenDigit), seenDigit || Number.digit(code), consumed + 1n, accepted(accepting, consumed, previous))

def decimal(+text: String, sign: String) -> F64:
  length = prefixLength(text, Continue{IntegerPart{}, False{}}, False{}, 0n, 0n)
  Number.toNumber(sign ++ String.take(text, length))

def numeric(+negative: Bool, +text: String) -> F64:
  Bool.pick(F64, String.starts_with(text, "Infinity"), F.infinity(negative), decimal(text, Bool.pick(String, negative, "-", "+")))

def trimmed(text: String) -> F64:
  match text:
    case SCon{'+', rest}: numeric(False{}, rest)
    case SCon{'-', rest}: numeric(True{}, rest)
    case other: numeric(False{}, other)

def parseFloat(text: String) -> F64: trimmed(Number.trimStart(text))
