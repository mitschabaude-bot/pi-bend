import Base
import ../src/api/constrained-sampling.bend as C
import ../../runtime/src/schema-builder.bend as D
import ../../runtime/src/schema-value.bend as V
import ../../runtime/src/record.bend as R
import ../../runtime/test/schema.bend as Assert
import ./api/strict-json-schema.bend as Check

def parameters() -> V.Value:
  D.schema(D.object(R.Record{
    R.Property{"path", D.required(D.string())} <>
    R.Property{"offset", D.optional(D.number())} <>
    R.Property{"metadata", D.required(D.object(R.Record{R.Property{"enabled", D.optional(D.boolean())} <> Nil{}}))} <>
    R.Property{"nullable", D.optional(D.union(D.string() <> D.null() <> Nil{}))} <> Nil{}}))

def nullable(schema: V.Value) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"anyOf", V.ArrayValue{schema <> D.schema(D.null()) <> Nil{}}} <> Nil{}}}

def object(properties: List<&2, R.Property<V.Value>>, names: List<&2, V.Value>) -> V.Value:
  V.ObjectValue{R.Record{R.Property{"type", V.Text{"object"}} <> R.Property{"properties", V.ObjectValue{R.Record{properties}}} <> R.Property{"required", V.ArrayValue{names}} <> R.Property{"additionalProperties", V.Boolean{False{}}} <> Nil{}}}

def expected() -> V.Value:
  object(
    R.Property{"path", D.schema(D.string())} <>
    R.Property{"offset", nullable(D.schema(D.number()))} <>
    R.Property{"metadata", object(R.Property{"enabled", nullable(D.schema(D.boolean()))} <> Nil{}, V.Text{"enabled"} <> Nil{})} <>
    R.Property{"nullable", nullable(D.schema(D.string()))} <> Nil{},
    V.Text{"path"} <> V.Text{"offset"} <> V.Text{"metadata"} <> V.Text{"nullable"} <> Nil{})

def originalRequired(value: Maybe<&2, V.Value>) -> Bool:
  match value:
    case Some{raw}: V.equal(raw, V.ArrayValue{V.Text{"path"} <> V.Text{"metadata"} <> Nil{}})
    case _: False{}

def unchanged(value: V.Value) -> Bool:
  match value:
    case V.ObjectValue{+fields}: Bool.not(Maybe.is_some(&2, V.Value, R.get(V.Value, fields, "additionalProperties"))) && originalRequired(R.get(V.Value, fields, "required"))
    case _: False{}

def derivesStrictSchemas() -> IO(Unit):
  +schema = parameters()
  do IO<Unit>:
    converted : Result<&2, &2, C.Error, V.Value> = C.makeStrictJsonSchema(schema)
    Assert.assertion(Check.sameSchema(converted, Done{expected()}), "strict provider schema preserves optional/nullable and nested fields")
    Assert.assertion(unchanged(schema), "original tool declaration retains its required fields and additionalProperties policy")
    IO.print("PASS derives strict provider schemas without changing tool definitions")

def main() -> IO(Unit): derivesStrictSchemas()
