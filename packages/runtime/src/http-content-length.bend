import Base
import ./u64.bend as W
import ./http-header.bend as H

type LengthError is Data:
  InvalidLength{}
  LengthOverflow{}
  DuplicateLength{}

type State is Data:
  Leading{}
  Digits{value: W.U64}
  Trailing{value: W.U64}

# floor((2^64 - 1) / 10), remainder 5. Check before modular arithmetic.
def fits(+value: W.U64, +digit: U32) -> Bool:
  Cmp.is_lt(W.compare(value, W.U64{429496729, 2576980377})) || (W.equal(value, W.U64{429496729, 2576980377}) && U32.is_le(digit, 5))

def accumulated(valid: Bool, value: W.U64, digit: U32) -> Result<&2, &2, LengthError, State>:
  match valid:
    case False{}: Fail{LengthOverflow{}}
    case True{}: Done{Digits{W.add(W.multiply(value, W.fromU32(10)), W.fromU32(digit))}}

def addDigit(+value: W.U64, +digit: U32) -> Result<&2, &2, LengthError, State>:
  accumulated(fits(value, digit), value, digit)

def digitStep(state: State, digit: U32) -> Result<&2, &2, LengthError, State>:
  match state:
    case Leading{}: Done{Digits{W.fromU32(digit)}}
    case Digits{value}: addDigit(value, digit)
    case Trailing{_}: Fail{InvalidLength{}}

# Node's received Content-Length parser permits SP after digits, but not HTAB.
# Leading OWS is accepted by its field parser before numeric interpretation.
def whitespaceStep(state: State, byte: U32) -> Result<&2, &2, LengthError, State>:
  match state byte:
    case Leading{} 32: Done{Leading{}}
    case Leading{} 9: Done{Leading{}}
    case Digits{value} 32: Done{Trailing{value}}
    case Trailing{value} 32: Done{Trailing{value}}
    case _ _: Fail{InvalidLength{}}

def step(isDigit: Bool, state: State, byte: U32) -> Result<&2, &2, LengthError, State>:
  match isDigit:
    case True{}: digitStep(state, (byte - 48 : U32))
    case False{}: whitespaceStep(state, byte)

def consume(state: State, +byte: U32) -> Result<&2, &2, LengthError, State>:
  step(U32.is_ge(byte, 48) && U32.is_le(byte, 57), state, byte)

def scan(text: String, result: Result<&2, &2, LengthError, State>) -> Result<&2, &2, LengthError, W.U64>:
  match text result:
    case _ Fail{error}: Fail{error}
    case SNil{} Done{Leading{}}: Fail{InvalidLength{}}
    case SNil{} Done{Digits{value}}: Done{value}
    case SNil{} Done{Trailing{value}}: Done{value}
    case SCon{Chr{byte}, rest} Done{state}: scan(rest, consume(state, byte))

def parse(value: String) -> Result<&2, &2, LengthError, W.U64>:
  scan(value, Done{Leading{}})

def optional(result: Result<&2, &2, LengthError, W.U64>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Some{value}}

def observed(previous: Maybe<&2, W.U64>, value: String) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match previous:
    case None{}: optional(parse(value))
    case Some{_}: Fail{DuplicateLength{}}

def field(matches: Bool, previous: Maybe<&2, W.U64>, value: String) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match matches:
    case False{}: Done{previous}
    case True{}: observed(previous, value)

def collect(fields: List<&2, H.Header>, result: Result<&2, &2, LengthError, Maybe<&2, W.U64>>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  match fields result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{value}: Done{value}
    case H.Header{name, value} <> rest Done{previous}:
      collect(rest, field(String.eq(H.lowercase(name), "content-length"), previous, value))

def fromFields(fields: List<&2, H.Header>) -> Result<&2, &2, LengthError, Maybe<&2, W.U64>>:
  collect(fields, Done{None{}})
