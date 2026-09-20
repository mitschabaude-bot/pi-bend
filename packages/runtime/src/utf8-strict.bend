import Base
import ./utf8.bend as UTF8

# Offsets count source bytes from zero; EOF errors point one past the input.
type Error is Data:
  InvalidByte{offset: Nat, value: U32}
  InvalidSequence{offset: Nat, value: U32}
  IncompleteSequence{offset: Nat}

type BOM is Data:
  Preserve{}
  StripLeading{}

type State is Data:
  State{offset: Nat, accumulator: UTF8.Accumulator}

def initial(mode: BOM) -> State:
  match mode:
    case Preserve{}: State{0n, UTF8.Accumulator{UTF8.Decoder{UTF8.Ready{}, True{}}, ""}}
    case StripLeading{}: State{0n, UTF8.Accumulator{UTF8.create(), ""}}

# The shared decoder supplies restricted continuation ranges, preventing
# overlong encodings, surrogate scalars and values beyond U+10FFFF.
def valid(pending: UTF8.Pending, +byte: U32) -> Bool:
  match pending:
    case UTF8.Ready{}: U32.is_le(byte, 127) || (U32.is_ge(byte, 194) && U32.is_le(byte, 244))
    case UTF8.Continuation{_, _, lower, upper}: U32.is_ge(byte, lower) && U32.is_le(byte, upper)

def checked(inRange: Bool, allowed: Bool, state: State, byte: U32) -> Result<&2, &2, Error, State>:
  match inRange allowed state:
    case False{} _ State{offset, _}: Fail{InvalidByte{offset, byte}}
    case True{} False{} State{offset, _}: Fail{InvalidSequence{offset, byte}}
    case True{} True{} State{offset, UTF8.Accumulator{UTF8.Decoder{pending, seen}, reversed}}: Done{State{Succ{offset}, UTF8.advance(UTF8.consume(pending, byte), seen, reversed)}}

def step(state: State, +byte: U32) -> Result<&2, &2, Error, State>:
  match state:
    case State{offset, UTF8.Accumulator{UTF8.Decoder{+pending, seen}, reversed}}: checked(U32.is_le(byte, 255), valid(pending, byte), State{offset, UTF8.Accumulator{UTF8.Decoder{pending, seen}, reversed}}, byte)

# State retains output internally across chunks. Only finish exposes text;
# failure drops the accumulator and preserves the first error thereafter.
def feed(bytes: List<&2, U32>, state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, State>:
  match bytes state:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case byte <> rest Done{value}: feed(rest, step(value, byte))

def finish(state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, String>:
  match state:
    case Fail{error}: Fail{error}
    case Done{State{_, UTF8.Accumulator{UTF8.Decoder{UTF8.Ready{}, _}, reversed}}}: Done{String.reverse(reversed)}
    case Done{State{offset, UTF8.Accumulator{UTF8.Decoder{UTF8.Continuation{_, _, _, _}, _}, _}}}: Fail{IncompleteSequence{offset}}

def decodeWith(mode: BOM, bytes: List<&2, U32>) -> Result<&2, &2, Error, String>:
  finish(feed(bytes, Done{initial(mode)}))

# Match the existing text decoder's single leading-BOM treatment, while
# rejecting malformed encoding. Preserve is explicitly available via decodeWith.
def decode(bytes: List<&2, U32>) -> Result<&2, &2, Error, String>:
  decodeWith(StripLeading{}, bytes)
