import Base
import ./u64.bend as W
import ./http-header.bend as H
import ./http-field.bend as Field

# A CRLF-framed chunk-size line. Extensions are validated and ignored, as in
# Fetch; no extension metadata or body-sized buffers are retained.
type Phase is Data:
  FirstDigit{}
  SizeDigits{}
  ExtensionStart{}
  ExtensionName{}
  ExtensionValue{}
  QuotedValue{}
  EscapedValue{}
  AfterQuote{}

type SizeError is Data:
  InvalidSize{}
  SizeOverflow{}
  InvalidExtension{}

type State is Data:
  State{phase: Phase, size: W.U64}

def hex(+byte: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 48) && U32.is_le(byte, 57), Some{(byte - 48 : U32)},
    Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 65) && U32.is_le(byte, 70), Some{(byte - 55 : U32)},
      Bool.pick(Maybe<&2, U32>, U32.is_ge(byte, 97) && U32.is_le(byte, 102), Some{(byte - 87 : U32)}, None{})))

def accumulated(fits: Bool, size: W.U64, digit: U32) -> Result<&2, &2, SizeError, State>:
  match fits:
    case False{}: Fail{SizeOverflow{}}
    case True{}: Done{State{SizeDigits{}, W.add(W.shiftLeft(size, 4n), W.fromU32(digit))}}

def addDigit(+size: W.U64, digit: U32) -> Result<&2, &2, SizeError, State>:
  accumulated(Bool.not(Cmp.is_gt(W.compare(size, W.U64{268435455, 4294967295}))), size, digit)

def tokenStep(valid: Bool, phase: Phase, size: W.U64) -> Result<&2, &2, SizeError, State>:
  match valid:
    case True{}: Done{State{phase, size}}
    case False{}: Fail{InvalidExtension{}}

def nameStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 61: Done{State{ExtensionValue{}, size}}
    case 59: Done{State{ExtensionStart{}, size}}
    case other: tokenStep(H.token(other), ExtensionName{}, size)

def valueStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 34: Done{State{QuotedValue{}, size}}
    case 59: Done{State{ExtensionStart{}, size}}
    case other: tokenStep(H.token(other), ExtensionValue{}, size)

# The installed Fetch parser accepts DEL inside an unescaped quoted value;
# its escaped-pair and header-field character classes are stricter.
def quotedByte(+byte: U32) -> Bool: Field.valueByte(byte) || U32.is_eq(byte, 127)

def quotedStep(size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match byte:
    case 34: Done{State{AfterQuote{}, size}}
    case 92: Done{State{EscapedValue{}, size}}
    case other: tokenStep(quotedByte(other), QuotedValue{}, size)

def sizeStep(digit: Maybe<&2, U32>, first: Bool, size: W.U64, byte: U32) -> Result<&2, &2, SizeError, State>:
  match digit first byte:
    case Some{value} _ _: addDigit(size, value)
    case None{} False{} 59: Done{State{ExtensionStart{}, size}}
    case _ _ _: Fail{InvalidSize{}}

def step(state: State, +byte: U32) -> Result<&2, &2, SizeError, State>:
  match state:
    case State{FirstDigit{}, size}: sizeStep(hex(byte), True{}, size, byte)
    case State{SizeDigits{}, size}: sizeStep(hex(byte), False{}, size, byte)
    case State{ExtensionStart{}, size}: nameStep(size, byte)
    case State{ExtensionName{}, size}: nameStep(size, byte)
    case State{ExtensionValue{}, size}: valueStep(size, byte)
    case State{QuotedValue{}, size}: quotedStep(size, byte)
    case State{EscapedValue{}, size}: tokenStep(Field.valueByte(byte), QuotedValue{}, size)
    case State{AfterQuote{}, size}:
      tokenStep(U32.is_eq(byte, 59), ExtensionStart{}, size)

def finish(state: State) -> Result<&2, &2, SizeError, W.U64>:
  match state:
    case State{FirstDigit{}, _}: Fail{InvalidSize{}}
    case State{ExtensionStart{}, _}: Fail{InvalidExtension{}}
    case State{QuotedValue{}, _}: Fail{InvalidExtension{}}
    case State{EscapedValue{}, _}: Fail{InvalidExtension{}}
    case State{_, size}: Done{size}

def scan(bytes: List<&2, U32>, result: Result<&2, &2, SizeError, State>) -> Result<&2, &2, SizeError, W.U64>:
  match bytes result:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{state}: finish(state)
    case byte <> rest Done{state}: scan(rest, step(state, byte))

def parse(bytes: List<&2, U32>) -> Result<&2, &2, SizeError, W.U64>:
  scan(bytes, Done{State{FirstDigit{}, W.zero()}})
