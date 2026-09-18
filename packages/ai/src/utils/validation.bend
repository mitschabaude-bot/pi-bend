import Base
import ./validation-normalize.bend as Normalize
import ../../../runtime/src/number-string.bend as NumberString
import ../../../runtime/src/f64-decimal.bend as Decimal
import ../../../runtime/src/schema-value.bend as V
import ../../../runtime/src/record.bend as R
import ../../../runtime/src/f64.bend as F

# Validation consumes immutable schema and argument data directly.
def stringTypes(values: List<&2, V.Value>) -> List<&2, String>:
  match values:
    case Nil{}: Nil{}
    case V.Text{text} <> tail: text <> stringTypes(tail)
    case _ <> tail: stringTypes(tail)

def typesFromProperty(value: Maybe<&2, V.Value>) -> List<&2, String>:
  match value:
    case Some{V.Text{text}}: text <> Nil{}
    case Some{V.ArrayValue{values}}: stringTypes(values)
    case _: Nil{}

def getSchemaTypes(schema: R.Record<V.Value>) -> List<&2, String>:
  typesFromProperty(R.get(V.Value, schema, "type"))

def matchesJsonType(value: V.Value, +kind: String) -> Bool:
  match value:
    case V.Number{number}: String.eq(kind, "number") || (String.eq(kind, "integer") && F.isInteger(number))
    case V.Boolean{_}: String.eq(kind, "boolean")
    case V.Text{_}: String.eq(kind, "string")
    case V.Null{}: String.eq(kind, "null")
    case V.ArrayValue{_}: String.eq(kind, "array")
    case V.ObjectValue{_}: String.eq(kind, "object")
    case _: False{}

# The formatter exposes an explicit impossible-state failure. Do not silently
# retain a number or fabricate a string if that dependency cannot format it.
type CoercionError is Data:
  NumberFormattingFailure{}

def Coercion() -> Data: Result<&2, &2, CoercionError, V.Value>

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

def numericText(integerOnly: Bool, +text: String) -> V.Value:
  +parsed = NumberString.toNumber(text)
  acceptable = Bool.pick(Bool, integerOnly, F.isInteger(parsed), finiteNumber(F.decode(parsed)))
  Bool.pick(V.Value, Bool.not(String.is_empty(NumberString.trim(text))) && acceptable, V.Number{parsed}, V.Text{text})

def coerceNumeric(integerOnly: Bool, value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.Number{F.fromU32(0)}
    case V.Boolean{flag}: V.Number{F.fromU32(Bool.pick(U32, flag, 1, 0))}
    case V.Text{text}: numericText(integerOnly, text)
    case other: other

def equalNumber(order: Maybe<&2, Cmp>) -> Bool:
  match order:
    case Some{EQ{}}: True{}
    case _: False{}

def coerceBoolean(value: V.Value) -> V.Value:
  match value:
    case V.Null{}: V.Boolean{False{}}
    case V.Text{+text}: Bool.pick(V.Value, String.eq(text, "true"), V.Boolean{True{}}, Bool.pick(V.Value, String.eq(text, "false"), V.Boolean{False{}}, V.Text{text}))
    case V.Number{+number}: Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(1))), V.Boolean{True{}}, Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(0))), V.Boolean{False{}}, V.Number{number}))
    case other: other

def formattedNumber(value: Maybe<&2, String>) -> Coercion():
  match value:
    case None{}: Fail{NumberFormattingFailure{}}
    case Some{text}: Done{V.Text{text}}

def coerceString(value: V.Value) -> Coercion():
  match value:
    case V.Null{}: Done{V.Text{""}}
    case V.Boolean{flag}: Done{V.Text{Bool.pick(String, flag, "true", "false")}}
    case V.Number{number}: formattedNumber(Decimal.toDecimal(number))
    case other: Done{other}

def coerceNull(value: V.Value) -> V.Value:
  match value:
    case V.Text{+text}: Bool.pick(V.Value, String.is_empty(text), V.Null{}, V.Text{text})
    case V.Number{+number}: Bool.pick(V.Value, equalNumber(F.compare(number, F.fromU32(0))), V.Null{}, V.Number{number})
    case V.Boolean{flag}: Bool.pick(V.Value, flag, V.Boolean{True{}}, V.Null{})
    case other: other

def coercePrimitive(kind: PrimitiveType, value: V.Value) -> Coercion():
  match kind:
    case Numeric{integerOnly}: Done{coerceNumeric(integerOnly, value)}
    case BooleanType{}: Done{coerceBoolean(value)}
    case StringType{}: coerceString(value)
    case NullType{}: Done{coerceNull(value)}
    case OtherType{}: Done{value}

def coercePrimitiveByType(value: V.Value, kind: String) -> Coercion():
  coercePrimitive(primitiveType(kind), value)

# Primitive coercion changes scalar values only; aggregates pass through.
def primitiveCandidateChanged(original: V.Value, candidate: V.Value) -> Bool:
  match original candidate:
    case V.Number{a} V.Number{b}: Bool.not(equalNumber(F.compare(a, b)))
    case V.Text{a} V.Text{b}: Bool.not(String.eq(a, b))
    case V.Boolean{+a} V.Boolean{+b}: (a && Bool.not(b)) || (Bool.not(a) && b)
    case V.Null{} V.Null{}: False{}
    case V.ArrayValue{_} V.ArrayValue{_}: False{}
    case V.ObjectValue{_} V.ObjectValue{_}: False{}
    case _ _: True{}

def matchesAnyType(types: List<&2, String>, +value: V.Value) -> Bool:
  match types:
    case Nil{}: False{}
    case head <> tail: matchesJsonType(value, head) || matchesAnyType(tail, value)

def matchesTypeUnion(types: List<&2, String>, value: V.Value) -> Bool:
  match types:
    case a <> b <> rest: matchesAnyType(a <> b <> rest, value)
    case _: False{}

type PrimitiveSelection is Data:
  TryNextType{}
  SelectedPrimitive{value: V.Value}
  PrimitiveSelectionFailed{error: CoercionError}

def primitiveSelection(original: V.Value, candidate: Coercion()) -> PrimitiveSelection:
  match candidate:
    case Fail{error}: PrimitiveSelectionFailed{error}
    case Done{+value}: Bool.pick(PrimitiveSelection, primitiveCandidateChanged(original, value), SelectedPrimitive{value}, TryNextType{})

def selectPrimitiveTypes(types: List<&2, String>, +original: V.Value, selected: PrimitiveSelection) -> Coercion():
  match types selected:
    case _ SelectedPrimitive{value}: Done{value}
    case _ PrimitiveSelectionFailed{error}: Fail{error}
    case Nil{} TryNextType{}: Done{original}
    case head <> tail TryNextType{}: selectPrimitiveTypes(tail, original, primitiveSelection(original, coercePrimitiveByType(original, head)))

def coerceUnmatchedTypes(matched: Bool, types: List<&2, String>, value: V.Value) -> Coercion():
  match matched:
    case True{}: Done{value}
    case False{}: selectPrimitiveTypes(types, value, TryNextType{})

# The scalar/type-array phase of coerceWithJsonSchema, after allOf/anyOf/oneOf
# and before object/array traversal. This is not the complete schema algorithm.
def coerceSchemaTypes(+value: V.Value, +types: List<&2, String>) -> Coercion():
  coerceUnmatchedTypes(matchesTypeUnion(types, value), types, value)

# Native normalization returns a new value; unsupported nullability decisions
# remain explicit until the full schema vocabulary is implemented.
def normalizeOptionalNulls(value: V.Value, schema: V.Value) -> Normalize.Outcome():
  Normalize.normalizeOptionalNulls(value, schema)
