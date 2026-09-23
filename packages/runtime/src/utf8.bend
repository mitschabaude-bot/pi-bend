import Base
import ./utf16.bend as Utf16


# Byte lists use Base's File.read_bytes convention: each U32 is in 0..255.
# Decoding follows replacement-mode UTF-8, including restricted first trailing
# bytes, reprocessing invalid continuations and stripping one leading BOM.
# State is explicit and immutable; no input or output buffer is shared mutably.
type Pending is Data:
  Ready{}
  Continuation{remaining: U32, value: U32, lower: U32, upper: U32}

type Decoder is Data:
  Decoder{pending: Pending, bomSeen: Bool}

type ByteStep is Data:
  ByteStep{pending: Pending, scalars: List<&2, U32>}

type Output is Data:
  Output{bomSeen: Bool, reversed: String}

type Accumulator is Data:
  Accumulator{decoder: Decoder, reversed: String}

type Decoded is Data:
  Decoded{decoder: Decoder, text: String}

def create() -> Decoder: Decoder{Ready{}, False{}}

def startByte(+byte: U32, ascii: Bool, two: Bool, three: Bool, four: Bool) -> ByteStep:
  match ascii two three four:
    case True{} _ _ _: ByteStep{Ready{}, byte <> Nil{}}
    case _ True{} _ _: ByteStep{Continuation{1, (byte - 192 : U32), 128, 191}, Nil{}}
    case _ _ True{} _: ByteStep{Continuation{2, (byte - 224 : U32), Bool.pick(U32, U32.is_eq(byte, 224), 160, 128), Bool.pick(U32, U32.is_eq(byte, 237), 159, 191)}, Nil{}}
    case _ _ _ True{}: ByteStep{Continuation{3, (byte - 240 : U32), Bool.pick(U32, U32.is_eq(byte, 240), 144, 128), Bool.pick(U32, U32.is_eq(byte, 244), 143, 191)}, Nil{}}
    case _ _ _ _: ByteStep{Ready{}, 65533 <> Nil{}}

def start(+byte: U32) -> ByteStep:
  startByte(byte, U32.is_le(byte, 127), U32.is_ge(byte, 194) && U32.is_le(byte, 223), U32.is_ge(byte, 224) && U32.is_le(byte, 239), U32.is_ge(byte, 240) && U32.is_le(byte, 244))

def reject(step: ByteStep) -> ByteStep:
  match step:
    case ByteStep{pending, scalars}: ByteStep{pending, 65533 <> scalars}

def continued(remaining: U32, value: U32) -> ByteStep:
  match remaining:
    case 1: ByteStep{Ready{}, value <> Nil{}}
    case count: ByteStep{Continuation{(count - 1 : U32), value, 128, 191}, Nil{}}

def continuation(isValid: Bool, remaining: U32, value: U32, byte: U32) -> ByteStep:
  match isValid:
    case True{}: continued(remaining, (value * 64 + byte - 128 : U32))
    case False{}: reject(start(byte))

def consume(pending: Pending, +byte: U32) -> ByteStep:
  match pending:
    case Ready{}: start(byte)
    case Continuation{remaining, value, lower, upper}: continuation(U32.is_ge(byte, lower) && U32.is_le(byte, upper), remaining, value, byte)

def emitFirst(bom: Bool, scalar: U32, reversed: String) -> Output:
  match bom:
    case True{}: Output{True{}, reversed}
    case False{}: Output{True{}, SCon{Chr{scalar}, reversed}}

def emit(scalars: List<&2, U32>, state: Output) -> Output:
  match scalars state:
    case Nil{} state: state
    case +head <> tail Output{seen, reversed}: emit(tail, emitFirst(Bool.not(seen) && U32.is_eq(head, 65279), head, reversed))

def accumulated(pending: Pending, output: Output) -> Accumulator:
  match output:
    case Output{seen, reversed}: Accumulator{Decoder{pending, seen}, reversed}

def advance(step: ByteStep, seen: Bool, reversed: String) -> Accumulator:
  match step:
    case ByteStep{pending, scalars}: accumulated(pending, emit(scalars, Output{seen, reversed}))

def loop(bytes: List<&2, U32>, state: Accumulator) -> Decoded:
  match bytes state:
    case Nil{} Accumulator{decoder, reversed}: Decoded{decoder, String.reverse(reversed)}
    case head <> tail Accumulator{Decoder{pending, seen}, reversed}: loop(tail, advance(consume(pending, head), seen, reversed))

def decode(decoder: Decoder, bytes: List<&2, U32>) -> Decoded:
  loop(bytes, Accumulator{decoder, ""})

# Ending a stream emits one replacement for an unfinished sequence and resets
# BOM handling for the next stream, as a fresh non-streaming TextDecoder call.
def finish(decoder: Decoder) -> Decoded:
  match decoder:
    case Decoder{Ready{}, _}: Decoded{create(), ""}
    case Decoder{Continuation{_, _, _, _}, _}: Decoded{create(), "\u{FFFD}"}

def complete(result: Decoded) -> String:
  match result:
    case Decoded{Decoder{Ready{}, _}, text}: text
    case Decoded{_, text}: text ++ "\u{FFFD}"

def decodeBytes(bytes: List<&2, U32>) -> String:
  complete(decode(create(), bytes))

# Node's Buffer#toString('utf8'): replacement mode that keeps a leading BOM.
def decodeBuffer(bytes: List<&2, U32>) -> String:
  complete(decode(Decoder{Ready{}, True{}}, bytes))

def scalarBytes(+scalar: U32, isValid: Bool, ascii: Bool, two: Bool, three: Bool) -> List<&2, U32>:
  match isValid ascii two three:
    case False{} _ _ _: 239 <> 191 <> 189 <> Nil{}
    case True{} True{} _ _: scalar <> Nil{}
    case True{} _ True{} _: (192 + scalar / 64 : U32) <> (128 + scalar % 64 : U32) <> Nil{}
    case True{} _ _ True{}: (224 + scalar / 4096 : U32) <> (128 + scalar / 64 % 64 : U32) <> (128 + scalar % 64 : U32) <> Nil{}
    case True{} _ _ _: (240 + scalar / 262144 : U32) <> (128 + scalar / 4096 % 64 : U32) <> (128 + scalar / 64 % 64 : U32) <> (128 + scalar % 64 : U32) <> Nil{}

def encodeScalar(+scalar: U32) -> List<&2, U32>:
  scalarBytes(scalar, U32.is_le(scalar, 1114111) && Bool.not(Utf16.highSurrogate(scalar) || Utf16.lowSurrogate(scalar)), U32.is_le(scalar, 127), U32.is_le(scalar, 2047), U32.is_le(scalar, 65535))

def prependReversed(bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: reversed
    case head <> tail: prependReversed(tail, head <> reversed)

def encodeLoop(text: String, reversed: List<&2, U32>) -> List<&2, U32>:
  match text:
    case SNil{}: List.reverse(&2, U32, reversed)
    case SCon{Chr{scalar}, rest}: encodeLoop(rest, prependReversed(encodeScalar(scalar), reversed))

# Native scalars and explicit UTF-16 surrogate pairs produce identical bytes;
# unmatched surrogates are replaced rather than placed on the wire.
def encode(text: String) -> List<&2, U32>:
  encodeLoop(Utf16.normalize(text), Nil{})


# Offsets count source bytes from zero; EOF errors point one past the input.
type Error is Data:
  InvalidByte{offset: Nat, value: U32}
  InvalidSequence{offset: Nat, value: U32}
  IncompleteSequence{offset: Nat}

type BOM is Data:
  Preserve{}
  StripLeading{}

type State is Data:
  State{offset: Nat, accumulator: Accumulator}

def initial(mode: BOM) -> State:
  match mode:
    case Preserve{}: State{0n, Accumulator{Decoder{Ready{}, True{}}, ""}}
    case StripLeading{}: State{0n, Accumulator{create(), ""}}

# The shared decoder supplies restricted continuation ranges, preventing
# overlong encodings, surrogate scalars and values beyond U+10FFFF.
def valid(pending: Pending, +byte: U32) -> Bool:
  match pending:
    case Ready{}: U32.is_le(byte, 127) || (U32.is_ge(byte, 194) && U32.is_le(byte, 244))
    case Continuation{_, _, lower, upper}: U32.is_ge(byte, lower) && U32.is_le(byte, upper)

def checked(inRange: Bool, allowed: Bool, state: State, byte: U32) -> Result<&2, &2, Error, State>:
  match inRange allowed state:
    case False{} _ State{offset, _}: Fail{InvalidByte{offset, byte}}
    case True{} False{} State{offset, _}: Fail{InvalidSequence{offset, byte}}
    case True{} True{} State{offset, Accumulator{Decoder{pending, seen}, reversed}}: Done{State{Succ{offset}, advance(consume(pending, byte), seen, reversed)}}

def step(state: State, +byte: U32) -> Result<&2, &2, Error, State>:
  match state:
    case State{offset, Accumulator{Decoder{+pending, seen}, reversed}}: checked(U32.is_le(byte, 255), valid(pending, byte), State{offset, Accumulator{Decoder{pending, seen}, reversed}}, byte)

# State retains output internally across chunks. Only finish exposes text;
# failure drops the accumulator and preserves the first error thereafter.
def feed(bytes: List<&2, U32>, state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, State>:
  match bytes state:
    case _ Fail{error}: Fail{error}
    case Nil{} result: result
    case byte <> rest Done{value}: feed(rest, step(value, byte))

def finishStrict(state: Result<&2, &2, Error, State>) -> Result<&2, &2, Error, String>:
  match state:
    case Fail{error}: Fail{error}
    case Done{State{_, Accumulator{Decoder{Ready{}, _}, reversed}}}: Done{String.reverse(reversed)}
    case Done{State{offset, Accumulator{Decoder{Continuation{_, _, _, _}, _}, _}}}: Fail{IncompleteSequence{offset}}

def decodeWith(mode: BOM, bytes: List<&2, U32>) -> Result<&2, &2, Error, String>:
  finishStrict(feed(bytes, Done{initial(mode)}))

# Match the existing text decoder's single leading-BOM treatment, while
# rejecting malformed encoding. Preserve is explicitly available via decodeWith.
def decodeStrict(bytes: List<&2, U32>) -> Result<&2, &2, Error, String>:
  decodeWith(StripLeading{}, bytes)

# Drain completed scalars after a streaming feed, retaining the strict decoder's
# pending sequence, BOM policy and absolute byte offset without retaining text.
type Chunk is Data: Chunk{state: State, text: String}
def drain(state: State) -> Chunk:
  match state:
    case State{offset, Accumulator{decoder, reversed}}:
      Chunk{State{offset, Accumulator{decoder, ""}}, String.reverse(reversed)}
