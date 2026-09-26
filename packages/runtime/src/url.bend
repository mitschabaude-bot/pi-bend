import Base
import ./string.bend as Split
import ./uri-component.bend as Uri
import ./utf8.bend as Utf8
import ./idna.bend as IDNA


# URL IPv4 addresses have one canonical numeric representation. Parsing accepts
# the URL Standard's decimal, octal, hexadecimal and abbreviated host syntax.
type Address is Data:
  Address{value: U32}

type NumberError is Data:
  InvalidNumber{}
  NumberOverflow{}

type AddressError is Data:
  InvalidPart{}
  TooManyParts{}
  OutOfRange{}

# Continue checking digits after overflow: a huge valid number must trigger
# numeric-host parsing, whereas a suffix with a non-digit can still be a domain.
def accumulated(fits: Bool, value: U32, radix: U32, digit: U32) -> Result<&2, &2, NumberError, U32>:
  match fits:
    case False{}: Fail{NumberOverflow{}}
    case True{}: Done{(value * radix + digit : U32)}

def digitValue(valid: Bool, +digit: U32, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match valid state:
    case False{} _: Fail{InvalidNumber{}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{+value}: accumulated(U32.is_le(value, ((4294967295 - digit) / radix : U32)), value, radix, digit)

def addDigit(digit: Maybe<&2, U32>, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match digit:
    case None{}: Fail{InvalidNumber{}}
    case Some{+value}: digitValue(U32.is_lt(value, radix), value, radix, state)

def digits(text: String, +radix: U32, state: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, NumberError, U32>:
  match text state:
    case _ Fail{InvalidNumber{}}: Fail{InvalidNumber{}}
    case SNil{} result: result
    case SCon{Chr{code}, rest} result: digits(rest, radix, addDigit(Uri.hex(code), radix, result))

def ipv4Number(text: String) -> Result<&2, &2, NumberError, U32>:
  match text:
    case SNil{}: Fail{InvalidNumber{}}
    case SCon{'0', SCon{'x', rest}}: digits(rest, 16, Done{0})
    case SCon{'0', SCon{'X', rest}}: digits(rest, 16, Done{0})
    case SCon{'0', rest}: digits(rest, 8, Done{0})
    case other: digits(other, 10, Done{0})

def trimTrailing(reversed: List<&2, String>) -> List<&2, String>:
  match reversed:
    case SNil{} <> first <> rest: first <> rest
    case other: other

def reversedParts(text: String) -> List<&2, String>:
  trimTrailing(List.reverse(&2, String, Split.split(text, '.')))

def decimalTail(text: String, valid: Bool) -> Bool:
  match text valid:
    case _ False{}: False{}
    case SNil{} True{}: True{}
    case SCon{Chr{+code}, rest} True{}: decimalTail(rest, U32.is_ge(code, 48) && U32.is_le(code, 57))

def decimal(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case other: decimalTail(other, True{})

def numeric(result: Result<&2, &2, NumberError, U32>) -> Bool:
  match result:
    case Fail{InvalidNumber{}}: False{}
    case _: True{}

def lastIsNumber(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: False{}
    case +last <> _: decimal(last) || numeric(ipv4Number(last))

# Input is the already-normalized ASCII domain, before host classification.
def endsInNumber(text: String) -> Bool: lastIsNumber(reversedParts(text))

type State is Data:
  Ipv4Prefix{count: U32, value: U32}
  Complete{address: Address}

def bounded(fits: Bool, value: U32) -> Result<&2, &2, AddressError, State>:
  match fits:
    case False{}: Fail{OutOfRange{}}
    case True{}: Done{Complete{Address{value}}}

def finalPart(count: U32, prefix: U32, +last: U32) -> Result<&2, &2, AddressError, State>:
  match count:
    case 0: Done{Complete{Address{last}}}
    case 1: bounded(U32.is_le(last, 16777215), (prefix * 16777216 + last : U32))
    case 2: bounded(U32.is_le(last, 65535), (prefix * 65536 + last : U32))
    case _: bounded(U32.is_le(last, 255), (prefix * 256 + last : U32))

def prefixPart(fits: Bool, count: U32, prefix: U32, value: U32) -> Result<&2, &2, AddressError, State>:
  match fits:
    case False{}: Fail{OutOfRange{}}
    case True{}: Done{Ipv4Prefix{(count + 1 : U32), (prefix * 256 + value : U32)}}

def ipv4Part(last: Bool, count: U32, prefix: U32, result: Result<&2, &2, NumberError, U32>) -> Result<&2, &2, AddressError, State>:
  match last result:
    case _ Fail{InvalidNumber{}}: Fail{InvalidPart{}}
    case _ Fail{NumberOverflow{}}: Fail{OutOfRange{}}
    case True{} Done{value}: finalPart(count, prefix, value)
    case False{} Done{+value}: prefixPart(U32.is_le(value, 255), count, prefix, value)

def scanIpv4(parts: List<&2, String>, state: Result<&2, &2, AddressError, State>) -> Result<&2, &2, AddressError, Address>:
  match parts state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Complete{address}}: Done{address}
    case Nil{} _: Fail{InvalidPart{}}
    case _ Done{Ipv4Prefix{4, _}}: Fail{TooManyParts{}}
    case value <> +rest Done{Ipv4Prefix{count, prefix}}: scanIpv4(rest, ipv4Part(List.is_empty(&2, String, rest), count, prefix, ipv4Number(value)))
    case _ _: Fail{TooManyParts{}}

def parseIpv4(text: String) -> Result<&2, &2, AddressError, Address>:
  scanIpv4(List.reverse(&2, String, reversedParts(text)), Done{Ipv4Prefix{0, 0}})

def serializeIpv4(address: Address) -> String:
  match address:
    case Address{+value}: U32.show((value / 16777216 : U32)) ++ "." ++ U32.show((value / 65536 % 256 : U32)) ++ "." ++ U32.show((value / 256 % 256 : U32)) ++ "." ++ U32.show((value % 256 : U32))


# Four 32-bit words in network order. Every value is a valid 128-bit address.
type Ipv6Address is Data:
  Ipv6Address{a: U32, b: U32, c: U32, d: U32}

type Ipv6AddressError is Data:
  InvalidPiece{}
  InvalidCompression{}
  InvalidEmbeddedIPv4{}
  WrongPieceCount{}

def words(address: Ipv6Address) -> List<&2, U32>:
  match address:
    case Ipv6Address{+a, +b, +c, +d}: (a / 65536 : U32) <> (a % 65536 : U32) <> (b / 65536 : U32) <> (b % 65536 : U32) <> (c / 65536 : U32) <> (c % 65536 : U32) <> (d / 65536 : U32) <> (d % 65536 : U32) <> Nil{}

def ipv6Address(parts: List<&2, U32>) -> Result<&2, &2, Ipv6AddressError, Ipv6Address>:
  match parts:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}: Done{Ipv6Address{(a * 65536 + b : U32), (c * 65536 + d : U32), (e * 65536 + f : U32), (g * 65536 + h : U32)}}
    case _: Fail{WrongPieceCount{}}

# Bounded digit accumulation is shared by hex pieces and decimal IPv4 octets.
def ipv6DigitValue(digit: Maybe<&2, U32>, +radix: U32, value: U32) -> Maybe<&2, U32>:
  match digit:
    case None{}: None{}
    case Some{+digit}: Bool.pick(Maybe<&2, U32>, U32.is_lt(digit, radix), Some{(value * radix + digit : U32)}, None{})

def ipv6Digits(text: String, +radix: U32, left: U32, value: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match text left value:
    case _ _ None{}: None{}
    case SNil{} _ result: result
    case _ 0 _: None{}
    case SCon{Chr{code}, rest} remaining Some{value}: ipv6Digits(rest, radix, (remaining - 1 : U32), ipv6DigitValue(Uri.hex(code), radix, value))

def hexPiece(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case other: ipv6Digits(other, 16, 4, Some{0})

def octetValue(value: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match value:
    case None{}: None{}
    case Some{+value}: Bool.pick(Maybe<&2, U32>, U32.is_le(value, 255), Some{value}, None{})

def octet(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case SCon{'0', SNil{}}: Some{0}
    case SCon{'0', _}: None{}
    case other: octetValue(ipv6Digits(other, 10, 3, Some{0}))

def embeddedValues(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>) -> Result<&2, &2, Ipv6AddressError, List<&2, U32>>:
  match a b c d:
    case Some{a} Some{b} Some{c} Some{d}: Done{(a * 256 + b : U32) <> (c * 256 + d : U32) <> Nil{}}
    case _ _ _ _: Fail{InvalidEmbeddedIPv4{}}

def embedded(parts: List<&2, String>) -> Result<&2, &2, Ipv6AddressError, List<&2, U32>>:
  match parts:
    case a <> b <> c <> d <> Nil{}: embeddedValues(octet(a), octet(b), octet(c), octet(d))
    case _: Fail{InvalidEmbeddedIPv4{}}

def hasDot(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'.', _}: True{}
    case SCon{_, rest}: hasDot(rest)

def single(value: Maybe<&2, U32>) -> Result<&2, &2, Ipv6AddressError, List<&2, U32>>:
  match value:
    case None{}: Fail{InvalidPiece{}}
    case Some{value}: Done{value <> Nil{}}

def piece(dotted: Bool, final: Bool, text: String) -> Result<&2, &2, Ipv6AddressError, List<&2, U32>>:
  match dotted final:
    case True{} True{}: embedded(Split.split(text, '.'))
    case True{} False{}: Fail{InvalidEmbeddedIPv4{}}
    case False{} _: single(hexPiece(text))

# Remove only the boundary empty token belonging to a double colon. Interior
# empty tokens are compression markers; a lone boundary colon is an error.
def trimEnd(reversed: List<&2, String>) -> Result<&2, &2, Ipv6AddressError, List<&2, String>>:
  match reversed:
    case SNil{} <> SNil{} <> rest: Done{List.reverse(&2, String, SNil{} <> rest)}
    case SNil{} <> _ <> _: Fail{InvalidCompression{}}
    case other: Done{List.reverse(&2, String, other)}

def tokens(parts: List<&2, String>) -> Result<&2, &2, Ipv6AddressError, List<&2, String>>:
  match parts:
    case SNil{} <> SNil{} <> third <> rest: trimEnd(List.reverse(&2, String, SNil{} <> third <> rest))
    case SNil{} <> _: Fail{InvalidCompression{}}
    case other: trimEnd(List.reverse(&2, String, other))

type Ipv6State is Data:
  Ipv6State{count: U32, reversed: List<&2, U32>, compression: Maybe<&2, U32>}

def markCompression(state: Ipv6State) -> Result<&2, &2, Ipv6AddressError, Ipv6State>:
  match state:
    case Ipv6State{+count, reversed, None{}}: Done{Ipv6State{count, reversed, Some{count}}}
    case _: Fail{InvalidCompression{}}

def appendWords(parts: List<&2, U32>, state: Ipv6State) -> Result<&2, &2, Ipv6AddressError, Ipv6State>:
  match parts state:
    case Nil{} state: Done{state}
    case _ Ipv6State{8, _, _}: Fail{WrongPieceCount{}}
    case value <> rest Ipv6State{count, reversed, compression}: appendWords(rest, Ipv6State{(count + 1 : U32), value <> reversed, compression})

def appendResult(result: Result<&2, &2, Ipv6AddressError, List<&2, U32>>, state: Ipv6State) -> Result<&2, &2, Ipv6AddressError, Ipv6State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{parts}: appendWords(parts, state)

def zeros(count: Nat, tail: List<&2, U32>) -> List<&2, U32>:
  match count:
    case Zero{}: tail
    case Succ{remaining}: zeros(remaining, 0 <> tail)

def expand(parts: List<&2, U32>, index: U32, count: U32) -> List<&2, U32>:
  match parts index:
    case parts 0: zeros(U32.to_nat(count), parts)
    case head <> rest remaining: head <> expand(rest, (remaining - 1 : U32), count)
    case Nil{} _: Nil{}

def finishIpv6(state: Ipv6State) -> Result<&2, &2, Ipv6AddressError, Ipv6Address>:
  match state:
    case Ipv6State{8, reversed, None{}}: ipv6Address(List.reverse(&2, U32, reversed))
    case Ipv6State{8, _, Some{_}}: Fail{InvalidCompression{}}
    case Ipv6State{count, reversed, Some{index}}: ipv6Address(expand(List.reverse(&2, U32, reversed), index, (8 - count : U32)))
    case _: Fail{WrongPieceCount{}}

def scanIpv6(parts: List<&2, String>, state: Result<&2, &2, Ipv6AddressError, Ipv6State>) -> Result<&2, &2, Ipv6AddressError, Ipv6Address>:
  match parts state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{state}: finishIpv6(state)
    case SNil{} <> rest Done{state}: scanIpv6(rest, markCompression(state))
    case +text <> +rest Done{state}: scanIpv6(rest, appendResult(piece(hasDot(text), List.is_empty(&2, String, rest), text), state))

def parsedTokens(result: Result<&2, &2, Ipv6AddressError, List<&2, String>>) -> Result<&2, &2, Ipv6AddressError, Ipv6Address>:
  match result:
    case Fail{error}: Fail{error}
    case Done{parts}: scanIpv6(parts, Done{Ipv6State{0, Nil{}, None{}}})

# Input excludes URL host brackets. Zone identifiers are not URL IPv6 syntax.
def parseIpv6(text: String) -> Result<&2, &2, Ipv6AddressError, Ipv6Address>:
  parsedTokens(tokens(Split.split(text, ':')))

type Run is Data:
  Run{start: U32, length: U32}

def longer(start: U32, +length: U32, best: Run) -> Run:
  match best:
    case Run{previousStart, +previous}: Bool.pick(Run, U32.is_gt(length, previous), Run{start, length}, Run{previousStart, previous})

def longest(parts: List<&2, U32>, +index: U32, start: U32, +length: U32, best: Run) -> Run:
  match parts:
    case Nil{}: longer(start, length, best)
    case 0 <> rest: longest(rest, (index + 1 : U32), start, (length + 1 : U32), best)
    case _ <> rest: longest(rest, (index + 1 : U32), (index + 1 : U32), 0, longer(start, length, best))

def hexDigit(+digit: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(digit, 10), (48 + digit : U32), (87 + digit : U32))}

def hexLoop(fuel: Nat, +value: U32, result: String, done: Bool) -> String:
  match fuel done:
    case _ True{}: result
    case Zero{} _: result
    case Succ{rest} False{}: hexLoop(rest, (value / 16 : U32), SCon{hexDigit((value % 16 : U32)), result}, U32.is_lt(value, 16))

def hex(value: U32) -> String:
  match value:
    case 0: "0"
    case other: hexLoop(8n, other, "", False{})

# Emit the first longest zero run once, ignoring its remaining pieces.
def token(begin: Bool, inside: Bool, +index: U32, value: U32) -> String:
  match begin inside:
    case True{} _: Bool.pick(String, U32.is_eq(index, 0), "::", ":")
    case False{} True{}: ""
    case False{} False{}: hex(value) ++ Bool.pick(String, U32.is_eq(index, 7), "", ":")

def render(parts: List<&2, U32>, +index: U32, +start: U32, +length: U32) -> String:
  match parts:
    case Nil{}: ""
    case head <> rest:
      token(U32.is_gt(length, 1) && U32.is_eq(index, start), U32.is_gt(length, 1) && U32.is_gt(index, start) && U32.is_lt(index, (start + length : U32)), index, head) ++ render(rest, (index + 1 : U32), start, length)

def compressed(parts: List<&2, U32>, best: Run) -> String:
  match best:
    case Run{start, length}: render(parts, 0, start, length)

def serializeIpv6(address: Ipv6Address) -> String:
  +parts = words(address)
  compressed(parts, longest(parts, 0, 0, 0, Run{0, 1}))


# URL Standard encode sets. These operate on UTF-8 bytes after converting
# unpaired surrogates to replacement scalars, as URL string inputs require.
type EncodeSet is Data:
  Controls{}
  Fragment{}
  Query{}
  SpecialQuery{}
  Path{}
  UserInfo{}
  Component{}
  Form{}
  EcmaUri{}

def control(+byte: U32) -> Bool: U32.is_lt(byte, 32) || U32.is_gt(byte, 126)
def queryExtra(+byte: U32) -> Bool: U32.is_eq(byte, 32) || U32.is_eq(byte, 34) || U32.is_eq(byte, 35) || U32.is_eq(byte, 60) || U32.is_eq(byte, 62)
def pathExtra(+byte: U32) -> Bool: U32.is_eq(byte, 63) || U32.is_eq(byte, 94) || U32.is_eq(byte, 96) || U32.is_eq(byte, 123) || U32.is_eq(byte, 125)
def userExtra(+byte: U32) -> Bool: U32.is_eq(byte, 47) || U32.is_eq(byte, 58) || U32.is_eq(byte, 59) || U32.is_eq(byte, 61) || U32.is_eq(byte, 64) || (U32.is_ge(byte, 91) && U32.is_le(byte, 93)) || U32.is_eq(byte, 124)
def componentExtra(+byte: U32) -> Bool: (U32.is_ge(byte, 36) && U32.is_le(byte, 38)) || U32.is_eq(byte, 43) || U32.is_eq(byte, 44)
def formExtra(+byte: U32) -> Bool: U32.is_eq(byte, 33) || (U32.is_ge(byte, 39) && U32.is_le(byte, 41)) || U32.is_eq(byte, 126)

# ECMAScript encodeURI keeps ASCII alphanumerics and ;,/?:@&=+$-_.!~*'()#.
def uriUnescaped(+byte: U32) -> Bool:
  (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122)) || U32.is_eq(byte, 33) || U32.is_eq(byte, 35) || U32.is_eq(byte, 36) || (U32.is_ge(byte, 38) && U32.is_le(byte, 47)) || U32.is_eq(byte, 58) || U32.is_eq(byte, 59) || U32.is_eq(byte, 61) || U32.is_eq(byte, 63) || U32.is_eq(byte, 64) || U32.is_eq(byte, 95) || U32.is_eq(byte, 126)

def includes(set: EncodeSet, +byte: U32) -> Bool:
  match set:
    case Controls{}: control(byte)
    case Fragment{}: control(byte) || U32.is_eq(byte, 32) || U32.is_eq(byte, 34) || U32.is_eq(byte, 60) || U32.is_eq(byte, 62) || U32.is_eq(byte, 96)
    case Query{}: control(byte) || queryExtra(byte)
    case SpecialQuery{}: control(byte) || queryExtra(byte) || U32.is_eq(byte, 39)
    case Path{}: control(byte) || queryExtra(byte) || pathExtra(byte)
    case UserInfo{}: control(byte) || queryExtra(byte) || pathExtra(byte) || userExtra(byte)
    case Component{}: control(byte) || queryExtra(byte) || pathExtra(byte) || userExtra(byte) || componentExtra(byte)
    case Form{}: control(byte) || queryExtra(byte) || pathExtra(byte) || userExtra(byte) || componentExtra(byte) || formExtra(byte)
    case EcmaUri{}: Bool.not(uriUnescaped(byte))

def percentHexDigit(+nibble: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(nibble, 10), (48 + nibble : U32), (55 + nibble : U32))}

def emit(plus: Bool, escape: Bool, +byte: U32, reversed: String) -> String:
  match plus escape:
    case True{} _: SCon{'+', reversed}
    case False{} True{}: SCon{percentHexDigit((byte % 16 : U32)), SCon{percentHexDigit((byte / 16 : U32)), SCon{'%', reversed}}}
    case False{} False{}: SCon{Chr{byte}, reversed}

def encodeBytes(bytes: List<&2, U32>, +set: EncodeSet, +spaceAsPlus: Bool, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: encodeBytes(rest, set, spaceAsPlus, emit(spaceAsPlus && U32.is_eq(byte, 32), includes(set, byte), byte, reversed))

def encode(set: EncodeSet, text: String) -> String:
  match set:
    case Form{}: encodeBytes(Utf8.encode(text), Form{}, True{}, "")
    case +other: encodeBytes(Utf8.encode(text), other, False{}, "")

# Invalid/incomplete percent escapes are literal bytes. Decoding is exactly
# one pass, so %2520 becomes %20 rather than a space. Input bytes are 0..255.
type Decoder is Data:
  Ready{reversed: List<&2, U32>}
  Percent{reversed: List<&2, U32>}
  High{raw: U32, nibble: U32, reversed: List<&2, U32>}

def beginByte(byte: U32, reversed: List<&2, U32>) -> Decoder:
  match byte:
    case 37: Percent{reversed}
    case value: Ready{value <> reversed}

def highByte(result: Maybe<&2, U32>, byte: U32, reversed: List<&2, U32>) -> Decoder:
  match result:
    case Some{nibble}: High{byte, nibble, reversed}
    case None{}: beginByte(byte, 37 <> reversed)

def lowByte(result: Maybe<&2, U32>, byte: U32, raw: U32, high: U32, reversed: List<&2, U32>) -> Decoder:
  match result:
    case Some{low}: Ready{(high * 16 + low : U32) <> reversed}
    case None{}: beginByte(byte, raw <> 37 <> reversed)

def advance(state: Decoder, +byte: U32) -> Decoder:
  match state:
    case Ready{reversed}: beginByte(byte, reversed)
    case Percent{reversed}: highByte(Uri.hex(byte), byte, reversed)
    case High{raw, high, reversed}: lowByte(Uri.hex(byte), byte, raw, high, reversed)

def finishPercent(state: Decoder) -> List<&2, U32>:
  match state:
    case Ready{reversed}: List.reverse(&2, U32, reversed)
    case Percent{reversed}: List.reverse(&2, U32, 37 <> reversed)
    case High{raw, _, reversed}: List.reverse(&2, U32, raw <> 37 <> reversed)

def decodeLoop(bytes: List<&2, U32>, state: Decoder) -> List<&2, U32>:
  match bytes:
    case Nil{}: finishPercent(state)
    case byte <> rest: decodeLoop(rest, advance(state, byte))

def decodePercent(bytes: List<&2, U32>) -> List<&2, U32>:
  decodeLoop(bytes, Ready{Nil{}})


# Parse a delimited port token, not a URL.port setter's numeric prefix. The
# authority parser handles delimiters and prohibits ports on file URLs.
type PortError is Data:
  InvalidDigit{}
  PortOutOfRange{}

def boundedPort(fits: Bool, value: U32) -> Result<&2, &2, PortError, U32>:
  match fits:
    case True{}: Done{value}
    case False{}: Fail{PortOutOfRange{}}

def addDigitPort(valid: Bool, +digit: U32, state: Result<&2, &2, PortError, U32>) -> Result<&2, &2, PortError, U32>:
  match valid state:
    case False{} _: Fail{InvalidDigit{}}
    case True{} Fail{error}: Fail{error}
    case True{} Done{+value}: boundedPort(U32.is_le((value * 10 + digit : U32), 65535), (value * 10 + digit : U32))

def portDigits(text: String, state: Result<&2, &2, PortError, U32>) -> Result<&2, &2, PortError, U32>:
  match text state:
    case _ Fail{InvalidDigit{}}: Fail{InvalidDigit{}}
    case SNil{} result: result
    case SCon{Chr{+code}, rest} result: portDigits(rest, addDigitPort(U32.is_ge(code, 48) && U32.is_le(code, 57), (code - 48 : U32), result))

def retainedPort(isDefault: Bool, value: U32) -> Maybe<&2, U32>:
  match isDefault:
    case True{}: None{}
    case False{}: Some{value}

def normalizePort(default: Maybe<&2, U32>, result: Result<&2, &2, PortError, U32>) -> Result<&2, &2, PortError, Maybe<&2, U32>>:
  match default result:
    case _ Fail{error}: Fail{error}
    case None{} Done{value}: Done{Some{value}}
    case Some{expected} Done{+value}: Done{retainedPort(U32.is_eq(value, expected), value)}

def parsePort(default: Maybe<&2, U32>, text: String) -> Result<&2, &2, PortError, Maybe<&2, U32>>:
  match text:
    case SNil{}: Done{None{}}
    case other: normalizePort(default, portDigits(other, Done{0}))


# Scheme tokens exclude the colon. Input preprocessing and relative-URL fallback
# belong to the enclosing URL parser.
type Scheme is Data:
  Ftp{}
  File{}
  Http{}
  Https{}
  Ws{}
  Wss{}
  Other{name: String}

def alpha(+code: U32) -> Bool:
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122))

def lower(upper: Bool, code: U32) -> Char:
  match upper:
    case True{}: Chr{(code + 32 : U32)}
    case False{}: Chr{code}

def normalized(+code: U32) -> Char:
  lower(U32.is_ge(code, 65) && U32.is_le(code, 90), code)

def continuation(+code: U32) -> Bool:
  alpha(code) || (U32.is_ge(code, 48) && U32.is_le(code, 57)) || U32.is_eq(code, 43) || U32.is_eq(code, 45) || U32.is_eq(code, 46)

def classify(text: String) -> Scheme:
  match text:
    case "ftp": Ftp{}
    case "file": File{}
    case "http": Http{}
    case "https": Https{}
    case "ws": Ws{}
    case "wss": Wss{}
    case other: Other{other}

def scanScheme(text: String, valid: Bool, reversed: String) -> Maybe<&2, Scheme>:
  match text valid:
    case _ False{}: None{}
    case SNil{} True{}: Some{classify(String.reverse(reversed))}
    case SCon{Chr{+code}, rest} True{}: scanScheme(rest, continuation(code), SCon{normalized(code), reversed})

def parseScheme(text: String) -> Maybe<&2, Scheme>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: scanScheme(rest, alpha(code), SCon{normalized(code), ""})

def serializeScheme(scheme: Scheme) -> String:
  match scheme:
    case Ftp{}: "ftp"
    case File{}: "file"
    case Http{}: "http"
    case Https{}: "https"
    case Ws{}: "ws"
    case Wss{}: "wss"
    case Other{name}: name

def isSpecialScheme(scheme: Scheme) -> Bool:
  match scheme:
    case Other{_}: False{}
    case _: True{}

def defaultPort(scheme: Scheme) -> Maybe<&2, U32>:
  match scheme:
    case Ftp{}: Some{21}
    case Http{}: Some{80}
    case Https{}: Some{443}
    case Ws{}: Some{80}
    case Wss{}: Some{443}
    case _: None{}


# Tokens from an already-delimited non-file authority. Host normalization and
# port validation are separate stages. Some{empty credentials/port} preserves
# syntax needed by the enclosing parser's empty-host and scheme checks.
type Credentials is Data:
  Credentials{username: String, password: String}

type Tokens is Data:
  Tokens{authorityCredentials: Maybe<&2, Credentials>, host: String, port: Maybe<&2, String>}

type UserHost is Data:
  UserHost{authorityCredentials: Maybe<&2, Credentials>, hostPort: String}

def authorityCredentials(text: String, reversedUsername: String) -> Credentials:
  match text:
    case SNil{}: Credentials{encode(UserInfo{}, String.reverse(reversedUsername)), ""}
    case SCon{':', password}: Credentials{encode(UserInfo{}, String.reverse(reversedUsername)), encode(UserInfo{}, password)}
    case SCon{char, rest}: authorityCredentials(rest, SCon{char, reversedUsername})

# The final '@' separates userinfo from host. Earlier '@' characters belong to
# userinfo and are percent encoded there, including across the password split.
def userHost(reversed: String, hostPort: String) -> UserHost:
  match reversed:
    case SNil{}: UserHost{None{}, hostPort}
    case SCon{'@', userinfo}: UserHost{Some{authorityCredentials(String.reverse(userinfo), "")}, hostPort}
    case SCon{char, rest}: userHost(rest, SCon{char, hostPort})

def hostPort(text: String, insideBrackets: Bool, reversedHost: String, user: Maybe<&2, Credentials>) -> Tokens:
  match text insideBrackets:
    case SNil{} _: Tokens{user, String.reverse(reversedHost), None{}}
    case SCon{':', port} False{}: Tokens{user, String.reverse(reversedHost), Some{port}}
    case SCon{'[', rest} _: hostPort(rest, True{}, SCon{'[', reversedHost}, user)
    case SCon{']', rest} _: hostPort(rest, False{}, SCon{']', reversedHost}, user)
    case SCon{char, rest} brackets: hostPort(rest, brackets, SCon{char, reversedHost}, user)

def separated(input: UserHost) -> Tokens:
  match input:
    case UserHost{user, text}: hostPort(text, False{}, "", user)

def parseAuthority(input: String) -> Tokens:
  separated(userHost(String.reverse(input), ""))

type Prefix is Data:
  Prefix{tokens: Tokens, remainder: String}

type RawPrefix is Data:
  RawPrefix{value: String, remainder: String}

def finish(reversed: String, remainder: String) -> RawPrefix:
  RawPrefix{String.reverse(reversed), remainder}

# Called after the URL parser enters the authority state. Keep the delimiter in
# the remainder so the enclosing path/query/fragment state can consume it.
def scan(text: String, special: Bool, reversed: String) -> RawPrefix:
  match text special:
    case SNil{} _: finish(reversed, "")
    case SCon{'/', rest} _: finish(reversed, SCon{'/', rest})
    case SCon{'?', rest} _: finish(reversed, SCon{'?', rest})
    case SCon{'#', rest} _: finish(reversed, SCon{'#', rest})
    case SCon{'\\', rest} True{}: finish(reversed, SCon{'\\', rest})
    case SCon{char, rest} isSpecial: scan(rest, isSpecial, SCon{char, reversed})

def rawAuthority(text: String, special: Bool) -> RawPrefix:
  scan(text, special, "")

def tokenized(value: RawPrefix) -> Prefix:
  match value:
    case RawPrefix{authority, remainder}: Prefix{parseAuthority(authority), remainder}

def read(text: String, special: Bool) -> Prefix:
  tokenized(rawAuthority(text, special))


# Ordered tuples retain duplicates and empty names/values. Delimiters are
# recognized before percent decoding, so encoded '&' and '=' remain data.
type Entry is Data:
  Entry{name: String, value: String}

def plus(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{'+', rest}: SCon{' ', plus(rest)}
    case SCon{char, rest}: SCon{char, plus(rest)}

# Form parsing uses replacement-mode UTF-8 without stripping a leading BOM.
def decoded(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, decodePercent(Utf8.encode(plus(text)))))

def split(text: String, reversed: String) -> Entry:
  match text:
    case SNil{}: Entry{decoded(String.reverse(reversed)), ""}
    case SCon{'=', value}: Entry{decoded(String.reverse(reversed)), decoded(value)}
    case SCon{char, rest}: split(rest, SCon{char, reversed})

def parseParts(parts: List<&2, String>, reversed: List<&2, Entry>) -> List<&2, Entry>:
  match parts:
    case Nil{}: List.reverse(&2, Entry, reversed)
    case SNil{} <> rest: parseParts(rest, reversed)
    case part <> rest: parseParts(rest, split(part, "") <> reversed)

# Unlike the URLSearchParams string constructor, a form body does not strip '?'.
def parseForm(text: String) -> List<&2, Entry>:
  parseParts(Split.split(text, '&'), Nil{})

def encoded(entry: Entry) -> String:
  match entry:
    case Entry{name, value}: encode(Form{}, name) ++ "=" ++ encode(Form{}, value)

def encodeEntries(entries: List<&2, Entry>) -> List<&2, String>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: encoded(entry) <> encodeEntries(rest)

def serializeSearchParams(entries: List<&2, Entry>) -> String:
  String.join(encodeEntries(entries), "&")

# Web URL inputs are scalar-value strings, preserving BOM and replacing only
# invalid scalar representations. This is not Unicode NFC/case normalization.
def scalarForm(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, Utf8.encode(text)))

def normalize(entry: Entry) -> Entry:
  match entry:
    case Entry{name, value}: Entry{scalarForm(name), scalarForm(value)}


# Provider configuration rejects malformed percent escapes and malformed UTF-8.
# FormStrictError positions count '&'-separated fields, including empty fields. Never put
# a credential-bearing field's contents into an error value.
type FormStrictError is Data:
  InvalidName{field: Nat}
  InvalidValue{field: Nat}

def decodedFormStrict(field: Nat, name: Maybe<&2, String>, value: Maybe<&2, String>) -> Result<&2, &2, FormStrictError, Entry>:
  match name value:
    case None{} _: Fail{InvalidName{field}}
    case Some{_} None{}: Fail{InvalidValue{field}}
    case Some{name} Some{value}: Done{Entry{name, value}}

def pair(+field: Nat, name: String, value: String) -> Result<&2, &2, FormStrictError, Entry>:
  decodedFormStrict(field, Uri.decode(plus(name)), Uri.decode(plus(value)))

def splitFormStrict(field: Nat, text: String, reversed: String) -> Result<&2, &2, FormStrictError, Entry>:
  match text:
    case SNil{}: pair(field, String.reverse(reversed), "")
    case SCon{'=', value}: pair(field, String.reverse(reversed), value)
    case SCon{char, rest}: splitFormStrict(field, rest, SCon{char, reversed})

def prepend(parsed: Result<&2, &2, FormStrictError, Entry>, reversed: List<&2, Entry>) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  match parsed:
    case Fail{cause}: Fail{cause}
    case Done{tuple}: Done{tuple <> reversed}

def step(field: Nat, text: String, result: Result<&2, &2, FormStrictError, List<&2, Entry>>) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  match text result:
    case _ Fail{cause}: Fail{cause}
    case SNil{} Done{reversed}: Done{reversed}
    case other Done{reversed}: prepend(splitFormStrict(field, other, ""), reversed)

def fields(parts: List<&2, String>, +field: Nat, result: Result<&2, &2, FormStrictError, List<&2, Entry>>) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  match parts result:
    case _ Fail{cause}: Fail{cause}
    case Nil{} done: done
    case text <> rest Done{reversed}: fields(rest, Succ{field}, step(field, text, Done{reversed}))

def finishFormStrict(result: Result<&2, &2, FormStrictError, List<&2, Entry>>) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{reversed}: Done{List.reverse(&2, Entry, reversed)}

def parseFormStrict(text: String) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  finishFormStrict(fields(Split.split(text, '&'), Zero{}, Done{Nil{}}))

# Query syntax allows one leading '?'; a form body treats it as ordinary data.
def queryFormStrict(text: String) -> Result<&2, &2, FormStrictError, List<&2, Entry>>:
  match text:
    case SCon{'?', rest}: parseFormStrict(rest)
    case other: parseFormStrict(other)


type Host is Data:
  Domain{name: String}
  IPv4{address: Address}
  IPv6{address: Ipv6Address}
  Opaque{value: String}
  Empty{}

type HostError is Data:
  EmptyDomain{}
  NonASCII{code: U32}
  Forbidden{code: U32}
  UnclosedIPv6{}
  InvalidIPv4{reason: AddressError}
  InvalidIPv6{reason: Ipv6AddressError}

def forbiddenHost(code: U32) -> Bool:
  match code:
    case 0: True{}
    case 9: True{}
    case 10: True{}
    case 13: True{}
    case 32: True{}
    case 35: True{}
    case 47: True{}
    case 58: True{}
    case 60: True{}
    case 62: True{}
    case 63: True{}
    case 64: True{}
    case 91: True{}
    case 92: True{}
    case 93: True{}
    case 94: True{}
    case 124: True{}
    case _: False{}

def forbiddenDomain(+code: U32) -> Bool:
  forbiddenHost(code) || U32.is_lt(code, 32) || U32.is_eq(code, 37) || U32.is_eq(code, 127)

def codeFailure(forbidden: Bool, nonASCII: Bool, code: U32) -> Maybe<&2, HostError>:
  match forbidden nonASCII:
    case True{} _: Some{Forbidden{code}}
    case False{} True{}: Some{NonASCII{code}}
    case _ _: None{}

def checkCode(opaque: Bool, +code: U32) -> Maybe<&2, HostError>:
  match opaque:
    case True{}: codeFailure(forbiddenHost(code), False{}, code)
    case False{}: codeFailure(forbiddenDomain(code), U32.is_gt(code, 127), code)

def scanHost(text: String, +opaque: Bool, error: Maybe<&2, HostError>) -> Maybe<&2, HostError>:
  match text error:
    case _ Some{failure}: Some{failure}
    case SNil{} None{}: None{}
    case SCon{Chr{code}, rest} None{}: scanHost(rest, opaque, checkCode(opaque, code))

def ipv4Result(value: Result<&2, &2, AddressError, Address>) -> Result<&2, &2, HostError, Host>:
  match value:
    case Fail{error}: Fail{InvalidIPv4{error}}
    case Done{address}: Done{IPv4{address}}

def numericDomain(numeric: Bool, text: String) -> Result<&2, &2, HostError, Host>:
  match numeric:
    case True{}: ipv4Result(parseIpv4(text))
    case False{}: Done{Domain{text}}

def checkedDomain(error: Maybe<&2, HostError>, +text: String) -> Result<&2, &2, HostError, Host>:
  match error text:
    case Some{failure} _: Fail{failure}
    case None{} SNil{}: Fail{EmptyDomain{}}
    case None{} _: numericDomain(endsInNumber(text), text)

# Final special-host classification AFTER percent decoding and domain processing.
# The supplied domain must already be normalized; this stage does not perform
# IDNA, lowercase text, decode escapes, or select a compatibility policy.
def classifyDomain(+asciiDomain: String) -> Result<&2, &2, HostError, Host>:
  checkedDomain(scanHost(asciiDomain, False{}, None{}), asciiDomain)

def ipv6Result(value: Result<&2, &2, Ipv6AddressError, Ipv6Address>) -> Result<&2, &2, HostError, Host>:
  match value:
    case Fail{error}: Fail{InvalidIPv6{error}}
    case Done{address}: Done{IPv6{address}}

def closedIPv6(reversed: String) -> Result<&2, &2, HostError, Host>:
  match reversed:
    case SCon{']', rest}: ipv6Result(parseIpv6(String.reverse(rest)))
    case _: Fail{UnclosedIPv6{}}

# The opening bracket was consumed by the caller. Brackets dispatch to IPv6
# before either opaque parsing or domain preparation; no percent decoding occurs.
def bracketed(tail: String) -> Result<&2, &2, HostError, Host>:
  closedIPv6(String.reverse(tail))

def checkedOpaque(error: Maybe<&2, HostError>, text: String) -> Result<&2, &2, HostError, Host>:
  match error text:
    case Some{failure} _: Fail{failure}
    case None{} SNil{}: Done{Empty{}}
    case None{} other: Done{Opaque{encode(Controls{}, other)}}

# Non-special schemes preserve case and literal percent sequences. Nonfatal URL
# unit/escape warnings do not cause rejection and are not exposed by this API.
def parseOpaque(+input: String) -> Result<&2, &2, HostError, Host>:
  match input:
    case SCon{'[', tail}: bracketed(tail)
    case _: checkedOpaque(scanHost(input, True{}, None{}), input)

def serializeHost(host: Host) -> String:
  match host:
    case Domain{name}: name
    case IPv4{address}: serializeIpv4(address)
    case IPv6{address}: "[" ++ serializeIpv6(address) ++ "]"
    case Opaque{value}: value
    case Empty{}: ""


type Prepared is Data:
  Literal{host: Host}
  DomainInput{text: String}

# WHATWG UTF-8 decode without BOM means preserve U+FEFF, not remove it.
# Percent decoding is one pass over UTF-8 bytes. '+' remains a literal plus.
# Replacement scalars from invalid UTF-8 are left for IDNA to reject.
def decode(text: String) -> String:
  Utf8.complete(Utf8.decode(Utf8.Decoder{Utf8.Ready{}, True{}}, decodePercent(Utf8.encode(text))))

def literal(result: Result<&2, &2, HostError, Host>) -> Result<&2, &2, HostError, Prepared>:
  match result:
    case Fail{error}: Fail{error}
    case Done{host}: Done{Literal{host}}

# Input is the raw special-host token after authority delimiting. A literal '['
# dispatches to IPv6 before decoding; percent-encoded brackets do not. The caller
# must process DomainInput through domain/IDNA policy and final classification.
def prepare(input: String) -> Result<&2, &2, HostError, Prepared>:
  match input:
    case SNil{}: Fail{EmptyDomain{}}
    case SCon{'[', rest}: literal(bracketed(rest))
    case text: Done{DomainInput{decode(text)}}


# Ordinary constructor input preprocessing. Setters on an existing URL can use
# removeTabsAndNewlines separately: their parser entry does not trim edge C0/space.
def visible(keep: Bool, char: Char) -> Maybe<&2, Char>:
  match keep:
    case True{}: Some{char}
    case False{}: None{}

def leading(text: String, first: Maybe<&2, Char>) -> String:
  match text first:
    case rest Some{char}: SCon{char, rest}
    case SNil{} None{}: ""
    case SCon{Chr{+code}, rest} None{}: leading(rest, visible(U32.is_gt(code, 32), Chr{code}))

def trim(text: String) -> String:
  String.reverse(leading(String.reverse(leading(text, None{})), None{}))

def retained(remove: Bool, char: Char, reversed: String) -> String:
  match remove:
    case True{}: reversed
    case False{}: SCon{char, reversed}

def filter(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{Chr{+code}, rest}: filter(rest, retained(U32.is_eq(code, 9) || U32.is_eq(code, 10) || U32.is_eq(code, 13), Chr{code}, reversed))

def removeTabsAndNewlines(text: String) -> String: filter(text, "")
def prepareInput(text: String) -> String: removeTabsAndNewlines(trim(text))

type Found is Data:
  Found{scheme: Scheme, remainder: String}

type InputPrefix is Data:
  Absolute{scheme: Scheme, remainder: String}
  Relative{input: String}

# A failed candidate must not consume or lowercase a relative path. Keep the
# original immutable input only at the outer boundary, not in every scan frame.
def schemeChar(colon: Bool, code: U32, reversed: String) -> String:
  match colon:
    case True{}: reversed
    case False{}: SCon{normalized(code), reversed}

def scanInput(text: String, valid: Bool, colon: Bool, reversed: String) -> Maybe<&2, Found>:
  match text valid colon:
    case _ False{} _: None{}
    case rest True{} True{}: Some{Found{classify(String.reverse(reversed)), rest}}
    case SNil{} True{} False{}: None{}
    case SCon{Chr{+code}, rest} True{} False{}: scanInput(rest, continuation(code) || U32.is_eq(code, 58), U32.is_eq(code, 58), schemeChar(U32.is_eq(code, 58), code, reversed))

def find(text: String) -> Maybe<&2, Found>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, rest}: scanInput(rest, alpha(code), False{}, SCon{normalized(code), ""})

def selected(found: Maybe<&2, Found>, original: String) -> InputPrefix:
  match found:
    case None{}: Relative{original}
    case Some{Found{scheme, remainder}}: Absolute{scheme, remainder}

# Input is already preprocessed. Absolute denotes a syntactically present
# scheme, not a successfully parsed URL; scheme-relative/base rules follow.
def inputPrefix(+input: String) -> InputPrefix: selected(find(input), input)


# Entry after '?'. Presence is represented by this result even when value is
# empty; an absent query never enters this parser.
type QueryParsed is Data:
  QueryParsed{value: String, fragment: Maybe<&2, String>}

def encodeSet(special: Bool) -> EncodeSet:
  match special:
    case True{}: SpecialQuery{}
    case False{}: Query{}

# URL queries preserve '+' and existing escapes. Form decoding is separate.
def scanQuery(text: String, +set: EncodeSet, reversed: String) -> QueryParsed:
  match text:
    case SNil{}: QueryParsed{encode(set, String.reverse(reversed)), None{}}
    case SCon{'#', rest}: QueryParsed{encode(set, String.reverse(reversed)), Some{encode(Fragment{}, rest)}}
    case SCon{char, rest}: scanQuery(rest, set, SCon{char, reversed})

def parseQuery(text: String, special: Bool) -> QueryParsed:
  scanQuery(text, encodeSet(special), "")


# RFC 3986 query-component encoding. Form '+' encoding is a different format.
def unreserved(+byte: U32) -> Bool:
  (U32.is_ge(byte, 65) && U32.is_le(byte, 90)) || (U32.is_ge(byte, 97) && U32.is_le(byte, 122)) || (U32.is_ge(byte, 48) && U32.is_le(byte, 57)) || U32.is_eq(byte, 45) || U32.is_eq(byte, 46) || U32.is_eq(byte, 95) || U32.is_eq(byte, 126)

def bytes(input: List<&2, U32>, reversed: String) -> String:
  match input:
    case Nil{}: String.reverse(reversed)
    case +byte <> rest: bytes(rest, emit(False{}, Bool.not(unreserved(byte)), byte, reversed))

def encodeQuery(text: String) -> String: bytes(Utf8.encode(text), "")


type Parsed is Data:
  Parsed{value: String, query: Maybe<&2, String>, fragment: Maybe<&2, String>}

# Only the final literal space directly before '?' or '#' is encoded here.
# Other spaces remain literal. Constructor-edge trimming happens before this
# state; path parsing must not trim data supplied through other parser entries.
def beforeDelimiter(reversed: String) -> String:
  match reversed:
    case SCon{' ', rest}: encode(Controls{}, String.reverse(rest)) ++ "%20"
    case other: encode(Controls{}, String.reverse(other))

def queried(value: String, result: QueryParsed) -> Parsed:
  match result:
    case QueryParsed{query, fragment}: Parsed{value, Some{query}, fragment}

# The enclosing parser enters this state only for an opaque path. It does not
# split slashes, shorten dot segments, decode escapes, or normalize drive names.
def scanOpaquePath(text: String, reversed: String) -> Parsed:
  match text:
    case SNil{}: Parsed{encode(Controls{}, String.reverse(reversed)), None{}, None{}}
    case SCon{'?', rest}: queried(beforeDelimiter(reversed), parseQuery(rest, False{}))
    case SCon{'#', rest}: Parsed{beforeDelimiter(reversed), None{}, Some{encode(Fragment{}, rest)}}
    case SCon{char, rest}: scanOpaquePath(rest, SCon{char, reversed})

def parseOpaquePath(text: String) -> Parsed: scanOpaquePath(text, "")


type PathParsed is Data:
  PathParsed{segments: List<&2, String>, queryPath: Maybe<&2, String>, fragment: Maybe<&2, String>}

type Segment is Data:
  Current{}
  Parent{}
  Name{value: String}

# Recognize one or two literal/percent-encoded dots with a bounded lexer.
# Longer names stay ordinary segments without decoding other percent escapes.
type DotState is Data:
  Dots{count: U32}
  PercentDot{count: U32}
  HexDot{count: U32}
  NotDots{}

def dotStart(room: Bool, dot: Bool, percent: Bool, count: U32) -> DotState:
  match room dot percent:
    case False{} _ _: NotDots{}
    case True{} True{} _: Dots{(count + 1 : U32)}
    case True{} False{} True{}: PercentDot{count}
    case _ _ _: NotDots{}

def dotHex(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: HexDot{count}
    case False{}: NotDots{}

def dotEnd(valid: Bool, count: U32) -> DotState:
  match valid:
    case True{}: Dots{(count + 1 : U32)}
    case False{}: NotDots{}

def dotStep(state: DotState, +char: Char) -> DotState:
  match state:
    case Dots{+count}: dotStart(U32.is_lt(count, 2), Char.is_eq(char, '.'), Char.is_eq(char, '%'), count)
    case PercentDot{count}: dotHex(Char.is_eq(char, '2'), count)
    case HexDot{count}: dotEnd(Char.is_eq(char, 'e') || Char.is_eq(char, 'E'), count)
    case NotDots{}: NotDots{}

def dotCount(text: String, state: DotState) -> Maybe<&2, U32>:
  match text state:
    case _ NotDots{}: None{}
    case SNil{} Dots{count}: Some{count}
    case SNil{} _: None{}
    case SCon{char, rest} previous: dotCount(rest, dotStep(previous, char))

def classified(count: Maybe<&2, U32>, text: String) -> Segment:
  match count:
    case Some{1}: Current{}
    case Some{2}: Parent{}
    case _: Name{encode(Path{}, text)}

def segment(+text: String) -> Segment:
  classified(dotCount(text, Dots{0}), text)

def drive(text: String) -> Bool:
  match text:
    case SCon{Chr{code}, SCon{':', SNil{}}}: alpha(code)
    case SCon{Chr{code}, SCon{'|', SNil{}}}: alpha(code)
    case _: False{}

def normalizedDrive(text: String) -> Bool:
  match text:
    case SCon{Chr{code}, SCon{':', SNil{}}}: alpha(code)
    case _: False{}

def normalizeDrive(valid: Bool, text: String) -> String:
  match valid text:
    case True{} SCon{letter, _}: SCon{letter, SCon{':', SNil{}}}
    case _ value: value

def retainedDrive(keep: Bool, value: String) -> List<&2, String>:
  match keep:
    case True{}: value <> Nil{}
    case False{}: Nil{}

# The working path is reversed, so shortening is constant time. A file drive
# root cannot be removed by '..', including when resolving against a base.
def shorten(reversed: List<&2, String>, file: Bool) -> List<&2, String>:
  match reversed:
    case Nil{}: Nil{}
    case +value <> Nil{}: retainedDrive(file && normalizedDrive(value), value)
    case _ <> rest: rest

def trailing(last: Bool, reversed: List<&2, String>) -> List<&2, String>:
  match last:
    case True{}: "" <> reversed
    case False{}: reversed

def appendName(reversed: List<&2, String>, file: Bool, +value: String) -> List<&2, String>:
  match reversed:
    case Nil{}: normalizeDrive(file && drive(value), value) <> Nil{}
    case rest: value <> rest

def push(part: Segment, file: Bool, last: Bool, reversed: List<&2, String>) -> List<&2, String>:
  match part:
    case Current{}: trailing(last, reversed)
    case Parent{}: trailing(last, shorten(reversed, file))
    case Name{value}: appendName(reversed, file, value)

def finishPath(reversed: List<&2, String>, queryPath: Maybe<&2, String>, fragment: Maybe<&2, String>) -> PathParsed:
  PathParsed{List.reverse(&2, String, reversed), queryPath, fragment}

def queryResult(result: QueryParsed, reversed: List<&2, String>) -> PathParsed:
  match result:
    case QueryParsed{value, fragment}: finishPath(reversed, Some{value}, fragment)

def queryPath(text: String, set: EncodeSet, reversed: String, segments: List<&2, String>) -> PathParsed:
  queryResult(scanQuery(text, set, reversed), segments)

def scanPath(text: String, +special: Bool, +file: Bool, reversed: String, segments: List<&2, String>) -> PathParsed:
  match text special:
    case SNil{} _: finishPath(push(segment(String.reverse(reversed)), file, True{}, segments), None{}, None{})
    case SCon{'/', rest} isSpecial: scanPath(rest, isSpecial, file, "", push(segment(String.reverse(reversed)), file, False{}, segments))
    case SCon{'\\', rest} True{}: scanPath(rest, True{}, file, "", push(segment(String.reverse(reversed)), file, False{}, segments))
    case SCon{'?', rest} isSpecial: queryPath(rest, encodeSet(isSpecial), "", push(segment(String.reverse(reversed)), file, True{}, segments))
    case SCon{'#', rest} _: finishPath(push(segment(String.reverse(reversed)), file, True{}, segments), None{}, Some{encode(Fragment{}, rest)})
    case SCon{char, rest} isSpecial: scanPath(rest, isSpecial, file, SCon{char, reversed}, segments)

def isFilePath(scheme: Scheme) -> Bool:
  match scheme:
    case File{}: True{}
    case _: False{}

# Enter the hierarchical path state, after any leading slash was consumed by
# path-start/relative handling. Existing segments are normalized base segments;
# the caller applies relative-path shortening/reset before entering this state.
def parsePath(text: String, +scheme: Scheme, base: List<&2, String>) -> PathParsed:
  scanPath(text, isSpecialScheme(scheme), isFilePath(scheme), "", List.reverse(&2, String, base))

# Path-start entry after authority parsing. Special schemes always have a path;
# non-special schemes retain an empty segment list until path input occurs.
def startSpecial(text: String, +file: Bool, segments: List<&2, String>) -> PathParsed:
  match text:
    case SCon{'/', rest}: scanPath(rest, True{}, file, "", segments)
    case SCon{'\\', rest}: scanPath(rest, True{}, file, "", segments)
    case other: scanPath(other, True{}, file, "", segments)

def startOther(text: String, segments: List<&2, String>) -> PathParsed:
  match text:
    case SNil{}: finishPath(segments, None{}, None{})
    case SCon{'/', rest}: scanPath(rest, False{}, False{}, "", segments)
    case SCon{'?', rest}: queryPath(rest, Query{}, "", segments)
    case SCon{'#', rest}: finishPath(segments, None{}, Some{encode(Fragment{}, rest)})
    case other: scanPath(other, False{}, False{}, "", segments)

def startState(text: String, special: Bool, file: Bool, segments: List<&2, String>) -> PathParsed:
  match special:
    case True{}: startSpecial(text, file, segments)
    case False{}: startOther(text, segments)

def startPath(text: String, +scheme: Scheme, base: List<&2, String>) -> PathParsed:
  startState(text, isSpecialScheme(scheme), isFilePath(scheme), List.reverse(&2, String, base))


# Internal URL value. Parsers establish normalized scheme/host/port and already
# encoded component strings. None host differs from Some{Empty{}}.
type RecordPath is Data:
  Hierarchical{segments: List<&2, String>}
  RecordOpaque{value: String}

type URL is Data:
  URL{scheme: Scheme, username: String, password: String, host: Maybe<&2, Host>, port: Maybe<&2, U32>, path: RecordPath, query: Maybe<&2, String>, fragment: Maybe<&2, String>}


# Persistent ordered name/value tuples. Operations return new values; retaining
# a prior value or its entries never observes later changes.
type URLSearchParams is Data:
  URLSearchParams{tuples: List<&2, Entry>}

def new() -> URLSearchParams: URLSearchParams{Nil{}}

def parseSearchParams(text: String) -> URLSearchParams:
  match text:
    case SCon{'?', rest}: URLSearchParams{parseForm(rest)}
    case other: URLSearchParams{parseForm(other)}

def normalizedSearchParams(entries: List<&2, Entry>) -> List<&2, Entry>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: normalize(entry) <> normalizedSearchParams(rest)

def fromEntries(entries: List<&2, Entry>) -> URLSearchParams:
  URLSearchParams{normalizedSearchParams(entries)}

def entries(params: URLSearchParams) -> List<&2, Entry>:
  match params:
    case URLSearchParams{tuples}: tuples

def names(tuples: List<&2, Entry>) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Entry{name, _} <> rest: name <> names(rest)

def contents(tuples: List<&2, Entry>) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Entry{_, value} <> rest: value <> contents(rest)

def keys(params: URLSearchParams) -> List<&2, String>: names(entries(params))
def searchParamValues(params: URLSearchParams) -> List<&2, String>: contents(entries(params))

def size(params: URLSearchParams) -> Nat:
  List.length(&2, Entry, entries(params))

def toString(params: URLSearchParams) -> String: serializeSearchParams(entries(params))

def append(params: URLSearchParams, name: String, value: String) -> URLSearchParams:
  URLSearchParams{List.append(&2, Entry, entries(params), normalize(Entry{name, value}) <> Nil{})}

def matches(entry: Entry, name: String, value: Maybe<&2, String>) -> Bool:
  match entry value:
    case Entry{key, _} None{}: String.eq(key, name)
    case Entry{key, stored} Some{value}: String.eq(key, name) && String.eq(stored, value)

def optional(value: Maybe<&2, String>) -> Maybe<&2, String>:
  match value:
    case None{}: None{}
    case Some{text}: Some{scalarForm(text)}

def findSearchParams(tuples: List<&2, Entry>, +name: String) -> Maybe<&2, String>:
  match tuples:
    case Nil{}: None{}
    case Entry{key, value} <> rest: Bool.pick(Maybe<&2, String>, String.eq(key, name), Some{value}, findSearchParams(rest, name))

def get(params: URLSearchParams, name: String) -> Maybe<&2, String>:
  findSearchParams(entries(params), scalarForm(name))

def findAll(tuples: List<&2, Entry>, +name: String) -> List<&2, String>:
  match tuples:
    case Nil{}: Nil{}
    case Entry{key, value} <> rest:
      +found = findAll(rest, name)
      Bool.pick(List<&2, String>, String.eq(key, name), value <> found, found)

def getAll(params: URLSearchParams, name: String) -> List<&2, String>:
  findAll(entries(params), scalarForm(name))

def contains(tuples: List<&2, Entry>, +name: String, +value: Maybe<&2, String>) -> Bool:
  match tuples:
    case Nil{}: False{}
    case entry <> rest: matches(entry, name, value) || contains(rest, name, value)

def has(params: URLSearchParams, name: String, value: Maybe<&2, String>) -> Bool:
  contains(entries(params), scalarForm(name), optional(value))

def remove(tuples: List<&2, Entry>, +name: String, +value: Maybe<&2, String>) -> List<&2, Entry>:
  match tuples:
    case Nil{}: Nil{}
    case +entry <> rest:
      +remaining = remove(rest, name, value)
      Bool.pick(List<&2, Entry>, matches(entry, name, value), remaining, entry <> remaining)

# An optional value restricts removal to matching name/value pairs.
def delete(params: URLSearchParams, name: String, value: Maybe<&2, String>) -> URLSearchParams:
  URLSearchParams{remove(entries(params), scalarForm(name), optional(value))}

type SetState is Data:
  SetState{found: Bool, reversed: List<&2, Entry>}

def setStep(equal: Bool, entry: Entry, name: String, value: String, state: SetState) -> SetState:
  match equal state:
    case False{} SetState{found, reversed}: SetState{found, entry <> reversed}
    case True{} SetState{False{}, reversed}: SetState{True{}, Entry{name, value} <> reversed}
    case True{} previous: previous

def finishSet(name: String, value: String, state: SetState) -> List<&2, Entry>:
  match state:
    case SetState{True{}, reversed}: List.reverse(&2, Entry, reversed)
    case SetState{False{}, reversed}: List.reverse(&2, Entry, Entry{name, value} <> reversed)

def replace(tuples: List<&2, Entry>, +name: String, +value: String, state: SetState) -> List<&2, Entry>:
  match tuples:
    case Nil{}: finishSet(name, value, state)
    case +entry <> rest: replace(rest, name, value, setStep(matches(entry, name, None{}), entry, name, value, state))

# Retain the first matching position, remove its later duplicates; append a
# missing name. One pass over the immutable tuple list performs the update.
def set(params: URLSearchParams, name: String, value: String) -> URLSearchParams:
  URLSearchParams{replace(entries(params), scalarForm(name), scalarForm(value), SetState{False{}, Nil{}})}

type SortEntry is Data:
  SortEntry{units: List<&2, U32>, entry: Entry}

def scalarUnits(+scalar: U32, +rest: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_ge(scalar, 65536), (55296 + (scalar - 65536) / 1024 : U32) <> (56320 + (scalar - 65536) % 1024 : U32) <> rest, scalar <> rest)

def utf16Units(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{scalar}, rest}: scalarUnits(scalar, utf16Units(rest))

def sortKey(entry: Entry) -> SortEntry:
  match entry:
    case Entry{+name, value}: SortEntry{utf16Units(name), Entry{name, value}}

def keyed(tuples: List<&2, Entry>) -> List<&2, SortEntry>:
  match tuples:
    case Nil{}: Nil{}
    case entry <> rest: sortKey(entry) <> keyed(rest)

def lessEqual(left: List<&2, U32>, right: List<&2, U32>) -> Bool:
  match left right:
    case Nil{} _: True{}
    case _ Nil{}: False{}
    case +a <> left +b <> right: U32.is_lt(a, b) || (U32.is_eq(a, b) && lessEqual(left, right))

def before(left: SortEntry, right: SortEntry) -> Bool:
  match left right:
    case SortEntry{a, _} SortEntry{b, _}: lessEqual(a, b)

def unkeyed(tuples: List<&2, SortEntry>) -> List<&2, Entry>:
  match tuples:
    case Nil{}: Nil{}
    case SortEntry{_, entry} <> rest: entry <> unkeyed(rest)

# The URL wire standard specifies stable UTF-16 name ordering. Cache each key
# once and use Base's stable merge sort; values never decide tie order.
def sort(params: URLSearchParams) -> URLSearchParams:
  URLSearchParams{unkeyed(List.sort(~SortEntry, ~before, keyed(entries(params))))}


# Append to reversed output with constant machine-stack use. Components are
# already encoded by the parser; serialization must not encode '%' a second time.
def appendSerialize(text: String, reversed: String) -> String:
  match text:
    case SNil{}: reversed
    case SCon{char, rest}: appendSerialize(rest, SCon{char, reversed})

def serializeSegments(parts: List<&2, String>, reversed: String) -> String:
  match parts:
    case Nil{}: reversed
    case head <> rest: serializeSegments(rest, appendSerialize(head, SCon{'/', reversed}))

def pathOutput(recordPath: RecordPath, reversed: String) -> String:
  match recordPath:
    case Hierarchical{parts}: serializeSegments(parts, reversed)
    case RecordOpaque{value}: appendSerialize(value, reversed)

def serializePath(recordPath: RecordPath) -> String:
  String.reverse(pathOutput(recordPath, ""))

# Prevent a hostless path beginning '//' from reparsing as an authority.
def hostless(recordPath: RecordPath, reversed: String) -> String:
  match recordPath:
    case Hierarchical{SNil{} <> next <> rest}: serializeSegments("" <> next <> rest, appendSerialize("/.", reversed))
    case other: pathOutput(other, reversed)

def serializeCredentials(username: String, password: String, reversed: String) -> String:
  match username password:
    case SNil{} SNil{}: reversed
    case user SNil{}: SCon{'@', appendSerialize(user, reversed)}
    case user pass: SCon{'@', appendSerialize(pass, SCon{':', appendSerialize(user, reversed)})}

def serializePort(value: Maybe<&2, U32>, reversed: String) -> String:
  match value:
    case None{}: reversed
    case Some{number}: appendSerialize(U32.show(number), SCon{':', reversed})

def body(host: Maybe<&2, Host>, recordPath: RecordPath, username: String, password: String, number: Maybe<&2, U32>, reversed: String) -> String:
  match host:
    case None{}: hostless(recordPath, reversed)
    case Some{value}: pathOutput(recordPath, serializePort(number, appendSerialize(serializeHost(value), serializeCredentials(username, password, appendSerialize("//", reversed)))))

def component(value: Maybe<&2, String>, delimiter: Char, reversed: String) -> String:
  match value:
    case None{}: reversed
    case Some{value}: appendSerialize(value, SCon{delimiter, reversed})

def serializeFragment(exclude: Bool, value: Maybe<&2, String>, reversed: String) -> String:
  match exclude:
    case True{}: reversed
    case False{}: component(value, '#', reversed)

def suffix(reversed: String, query: Maybe<&2, String>, hash: Maybe<&2, String>, excludeFragment: Bool) -> String:
  String.reverse(serializeFragment(excludeFragment, hash, component(query, '?', reversed)))

def serialize(value: URL, excludeFragment: Bool) -> String:
  match value:
    case URL{scheme, username, password, host, number, urlPath, query, hash}: suffix(body(host, urlPath, username, password, number, SCon{':', appendSerialize(serializeScheme(scheme), "")}), query, hash, excludeFragment)


type SpecialHostError is Data:
  Preparation{reason: HostError}
  SpecialHostDomain{reason: IDNA.DomainError}
  Classification{reason: HostError}

def classifiedSpecialHost(result: Result<&2, &2, HostError, Host>) -> Result<&2, &2, SpecialHostError, Host>:
  match result:
    case Fail{reason}: Fail{Classification{reason}}
    case Done{host}: Done{host}

def domain(result: Result<&2, &2, IDNA.DomainError, String>) -> Result<&2, &2, SpecialHostError, Host>:
  match result:
    case Fail{reason}: Fail{SpecialHostDomain{reason}}
    case Done{text}: classifiedSpecialHost(classifyDomain(text))

def prepared(result: Result<&2, &2, HostError, Prepared>, context: IDNA.Context, options: IDNA.Options) -> Result<&2, &2, SpecialHostError, Host>:
  match result:
    case Fail{reason}: Fail{Preparation{reason}}
    case Done{Literal{host}}: Done{host}
    case Done{DomainInput{text}}: domain(IDNA.toASCII(context, options, text))

# Compose the full special-host pipeline on a delimited token. IPv6 dispatch
# precedes percent decoding; numeric-host detection follows Unicode mapping.
# Callers explicitly supply IDNA policy and reusable immutable Unicode tables.
# No default Node/Unicode joiner-compatibility decision is made by this module.
def parseSpecialHost(context: IDNA.Context, options: IDNA.Options, input: String) -> Result<&2, &2, SpecialHostError, Host>:
  prepared(prepare(input), context, options)


type Context is Data:
  Context{unicode: IDNA.Context, idna: IDNA.Options}

type Error is Data:
  MissingScheme{}
  MissingHost{}
  InvalidSpecialHost{reason: SpecialHostError}
  InvalidOpaqueHost{reason: HostError}
  InvalidPort{reason: PortError}

def hierarchical(scheme: Scheme, username: String, password: String, host: Maybe<&2, Host>, port: Maybe<&2, U32>, parsed: PathParsed) -> URL:
  match parsed:
    case PathParsed{segments, query, fragment}: URL{scheme, username, password, host, port, Hierarchical{segments}, query, fragment}

def opaque(scheme: Scheme, parsed: Parsed) -> URL:
  match parsed:
    case Parsed{value, query, fragment}: URL{scheme, "", "", None{}, None{}, RecordOpaque{value}, query, fragment}

def credentials(value: Maybe<&2, Credentials>) -> Credentials:
  match value:
    case None{}: Credentials{"", ""}
    case Some{result}: result

def authorityURL(+scheme: Scheme, user: Credentials, host: Host, port: Maybe<&2, U32>, remainder: String) -> URL:
  match user:
    case Credentials{username, password}: hierarchical(scheme, username, password, Some{host}, port, startPath(remainder, scheme, Nil{}))

def portResult(result: Result<&2, &2, PortError, Maybe<&2, U32>>, scheme: Scheme, user: Credentials, host: Host, remainder: String) -> Result<&2, &2, Error, URL>:
  match result:
    case Fail{reason}: Fail{InvalidPort{reason}}
    case Done{value}: Done{authorityURL(scheme, user, host, value, remainder)}

def parsedPort(value: Maybe<&2, String>, scheme: Scheme) -> Result<&2, &2, PortError, Maybe<&2, U32>>:
  match value:
    case None{}: Done{None{}}
    case Some{text}: parsePort(defaultPort(scheme), text)

def specialResult(result: Result<&2, &2, SpecialHostError, Host>) -> Result<&2, &2, Error, Host>:
  match result:
    case Fail{reason}: Fail{InvalidSpecialHost{reason}}
    case Done{value}: Done{value}

def opaqueResult(result: Result<&2, &2, HostError, Host>) -> Result<&2, &2, Error, Host>:
  match result:
    case Fail{reason}: Fail{InvalidOpaqueHost{reason}}
    case Done{value}: Done{value}

def absoluteHost(special: Bool, context: Context, input: String) -> Result<&2, &2, Error, Host>:
  match special context:
    case True{} Context{unicode, options}: specialResult(parseSpecialHost(unicode, options, input))
    case False{} _: opaqueResult(parseOpaque(input))

def hostResult(result: Result<&2, &2, Error, Host>, +scheme: Scheme, user: Maybe<&2, Credentials>, port: Maybe<&2, String>, remainder: String) -> Result<&2, &2, Error, URL>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{value}: portResult(parsedPort(port, scheme), scheme, credentials(user), value, remainder)

def checkedAuthority(missing: Bool, context: Context, +scheme: Scheme, text: String, user: Maybe<&2, Credentials>, port: Maybe<&2, String>, remainder: String) -> Result<&2, &2, Error, URL>:
  match missing:
    case True{}: Fail{MissingHost{}}
    case False{}: hostResult(absoluteHost(isSpecialScheme(scheme), context, text), scheme, user, port, remainder)

def absoluteAuthority(context: Context, +scheme: Scheme, prefix: Prefix) -> Result<&2, &2, Error, URL>:
  match prefix:
    case Prefix{Tokens{+user, +text, +port}, remainder}: checkedAuthority(String.is_empty(text) && (isSpecialScheme(scheme) || Maybe.is_some(&2, Credentials, user) || Maybe.is_some(&2, String, port)), context, scheme, text, user, port, remainder)

def slashes(text: String) -> String:
  match text:
    case SCon{'/', rest}: slashes(rest)
    case SCon{'\\', rest}: slashes(rest)
    case other: other

def localHost(local: Bool, value: Host) -> Host:
  match local:
    case True{}: Empty{}
    case False{}: value

def fileHost(value: Host) -> Host:
  match value:
    case Domain{+name}: localHost(String.eq(name, "localhost"), Domain{name})
    case other: other

def fileResult(result: Result<&2, &2, Error, Host>, remainder: String) -> Result<&2, &2, Error, URL>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{value}: Done{hierarchical(File{}, "", "", Some{fileHost(value)}, None{}, startPath(remainder, File{}, Nil{}))}

def fileDomain(context: Context, text: String) -> Result<&2, &2, Error, Host>:
  match text:
    case SNil{}: Done{Empty{}}
    case other: absoluteHost(True{}, context, other)

def fileAuthorityDrive(drive: Bool, context: Context, text: String, remainder: String) -> Result<&2, &2, Error, URL>:
  match drive:
    case True{}: Done{hierarchical(File{}, "", "", Some{Empty{}}, None{}, parsePath(text ++ remainder, File{}, Nil{}))}
    case False{}: fileResult(fileDomain(context, text), remainder)

def fileAuthority(context: Context, prefix: RawPrefix) -> Result<&2, &2, Error, URL>:
  match prefix:
    case RawPrefix{+text, remainder}: fileAuthorityDrive(drive(text), context, text, remainder)

# The first file slash has been consumed. Either kind of second slash enters
# the file-host state; a single slash enters the path state with an empty host.
def fileSlash(context: Context, text: String) -> Result<&2, &2, Error, URL>:
  match text:
    case SCon{'/', rest}: fileAuthority(context, rawAuthority(rest, True{}))
    case SCon{'\\', rest}: fileAuthority(context, rawAuthority(rest, True{}))
    case other: Done{hierarchical(File{}, "", "", Some{Empty{}}, None{}, parsePath(other, File{}, Nil{}))}

def file(context: Context, text: String) -> Result<&2, &2, Error, URL>:
  match text:
    case SCon{'/', rest}: fileSlash(context, rest)
    case SCon{'\\', rest}: fileSlash(context, rest)
    case other: Done{hierarchical(File{}, "", "", Some{Empty{}}, None{}, parsePath(other, File{}, Nil{}))}

# Non-special schemes only recognize forward slashes as authority delimiters.
def otherSlash(context: Context, +scheme: Scheme, text: String) -> Result<&2, &2, Error, URL>:
  match text:
    case SCon{'/', rest}: absoluteAuthority(context, scheme, read(rest, False{}))
    case other: Done{hierarchical(scheme, "", "", None{}, None{}, parsePath(other, scheme, Nil{}))}

def absoluteOther(context: Context, +scheme: Scheme, text: String) -> Result<&2, &2, Error, URL>:
  match text:
    case SCon{'/', rest}: otherSlash(context, scheme, rest)
    case remainder: Done{opaque(scheme, parseOpaquePath(remainder))}

def nonFile(special: Bool, context: Context, scheme: Scheme, text: String) -> Result<&2, &2, Error, URL>:
  match special:
    case True{}: absoluteAuthority(context, scheme, read(slashes(text), True{}))
    case False{}: absoluteOther(context, scheme, text)

def absoluteScheme(context: Context, value: Scheme, text: String) -> Result<&2, &2, Error, URL>:
  match value:
    case File{}: file(context, text)
    case +otherScheme: nonFile(isSpecialScheme(otherScheme), context, otherScheme, text)

def prefixed(context: Context, prefix: InputPrefix) -> Result<&2, &2, Error, URL>:
  match prefix:
    case Relative{_}: Fail{MissingScheme{}}
    case Absolute{value, remainder}: absoluteScheme(context, value, remainder)

# Absolute parsing has no base URL. Relative resolution is a separate entry
# that will share these states. Domain policy remains explicit in Context.
def parse(context: Context, input: String) -> Result<&2, &2, Error, URL>:
  prefixed(context, inputPrefix(prepareInput(input)))


type ResolveError is Data:
  InvalidURL{reason: Error}
  OpaqueBase{}

def absoluteResult(result: Result<&2, &2, Error, URL>) -> Result<&2, &2, ResolveError, URL>:
  match result:
    case Fail{reason}: Fail{InvalidURL{reason}}
    case Done{value}: Done{value}

# Inheritance copies immutable normalized components. Every reference replaces
# the fragment, including an empty reference (which removes it).
def resolveFragment(base: URL, value: Maybe<&2, String>) -> URL:
  match base:
    case URL{scheme, user, password, host, port, urlPath, queryResolve, _}: URL{scheme, user, password, host, port, urlPath, queryResolve, value}

def queryResolve(base: URL, parsed: QueryParsed) -> URL:
  match base parsed:
    case URL{scheme, user, password, host, port, urlPath, _, _} QueryParsed{value, hash}: URL{scheme, user, password, host, port, urlPath, Some{value}, hash}

def path(base: URL, parsed: PathParsed) -> URL:
  match base:
    case URL{scheme, user, password, host, port, _, _, _}: hierarchical(scheme, user, password, host, port, parsed)

def baseScheme(base: URL) -> Scheme:
  match base:
    case URL{value, _, _, _, _, _, _, _}: value

def baseSegments(base: URL) -> List<&2, String>:
  match base:
    case URL{_, _, _, _, _, Hierarchical{values}, _, _}: values
    case _: Nil{}

def driveBoundary(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code}, _}: U32.is_eq(code, 47) || U32.is_eq(code, 92) || U32.is_eq(code, 63) || U32.is_eq(code, 35)

# This is a drive prefix only at a path-component boundary. C:foo is not one.
def startsDrive(text: String) -> Bool:
  match text:
    case SCon{Chr{letter}, SCon{Chr{+separator}, rest}}: alpha(letter) && (U32.is_eq(separator, 58) || U32.is_eq(separator, 124)) && driveBoundary(rest)
    case _: False{}

def baseDrive(values: List<&2, String>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case +first <> _: retainedDrive(normalizedDrive(first), first)

def rootSegments(file: Bool, newDrive: Bool, base: URL) -> List<&2, String>:
  match file newDrive:
    case True{} False{}: baseDrive(baseSegments(base))
    case _ _: Nil{}

def root(+base: URL, +input: String) -> URL:
  path(base, parsePath(input, baseScheme(base), rootSegments(isFilePath(baseScheme(base)), startsDrive(input), base)))

def relativeSegments(newDrive: Bool, file: Bool, base: URL) -> List<&2, String>:
  match newDrive file:
    case True{} True{}: Nil{}
    case _ isFile: List.reverse(&2, String, shorten(List.reverse(&2, String, baseSegments(base)), isFile))

def relativePath(+base: URL, +input: String) -> URL:
  path(base, parsePath(input, baseScheme(base), relativeSegments(startsDrive(input), isFilePath(baseScheme(base)), base)))

def network(context: Context, value: Scheme, input: String) -> Result<&2, &2, ResolveError, URL>:
  match value:
    case File{}: absoluteResult(fileAuthority(context, rawAuthority(input, True{})))
    case +other: absoluteResult(nonFile(isSpecialScheme(other), context, other, "//" ++ input))

# The first slash has already been consumed. Special schemes also treat a
# backslash as a slash; custom schemes preserve it as a path character.
def slash(context: Context, +base: URL, input: String, special: Bool) -> Result<&2, &2, ResolveError, URL>:
  match input special:
    case SCon{'/', rest} _: network(context, baseScheme(base), rest)
    case SCon{'\\', rest} True{}: network(context, baseScheme(base), rest)
    case rest _: Done{root(base, rest)}

def hierarchicalResolve(context: Context, +base: URL, input: String, special: Bool) -> Result<&2, &2, ResolveError, URL>:
  match input special:
    case SNil{} _: Done{resolveFragment(base, None{})}
    case SCon{'?', rest} isSpecial: Done{queryResolve(base, parseQuery(rest, isSpecial))}
    case SCon{'#', rest} _: Done{resolveFragment(base, Some{encode(Fragment{}, rest)})}
    case SCon{'/', rest} isSpecial: slash(context, base, rest, isSpecial)
    case SCon{'\\', rest} True{}: slash(context, base, rest, True{})
    case rest _: Done{relativePath(base, rest)}

def opaqueResolve(base: URL, input: String) -> Result<&2, &2, ResolveError, URL>:
  match input:
    case SCon{'#', rest}: Done{resolveFragment(base, Some{encode(Fragment{}, rest)})}
    case _: Fail{OpaqueBase{}}

def relative(context: Context, +base: URL, input: String) -> Result<&2, &2, ResolveError, URL>:
  match base:
    case URL{_, _, _, _, _, RecordOpaque{_}, _, _}: opaqueResolve(base, input)
    case _: hierarchicalResolve(context, base, input, isSpecialScheme(baseScheme(base)))

def absoluteOrRelative(sameSpecial: Bool, context: Context, base: URL, value: Scheme, input: String) -> Result<&2, &2, ResolveError, URL>:
  match sameSpecial:
    case True{}: relative(context, base, input)
    case False{}: absoluteResult(absoluteScheme(context, value, input))

def prefixedResolve(context: Context, +base: URL, prefix: InputPrefix) -> Result<&2, &2, ResolveError, URL>:
  match prefix:
    case Relative{input}: relative(context, base, input)
    case Absolute{+value, input}: absoluteOrRelative(isSpecialScheme(value) && String.eq(serializeScheme(value), serializeScheme(baseScheme(base))), context, base, value, input)

# Constructor resolution against an already parsed base. Domain policy remains
# explicit in the same Context as absolute parsing; no host-language URL code.
def parseResolve(context: Context, base: URL, input: String) -> Result<&2, &2, ResolveError, URL>:
  prefixedResolve(context, base, inputPrefix(prepareInput(input)))


# WHATWG URL getters for the components a caller reads from a parsed URL
# (Node's url.protocol, .hostname, .pathname, .hash, .href).
def protocol(value: URL) -> String:
  match value:
    case URL{scheme, _, _, _, _, _, _, _}: serializeScheme(scheme) ++ ":"

def usernameOf(value: URL) -> String:
  match value:
    case URL{_, username, _, _, _, _, _, _}: username

def passwordOf(value: URL) -> String:
  match value:
    case URL{_, _, password, _, _, _, _, _}: password

def hostname(value: URL) -> String:
  match value:
    case URL{_, _, _, Some{host}, _, _, _, _}: serializeHost(host)
    case _: ""

def pathname(value: URL) -> String:
  match value:
    case URL{_, _, _, _, _, recordPath, _, _}: serializePath(recordPath)

def hash(value: URL) -> String:
  match value:
    case URL{_, _, _, _, _, _, _, Some{SNil{}}}: ""
    case URL{_, _, _, _, _, _, _, Some{fragment}}: "#" ++ fragment
    case _: ""

def href(value: URL) -> String: serialize(value, False{})

# The pathname setter: the path state with a state override, where '?' and
# '#' are path code points (percent-encoded) rather than delimiters, and tab
# and newline are removed as in every basic URL parse. An opaque path is
# unchanged.
def setterInput(text: String, reversed: String) -> String:
  match text:
    case SNil{}: String.reverse(reversed)
    case SCon{'\t', rest}: setterInput(rest, reversed)
    case SCon{'\n', rest}: setterInput(rest, reversed)
    case SCon{'\r', rest}: setterInput(rest, reversed)
    case SCon{'?', rest}: setterInput(rest, SCon{'F', SCon{'3', SCon{'%', reversed}}})
    case SCon{'#', rest}: setterInput(rest, SCon{'3', SCon{'2', SCon{'%', reversed}}})
    case SCon{char, rest}: setterInput(rest, SCon{char, reversed})

def segmentsOf(parsed: PathParsed) -> List<&2, String>:
  match parsed:
    case PathParsed{segments, _, _}: segments

def setterSegments(special: Bool, file: Bool, hostless: Bool, text: String) -> List<&2, String>:
  match special text:
    case True{} other: segmentsOf(startSpecial(other, file, Nil{}))
    case False{} SNil{}: Bool.pick(List<&2, String>, hostless, "" <> Nil{}, Nil{})
    case False{} SCon{'/', rest}: segmentsOf(scanPath(rest, False{}, False{}, "", Nil{}))
    case False{} other: segmentsOf(scanPath(other, False{}, False{}, "", Nil{}))

def setPathname(value: URL, text: String) -> URL:
  match value:
    case URL{scheme, username, password, host, port, RecordOpaque{opaquePath}, query, fragment}: URL{scheme, username, password, host, port, RecordOpaque{opaquePath}, query, fragment}
    case URL{+scheme, username, password, +host, port, Hierarchical{_}, query, fragment}:
      URL{scheme, username, password, host, port, Hierarchical{setterSegments(isSpecialScheme(scheme), isFilePath(scheme), Maybe.is_none(&2, Host, host), setterInput(text, ""))}, query, fragment}
