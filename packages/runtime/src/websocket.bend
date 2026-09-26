import Base
import ./base64.bend as Base64
import ./http-message.bend as HTTP
import ./sha1.bend as SHA1
import ./text.bend as Text
import ./utf8.bend as UTF8

# RFC 6455 client framing. Decoding consumes each wire byte once and joins
# fragmented messages once. Control frames do not disturb a partial message.
# No extensions are negotiated; server frames must be unmasked.
type Message is Data:
  TextMessage{value: String}
  BinaryMessage{bytes: List<&2, U32>}
  Ping{bytes: List<&2, U32>}
  Pong{bytes: List<&2, U32>}
  CloseMessage{code: Maybe<&2, U32>, reason: String}

type Phase is Data:
  First{}
  Second{first: U32}
  Length{first: U32, marker: U32, remaining: Nat, count: Nat}
  Payload{first: U32, remaining: Nat, reversed: List<&2, U32>}
type Fragments is Data:
  Fragments{opcode: U32, count: Nat, reversed: List<&2, List<&2, U32>>}
type Decoder is Data:
  Decoder{phase: Phase, fragments: Maybe<&2, Fragments>, maximum: Nat}
type Decoded is Data:
  Decoded{decoder: Decoder, message: Maybe<&2, Message>, rest: List<&2, U32>}

def new(maximum: Nat) -> Decoder: Decoder{First{}, None{}, maximum}
def opcode(first: U32) -> U32: U32.and(first, 15)
def final(first: U32) -> Bool: U32.is_ge(first, 128)
def control(first: U32) -> Bool: U32.is_ge(opcode(first), 8)
def validOpcode(value: U32) -> Bool:
  match value:
    case 0: True{}
    case 1: True{}
    case 2: True{}
    case 8: True{}
    case 9: True{}
    case 10: True{}
    case _: False{}

def textMessage(value: Result<&2, &2, UTF8.Error, String>) -> Result<&2, &2, String, Message>:
  match value:
    case Done{text}: Done{TextMessage{text}}
    case Fail{_}: Fail{"Invalid WebSocket UTF-8"}

def dataMessage(kind: U32, bytes: List<&2, U32>) -> Result<&2, &2, String, Message>:
  match kind:
    case 1: textMessage(UTF8.decodeStrict(bytes))
    case _: Done{BinaryMessage{bytes}}

def closeCode(+code: U32) -> Bool:
  (U32.is_ge(code, 1000) && U32.is_le(code, 1014) && Bool.not(U32.is_eq(code, 1004) || U32.is_eq(code, 1005) || U32.is_eq(code, 1006))) || (U32.is_ge(code, 3000) && U32.is_lt(code, 5000))

def closedText(+code: U32, text: Result<&2, &2, UTF8.Error, String>) -> Result<&2, &2, String, Message>:
  match text:
    case Fail{_}: Fail{"Invalid WebSocket close reason"}
    case Done{reason}: Bool.pick(Result<&2, &2, String, Message>, closeCode(code), Done{CloseMessage{Some{code}, reason}}, Fail{"Invalid WebSocket close code"})

def closeMessage(bytes: List<&2, U32>) -> Result<&2, &2, String, Message>:
  match bytes:
    case Nil{}: Done{CloseMessage{None{}, ""}}
    case _ <> Nil{}: Fail{"Invalid WebSocket close payload"}
    case a <> b <> rest: closedText((a * 256 + b : U32), UTF8.decodeStrict(rest))

def assembled(maximum: Nat, result: Result<&2, &2, String, Message>) -> Result<&2, &2, String, Decoded>:
  Result.map(&2, &2, String, Message, Decoded, value => Decoded{new(maximum), Some{value}, Nil{}}, result)

def continuation(final: Bool, +maximum: Nat, +bytes: List<&2, U32>, fragments: Maybe<&2, Fragments>) -> Result<&2, &2, String, Decoded>:
  match fragments:
    case None{}: Fail{"Unexpected WebSocket continuation"}
    case Some{Fragments{+kind, previous, +chunks}}:
      +next = List.length(&2, U32, bytes) + previous
      Bool.pick(Unit -> Result<&2, &2, String, Decoded>, Nat.is_gt(next, maximum), _ => Fail{"WebSocket message exceeds limit"},
        _ => Bool.pick(Unit -> Result<&2, &2, String, Decoded>, final,
          _ => assembled(maximum, dataMessage(kind, List.concat(&2, U32, List.reverse(&2, List<&2, U32>, bytes <> chunks)))),
          _ => Done{Decoded{Decoder{First{}, Some{Fragments{kind, next, bytes <> chunks}}, maximum}, None{}, Nil{}}})(Unit{}))(Unit{})

def started(+first: U32, +maximum: Nat, +bytes: List<&2, U32>, fragments: Maybe<&2, Fragments>) -> Result<&2, &2, String, Decoded>:
  match fragments:
    case Some{_}: Fail{"WebSocket data frame interrupts fragmented message"}
    case None{}:
      Bool.pick(Unit -> Result<&2, &2, String, Decoded>, final(first),
        _ => assembled(maximum, dataMessage(opcode(first), bytes)),
        _ => Done{Decoded{Decoder{First{}, Some{Fragments{opcode(first), List.length(&2, U32, bytes), [bytes]}}, maximum}, None{}, Nil{}}})(Unit{})

def frame(first: U32, fragments: Maybe<&2, Fragments>, maximum: Nat, bytes: List<&2, U32>) -> Result<&2, &2, String, Decoded>:
  match first:
    case 0: continuation(False{}, maximum, bytes, fragments)
    case 128: continuation(True{}, maximum, bytes, fragments)
    case 137: Done{Decoded{Decoder{First{}, fragments, maximum}, Some{Ping{bytes}}, Nil{}}}
    case 138: Done{Decoded{Decoder{First{}, fragments, maximum}, Some{Pong{bytes}}, Nil{}}}
    case 136: assembled(maximum, closeMessage(bytes))
    case value: started(value, maximum, bytes, fragments)

def beginPayload(+first: U32, +length: Nat, fragments: Maybe<&2, Fragments>, +maximum: Nat) -> Result<&2, &2, String, Decoder>:
  Bool.pick(Result<&2, &2, String, Decoder>, Nat.is_gt(length, maximum) || (control(first) && Nat.is_gt(length, 125n)), Fail{"WebSocket frame exceeds limit"}, Done{Decoder{Payload{first, length, Nil{}}, fragments, maximum}})

def second(first: U32, +byte: U32, +fragments: Maybe<&2, Fragments>, +maximum: Nat) -> Result<&2, &2, String, Decoder>:
  match byte:
    case 126: Done{Decoder{Length{first, byte, 2n, 0n}, fragments, maximum}}
    case 127: Done{Decoder{Length{first, byte, 8n, 0n}, fragments, maximum}}
    case +value: Bool.pick(Result<&2, &2, String, Decoder>, U32.is_ge(value, 128), Fail{"Masked WebSocket server frame"}, beginPayload(first, U32.to_nat(value), fragments, maximum))

def extended(+first: U32, +marker: U32, +remaining: Nat, previous: Nat, +byte: U32, +fragments: Maybe<&2, Fragments>, +maximum: Nat) -> Result<&2, &2, String, Decoder>:
  +next = previous * 256n + U32.to_nat(byte)
  Bool.pick(Unit -> Result<&2, &2, String, Decoder>, U32.is_eq(marker, 127) && Nat.is_eq(remaining, 8n) && U32.is_ge(byte, 128), _ => Fail{"Invalid WebSocket length"},
    _ => Bool.pick(Unit -> Result<&2, &2, String, Decoder>, Nat.is_eq(remaining, 1n),
      _ => Bool.pick(Result<&2, &2, String, Decoder>, (U32.is_eq(marker, 126) && Nat.is_lt(next, 126n)) || (U32.is_eq(marker, 127) && Nat.is_lt(next, 65536n)), Fail{"Noncanonical WebSocket length"}, beginPayload(first, next, fragments, maximum)),
      _ => Done{Decoder{Length{first, marker, remaining - 1n, next}, fragments, maximum}})(Unit{}))(Unit{})

def consume(decoder: Decoder, +byte: U32) -> Result<&2, &2, String, Decoder>:
  match decoder:
    case Decoder{First{}, fragments, maximum}:
      Bool.pick(Result<&2, &2, String, Decoder>, U32.is_le(byte, 255) && U32.is_eq(U32.and(byte, 112), 0) && validOpcode(opcode(byte)) && (Bool.not(control(byte)) || final(byte)), Done{Decoder{Second{byte}, fragments, maximum}}, Fail{"Invalid WebSocket frame header"})
    case Decoder{Second{first}, fragments, maximum}: second(first, byte, fragments, maximum)
    case Decoder{Length{first, marker, remaining, count}, fragments, maximum}: extended(first, marker, remaining, count, byte, fragments, maximum)
    case Decoder{Payload{first, remaining, reversed}, fragments, maximum}: Done{Decoder{Payload{first, remaining - 1n, byte <> reversed}, fragments, maximum}}

def consumed(result: Result<&2, &2, String, Decoder>) -> Result<&2, &2, String, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{decoder}: Done{Decoded{decoder, None{}, Nil{}}}

# Stop at the first complete message/control frame. The caller processes it
# before feeding `rest`, preserving event ordering even if a later frame fails.
@unsafe
def feedResult(result: Result<&2, &2, String, Decoded>, bytes: List<&2, U32>) -> Result<&2, &2, String, Decoded>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Decoded{decoder, Some{message}, _}}: Done{Decoded{decoder, Some{message}, bytes}}
    case Done{Decoded{Decoder{Payload{first, 0n, reversed}, fragments, maximum}, None{}, _}}:
      feedResult(frame(first, fragments, maximum, List.reverse(&2, U32, reversed)), bytes)
    case Done{Decoded{decoder, None{}, _}}:
      match bytes:
        case Nil{}: Done{Decoded{decoder, None{}, Nil{}}}
        case byte <> rest: feedResult(consumed(consume(decoder, byte)), rest)

def feed(decoder: Decoder, bytes: List<&2, U32>) -> Result<&2, &2, String, Decoded>:
  feedResult(Done{Decoded{decoder, None{}, Nil{}}}, bytes)

# Outgoing frames always have a fresh, caller-supplied 32-bit entropy mask.
# The transport obtains that mask from Entropy.bytes for each send.
def lengthBytes(count: Nat, +length: Nat, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case 0n: tail
    case 1n+rest: lengthBytes(rest, length / 256n, U32.from_nat(length % 256n) <> tail)

def lengthHeader(+length: Nat) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, Nat.is_lt(length, 126n), [(U32.from_nat(length) + 128 : U32)], Bool.pick(List<&2, U32>, Nat.is_lt(length, 65536n), 254 <> lengthBytes(2n, length, Nil{}), 255 <> lengthBytes(8n, length, Nil{})))

def maskBytes(+mask: U32) -> List<&2, U32>:
  [U32.and(U32.shrn(mask, 24n), 255), U32.and(U32.shrn(mask, 16n), 255), U32.and(U32.shrn(mask, 8n), 255), U32.and(mask, 255)]

def masked(bytes: List<&2, U32>, +mask: U32, +position: Nat, reversed: List<&2, U32>) -> List<&2, U32>:
  match bytes:
    case Nil{}: List.reverse(&2, U32, reversed)
    case byte <> rest: masked(rest, mask, (position + 1n) % 4n, U32.xor(byte, U32.and(U32.shrn(mask, (3n - position) * 8n), 255)) <> reversed)

def encode(kind: U32, +mask: U32, +payload: List<&2, U32>) -> List<&2, U32>:
  (128 + kind : U32) <> List.concat(&2, U32, [lengthHeader(List.length(&2, U32, payload)), maskBytes(mask), masked(payload, mask, 0n, Nil{})])

def accept(key: String) -> String:
  Base64.encoded(SHA1.toBytes(SHA1.digest(UTF8.encode(key ++ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))), "")

def header(head: HTTP.ResponseHead, name: String) -> Maybe<&2, String>:
  Result.default(&2, &2, HTTP.HeaderSyntaxError, Maybe<&2, String>, HTTP.get(HTTP.headHeaders(head), name), None{})

def tokenIn(values: List<&2, String>, +expected: String) -> Bool:
  match values:
    case Nil{}: False{}
    case value <> rest: String.eq(String.to_lower(Text.trim(value)), expected) || tokenIn(rest, expected)

def hasToken(value: Maybe<&2, String>, expected: String) -> Bool:
  match value:
    case None{}: False{}
    case Some{text}: tokenIn(String.split(text, ','), expected)

def handshake(+head: HTTP.ResponseHead, key: String) -> Result<&2, &2, String, Unit>:
  match head:
    case HTTP.ResponseHead{HTTP.StatusLine{major, minor, status, _}, _}:
      Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(major, 1) && U32.is_eq(minor, 1) && U32.is_eq(status, 101) && hasToken(header(head, "upgrade"), "websocket") && hasToken(header(head, "connection"), "upgrade") && String.eq(Maybe.default(&2, String, header(head, "sec-websocket-accept"), ""), accept(key)) && Maybe.is_none(&2, String, header(head, "sec-websocket-extensions")) && Maybe.is_none(&2, String, header(head, "sec-websocket-protocol")), Done{Unit{}}, Fail{"Invalid WebSocket upgrade response"})
