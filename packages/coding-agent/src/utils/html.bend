import Base
import ../../../runtime/src/ecma-regex.bend as Re

# HTML entity decoding for highlight.js output (upstream utils/html.ts).
# Numeric references follow Number.parseInt: leading whitespace, a sign, a
# "0x" prefix in base 16, then the longest run of digits; a code point outside
# 0..0x10FFFF (or no digits) is no entity.

type DecodedHtmlEntity is Data: DecodedHtmlEntity{text: String, length: Nat}

def trimmedStart(text: String) -> String:
  match text:
    case SCon{Chr{+code}, +rest}: Bool.pick(Unit -> String, Re.isSpaceCode(code), _ => trimmedStart(rest), _ => SCon{Chr{code}, rest})(Unit{})
    case other: other
# A scalar's digit value in bases up to 36 (99 for a non-digit).
def digitValue(+code: U32) -> U32:
  Bool.pick(U32, U32.is_ge(code, 48) && U32.is_le(code, 57), (code - 48 : U32), Bool.pick(U32, U32.is_ge(code, 97) && U32.is_le(code, 122), (code - 87 : U32), Bool.pick(U32, U32.is_ge(code, 65) && U32.is_le(code, 90), (code - 55 : U32), 99)))
# The value of the leading digits (none without any), saturated just above
# the largest code point.
def digitsFrom(text: String, +radix: U32, +value: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match text:
    case SCon{Chr{code}, rest}:
      +digit = digitValue(code)
      Bool.pick(Unit -> Maybe<&2, Nat>, U32.is_lt(digit, radix), _ => digitsFrom(rest, radix, Some{Nat.min(1114112n, Maybe.default(&2, Nat, value, 0n) * U32.to_nat(radix) + U32.to_nat(digit))}), _ => value)(Unit{})
    case SNil{}: value
type Parsed is Data: Parsed{negative: Bool, value: Maybe<&2, Nat>}
def unprefixed(hex: Bool, text: String) -> String:
  match hex text:
    case True{} SCon{Chr{48}, SCon{Chr{120}, rest}}: rest
    case True{} SCon{Chr{48}, SCon{Chr{88}, rest}}: rest
    case _ other: other
def signed(text: String, hex: Bool, +radix: U32) -> Parsed:
  match text:
    case SCon{Chr{45}, rest}: Parsed{True{}, digitsFrom(unprefixed(hex, rest), radix, None{})}
    case SCon{Chr{43}, rest}: Parsed{False{}, digitsFrom(unprefixed(hex, rest), radix, None{})}
    case other: Parsed{False{}, digitsFrom(unprefixed(hex, other), radix, None{})}
# Strings hold Unicode scalars: a surrogate code point (a lone UTF-16 unit
# in JavaScript) becomes U+FFFD.
def scalarOf(+code: U32) -> U32: Bool.pick(U32, U32.is_ge(code, 55296) && U32.is_le(code, 57343), 65533, code)
def codePointOf(parsed: Parsed) -> Maybe<&2, String>:
  match parsed:
    case Parsed{_, None{}}: None{}
    case Parsed{True{}, Some{Zero{}}}: Some{SCon{Chr{0}, SNil{}}}
    case Parsed{True{}, Some{_}}: None{}
    case Parsed{False{}, Some{+value}}: Bool.pick(Unit -> Maybe<&2, String>, Nat.is_le(value, 1114111n), _ => Some{SCon{Chr{scalarOf(U32.from_nat(value))}, SNil{}}}, _ => None{})(Unit{})
def decodeHtmlEntity(entity: String) -> Maybe<&2, String>:
  match entity:
    case "amp": Some{"&"}
    case "lt": Some{"<"}
    case "gt": Some{">"}
    case "quot": Some{"\""}
    case "apos": Some{"'"}
    case SCon{Chr{35}, SCon{Chr{120}, rest}}: codePointOf(signed(trimmedStart(rest), True{}, 16))
    case SCon{Chr{35}, SCon{Chr{88}, rest}}: codePointOf(signed(trimmedStart(rest), True{}, 16))
    case SCon{Chr{35}, rest}: codePointOf(signed(trimmedStart(rest), False{}, 10))
    case _: None{}

type Entity is Data: Entity{name: String, offset: Nat}
# The entity starting at `html` (at its "&"): up to the first ";", which must
# be at most 16 scalars on. (Upstream takes the html and an index.)
def entityText(text: String, +offset: Nat, reversed: String) -> Maybe<&2, Entity>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{59}, _}: Bool.pick(Maybe<&2, Entity>, Nat.is_le(offset, 16n), Some{Entity{String.reverse(reversed), offset}}, None{})
    case SCon{char, rest}: Bool.pick(Unit -> Maybe<&2, Entity>, Nat.is_ge(offset, 16n), _ => None{}, _ => entityText(rest, offset + 1n, SCon{char, reversed}))(Unit{})
def decodedAt(found: Maybe<&2, Entity>) -> Maybe<&2, DecodedHtmlEntity>:
  match found:
    case None{}: None{}
    case Some{Entity{entity, +offset}}: Maybe.map(&2, String, DecodedHtmlEntity, text => DecodedHtmlEntity{text, offset + 1n}, decodeHtmlEntity(entity))
def decodeHtmlEntityAt(html: String) -> Maybe<&2, DecodedHtmlEntity>:
  match html:
    case SCon{_, rest}: decodedAt(entityText(rest, 1n, ""))
    case SNil{}: None{}
