import Base
import ./schema-value.bend as V
import ./schema.bend as S
import ./f64.bend as F
import ./f64-decimal.bend as Decimal
import ./number-string.bend as Number
import ./big-nat.bend as B

# Builder conversion is a separate policy from pi's plain-JSON coercion. A
# native declaration will choose its policy explicitly, without hidden symbols.
type Primitive is Data:
  ToBoolean{}
  ToNumber{}
  ToInteger{}
  ToString{}
  ToNull{}

type Error is Data:
  NumberFormattingFailed{}

def Converted() -> Data: Result<&2, &2, Error, V.Value>

def booleanText(+text: String) -> Maybe<&2, V.Value>:
  +lower = String.to_lower(text)
  Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "true") || String.eq(text, "1"), Some{V.Boolean{True{}}},
    Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "false") || String.eq(text, "0"), Some{V.Boolean{False{}}}, None{}))

def tryBoolean(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Boolean{False{}}}
    case V.Boolean{value}: Some{V.Boolean{value}}
    case V.Text{text}: booleanText(text)
    case V.Number{+number}:
      Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(0)}), Some{V.Boolean{False{}}}, Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(1)}), Some{V.Boolean{True{}}}, None{}))
    case _: None{}

# TypeBox also accepts decimal bigint-literal strings within the exact integer
# range. Parse that finite grammar directly; no JavaScript bigint is involved.
def literalDigits(text: String, +magnitude: B.BigNat) -> Maybe<&2, B.BigNat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, +rest}:
      Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_eq(code, 110),
        _ => Bool.pick(Maybe<&2, B.BigNat>, String.is_empty(rest), Some{magnitude}, None{}),
        _ => Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_ge(code, 48) && U32.is_le(code, 57),
          _ => literalDigits(rest, B.add(B.multiplyU32(magnitude, 10), B.fromU32((code - 48 : U32)))), _ => None{})(Unit{}))(Unit{})

def unsignedLiteral(text: String) -> Maybe<&2, B.BigNat>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{+code}, +rest}:
      Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_eq(code, 48),
        _ => Bool.pick(Maybe<&2, B.BigNat>, String.eq(rest, "n"), Some{B.zero()}, None{}),
        _ => Bool.pick(Unit -> Maybe<&2, B.BigNat>, U32.is_ge(code, 49) && U32.is_le(code, 57),
          _ => literalDigits(rest, B.fromU32((code - 48 : U32))), _ => None{})(Unit{}))(Unit{})

def safeLiteral(negative: Bool, result: Maybe<&2, B.BigNat>) -> Maybe<&2, V.Value>:
  match result:
    case None{}: None{}
    case Some{+magnitude}:
      limit = {B.BigNat{65535 <> 65535 <> 65535 <> 31 <> Nil{}} : B.BigNat}
      prefix = Bool.pick(String, negative && Bool.not(B.isZero(magnitude)), "-", "")
      Bool.pick(Unit -> Maybe<&2, V.Value>, Cmp.is_le(B.compare(magnitude, limit)),
        _ => Some{V.Number{Number.toNumber(prefix ++ B.toDecimal(magnitude))}}, _ => None{})(Unit{})

def bigintLiteral(text: String) -> Maybe<&2, V.Value>:
  match text:
    case SCon{Chr{45}, rest}: safeLiteral(True{}, unsignedLiteral(rest))
    case other: safeLiteral(False{}, unsignedLiteral(other))

def booleanNumber(result: Maybe<&2, V.Value>, fallback: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match result:
    case Some{V.Boolean{flag}}: Some{V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}}
    case _: fallback

def parsedNumber(finite: Bool, parsed: F.F64, +text: String) -> Maybe<&2, V.Value>:
  match finite:
    case True{}: Some{V.Number{parsed}}
    case False{}: booleanNumber(booleanText(text), bigintLiteral(text))

def tryNumber(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Number{F.fromU32(0)}}
    case V.Boolean{flag}: Some{V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}}
    case V.Number{+number}: Bool.pick(Maybe<&2, V.Value>, S.finite(F.decode(number)), Some{V.Number{number}}, None{})
    case V.Text{+text}:
      +parsed = Number.toNumber(text)
      parsedNumber(S.finite(F.decode(parsed)), parsed, text)
    case _: None{}

def tryNull(value: V.Value) -> Maybe<&2, V.Value>:
  match value:
    case V.Null{}: Some{V.Null{}}
    case V.Boolean{flag}: Bool.pick(Maybe<&2, V.Value>, flag, None{}, Some{V.Null{}})
    case V.Number{number}: Bool.pick(Maybe<&2, V.Value>, V.equal(V.Number{number}, V.Number{F.fromU32(0)}), Some{V.Null{}}, None{})
    case V.Text{+text}:
      +lower = String.to_lower(text)
      Bool.pick(Maybe<&2, V.Value>, String.eq(lower, "null") || String.eq(lower, "undefined") || String.eq(text, "") || String.eq(text, "0"), Some{V.Null{}}, None{})
    case _: None{}

def convertedOrOriginal(original: V.Value, converted: Maybe<&2, V.Value>) -> Converted():
  match converted:
    case None{}: Done{original}
    case Some{value}: Done{value}

def integerResult(value: Maybe<&2, V.Value>) -> Maybe<&2, V.Value>:
  match value:
    case Some{V.Number{number}}: Some{V.Number{F.truncate(number)}}
    case other: other

def formattedNumber(text: Maybe<&2, String>) -> Converted():
  match text:
    case Some{text}: Done{V.Text{text}}
    case None{}: Fail{NumberFormattingFailed{}}

def convertString(value: V.Value) -> Converted():
  match value:
    case V.Null{}: Done{V.Text{"null"}}
    case V.Boolean{flag}: Done{V.Text{Bool.pick(String, flag, "true", "false")}}
    case V.Number{number}: formattedNumber(Decimal.toDecimal(number))
    case other: Done{other}

def convert(primitive: Primitive, +value: V.Value) -> Converted():
  match primitive:
    case ToBoolean{}: convertedOrOriginal(value, tryBoolean(value))
    case ToNumber{}: convertedOrOriginal(value, tryNumber(value))
    case ToInteger{}: convertedOrOriginal(value, integerResult(tryNumber(value)))
    case ToString{}: convertString(value)
    case ToNull{}: convertedOrOriginal(value, tryNull(value))
