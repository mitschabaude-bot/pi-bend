import Base
import ./string-split.bend as Split
import ./uri-component.bend as Uri

# Four 32-bit words in network order. Every value is a valid 128-bit address.
type Address is Data:
  Address{a: U32, b: U32, c: U32, d: U32}

type AddressError is Data:
  InvalidPiece{}
  InvalidCompression{}
  InvalidEmbeddedIPv4{}
  WrongPieceCount{}

def words(address: Address) -> List<&2, U32>:
  match address:
    case Address{+a, +b, +c, +d}: (a / 65536 : U32) <> (a % 65536 : U32) <> (b / 65536 : U32) <> (b % 65536 : U32) <> (c / 65536 : U32) <> (c % 65536 : U32) <> (d / 65536 : U32) <> (d % 65536 : U32) <> Nil{}

def address(parts: List<&2, U32>) -> Result<&2, &2, AddressError, Address>:
  match parts:
    case a <> b <> c <> d <> e <> f <> g <> h <> Nil{}: Done{Address{(a * 65536 + b : U32), (c * 65536 + d : U32), (e * 65536 + f : U32), (g * 65536 + h : U32)}}
    case _: Fail{WrongPieceCount{}}

# Bounded digit accumulation is shared by hex pieces and decimal IPv4 octets.
def digitValue(digit: Maybe<&2, U32>, +radix: U32, value: U32) -> Maybe<&2, U32>:
  match digit:
    case None{}: None{}
    case Some{+digit}: Bool.pick(Maybe<&2, U32>, U32.is_lt(digit, radix), Some{(value * radix + digit : U32)}, None{})

def digits(text: String, +radix: U32, left: U32, value: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match text left value:
    case _ _ None{}: None{}
    case SNil{} _ result: result
    case _ 0 _: None{}
    case SCon{Chr{code}, rest} remaining Some{value}: digits(rest, radix, (remaining - 1 : U32), digitValue(Uri.hex(code), radix, value))

def hexPiece(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case other: digits(other, 16, 4, Some{0})

def octetValue(value: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match value:
    case None{}: None{}
    case Some{+value}: Bool.pick(Maybe<&2, U32>, U32.is_le(value, 255), Some{value}, None{})

def octet(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case SCon{'0', SNil{}}: Some{0}
    case SCon{'0', _}: None{}
    case other: octetValue(digits(other, 10, 3, Some{0}))

def embeddedValues(a: Maybe<&2, U32>, b: Maybe<&2, U32>, c: Maybe<&2, U32>, d: Maybe<&2, U32>) -> Result<&2, &2, AddressError, List<&2, U32>>:
  match a b c d:
    case Some{a} Some{b} Some{c} Some{d}: Done{(a * 256 + b : U32) <> (c * 256 + d : U32) <> Nil{}}
    case _ _ _ _: Fail{InvalidEmbeddedIPv4{}}

def embedded(parts: List<&2, String>) -> Result<&2, &2, AddressError, List<&2, U32>>:
  match parts:
    case a <> b <> c <> d <> Nil{}: embeddedValues(octet(a), octet(b), octet(c), octet(d))
    case _: Fail{InvalidEmbeddedIPv4{}}

def hasDot(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{'.', _}: True{}
    case SCon{_, rest}: hasDot(rest)

def single(value: Maybe<&2, U32>) -> Result<&2, &2, AddressError, List<&2, U32>>:
  match value:
    case None{}: Fail{InvalidPiece{}}
    case Some{value}: Done{value <> Nil{}}

def piece(dotted: Bool, final: Bool, text: String) -> Result<&2, &2, AddressError, List<&2, U32>>:
  match dotted final:
    case True{} True{}: embedded(Split.split(text, '.'))
    case True{} False{}: Fail{InvalidEmbeddedIPv4{}}
    case False{} _: single(hexPiece(text))

# Remove only the boundary empty token belonging to a double colon. Interior
# empty tokens are compression markers; a lone boundary colon is an error.
def trimEnd(reversed: List<&2, String>) -> Result<&2, &2, AddressError, List<&2, String>>:
  match reversed:
    case SNil{} <> SNil{} <> rest: Done{List.reverse(&2, String, SNil{} <> rest)}
    case SNil{} <> _ <> _: Fail{InvalidCompression{}}
    case other: Done{List.reverse(&2, String, other)}

def tokens(parts: List<&2, String>) -> Result<&2, &2, AddressError, List<&2, String>>:
  match parts:
    case SNil{} <> SNil{} <> third <> rest: trimEnd(List.reverse(&2, String, SNil{} <> third <> rest))
    case SNil{} <> _: Fail{InvalidCompression{}}
    case other: trimEnd(List.reverse(&2, String, other))

type State is Data:
  State{count: U32, reversed: List<&2, U32>, compression: Maybe<&2, U32>}

def markCompression(state: State) -> Result<&2, &2, AddressError, State>:
  match state:
    case State{+count, reversed, None{}}: Done{State{count, reversed, Some{count}}}
    case _: Fail{InvalidCompression{}}

def appendWords(parts: List<&2, U32>, state: State) -> Result<&2, &2, AddressError, State>:
  match parts state:
    case Nil{} state: Done{state}
    case _ State{8, _, _}: Fail{WrongPieceCount{}}
    case value <> rest State{count, reversed, compression}: appendWords(rest, State{(count + 1 : U32), value <> reversed, compression})

def appendResult(result: Result<&2, &2, AddressError, List<&2, U32>>, state: State) -> Result<&2, &2, AddressError, State>:
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

def finish(state: State) -> Result<&2, &2, AddressError, Address>:
  match state:
    case State{8, reversed, None{}}: address(List.reverse(&2, U32, reversed))
    case State{8, _, Some{_}}: Fail{InvalidCompression{}}
    case State{count, reversed, Some{index}}: address(expand(List.reverse(&2, U32, reversed), index, (8 - count : U32)))
    case _: Fail{WrongPieceCount{}}

def empty(parts: List<&2, String>) -> Bool:
  match parts:
    case Nil{}: True{}
    case _: False{}

def scan(parts: List<&2, String>, state: Result<&2, &2, AddressError, State>) -> Result<&2, &2, AddressError, Address>:
  match parts state:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{state}: finish(state)
    case SNil{} <> rest Done{state}: scan(rest, markCompression(state))
    case +text <> +rest Done{state}: scan(rest, appendResult(piece(hasDot(text), empty(rest), text), state))

def parsedTokens(result: Result<&2, &2, AddressError, List<&2, String>>) -> Result<&2, &2, AddressError, Address>:
  match result:
    case Fail{error}: Fail{error}
    case Done{parts}: scan(parts, Done{State{0, Nil{}, None{}}})

# Input excludes URL host brackets. Zone identifiers are not URL IPv6 syntax.
def parse(text: String) -> Result<&2, &2, AddressError, Address>:
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

def serialize(address: Address) -> String:
  +parts = words(address)
  compressed(parts, longest(parts, 0, 0, 0, Run{0, 1}))
