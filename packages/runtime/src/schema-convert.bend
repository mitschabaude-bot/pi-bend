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
  InvalidConversionState{}

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

# JSON-compatible literals have an explicit conversion kind. Bigint literals
# are outside JSON tool arguments; there is no host-language bigint value here.
type LiteralValue is Data:
  BooleanLiteral{value: Bool}
  NumberLiteral{value: F.F64}
  StringLiteral{value: String}

def literalValue(literal: LiteralValue) -> V.Value:
  match literal:
    case BooleanLiteral{value}: V.Boolean{value}
    case NumberLiteral{value}: V.Number{value}
    case StringLiteral{value}: V.Text{value}

def literalPrimitive(literal: LiteralValue) -> Primitive:
  match literal:
    case BooleanLiteral{_}: ToBoolean{}
    case NumberLiteral{_}: ToNumber{}
    case StringLiteral{_}: ToString{}

def selectLiteral(+expected: V.Value, +original: V.Value, result: Converted()) -> Converted():
  match result:
    case Fail{error}: Fail{error}
    case Done{+candidate}: Done{Bool.pick(V.Value, V.equal(expected, original), original, Bool.pick(V.Value, V.equal(expected, candidate), candidate, original))}

# Each union branch carries its executable constraint alongside its conversion
# policy. Candidates are checked against the complete union, in source order.
type Branch<-P: Data> is Data:
  Branch{schema: S.Schema, policy: P}

# Conversion policy is explicit data, separate from schema validation. Tuple
# conversion does not pad missing positions or drop additional positions.
type Policy is Data:
  Preserve{}
  Literal{value: LiteralValue}
  Union{branches: List<&2, Branch<Policy>>}
  Scalar{primitive: Primitive}
  ArrayItems{item: Policy}
  TupleItems{items: List<&2, Policy>}

type Task is Data:
  Visit{policy: Policy, value: V.Value}
  FinishArray{count: Nat}
  ConvertedValue{result: Converted()}
  TryAlternative{schema: S.Schema, branches: List<&2, Branch<Policy>>, original: V.Value}
  SelectAlternative{schema: S.Schema, remaining: List<&2, Branch<Policy>>, original: V.Value}

def branchSchemas(branches: List<&2, Branch<Policy>>) -> List<&2, S.Schema>:
  match branches:
    case Nil{}: Nil{}
    case Branch{schema, _} <> rest: schema <> branchSchemas(rest)

def scheduleUnion(+branches: List<&2, Branch<Policy>>, +original: V.Value, +rest: List<&2, Task>) -> List<&2, Task>:
  +schema = {S.Any{branchSchemas(branches)} : S.Schema}
  Bool.pick(Unit -> List<&2, Task>, S.check(schema, original),
    _ => Visit{Preserve{}, original} <> rest,
    _ => TryAlternative{schema, branches, original} <> rest)(Unit{})

def arrayTasks(+policy: Policy, values: List<&2, V.Value>) -> List<&2, Task>:
  match values:
    case Nil{}: Nil{}
    case head <> tail: Visit{policy, head} <> arrayTasks(policy, tail)

def tupleTasks(policies: List<&2, Policy>, values: List<&2, V.Value>) -> List<&2, Task>:
  match policies values:
    case _ Nil{}: Nil{}
    case Nil{} head <> tail: Visit{Preserve{}, head} <> tupleTasks(Nil{}, tail)
    case policy <> policies head <> tail: Visit{policy, head} <> tupleTasks(policies, tail)

def arrayInput(value: V.Value) -> List<&2, V.Value>:
  match value:
    case V.ArrayValue{items}: items
    case other: other <> Nil{}

def scheduleArray(policy: Policy, +items: List<&2, V.Value>, rest: List<&2, Task>) -> List<&2, Task>:
  List.append(&2, Task, arrayTasks(policy, items), FinishArray{List.length(&2, V.Value, items)} <> rest)

def scheduleTuple(policies: List<&2, Policy>, value: V.Value, rest: List<&2, Task>) -> List<&2, Task>:
  match value:
    case V.ArrayValue{+items}: List.append(&2, Task, tupleTasks(policies, items), FinishArray{List.length(&2, V.Value, items)} <> rest)
    case other: Visit{Preserve{}, other} <> rest

# Child results arrive in reverse traversal order. Reassemble their original
# order without changing any input value or exposing intermediate mutations.
def finishArray(count: Nat, values: List<&2, V.Value>, items: List<&2, V.Value>) -> List<&2, V.Value>:
  match count values:
    case Zero{} rest: V.ArrayValue{items} <> rest
    case Succ{count} head <> tail: finishArray(count, tail, head <> items)
    case Succ{_} Nil{}: Nil{}

# Visits consume finite policy/value nodes; alternatives consume a finite
# branch list, always retrying the original value. FinishArray consumes its
# completed children. The explicit work list also handles deeply nested inputs.
@unsafe
def run(tasks: List<&2, Task>, values: List<&2, V.Value>) -> Converted():
  match tasks values:
    case Nil{} value <> Nil{}: Done{value}
    case Nil{} _: Fail{InvalidConversionState{}}
    case FinishArray{count} <> rest values: run(rest, finishArray(count, values, Nil{}))
    case Visit{Preserve{}, value} <> rest values: run(rest, value <> values)
    case Visit{Literal{+literal}, +original} <> rest values: run(ConvertedValue{selectLiteral(literalValue(literal), original, convert(literalPrimitive(literal), original))} <> rest, values)
    case Visit{Union{branches}, original} <> rest values: run(scheduleUnion(branches, original, rest), values)
    case TryAlternative{_, Nil{}, original} <> rest values: run(rest, original <> values)
    case TryAlternative{+schema, Branch{_, policy} <> remaining, +original} <> rest values: run(Visit{policy, original} <> SelectAlternative{schema, remaining, original} <> rest, values)
    case SelectAlternative{+schema, remaining, original} <> +rest +candidate <> +values:
      Bool.pick(Unit -> Converted(), S.check(schema, candidate),
        _ => run(rest, candidate <> values),
        _ => run(TryAlternative{schema, remaining, original} <> rest, values))(Unit{})
    case SelectAlternative{_, _, _} <> _ Nil{}: Fail{InvalidConversionState{}}
    case Visit{Scalar{primitive}, value} <> rest values: run(ConvertedValue{convert(primitive, value)} <> rest, values)
    case ConvertedValue{Done{converted}} <> rest values: run(rest, converted <> values)
    case ConvertedValue{Fail{error}} <> _ _: Fail{error}
    case Visit{ArrayItems{policy}, value} <> rest values: run(scheduleArray(policy, arrayInput(value), rest), values)
    case Visit{TupleItems{policies}, value} <> rest values: run(scheduleTuple(policies, value, rest), values)

def apply(policy: Policy, value: V.Value) -> Converted():
  run(Visit{policy, value} <> Nil{}, Nil{})
