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
