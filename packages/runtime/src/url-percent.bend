import Base
import ./utf8.bend as Utf8
import ./uri-component.bend as Uri

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

def control(+byte: U32) -> Bool: U32.is_lt(byte, 32) || U32.is_gt(byte, 126)
def queryExtra(+byte: U32) -> Bool: U32.is_eq(byte, 32) || U32.is_eq(byte, 34) || U32.is_eq(byte, 35) || U32.is_eq(byte, 60) || U32.is_eq(byte, 62)
def pathExtra(+byte: U32) -> Bool: U32.is_eq(byte, 63) || U32.is_eq(byte, 94) || U32.is_eq(byte, 96) || U32.is_eq(byte, 123) || U32.is_eq(byte, 125)
def userExtra(+byte: U32) -> Bool: U32.is_eq(byte, 47) || U32.is_eq(byte, 58) || U32.is_eq(byte, 59) || U32.is_eq(byte, 61) || U32.is_eq(byte, 64) || (U32.is_ge(byte, 91) && U32.is_le(byte, 93)) || U32.is_eq(byte, 124)
def componentExtra(+byte: U32) -> Bool: (U32.is_ge(byte, 36) && U32.is_le(byte, 38)) || U32.is_eq(byte, 43) || U32.is_eq(byte, 44)
def formExtra(+byte: U32) -> Bool: U32.is_eq(byte, 33) || (U32.is_ge(byte, 39) && U32.is_le(byte, 41)) || U32.is_eq(byte, 126)

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

def hexDigit(+nibble: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(nibble, 10), (48 + nibble : U32), (55 + nibble : U32))}

def emit(plus: Bool, escape: Bool, +byte: U32, reversed: String) -> String:
  match plus escape:
    case True{} _: SCon{'+', reversed}
    case False{} True{}: SCon{hexDigit((byte % 16 : U32)), SCon{hexDigit((byte / 16 : U32)), SCon{'%', reversed}}}
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

def finish(state: Decoder) -> List<&2, U32>:
  match state:
    case Ready{reversed}: List.reverse(&2, U32, reversed)
    case Percent{reversed}: List.reverse(&2, U32, 37 <> reversed)
    case High{raw, _, reversed}: List.reverse(&2, U32, raw <> 37 <> reversed)

def decodeLoop(bytes: List<&2, U32>, state: Decoder) -> List<&2, U32>:
  match bytes:
    case Nil{}: finish(state)
    case byte <> rest: decodeLoop(rest, advance(state, byte))

def decode(bytes: List<&2, U32>) -> List<&2, U32>:
  decodeLoop(bytes, Ready{Nil{}})
