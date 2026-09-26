import Base
import ./crc32.bend as CRC
import ./utf8.bend as Utf8

# The AWS event-stream binary framing (application/vnd.amazon.eventstream),
# as @smithy/eventstream-codec decodes it: a prelude of the total and header
# lengths with its CRC-32, typed headers, the payload and the message CRC-32.
# Bytes arrive in arbitrary chunks; the decoder keeps the unfinished tail.

type HeaderValue is Data:
  BooleanValue{value: Bool}
  ByteValue{value: U32}
  ShortValue{value: U32}
  IntegerValue{value: U32}
  LongValue{bytes: List<&2, U32>}
  BinaryValue{bytes: List<&2, U32>}
  StringValue{value: String}
  TimestampValue{bytes: List<&2, U32>}
  UuidValue{bytes: List<&2, U32>}

type Header is Data:
  Header{name: String, value: HeaderValue}

type Error is Data:
  InvalidLength{}
  PreludeChecksumMismatch{expected: U32, computed: U32}
  MessageChecksumMismatch{expected: U32, computed: U32}
  InvalidHeaderType{code: U32}
  TruncatedHeader{}
  InvalidHeaderName{}
  TruncatedStream{remaining: Nat}

def take(bytes: List<&2, U32>, count: Nat) -> List<&2, U32>: List.take(&2, U32, bytes, count)

def drop(bytes: List<&2, U32>, count: Nat) -> List<&2, U32>: List.drop(&2, U32, bytes, count)

def decodedText(decoded: Utf8.Decoded) -> String:
  match decoded:
    case Utf8.Decoded{_, text}: text

def utf8Text(bytes: List<&2, U32>) -> String: decodedText(Utf8.decode(Utf8.create(), bytes))

# Header values: the type code, then a fixed-size value or a 2-byte length
# and that many bytes.
type Parsed is Data:
  Parsed{value: HeaderValue, rest: List<&2, U32>}

def word(bytes: List<&2, U32>) -> U32:
  match bytes:
    case a <> b <> c <> d <> _: U32.or(U32.or(U32.shln(a, 24n), U32.shln(b, 16n)), U32.or(U32.shln(c, 8n), d))
    case _: 0

def short(bytes: List<&2, U32>) -> U32:
  match bytes:
    case a <> b <> _: U32.or(U32.shln(a, 8n), b)
    case _: 0

def sized(+bytes: List<&2, U32>, +size: Nat, make: List<&2, U32> -> HeaderValue) -> Result<&2, &2, Error, Parsed>:
  +available = List.length(&2, U32, bytes)
  Bool.pick(Result<&2, &2, Error, Parsed>, Nat.is_lt(available, size), Fail{TruncatedHeader{}}, Done{Parsed{make(take(bytes, size)), drop(bytes, size)}})

def prefixed(+bytes: List<&2, U32>, make: List<&2, U32> -> HeaderValue) -> Result<&2, &2, Error, Parsed>:
  sized(drop(bytes, 2n), U32.to_nat(short(bytes)), make)

def stringValue(bytes: List<&2, U32>) -> HeaderValue: StringValue{utf8Text(bytes)}

def headerValueOf(kind: Nat, code: U32, +bytes: List<&2, U32>) -> Result<&2, &2, Error, Parsed>:
  match kind:
    case 0n: Done{Parsed{BooleanValue{True{}}, bytes}}
    case 1n: Done{Parsed{BooleanValue{False{}}, bytes}}
    case 2n: sized(bytes, 1n, value => ByteValue{word(0 <> 0 <> 0 <> value)})
    case 3n: sized(bytes, 2n, value => ShortValue{short(value)})
    case 4n: sized(bytes, 4n, value => IntegerValue{word(value)})
    case 5n: sized(bytes, 8n, value => LongValue{value})
    case 6n: prefixed(bytes, value => BinaryValue{value})
    case 7n: prefixed(bytes, stringValue)
    case 8n: sized(bytes, 8n, value => TimestampValue{value})
    case 9n: sized(bytes, 16n, value => UuidValue{value})
    case _: Fail{InvalidHeaderType{code}}

def headerValue(+code: U32, +bytes: List<&2, U32>) -> Result<&2, &2, Error, Parsed>:
  headerValueOf(U32.to_nat(code), code, bytes)

def oneHeader(truncated: Bool, after: List<&2, U32>) -> Result<&2, &2, Error, Parsed>:
  match truncated after:
    case True{} _: Fail{TruncatedHeader{}}
    case False{} code <> values: headerValue(code, values)
    case False{} Nil{}: Fail{TruncatedHeader{}}

def withHeader(-A: Data, name: String, parsed: Parsed, rest: List<&2, U32> -> Result<&2, &2, Error, List<&2, Header>>) -> Result<&2, &2, Error, List<&2, Header>>:
  match parsed:
    case Parsed{value, remaining}: Result.map(&2, &2, Error, List<&2, Header>, List<&2, Header>, fields => Header{name, value} <> fields, rest(remaining))

# Headers: a 1-byte name length, the name, the value type and the value,
# until the header bytes run out.
@unsafe def headers(bytes: List<&2, U32>) -> Result<&2, &2, Error, List<&2, Header>>:
  match bytes:
    case Nil{}: Done{Nil{}}
    case +length <> +rest:
      +size = U32.to_nat(length)
      +after = drop(rest, size)
      +name = utf8Text(take(rest, size))
      Result.bind(&2, &2, Error, Parsed, List<&2, Header>, oneHeader(Nat.is_lt(List.length(&2, U32, rest), size + 1n), after), parsed => withHeader(Unit, name, parsed, headers))

type Message is Data:
  Message{headers: List<&2, Header>, payload: List<&2, U32>}

type Decoder is Data:
  Decoder{pending: List<&2, U32>, length: Nat}

def create() -> Decoder: Decoder{Nil{}, 0n}

def checked(+expected: U32, +computed: U32, mismatch: U32 -> U32 -> Error) -> Result<&2, &2, Error, Unit>:
  Bool.pick(Result<&2, &2, Error, Unit>, U32.is_eq(expected, computed), Done{Unit{}}, Fail{mismatch(expected, computed)})

def framed(+bytes: List<&2, U32>, +total: Nat, +headerLength: Nat) -> Result<&2, &2, Error, Message>:
  do Result<&2, &2, Error, Message>:
    prelude : Unit <- checked(word(drop(bytes, 8n)), CRC.checksum(take(bytes, 8n)), expected => computed => PreludeChecksumMismatch{expected, computed})
    whole : Unit <- checked(word(drop(bytes, total - 4n)), CRC.checksum(take(bytes, total - 4n)), expected => computed => MessageChecksumMismatch{expected, computed})
    fields : List<&2, Header> <- headers(take(drop(bytes, 12n), headerLength))
    return Message{fields, take(drop(bytes, 12n + headerLength), total - 16n - headerLength)}

# One complete message of `total` bytes.
def message(+bytes: List<&2, U32>) -> Result<&2, &2, Error, Message>:
  +total = U32.to_nat(word(bytes))
  +headerLength = U32.to_nat(word(drop(bytes, 4n)))
  Bool.pick(Result<&2, &2, Error, Message>, Nat.is_lt(total, 16n + headerLength), Fail{InvalidLength{}}, framed(bytes, total, headerLength))

type Decoded is Data:
  Decoded{decoder: Decoder, messages: List<&2, Message>}

def prepended(message: Message, result: Result<&2, &2, Error, Decoded>) -> Result<&2, &2, Error, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoded{decoder, messages}}: Done{Decoded{decoder, message <> messages}}

# Split every complete message off the pending bytes.
@unsafe def split(+pending: List<&2, U32>, +length: Nat) -> Result<&2, &2, Error, Decoded>:
  +total = U32.to_nat(word(pending))
  Bool.pick(Unit -> Result<&2, &2, Error, Decoded>, Nat.is_lt(length, 4n) || Nat.is_lt(length, total), _ => Done{Decoded{Decoder{pending, length}, Nil{}}}, _ => Bool.pick(Unit -> Result<&2, &2, Error, Decoded>, Nat.is_lt(total, 16n), _ => Fail{InvalidLength{}}, _ => Result.bind(&2, &2, Error, Message, Decoded, message(take(pending, total)), decoded => prepended(decoded, split(drop(pending, total), length - total))))(Unit{}))(Unit{})

def decode(decoder: Decoder, +chunk: List<&2, U32>) -> Result<&2, &2, Error, Decoded>:
  match decoder:
    case Decoder{pending, length}: split(List.append(&2, U32, pending, chunk), length + List.length(&2, U32, chunk))

# The end of the stream: bytes of an unfinished message are an error.
def finish(decoder: Decoder) -> Result<&2, &2, Error, Unit>:
  match decoder:
    case Decoder{_, 0n}: Done{Unit{}}
    case Decoder{_, remaining}: Fail{TruncatedStream{remaining}}

def headerOf(headers: List<&2, Header>, +name: String) -> Maybe<&2, HeaderValue>:
  match headers:
    case Nil{}: None{}
    case Header{+key, +value} <> rest: Bool.pick(Maybe<&2, HeaderValue>, String.eq(key, name), Some{value}, headerOf(rest, name))

def stringHeader(value: Maybe<&2, HeaderValue>) -> Maybe<&2, String>:
  match value:
    case Some{StringValue{text}}: Some{text}
    case _: None{}

# A string header's value, e.g. ":event-type" or ":message-type".
def header(headers: List<&2, Header>, name: String) -> Maybe<&2, String>: stringHeader(headerOf(headers, name))
