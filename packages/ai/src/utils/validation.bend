import Base
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
