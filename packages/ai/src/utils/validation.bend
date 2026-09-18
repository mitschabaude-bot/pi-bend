import Base
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/f64-decimal.bend as Decimal
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# The source's unknown values retain non-JSON variants. These predicates do
# not serialize the schema or arguments before inspecting their types.
def stringTypes(-M: Data, values: List<&2, V.Value<M>>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{text} <> tail: text <> stringTypes(M, tail)
    case _ <> tail: stringTypes(M, tail)

def typesFromProperty(-M: Data, value: Maybe<&2, V.Property<V.Value<M>>>) -> List<&2, String>:
  match value:
    case Some{V.Property{V.Text{text}, _}}: text <> Nil{}
    case Some{V.Property{V.ArrayValue{values}, _}}: stringTypes(M, values)
    case _: Nil{}

def getSchemaTypes(-M: Data, schema: R.Record<V.Property<V.Value<M>>>) -> List<&2, String>:
  typesFromProperty(M, R.get(V.Property<V.Value<M>>, schema, "type"))

def matchesJsonType(-M: Data, value: V.Value<M>, +kind: String) -> Bool:
  match value:
    case V.Number{number}: String.eq(kind, "number") || (String.eq(kind, "integer") && F.isInteger(number))
    case V.Boolean{_}: String.eq(kind, "boolean")
    case V.Text{_}: String.eq(kind, "string")
    case V.Null{}: String.eq(kind, "null")
    case V.ArrayValue{_}: String.eq(kind, "array")
    case V.ObjectValue{_, _}: String.eq(kind, "object")
    case _: False{}

# The formatter exposes an explicit impossible-state failure. Do not silently
# retain a number or fabricate a string if that dependency cannot format it.
type CoercionError is Data:
  NumberFormattingFailure{}

def Coercion(-M: Data) -> Data: Result<&2, &2, CoercionError, V.Value<M>>

type PrimitiveType is Data:
  Numeric{integerOnly: Bool}
  BooleanType{}
  StringType{}
  NullType{}
  OtherType{}

def primitiveType(+kind: String) -> PrimitiveType:
  Bool.pick(PrimitiveType, String.eq(kind, "number"), Numeric{False{}}, Bool.pick(PrimitiveType, String.eq(kind, "integer"), Numeric{True{}}, Bool.pick(PrimitiveType, String.eq(kind, "boolean"), BooleanType{}, Bool.pick(PrimitiveType, String.eq(kind, "string"), StringType{}, Bool.pick(PrimitiveType, String.eq(kind, "null"), NullType{}, OtherType{})))))

def finiteNumber(value: F.Decoded) -> Bool:
  match value:
    case F.Finite{_, _, _}: True{}
    case _: False{}

def numericText(-M: Data, integerOnly: Bool, +text: String) -> V.Value<M>:
  +parsed = NumberString.toNumber(text)
  acceptable = Bool.pick(Bool, integerOnly, F.isInteger(parsed), finiteNumber(F.decode(parsed)))
  Bool.pick(V.Value<M>, Bool.not(String.is_empty(NumberString.trim(text))) && acceptable, V.Number{parsed}, V.Text{text})

def coerceNumeric(-M: Data, integerOnly: Bool, value: V.Value<M>) -> V.Value<M>:
  match value:
    case V.Null{}: V.Number{F.fromU32(0)}
    case V.Boolean{flag}: V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}
    case V.Text{text}: numericText(M, integerOnly, text)
    case other: other

def equalNumber(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def coerceBoolean(-M: Data, value: V.Value<M>) -> V.Value<M>:
  match value:
    case V.Null{}: V.Boolean{False{}}
    case V.Text{+text}: Bool.pick(V.Value<M>, String.eq(text, "true"), V.Boolean{True{}}, Bool.pick(V.Value<M>, String.eq(text, "false"), V.Boolean{False{}}, V.Text{text}))
    case V.Number{+number}: Bool.pick(V.Value<M>, equalNumber(F.compare(number, F.fromU32(1))), V.Boolean{True{}}, Bool.pick(V.Value<M>, equalNumber(F.compare(number, F.fromU32(0))), V.Boolean{False{}}, V.Number{number}))
    case other: other

def formattedNumber(-M: Data, value: Maybe<&2, String>) -> Coercion(M):
  match value:
    case None{}: Fail{NumberFormattingFailure{}}
    case Some{text}: Done{V.Text{text}}

def coerceString(-M: Data, value: V.Value<M>) -> Coercion(M):
  match value:
    case V.Null{}: Done{V.Text{""}}
    case V.Boolean{flag}: Done{V.Text{Bool.pick(String, flag, "true", "false")}}
    case V.Number{number}: formattedNumber(M, Decimal.toDecimal(number))
    case other: Done{other}

def coerceNull(-M: Data, value: V.Value<M>) -> V.Value<M>:
  match value:
    case V.Text{+text}: Bool.pick(V.Value<M>, String.is_empty(text), V.Null{}, V.Text{text})
    case V.Number{+number}: Bool.pick(V.Value<M>, equalNumber(F.compare(number, F.fromU32(0))), V.Null{}, V.Number{number})
    case V.Boolean{flag}: Bool.pick(V.Value<M>, flag, V.Boolean{True{}}, V.Null{})
    case other: other

def coercePrimitive(-M: Data, kind: PrimitiveType, value: V.Value<M>) -> Coercion(M):
  match kind:
    case Numeric{integerOnly}: Done{coerceNumeric(M, integerOnly, value)}
    case BooleanType{}: Done{coerceBoolean(M, value)}
    case StringType{}: coerceString(M, value)
    case NullType{}: Done{coerceNull(M, value)}
    case OtherType{}: Done{value}

def coercePrimitiveByType(-M: Data, value: V.Value<M>, kind: String) -> Coercion(M):
  coercePrimitive(M, primitiveType(kind), value)

# This comparison is scoped to outputs of coercePrimitiveByType. That helper
# never allocates/replaces objects, arrays, symbols or callable metadata. Their
# unchanged payloads therefore retain identity; no structural equality is used.
def primitiveCandidateChanged(-M: Data, original: V.Value<M>, candidate: V.Value<M>) -> Bool:
  match original candidate:
    case V.Number{a} V.Number{b}: Bool.not(equalNumber(F.compare(a, b)))
    case V.Text{a} V.Text{b}: Bool.not(String.eq(a, b))
    case V.Boolean{+a} V.Boolean{+b}: (a && Bool.not(b)) || (Bool.not(a) && b)
    case V.Null{} V.Null{}: False{}
    case V.Undefined{} V.Undefined{}: False{}
    case V.ArrayValue{_} V.ArrayValue{_}: False{}
    case V.ObjectValue{_, _} V.ObjectValue{_, _}: False{}
    case V.Symbol{_} V.Symbol{_}: False{}
    case V.Callable{_} V.Callable{_}: False{}
    case V.BigInteger{_, _} V.BigInteger{_, _}: False{}
    case _ _: True{}

def matchesAnyType(-M: Data, types: List<&2, String>, +value: V.Value<M>) -> Bool:
  match types:
    case Nil{}: False{}
    case head <> tail: matchesJsonType(M, value, head) || matchesAnyType(M, tail, value)

def matchesTypeUnion(-M: Data, types: List<&2, String>, value: V.Value<M>) -> Bool:
  match types:
    case a <> b <> rest: matchesAnyType(M, a <> b <> rest, value)
    case _: False{}

type PrimitiveSelection<-M: Data> is Data:
  TryNextType{}
  SelectedPrimitive{value: V.Value<M>}
  PrimitiveSelectionFailed{error: CoercionError}

def primitiveSelection(-M: Data, original: V.Value<M>, candidate: Coercion(M)) -> PrimitiveSelection<M>:
  match candidate:
    case Fail{error}: PrimitiveSelectionFailed{error}
    case Done{+value}: Bool.pick(PrimitiveSelection<M>, primitiveCandidateChanged(M, original, value), SelectedPrimitive{value}, TryNextType{})

def selectPrimitiveTypes(-M: Data, types: List<&2, String>, +original: V.Value<M>, selected: PrimitiveSelection<M>) -> Coercion(M):
  match types selected:
    case _ SelectedPrimitive{value}: Done{value}
    case _ PrimitiveSelectionFailed{error}: Fail{error}
    case Nil{} TryNextType{}: Done{original}
    case head <> tail TryNextType{}: selectPrimitiveTypes(M, tail, original, primitiveSelection(M, original, coercePrimitiveByType(M, original, head)))

def coerceUnmatchedTypes(-M: Data, matched: Bool, types: List<&2, String>, value: V.Value<M>) -> Coercion(M):
  match matched:
    case True{}: Done{value}
    case False{}: selectPrimitiveTypes(M, types, value, TryNextType{})

# The scalar/type-array phase of coerceWithJsonSchema, after allOf/anyOf/oneOf
# and before object/array traversal. This is not the complete schema algorithm.
def coerceSchemaTypes(-M: Data, +value: V.Value<M>, +types: List<&2, String>) -> Coercion(M):
  coerceUnmatchedTypes(M, matchesTypeUnion(M, types, value), types, value)
